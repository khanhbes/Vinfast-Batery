import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../data/models/vehicle_model.dart';
import '../../core/utils/app_error_formatter.dart';
import '../../core/widgets/app_popup.dart';
import '../../data/services/charge_estimator.dart';
import '../../data/services/server_smart_charger_service.dart';
import '../../data/services/shelly_charge_log_service.dart';
import '../../data/services/trip_energy_model.dart';
import '../../data/services/trip_route_service.dart';
import '../ai/services/learning_flow.dart';
import '../ai/widgets/battery_reading_sheet.dart';
import '../ai/widgets/edit_current_battery_sheet.dart';
import '../premium/premium_gate.dart';
import '../../data/models/entitlement.dart';

/// Trip battery planner (Task 126): where to, under which conditions, and
/// whether the battery is enough — with a concrete alternative when it is
/// not. Everything is an on-phone estimate; routing uses OpenStreetMap.
class TripPlannerScreen extends ConsumerStatefulWidget {
  const TripPlannerScreen({
    super.key,
    required this.vehicle,
    this.initialDestination,
    this.initialDistanceKm,
    this.initialConditions,
    this.learningService,
  });

  final VehicleModel vehicle;

  /// Server learning API (Task 127); injectable for tests.
  final ServerSmartChargerService? learningService;

  /// BatteryBot prefill: a place name to search, or a distance in km.
  final String? initialDestination;
  final double? initialDistanceKm;
  final TripConditions? initialConditions;

  @override
  ConsumerState<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends ConsumerState<TripPlannerScreen> {
  final _mapController = MapController();
  final _distanceController = TextEditingController();

  LatLng? _origin;
  String _originName = '';
  LatLng? _destination;
  String _destinationName = '';
  List<PlannedRoute> _routes = const [];
  int _routeIndex = 0;
  bool _locating = false;
  bool _routing = false;
  late TripConditions _conditions;
  late double _soc;
  bool _socKnown = false;

  /// The owner typed a % for this plan; the vehicle's % no longer replaces it.
  bool _socEdited = false;
  double? _personalKmPerPct;
  int _personalPairs = 0;
  double? _historyPowerW;
  TripPlan? _plan;
  List<_SavedPlan> _saved = const [];

  /// Task 127: the trip model trained on this vehicle's rides (server).
  TripModelParams? _trainedModel;

  /// Learned charge model (server), so "charge first" matches the Charge tab.
  double? _learnedWhPerPct;
  double? _learnedPowerW;
  _ActiveTrip? _activeTrip;
  bool _savingTrip = false;

  PlannedRoute? get _route => _routes.isEmpty
      ? null
      : _routes[_routeIndex.clamp(0, _routes.length - 1)];

  double? get _catalogKmPerPct => widget.vehicle.hasEfficiencyData
      ? TripEnergyModel.catalogKmPerPct(
          widget.vehicle.defaultEfficiency,
          widget.vehicle.hasSohData ? widget.vehicle.stateOfHealth : null,
        )
      : null;

  double? get _manualKm {
    final value = double.tryParse(
      _distanceController.text.trim().replaceAll(',', '.'),
    );
    return value != null && value > 0 && value <= 1000 ? value : null;
  }

  double? get _distanceKm => _route?.distanceKm ?? _manualKm;

  @override
  void didUpdateWidget(TripPlannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // QA 137: a % saved elsewhere (a reading, a confirmed charge, Pinova
    // Bot) reaches the plan too, unless the owner set one here.
    final vehicle = widget.vehicle;
    if (!_socEdited &&
        (vehicle.currentBattery != oldWidget.vehicle.currentBattery ||
            vehicle.hasBatteryData != oldWidget.vehicle.hasBatteryData)) {
      setState(() {
        _soc = vehicle.currentBattery.toDouble().clamp(0, 100);
        _socKnown = vehicle.hasBatteryData;
      });
      _recompute();
    }
  }

  @override
  void initState() {
    super.initState();
    _conditions = widget.initialConditions ?? const TripConditions();
    _soc = widget.vehicle.currentBattery.toDouble().clamp(0, 100);
    _socKnown = widget.vehicle.hasBatteryData;
    if (widget.initialDistanceKm != null) {
      _distanceController.text = widget.initialDistanceKm!.toStringAsFixed(1);
    }
    unawaited(_loadLearning());
    unawaited(_loadTrainedModel());
    unawaited(_loadSaved());
    unawaited(_loadActiveTrip());
    final query = widget.initialDestination?.trim();
    if (query != null && query.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickPlace(origin: false, initialQuery: query);
      });
    }
  }

  @override
  void dispose() {
    _distanceController.dispose();
    super.dispose();
  }

  // ── data ────────────────────────────────────────────────────────────────

  /// km per 1 % from this vehicle's ODO + confirmed % pairs, and the power
  /// of its recent charges (for "charge first" time).
  Future<void> _loadLearning() async {
    try {
      final sessions = (await ShellyChargeLogService().loadTerminalSessions(
        limit: 40,
      )).where((s) => s.vehicleId == widget.vehicle.vehicleId).toList();
      final learned = TripEnergyModel.learnKmPerPct(
        TripChargeReading.fromSessions(sessions),
        catalog: _catalogKmPerPct,
      );
      final power = ChargeEstimator.medianChargingPower([
        for (final s in sessions.take(10))
          if (s.averagePowerW != null) s.averagePowerW!,
      ], minSamples: 1);
      if (!mounted) return;
      setState(() {
        _personalKmPerPct = learned.kmPerPct;
        _personalPairs = learned.pairs;
        _historyPowerW = power;
      });
      _recompute();
    } on Object {
      // Offline or no history: the catalog value still works.
    }
  }

  /// The trained trip model, if the owner has trained one (Task 127).
  Future<void> _loadTrainedModel() async {
    ServerSmartChargerService? api;
    try {
      api = widget.learningService ?? ServerSmartChargerService();
      final status = await api.learningStatus(widget.vehicle.vehicleId);
      if (!mounted) return;
      final charge = status?.charge.raw ?? const <String, dynamic>{};
      final params = status?.tripParams;
      setState(() {
        _learnedWhPerPct = (charge['whPerPct'] as num?)?.toDouble();
        _learnedPowerW = (charge['powerW'] as num?)?.toDouble();
        if (params != null && params.source == TripKmSource.model) {
          _trainedModel = params;
        }
      });
      _recompute();
    } on Object {
      // Offline: the ODO / catalog value still works.
    } finally {
      if (widget.learningService == null) api?.close();
    }
  }

  // ── trip recording (Task 127) ───────────────────────────────────────────

  String get _activeKey => 'trip_active_v1_${widget.vehicle.vehicleId}';

  Future<void> _loadActiveTrip() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trip = _ActiveTrip.tryParse(prefs.getString(_activeKey));
      if (mounted && trip != null) setState(() => _activeTrip = trip);
    } on Object {
      // No recording in progress.
    }
  }

  Future<void> _storeActiveTrip(_ActiveTrip? trip) async {
    setState(() => _activeTrip = trip);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (trip == null) {
        await prefs.remove(_activeKey);
      } else {
        await prefs.setString(_activeKey, trip.encode());
      }
    } on Object {
      // Kept in memory for this screen.
    }
  }

  Future<void> _startTrip() async {
    final plan = _plan;
    final input = await BatteryReadingSheet.show(
      context,
      eyebrow: 'Lúc xuất phát',
      title: '% pin và ODO trên đồng hồ',
      initialSoc: _socKnown ? _soc : null,
      currentOdoKm: widget.vehicle.currentOdo > 0
          ? widget.vehicle.currentOdo.toDouble()
          : null,
      requireSoc: true,
    );
    if (input == null || !mounted || input.soc == null) return;
    final trip = _ActiveTrip(
      id: 'trip_${DateTime.now().microsecondsSinceEpoch}',
      startedAt: DateTime.now(),
      startSoc: input.soc!,
      startOdoKm: input.odoKm,
      plannedKm: plan?.distanceKm ?? _distanceKm,
      predictedUsePct: plan?.usePct,
      riders: _conditions.riders,
      cargoKg: _conditions.cargoKg,
      rain: _conditions.weather == TripWeather.rain,
      to: _destinationName,
    );
    setState(() {
      _soc = input.soc!;
      _socKnown = true;
    });
    _recompute();
    await _storeActiveTrip(trip);
    unawaited(
      _postReading(soc: input.soc, odoKm: input.odoKm, source: 'trip_start'),
    );
    AppPopup.showSuccess(
      'Đang ghi chuyến đi',
      detail: 'Khi tới nơi, bấm "Đã đến nơi" và nhập % pin trên đồng hồ.',
    );
  }

  Future<void> _postReading({
    double? soc,
    double? odoKm,
    required String source,
  }) async {
    ServerSmartChargerService? api;
    try {
      api = widget.learningService ?? ServerSmartChargerService();
      await api.addBatteryReading(
        widget.vehicle.vehicleId,
        soc: soc,
        odoKm: odoKm,
        source: source,
      );
    } on Object {
      // The ride sample below is what teaches the model.
    } finally {
      if (widget.learningService == null) api?.close();
    }
  }

  Future<void> _finishTrip() async {
    final trip = _activeTrip;
    if (trip == null) return;
    final input = await BatteryReadingSheet.show(
      context,
      eyebrow: 'Khi đến nơi',
      title: '% pin và ODO trên đồng hồ',
      currentOdoKm: trip.startOdoKm,
      requireSoc: true,
    );
    if (input == null || !mounted || input.soc == null) return;
    final odoKm = input.odoKm;
    final startOdo = trip.startOdoKm;
    final distance = odoKm != null && startOdo != null && odoKm > startOdo
        ? odoKm - startOdo
        : trip.plannedKm;
    if (distance == null || distance <= 0) {
      AppPopup.showInfo(
        'Cần quãng đường',
        detail:
            'Nhập ODO lúc xuất phát và khi đến nơi để app biết đã đi bao xa.',
      );
      return;
    }
    final minutes = DateTime.now().difference(trip.startedAt).inSeconds / 60;
    final used = trip.startSoc - input.soc!;
    setState(() => _savingTrip = true);
    ServerSmartChargerService? api;
    try {
      api = widget.learningService ?? ServerSmartChargerService();
      final result = await api.addTripSamples(widget.vehicle.vehicleId, [
        {
          'clientId': trip.id,
          'at': trip.startedAt.toUtc().toIso8601String(),
          'distanceKm': double.parse(distance.toStringAsFixed(2)),
          'startSoc': trip.startSoc,
          'endSoc': input.soc,
          if (minutes >= 1 && minutes <= 1440)
            'durationMin': double.parse(minutes.toStringAsFixed(1)),
          'payloadKg': TripEnergyModel.payloadKg(
            TripConditions(riders: trip.riders, cargoKg: trip.cargoKg),
          ),
          'riders': trip.riders,
          'cargoKg': trip.cargoKg,
          'weather': trip.rain ? 'rain' : 'dry',
          'predictedUsePct': ?trip.predictedUsePct,
        },
      ], source: 'trip');
      await _postReading(soc: input.soc, odoKm: odoKm, source: 'trip_end');
      await _storeActiveTrip(null);
      if (!mounted) return;
      setState(() {
        _soc = input.soc!;
        _socKnown = true;
      });
      _recompute();
      final predicted = trip.predictedUsePct;
      AppPopup.showSuccess(
        result.added > 0
            ? 'Đã lưu chuyến ${distance.toStringAsFixed(1)} km'
            : 'Chuyến này đã được lưu trước đó',
        detail:
            'Thực tế dùng ${used.round()}%'
            '${predicted == null ? '' : ' · dự đoán khoảng ${predicted.round()}%'}. '
            'AI sẽ học từ chuyến này khi bạn bấm Huấn luyện.',
      );
      await TrainingReadiness.check(result.status);
    } catch (error) {
      AppPopup.showError(
        'Chưa lưu được chuyến đi',
        detail: AppErrorFormatter.format(error),
      );
    } finally {
      if (widget.learningService == null) api?.close();
      if (mounted) setState(() => _savingTrip = false);
    }
  }

  Widget _tripRecorder() {
    final trip = _activeTrip;
    if (trip == null) {
      if (_plan == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: OutlinedButton.icon(
          key: const ValueKey('trip-record-start'),
          onPressed: _startTrip,
          icon: const Icon(Icons.fiber_manual_record_outlined),
          label: const Text('Bắt đầu đi & ghi chuyến để AI học'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
        ),
      );
    }
    final started = TimeOfDay.fromDateTime(trip.startedAt).format(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: LuxeGlass(
        key: const ValueKey('trip-recording'),
        radius: 22,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('ĐANG GHI CHUYẾN ĐI', style: LuxeText.eyebrow),
            const SizedBox(height: 6),
            Text(
              'Xuất phát $started ở ${trip.startSoc.round()}%'
              '${trip.to.isEmpty ? '' : ' · tới ${trip.to.split(',').first}'}',
              style: LuxeText.item.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 12),
            if (_savingTrip)
              const LinearProgressIndicator(minHeight: 2)
            else
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('trip-record-finish'),
                    onPressed: _finishTrip,
                    icon: const Icon(Icons.flag_rounded),
                    label: const Text('Đã đến nơi'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('trip-record-cancel'),
                    onPressed: () => _storeActiveTrip(null),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text('Hủy ghi'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String get _savedKey => 'trip_plans_v1_${widget.vehicle.vehicleId}';

  Future<void> _loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rows = prefs.getStringList(_savedKey) ?? const [];
      if (!mounted) return;
      setState(
        () => _saved = [for (final row in rows) ?_SavedPlan.tryParse(row)],
      );
    } on Object {
      // A corrupt local list only hides "recent plans".
    }
  }

  Future<void> _remember(TripPlan plan) async {
    final item = _SavedPlan(
      to: _destinationName.isEmpty
          ? '${plan.distanceKm.toStringAsFixed(1)} km'
          : _destinationName,
      distanceKm: plan.distanceKm,
      usePct: plan.usePct,
      verdict: plan.verdict,
      at: DateTime.now(),
    );
    final next = [
      item,
      ..._saved.where((s) => s.to != item.to),
    ].take(5).toList();
    setState(() => _saved = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_savedKey, [for (final s in next) s.encode()]);
    } on Object {
      // Recent plans are a convenience only.
    }
  }

  // ── places & routes ─────────────────────────────────────────────────────

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _TripMessage('Hãy bật dịch vụ vị trí.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const _TripMessage(
          'Không có quyền vị trí. Bạn vẫn có thể gõ điểm đi.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        _origin = LatLng(position.latitude, position.longitude);
        _originName = 'Vị trí của tôi';
        _locating = false;
      });
      _mapController.move(_origin!, 14);
      await _calculateRoute();
    } on _TripMessage catch (message) {
      if (!mounted) return;
      setState(() => _locating = false);
      _notice(message.text);
    } on Object {
      if (!mounted) return;
      setState(() => _locating = false);
      _notice('Chưa lấy được vị trí. Hãy gõ điểm đi.');
    }
  }

  Future<void> _pickPlace({required bool origin, String? initialQuery}) async {
    final place = await showLuxeSheet<PlaceSuggestion>(
      context,
      builder: (_) => _PlaceSearchSheet(
        title: origin ? 'Chọn điểm đi' : 'Chọn điểm đến',
        initialQuery: initialQuery,
      ),
    );
    if (place == null || !mounted) return;
    setState(() {
      if (origin) {
        _origin = place.point;
        _originName = place.name;
      } else {
        _destination = place.point;
        _destinationName = place.name;
      }
    });
    await _calculateRoute();
  }

  Future<void> _selectPoint(LatLng point) async {
    setState(() {
      _destination = point;
      _destinationName =
          '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
    });
    await _calculateRoute();
  }

  Future<void> _calculateRoute() async {
    final start = _origin;
    final end = _destination;
    if (start == null || end == null) {
      if (end != null) _mapController.move(end, 13);
      return;
    }
    setState(() => _routing = true);
    try {
      final routes = await TripRouteService.routes(start, end);
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _routeIndex = 0;
        _routing = false;
        _distanceController.clear();
      });
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([start, end]),
          padding: const EdgeInsets.fromLTRB(36, 72, 36, 54),
        ),
      );
      _recompute(remember: true);
    } on Object {
      if (!mounted) return;
      setState(() => _routing = false);
      _notice(
        'Chưa tính được tuyến đường. Kiểm tra mạng, hoặc nhập quãng đường bằng tay.',
      );
    }
  }

  // ── model ───────────────────────────────────────────────────────────────

  void _recompute({bool remember = false}) {
    final distance = _distanceKm;
    final personal = _personalKmPerPct;
    final catalog = _catalogKmPerPct;
    final trained = _trainedModel;
    final base = personal ?? catalog;
    if (distance == null || (base == null && trained == null) || !_socKnown) {
      if (_plan != null) setState(() => _plan = null);
      return;
    }
    final alternatives = [
      for (var i = 0; i < _routes.length; i++)
        if (i != _routeIndex) _routes[i].distanceKm,
    ];
    final plan = TripEnergyModel.plan(
      distanceKm: distance,
      currentSoc: _soc,
      kmPerPct: base,
      source: personal != null ? TripKmSource.personal : TripKmSource.catalog,
      model: trained,
      conditions: _conditions,
      durationMin: _route?.durationMin,
      alternativeKm: alternatives,
    );
    setState(() => _plan = plan);
    if (remember) unawaited(_remember(plan));
  }

  void _setConditions(TripConditions next) {
    HapticFeedback.selectionClick();
    setState(() => _conditions = next);
    _recompute();
  }

  Duration? _chargeTime(double target) {
    final capacity = widget.vehicle.batteryCapacityWh;
    final whPerPct = _learnedWhPerPct;
    if ((capacity <= 0 && whPerPct == null) || target <= _soc) return null;
    final learnedPower = _learnedPowerW;
    final power = ChargeEstimator.pickPower(
      recentSessionPowers: [?learnedPower ?? _historyPowerW],
    );
    return ChargeEstimator.estimate(
      currentSoc: _soc,
      targetSoc: target,
      capacityWh: capacity > 0
          ? capacity
          : whPerPct! * 100 * ChargeEstimator.efficiency,
      powerW: power.watts,
      powerSource: power.source,
      whPerPercent: whPerPct,
    )?.duration;
  }

  void _chargeFirst(double target) {
    ref.read(pendingChargeTargetSocProvider.notifier).state = (
      vehicleId: widget.vehicle.vehicleId,
      targetSoc: target,
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
    ref.read(currentTabProvider.notifier).state = 1;
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  // QA 136: however this screen is reached (a tile, Pinova Bot, a
  // notification), outside the plan it shows Pinova Premium instead.
  Widget build(BuildContext context) => PremiumRequired(
    feature: PremiumFeature.tripEstimate,
    child: Builder(builder: _screen),
  );

  Widget _screen(BuildContext context) {
    final center = _destination ?? _origin ?? const LatLng(21.0285, 105.8542);
    return LuxeScaffold(
      appBar: Navigator.canPop(context) ? const LuxeAppBar() : null,
      body: SafeArea(
        top: !Navigator.canPop(context),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(child: LuxeReveal(index: 1, child: _places())),
            SliverToBoxAdapter(
              child: LuxeReveal(index: 2, child: _map(center)),
            ),
            if (_routes.length > 1) SliverToBoxAdapter(child: _routeChoices()),
            SliverToBoxAdapter(child: _manualDistance()),
            SliverToBoxAdapter(
              child: LuxeReveal(index: 3, child: _conditionsCard()),
            ),
            SliverToBoxAdapter(child: _resultOrHint()),
            SliverToBoxAdapter(child: _tripRecorder()),
            if (_saved.isNotEmpty) SliverToBoxAdapter(child: _recent()),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
    child: LuxeReveal(
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LỘ TRÌNH', style: LuxeText.eyebrow),
                SizedBox(height: 6),
                Text('Đi được tới đâu?', style: LuxeText.title),
                SizedBox(height: 4),
                Text(
                  'Ước tính pin hao theo tuyến đường và điều kiện bạn chọn',
                  style: LuxeText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _BatteryBadge(
            value: _soc.round(),
            known: _socKnown,
            onTap: () => EditCurrentBatterySheet.show(
              context,
              initialPercent: _soc,
              onSave: (value) {
                setState(() {
                  _soc = value;
                  _socKnown = true;
                  _socEdited = true;
                });
                _recompute();
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _places() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: LuxeGlass(
      radius: 22,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          _PlaceRow(
            key: const ValueKey('trip-origin'),
            icon: Icons.trip_origin_rounded,
            label: 'Điểm đi',
            value: _originName,
            placeholder: 'Gõ điểm đi',
            onTap: () => _pickPlace(origin: true),
            trailing: IconButton(
              tooltip: 'Vị trí của tôi',
              onPressed: _locating ? null : _locate,
              icon: _locating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.my_location_rounded,
                      color: LuxeColors.platinum,
                    ),
            ),
          ),
          const Divider(height: 1, indent: 52),
          _PlaceRow(
            key: const ValueKey('trip-destination'),
            icon: Icons.flag_rounded,
            label: 'Điểm đến',
            value: _destinationName,
            placeholder: 'Bạn muốn đi đâu?',
            onTap: () => _pickPlace(origin: false),
          ),
        ],
      ),
    ),
  );

  Widget _map(LatLng center) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: LuxeColors.hairlineStrong),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: SizedBox(
          height: 260,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 12,
                  backgroundColor: LuxeColors.surface,
                  onLongPress: (_, point) {
                    HapticFeedback.mediumImpact();
                    _selectPoint(point);
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.bes.vinbatery',
                    tileBuilder: darkModeTileBuilder,
                  ),
                  if (_route != null)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _route!.geometry,
                          strokeWidth: 10,
                          color: LuxeColors.platinum.withValues(alpha: 0.18),
                        ),
                        Polyline(
                          points: _route!.geometry,
                          strokeWidth: 4,
                          color: LuxeColors.platinumHi,
                          borderStrokeWidth: 1,
                          borderColor: const Color(0x66000000),
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      if (_origin != null)
                        Marker(
                          point: _origin!,
                          width: 40,
                          height: 40,
                          child: const _MapPin(origin: true),
                        ),
                      if (_destination != null)
                        Marker(
                          point: _destination!,
                          width: 44,
                          height: 44,
                          child: const _MapPin(origin: false),
                        ),
                    ],
                  ),
                ],
              ),
              if (_routing)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x88050506),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              const Positioned(left: 12, top: 12, child: _MapHint()),
              // Required credit for OpenStreetMap data and tiles.
              Positioned(
                right: 8,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  color: const Color(0xCC121315),
                  child: const Text(
                    '© OpenStreetMap',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(color: LuxeColors.muted, fontSize: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _routeChoices() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < _routes.length; i++)
          ChoiceChip(
            key: ValueKey('trip-route-$i'),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            selected: i == _routeIndex,
            label: Text(
              '${i == 0 ? 'Nhanh nhất' : 'Tuyến ${i + 1}'} · '
              '${_routes[i].distanceKm.toStringAsFixed(1)} km · '
              '${_routes[i].durationMin.round()} phút',
            ),
            onSelected: (_) {
              setState(() => _routeIndex = i);
              _recompute();
            },
          ),
      ],
    ),
  );

  Widget _manualDistance() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: _route != null
        ? Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'Quãng đường',
                  icon: Icons.straighten_rounded,
                  value: '${_route!.distanceKm.toStringAsFixed(1)} km',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Metric(
                  label: 'Thời gian (ô tô)',
                  icon: Icons.schedule_rounded,
                  value: '${_route!.durationMin.round()} phút',
                ),
              ),
            ],
          )
        : TextField(
            key: const ValueKey('trip-manual-km'),
            controller: _distanceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _recompute(),
            style: const TextStyle(color: LuxeColors.text),
            decoration: const InputDecoration(
              labelText: 'Hoặc nhập quãng đường',
              suffixText: 'km',
              prefixIcon: Icon(Icons.straighten_rounded, size: 20),
            ),
          ),
  );

  Widget _conditionsCard() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
    child: LuxeGlass(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel('Tốc độ'),
          const SizedBox(height: 8),
          LuxeSegmented<TripSpeed>(
            segments: const [
              (TripSpeed.slow, 'Chậm'),
              (TripSpeed.normal, 'Vừa'),
              (TripSpeed.fast, 'Nhanh'),
            ],
            selected: _conditions.speed == TripSpeed.auto
                ? TripSpeed.normal
                : _conditions.speed,
            onChanged: (v) => _setConditions(_conditions.copyWith(speed: v)),
          ),
          const SizedBox(height: 14),
          const _SectionLabel('Thời tiết'),
          const SizedBox(height: 8),
          LuxeSegmented<TripWeather>(
            segments: const [
              (TripWeather.dry, 'Khô ráo'),
              (TripWeather.rain, 'Mưa'),
              (TripWeather.hot, 'Nóng'),
              (TripWeather.cold, 'Lạnh'),
            ],
            selected: _conditions.weather,
            onChanged: (v) => _setConditions(_conditions.copyWith(weather: v)),
          ),
          const SizedBox(height: 14),
          const _SectionLabel('Người & hàng'),
          const SizedBox(height: 8),
          LuxeSegmented<int>(
            segments: const [(1, '1 người'), (2, '2 người')],
            selected: _conditions.riders,
            onChanged: (v) => _setConditions(_conditions.copyWith(riders: v)),
          ),
          const SizedBox(height: 10),
          Text(
            'Hàng mang theo: ${_conditions.cargoKg.round()} kg',
            style: LuxeText.caption,
          ),
          Slider(
            value: _conditions.cargoKg,
            max: 40,
            divisions: 8,
            label: '${_conditions.cargoKg.round()} kg',
            semanticFormatterCallback: (v) => '${v.round()} ki-lô-gam',
            onChanged: (v) => _setConditions(_conditions.copyWith(cargoKg: v)),
          ),
          _ToggleRow(
            title: 'Đường dốc nhiều',
            value: _conditions.hilly,
            onChanged: (v) => _setConditions(_conditions.copyWith(hilly: v)),
          ),
          _ToggleRow(
            title: 'Đi rồi về (khứ hồi)',
            value: _conditions.roundTrip,
            onChanged: (v) =>
                _setConditions(_conditions.copyWith(roundTrip: v)),
          ),
        ],
      ),
    ),
  );

  Widget _resultOrHint() {
    final plan = _plan;
    if (plan != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: LuxeReveal(
          key: ValueKey(
            '${plan.distanceKm}-${plan.usePct.toStringAsFixed(2)}-${_soc.round()}',
          ),
          child: _TripResultCard(
            plan: plan,
            startSoc: _soc,
            personalPairs: _personalPairs,
            chargeTime: _chargeTime,
            onChargeFirst: _chargeFirst,
            // The owner's rides cost least around 15-21 km/h average.
            onEco: () =>
                _setConditions(_conditions.copyWith(speed: TripSpeed.normal)),
            onShorterRoute: (km) {
              final index = _routes.indexWhere(
                (r) => (r.distanceKm - km).abs() < 0.06,
              );
              if (index >= 0) {
                setState(() => _routeIndex = index);
                _recompute();
              }
            },
          ),
        ),
      );
    }
    final String message;
    if (!_socKnown) {
      message = 'Chạm vào vòng pin ở trên để nhập mức pin hiện tại của xe.';
    } else if (_catalogKmPerPct == null && _personalKmPerPct == null) {
      message =
          'Xe chưa có định mức km cho mỗi 1 % pin. Hãy chọn đúng dòng xe trong Xe của tôi.';
    } else {
      message =
          'Chọn điểm đi và điểm đến, hoặc nhập quãng đường, để xem pin có đủ không.';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: LuxeNotice(
        key: const ValueKey('trip-hint'),
        icon: Icons.route_rounded,
        color: LuxeColors.steel,
        message: message,
      ),
    );
  }

  Widget _recent() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LuxeSectionLabel('Kế hoạch gần đây'),
        LuxeSettingsGroup(
          children: [
            for (final item in _saved)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                child: Row(
                  children: [
                    const LuxeMedallion(icon: Icons.route_rounded),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.to,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LuxeText.item.copyWith(fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item.distanceKm.toStringAsFixed(1)} km · '
                            '${_verdictShort(item.verdict)}',
                            style: LuxeText.caption.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'hao ${item.usePct.round()}%',
                      style: const TextStyle(
                        color: LuxeColors.platinum,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

String _verdictShort(TripVerdict verdict) => switch (verdict) {
  TripVerdict.comfortable => 'đủ pin',
  TripVerdict.tight => 'sát',
  TripVerdict.insufficient => 'không đủ',
};

Color _verdictColor(TripVerdict verdict) => switch (verdict) {
  TripVerdict.comfortable => LuxeColors.steel,
  TripVerdict.tight => LuxeColors.champagne,
  TripVerdict.insufficient => LuxeColors.danger,
};

class _TripResultCard extends StatelessWidget {
  const _TripResultCard({
    required this.plan,
    required this.startSoc,
    required this.personalPairs,
    required this.chargeTime,
    required this.onChargeFirst,
    required this.onEco,
    required this.onShorterRoute,
  });

  final TripPlan plan;
  final double startSoc;
  final int personalPairs;
  final Duration? Function(double target) chargeTime;
  final ValueChanged<double> onChargeFirst;
  final VoidCallback onEco;
  final ValueChanged<double> onShorterRoute;

  @override
  Widget build(BuildContext context) {
    final color = _verdictColor(plan.verdict);
    final arrival = plan.arrivalSoc.clamp(0, 100).toDouble();
    return LuxeGlass(
      key: const ValueKey('trip-result'),
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                plan.verdict == TripVerdict.comfortable
                    ? Icons.check_circle_outline_rounded
                    : Icons.warning_amber_rounded,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  plan.verdictLabel,
                  key: const ValueKey('trip-verdict'),
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('HAO KHOẢNG', style: LuxeText.eyebrow),
                  const SizedBox(height: 4),
                  LuxeMetalText(
                    '${plan.usePct.round()}%',
                    style: const TextStyle(
                      fontSize: 40,
                      height: 1,
                      fontWeight: FontWeight.w200,
                    ),
                  ),
                  Text(
                    '${plan.useLowPct.round()}–${plan.useHighPct.round()}% '
                    'tùy đường',
                    style: LuxeText.caption.copyWith(fontSize: 12),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    plan.arrivalSoc < 0
                        ? 'HẾT PIN TRƯỚC KHI TỚI'
                        : 'KHI TỚI NƠI (ƯỚC TÍNH)',
                    style: LuxeText.eyebrow,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    plan.arrivalSoc < 0 ? '0%' : '${arrival.round()}%',
                    style: TextStyle(
                      color: color,
                      fontSize: 28,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _TripEnergyBar(start: startSoc, end: arrival, color: color),
          const SizedBox(height: 12),
          Text(switch (plan.source) {
            TripKmSource.model =>
              // Say why this differs from the Overview average (QA 129:
              // 1.36 here vs 1.21 there read as two models).
              'Mô hình đã huấn luyện từ ${plan.modelSamples} chuyến của bạn. '
                  'Ở điều kiện này (khoảng ${plan.avgSpeedKmh.round()} km/h, '
                  '${plan.payloadKg.round()} kg): '
                  'khoảng ${(plan.kmPerPct / (TripEnergyModel.refToMean * plan.factor)).toStringAsFixed(2)} km cho 1%; '
                  'trung bình các chuyến của bạn: '
                  '${plan.kmPerPct.toStringAsFixed(2)} km cho 1% (số ở Tổng quan).',
            TripKmSource.personal =>
              'Dựa trên $personalPairs lần sạc có ODO của xe bạn '
                  '(khoảng ${plan.kmPerPct.toStringAsFixed(2)} km cho 1 %).',
            TripKmSource.catalog =>
              'Theo định mức dòng xe (khoảng ${plan.kmPerPct.toStringAsFixed(2)} km cho 1 %). '
                  'Ghi chuyến đi hoặc nhập ODO để AI học theo xe của bạn.',
          }, style: LuxeText.caption.copyWith(fontSize: 12)),
          if (plan.suggestions.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            const Text('GỢI Ý', style: LuxeText.eyebrow),
            for (final suggestion in plan.suggestions)
              _SuggestionRow(
                suggestion: suggestion,
                chargeTime: chargeTime,
                onChargeFirst: onChargeFirst,
                onEco: onEco,
                onShorterRoute: onShorterRoute,
              ),
          ],
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.chargeTime,
    required this.onChargeFirst,
    required this.onEco,
    required this.onShorterRoute,
  });

  final TripSuggestion suggestion;
  final Duration? Function(double target) chargeTime;
  final ValueChanged<double> onChargeFirst;
  final VoidCallback onEco;
  final ValueChanged<double> onShorterRoute;

  @override
  Widget build(BuildContext context) {
    final (
      IconData icon,
      String text,
      String? action,
      VoidCallback? onTap,
    ) = switch (suggestion.kind) {
      TripSuggestionKind.chargeFirst => () {
        final target = suggestion.targetSoc!;
        final time = chargeTime(target);
        return (
          Icons.bolt_rounded,
          'Sạc lên ${target.round()}% trước khi đi'
              '${time == null ? '' : ' (khoảng ${formatChargeDuration(time)})'}.',
          'Sạc đến ${target.round()}%',
          () => onChargeFirst(target),
        );
      }(),
      TripSuggestionKind.chargeOnTheWay => (
        Icons.ev_station_rounded,
        'Quãng đường vượt quá một lần sạc đầy: cần sạc giữa đường khoảng '
            '${suggestion.stops} lần.',
        null,
        null,
      ),
      TripSuggestionKind.chargeAtDestination => (
        Icons.home_work_outlined,
        'Đủ pin để tới nơi; hãy sạc ở điểm đến trước khi quay về.',
        null,
        null,
      ),
      TripSuggestionKind.rideEco => (
        Icons.eco_outlined,
        'Chạy chậm lại tiết kiệm khoảng ${suggestion.savedPct!.round()}% pin.',
        'Áp dụng',
        onEco,
      ),
      TripSuggestionKind.shorterRoute => (
        Icons.alt_route_rounded,
        'Tuyến ${suggestion.distanceKm!.toStringAsFixed(1)} km ngắn hơn, '
            'tiết kiệm khoảng ${suggestion.savedPct!.round()}% pin.',
        'Chọn tuyến này',
        () => onShorterRoute(suggestion.distanceKm!),
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: LuxeColors.platinumMid),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: LuxeColors.text,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (action != null && onTap != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: ValueKey('trip-suggestion-${suggestion.wire}'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: onTap,
                child: Text(action),
              ),
            ),
        ],
      ),
    );
  }
}

class _TripMessage implements Exception {
  const _TripMessage(this.text);
  final String text;
}

/// A ride being recorded from the planner (Task 127), kept on the phone
/// until the owner reads the dashboard at the destination.
class _ActiveTrip {
  const _ActiveTrip({
    required this.id,
    required this.startedAt,
    required this.startSoc,
    this.startOdoKm,
    this.plannedKm,
    this.predictedUsePct,
    this.riders = 1,
    this.cargoKg = 0,
    this.rain = false,
    this.to = '',
  });

  final String id;
  final DateTime startedAt;
  final double startSoc;
  final double? startOdoKm;
  final double? plannedKm;
  final double? predictedUsePct;
  final int riders;
  final double cargoKg;
  final bool rain;
  final String to;

  String encode() => jsonEncode({
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'startSoc': startSoc,
    'startOdoKm': startOdoKm,
    'plannedKm': plannedKm,
    'predictedUsePct': predictedUsePct,
    'riders': riders,
    'cargoKg': cargoKg,
    'rain': rain,
    'to': to,
  });

  static _ActiveTrip? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final started = DateTime.parse(data['startedAt'] as String);
      // A recording older than a day was forgotten.
      if (DateTime.now().difference(started) > const Duration(days: 1)) {
        return null;
      }
      double? number(Object? value) => (value as num?)?.toDouble();
      return _ActiveTrip(
        id: data['id'] as String,
        startedAt: started,
        startSoc: number(data['startSoc'])!,
        startOdoKm: number(data['startOdoKm']),
        plannedKm: number(data['plannedKm']),
        predictedUsePct: number(data['predictedUsePct']),
        riders: (data['riders'] as num?)?.toInt() ?? 1,
        cargoKg: number(data['cargoKg']) ?? 0,
        rain: data['rain'] == true,
        to: data['to'] as String? ?? '',
      );
    } on Object {
      return null;
    }
  }
}

class _SavedPlan {
  const _SavedPlan({
    required this.to,
    required this.distanceKm,
    required this.usePct,
    required this.verdict,
    required this.at,
  });

  final String to;
  final double distanceKm;
  final double usePct;
  final TripVerdict verdict;
  final DateTime at;

  String encode() => jsonEncode({
    'to': to,
    'km': distanceKm,
    'use': usePct,
    'verdict': verdict.name,
    'at': at.toIso8601String(),
  });

  static _SavedPlan? tryParse(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return _SavedPlan(
        to: data['to'] as String,
        distanceKm: (data['km'] as num).toDouble(),
        usePct: (data['use'] as num).toDouble(),
        verdict: TripVerdict.values.byName(data['verdict'] as String),
        at: DateTime.parse(data['at'] as String),
      );
    } on Object {
      return null;
    }
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final String placeholder;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: LuxeColors.platinumMid),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: LuxeText.label.copyWith(fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(
                    value.isEmpty ? placeholder : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: value.isEmpty ? LuxeColors.muted : LuxeColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    ),
  );
}

/// Battery journey bar: the full track, the share the trip will use (hatched
/// band from start to arrival) and the arrival level; fills once.
class _TripEnergyBar extends StatelessWidget {
  const _TripEnergyBar({
    required this.start,
    required this.end,
    required this.color,
  });

  final double start;
  final double end;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = (start.isFinite ? start : 0).clamp(0.0, 100.0) / 100;
    final e = (end.isFinite ? end : 0).clamp(0.0, 100.0) / 100;
    return Semantics(
      label:
          'Pin từ ${start.toStringAsFixed(0)}% xuống ${end.toStringAsFixed(0)}% khi tới nơi',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 22,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: luxeDuration(context, 1100),
              curve: LuxeMotion.enter,
              builder: (context, t, _) => CustomPaint(
                painter: _EnergyBarPainter(
                  start: s,
                  end: e,
                  color: color,
                  t: t,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            children: [
              Text(
                'Tới nơi ${end.toStringAsFixed(0)}%',
                style: LuxeText.label.copyWith(fontSize: 11, color: color),
              ),
              Text(
                'Xuất phát ${start.toStringAsFixed(0)}%',
                style: LuxeText.label.copyWith(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EnergyBarPainter extends CustomPainter {
  _EnergyBarPainter({
    required this.start,
    required this.end,
    required this.color,
    required this.t,
  });
  final double start, end, t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const h = 8.0;
    final y = (size.height - h) / 2;
    final track = RRect.fromLTRBR(
      0,
      y,
      size.width,
      y + h,
      const Radius.circular(4),
    );
    canvas.drawRRect(track, Paint()..color = const Color(0x1AFFFFFF));
    final arrive = size.width * end * t;
    if (arrive > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, y, arrive, y + h, const Radius.circular(4)),
        Paint()
          ..shader = LinearGradient(
            colors: [color.withValues(alpha: 0.6), color],
          ).createShader(Rect.fromLTWH(0, y, arrive, h)),
      );
    }
    final from = size.width * end;
    final to = size.width * (end + (start - end) * t);
    if (to > from) {
      final band = Rect.fromLTRB(from, y, to, y + h);
      canvas.drawRect(
        band,
        Paint()..color = LuxeColors.champagne.withValues(alpha: 0.22),
      );
      canvas.save();
      canvas.clipRect(band);
      final hatch = Paint()
        ..color = LuxeColors.champagne.withValues(alpha: 0.55)
        ..strokeWidth = 1;
      for (var x = from - h; x < to + h; x += 5) {
        canvas.drawLine(Offset(x, y + h), Offset(x + h, y), hatch);
      }
      canvas.restore();
    }
    final cx = size.width * end * t;
    canvas.drawCircle(
      Offset(cx, size.height / 2),
      4,
      Paint()..color = LuxeColors.platinumHi,
    );
  }

  @override
  bool shouldRepaint(_EnergyBarPainter old) =>
      old.t != t || old.start != start || old.end != end || old.color != color;
}

class _PlaceSearchSheet extends StatefulWidget {
  const _PlaceSearchSheet({required this.title, this.initialQuery});
  final String title;
  final String? initialQuery;
  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  List<PlaceSuggestion> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if ((widget.initialQuery ?? '').trim().length >= 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await TripRouteService.searchPlaces(_controller.text);
      if (mounted) {
        setState(() {
          _results = rows;
          _loading = false;
          if (rows.isEmpty) _error = 'Không thấy địa điểm phù hợp.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Không tìm được địa điểm. Thử từ khóa khác hoặc kiểm tra kết nối.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      4,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .68,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LuxeSheetHeader(eyebrow: 'Hành trình', title: widget.title),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: widget.initialQuery == null,
            onSubmitted: (_) => _search(),
            style: const TextStyle(color: LuxeColors.text),
            decoration: InputDecoration(
              hintText: 'Tên đường, địa điểm, quận...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'Tìm',
                onPressed: _search,
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                  color: LuxeColors.platinum,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const LinearProgressIndicator()
          else if (_error != null)
            LuxeNotice(
              message: _error!,
              icon: Icons.error_outline_rounded,
              color: LuxeColors.champagne,
            ),
          Expanded(
            child: _results.isEmpty && !_loading && _error == null
                ? const Center(
                    child: Text(
                      'Tìm địa điểm, hoặc nhấn giữ trên bản đồ để chọn điểm đến.',
                      textAlign: TextAlign.center,
                      style: LuxeText.body,
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (_, i) => Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.pop(context, _results[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          child: Row(
                            children: [
                              const LuxeMedallion(
                                icon: Icons.location_on_outlined,
                                size: 38,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  _results[i].name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: LuxeColors.text,
                                    fontSize: 13.5,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Dữ liệu địa điểm © OpenStreetMap contributors',
            textAlign: TextAlign.center,
            style: TextStyle(color: LuxeColors.dim, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _BatteryBadge extends StatelessWidget {
  const _BatteryBadge({
    required this.value,
    required this.known,
    required this.onTap,
  });
  final int value;
  final bool known;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: known
        ? 'Pin hiện tại $value phần trăm, chạm để sửa'
        : 'Chưa có mức pin, chạm để nhập',
    child: InkWell(
      key: const ValueKey('trip-battery'),
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: LuxeRing(
        value: known ? value / 100 : 0,
        size: 58,
        stroke: 5,
        color: !known
            ? LuxeColors.platinumLow
            : value < 20
            ? LuxeColors.danger
            : value < 40
            ? LuxeColors.champagne
            : LuxeColors.platinum,
        child: ExcludeSemantics(
          child: Text(
            known ? '$value%' : 'Nhập',
            style: const TextStyle(
              color: LuxeColors.text,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    ),
  );
}

class _MapPin extends StatelessWidget {
  final bool origin;
  const _MapPin({required this.origin});
  @override
  Widget build(BuildContext context) => origin
      ? Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: LuxeColors.platinum.withValues(alpha: 0.18),
            border: Border.all(
              color: LuxeColors.platinum.withValues(alpha: 0.5),
            ),
          ),
          child: Center(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: LuxeColors.platinumHi,
                border: Border.all(color: const Color(0xFF0B0C0E), width: 2),
              ),
            ),
          ),
        )
      : Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [LuxeColors.platinumHi, LuxeColors.platinumMid],
            ),
            border: Border.all(color: const Color(0xFF0B0C0E), width: 2),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
          ),
          child: const Icon(
            Icons.flag_rounded,
            color: Color(0xFF0B0C0E),
            size: 20,
          ),
        );
}

class _MapHint extends StatelessWidget {
  const _MapHint();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xD9121315),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: LuxeColors.hairline),
    ),
    child: const Text(
      'Nhấn giữ để chọn điểm đến',
      style: TextStyle(
        color: LuxeColors.muted,
        fontSize: 10.5,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _Metric({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => LuxeGlass(
    radius: 18,
    padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: LuxeColors.platinumMid),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: LuxeColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, maxLines: 2, style: LuxeText.label.copyWith(fontSize: 11)),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: LuxeText.label.copyWith(
      fontSize: 11,
      letterSpacing: 1.6,
      color: LuxeColors.platinumMid,
    ),
  );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: Row(
      children: [
        Expanded(child: Text(title, style: LuxeText.body)),
        LuxeSwitch(value: value, semanticLabel: title, onChanged: onChanged),
      ],
    ),
  );
}
