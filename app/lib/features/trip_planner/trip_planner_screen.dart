import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/services/sync_service.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../data/models/trip_prediction_model.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/services/trip_prediction_service.dart';
import '../../data/services/trip_route_service.dart';

class TripPlannerScreen extends ConsumerStatefulWidget {
  final VehicleModel vehicle;

  const TripPlannerScreen({super.key, required this.vehicle});

  @override
  ConsumerState<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends ConsumerState<TripPlannerScreen> {
  final _mapController = MapController();
  final _payloadController = TextEditingController(text: '75');

  LatLng? _origin;
  LatLng? _destination;
  String _destinationName = '';
  PlannedRoute? _route;
  TripPredictionModel? _prediction;
  List<TripPredictionModel> _history = const [];

  bool _locating = true;
  bool _routing = false;
  bool _predicting = false;
  bool _showConditions = false;
  String _weather = 'sunny';
  String _drivingStyle = 'normal';
  double _temperature = 30;
  double _elevation = 0;

  @override
  void initState() {
    super.initState();
    _locate();
    _loadHistory();
  }

  @override
  void dispose() {
    _payloadController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final rows = await TripPredictionService.getPredictionHistory(
      vehicleId: widget.vehicle.vehicleId,
      limit: 3,
    );
    if (mounted) setState(() => _history = rows);
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Hãy bật dịch vụ vị trí');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Ứng dụng cần quyền vị trí để lập tuyến');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _origin = point;
        _locating = false;
      });
      _mapController.move(point, 15);
    } catch (e) {
      if (!mounted) return;
      setState(() => _locating = false);
      _message(
        'Chưa thể lấy vị trí. Kiểm tra quyền vị trí hoặc nhập điểm đi.',
        error: true,
      );
    }
  }

  Future<void> _selectDestination(PlaceSuggestion place) async {
    setState(() {
      _destination = place.point;
      _destinationName = place.name;
      _prediction = null;
      _routing = true;
    });
    await _calculateRoute();
  }

  Future<void> _selectPoint(LatLng point) async {
    await _selectDestination(
      PlaceSuggestion(
        name:
            '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
        point: point,
      ),
    );
  }

  Future<void> _calculateRoute() async {
    final start = _origin;
    final end = _destination;
    if (start == null || end == null) return;
    try {
      final route = await TripRouteService.route(start, end);
      if (!mounted) return;
      setState(() {
        _route = route;
        _routing = false;
      });
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([start, end]),
          padding: const EdgeInsets.fromLTRB(36, 96, 36, 54),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _routing = false);
      _message(
        'Chưa thể lập lộ trình. Kiểm tra điểm đi, điểm đến và kết nối mạng.',
        error: true,
      );
    }
  }

  Future<void> _searchDestination() async {
    final place = await showLuxeSheet<PlaceSuggestion>(
      context,
      builder: (_) => const _PlaceSearchSheet(),
    );
    if (place != null) await _selectDestination(place);
  }

  ({double avg, double max, double avgAcc, double maxAcc, double minAcc})
  get _drivingValues {
    switch (_drivingStyle) {
      case 'eco':
        return (avg: 25, max: 42, avgAcc: -0.05, maxAcc: 1.2, minAcc: -1.4);
      case 'sport':
        return (avg: 42, max: 70, avgAcc: 0.12, maxAcc: 3.5, minAcc: -4.0);
      default:
        return (avg: 32, max: 55, avgAcc: 0, maxAcc: 2.2, minAcc: -2.5);
    }
  }

  Future<void> _predict() async {
    final route = _route;
    if (route == null) {
      _message('Hãy chọn điểm đến trước', error: true);
      return;
    }
    final payload = double.tryParse(_payloadController.text);
    if (payload == null || payload < 20 || payload > 300) {
      _message('Tải trọng phải từ 20 đến 300 kg', error: true);
      return;
    }
    setState(() => _predicting = true);
    try {
      final driving = _drivingValues;
      final weatherCode = _weather == 'rain'
          ? 0.0
          : _weather == 'cloudy'
          ? 0.5
          : 1.0;
      final prediction = await TripPredictionService.predictTrip(
        vehicleId: widget.vehicle.vehicleId,
        from: 'Vị trí hiện tại',
        to: _destinationName,
        distance: route.distanceKm,
        vehicle: widget.vehicle,
        weather: weatherCode,
        temperature: _temperature,
        riderWeight: payload,
        durationMin: route.durationMin,
        averageSpeedKmh: driving.avg,
        maxSpeedKmh: driving.max,
        averageAcceleration: driving.avgAcc,
        maxAcceleration: driving.maxAcc,
        minAcceleration: driving.minAcc,
        elevationChangeM: _elevation,
      );
      await SyncService().syncTripPredictionToWeb(prediction.id);
      if (!mounted) return;
      setState(() {
        _prediction = prediction;
        _predicting = false;
      });
      await _loadHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() => _predicting = false);
      _message(
        'Chưa thể dự đoán lúc này. Kiểm tra kết nối rồi thử lại.',
        error: true,
      );
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_rounded,
              size: 18,
              color: error ? LuxeColors.champagne : LuxeColors.emerald,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _origin ?? const LatLng(10.8231, 106.6297);
    return LuxeScaffold(
      appBar: Navigator.canPop(context) ? const LuxeAppBar() : null,
      body: SafeArea(
        top: !Navigator.canPop(context),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(
              child: LuxeReveal(index: 1, child: _map(center)),
            ),
            SliverToBoxAdapter(
              child: LuxeReveal(index: 2, child: _routeSummary()),
            ),
            SliverToBoxAdapter(
              child: LuxeReveal(index: 3, child: _conditions()),
            ),
            SliverToBoxAdapter(child: LuxeReveal(index: 4, child: _action())),
            if (_prediction != null)
              SliverToBoxAdapter(
                child: LuxeReveal(
                  key: ValueKey(_prediction!.id),
                  child: _result(_prediction!),
                ),
              ),
            if (_history.isNotEmpty) SliverToBoxAdapter(child: _recent()),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
    child: LuxeReveal(
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HÀNH TRÌNH', style: LuxeText.eyebrow),
                SizedBox(height: 6),
                Text('Lập kế hoạch chuyến đi', style: LuxeText.title),
                SizedBox(height: 4),
                Text(
                  'Tuyến đường thật · dự đoán bằng AI',
                  style: LuxeText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _BatteryBadge(value: widget.vehicle.currentBattery),
        ],
      ),
    ),
  );

  Widget _map(LatLng center) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: LuxeColors.hairlineStrong),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: SizedBox(
          height: 320,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 14,
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
                    userAgentPackageName: 'com.vinfast.vinfast_battery',
                    // Night tiles so the map sits inside the LUXE palette.
                    tileBuilder: darkModeTileBuilder,
                  ),
                  if (_route != null)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _route!.geometry,
                          strokeWidth: 12,
                          color: LuxeColors.emerald.withValues(alpha: 0.18),
                        ),
                        Polyline(
                          points: _route!.geometry,
                          strokeWidth: 4,
                          color: LuxeColors.emerald,
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
              // Soft vignette so map edges melt into the glass frame.
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 1.1,
                      colors: [Color(0x00000000), Color(0x66050506)],
                      stops: [0.65, 1.0],
                    ),
                  ),
                  child: SizedBox.expand(),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: _searchDestination,
                    child: Ink(
                      decoration: BoxDecoration(
                        color: const Color(0xEB121315),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: LuxeColors.hairlineStrong),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search_rounded,
                            color: LuxeColors.emerald,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _destinationName.isEmpty
                                  ? 'Bạn muốn đi đâu?'
                                  : _destinationName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _destinationName.isEmpty
                                    ? LuxeColors.muted
                                    : LuxeColors.text,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: LuxeColors.dim,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: Material(
                  color: const Color(0xEB121315),
                  shape: const CircleBorder(
                    side: BorderSide(color: LuxeColors.hairlineStrong),
                  ),
                  child: IconButton(
                    tooltip: 'Vị trí của tôi',
                    onPressed: _locating ? null : _locate,
                    icon: _locating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.my_location_rounded,
                            color: LuxeColors.emerald,
                          ),
                  ),
                ),
              ),
              if (_routing)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x88050506),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              const Positioned(left: 12, bottom: 16, child: _MapHint()),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _routeSummary() {
    final route = _route;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              label: 'Quãng đường',
              icon: Icons.straighten_rounded,
              value: route == null
                  ? '—'
                  : '${route.distanceKm.toStringAsFixed(1)} km',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Metric(
              label: 'Thời gian',
              icon: Icons.schedule_rounded,
              value: route == null ? '—' : '${route.durationMin.round()} phút',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Metric(
              label: 'Pin hiện tại',
              icon: Icons.battery_charging_full_rounded,
              value: '${widget.vehicle.currentBattery}%',
            ),
          ),
        ],
      ),
    );
  }

  Widget _conditions() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
    child: LuxeGlass(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _showConditions = !_showConditions),
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Row(
                children: [
                  const LuxeMedallion(icon: Icons.tune_rounded, size: 36),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Điều kiện chuyến đi',
                      style: TextStyle(
                        color: LuxeColors.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    '${_temperature.round()}° · ${_payloadController.text} kg',
                    style: LuxeText.caption.copyWith(fontSize: 12),
                  ),
                  AnimatedRotation(
                    turns: _showConditions ? .5 : 0,
                    duration: luxeDuration(context, 260),
                    curve: LuxeMotion.enter,
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: LuxeColors.platinumMid,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: luxeDuration(context, 320),
            curve: LuxeMotion.enter,
            alignment: Alignment.topCenter,
            child: _showConditions
                ? _conditionBody()
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    ),
  );

  Widget _conditionBody() => Padding(
    padding: const EdgeInsets.fromLTRB(2, 6, 4, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('Phong cách lái'),
        const SizedBox(height: 8),
        LuxeSegmented<String>(
          segments: const [
            ('eco', 'Êm'),
            ('normal', 'Thường'),
            ('sport', 'Nhanh'),
          ],
          selected: _drivingStyle,
          onChanged: (v) => setState(() => _drivingStyle = v),
        ),
        const SizedBox(height: 16),
        const _SectionLabel('Thời tiết'),
        const SizedBox(height: 8),
        LuxeSegmented<String>(
          segments: const [
            ('sunny', 'Nắng'),
            ('cloudy', 'Mây'),
            ('rain', 'Mưa'),
          ],
          selected: _weather,
          onChanged: (v) => setState(() => _weather = v),
        ),
        const SizedBox(height: 12),
        _SliderLine(
          icon: Icons.thermostat_rounded,
          label: 'Nhiệt độ',
          value: _temperature,
          min: 0,
          max: 45,
          suffix: '°C',
          onChanged: (v) => setState(() => _temperature = v),
        ),
        _SliderLine(
          icon: Icons.terrain_rounded,
          label: 'Chênh cao',
          value: _elevation,
          min: -100,
          max: 300,
          suffix: ' m',
          onChanged: (v) => setState(() => _elevation = v),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _payloadController,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: LuxeColors.text),
          decoration: const InputDecoration(
            labelText: 'Tổng tải trọng (người + hành lý)',
            suffixText: 'kg',
            prefixIcon: Icon(Icons.scale_rounded, size: 20),
          ),
        ),
      ],
    ),
  );

  Widget _action() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
    child: FilledButton.icon(
      onPressed: _route == null || _predicting ? null : _predict,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      icon: _predicting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF0B0C0E),
              ),
            )
          : const Icon(Icons.auto_awesome_rounded),
      label: Text(
        _predicting ? 'AI đang tính toán...' : 'Dự đoán pin tiêu thụ',
      ),
    ),
  );

  Widget _result(TripPredictionModel p) {
    final color = p.isSafe ? LuxeColors.emerald : LuxeColors.champagne;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: LuxeGlass(
        selected: p.isSafe,
        radius: 24,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AI ƯỚC TÍNH HAO HỤT',
                        style: LuxeText.eyebrow,
                      ),
                      const SizedBox(height: 6),
                      LuxeCountUp(
                        value: p.consumption.isFinite ? p.consumption : 0,
                        decimals: 1,
                        suffix: '%',
                        style: TextStyle(
                          color: color,
                          fontSize: 44,
                          height: 1,
                          fontWeight: FontWeight.w200,
                          letterSpacing: -1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Còn lại',
                      style: LuxeText.label.copyWith(fontSize: 11),
                    ),
                    Text(
                      '${p.endBattery.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: LuxeColors.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            _TripEnergyBar(
              start: widget.vehicle.currentBattery.toDouble(),
              end: p.endBattery,
              color: color,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  p.isSafe
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                  color: color,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.safetyText,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
            if (p.reasoningText?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                p.reasoningText!,
                style: LuxeText.caption.copyWith(fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _recent() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LuxeSectionLabel('Dự đoán gần đây'),
        LuxeSettingsGroup(
          children: [
            for (final item in _history)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                child: Row(
                  children: [
                    const LuxeMedallion(
                      icon: Icons.route_rounded,
                      accent: LuxeColors.emerald,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.to,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: LuxeColors.text,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item.distance.toStringAsFixed(1)} km · ${item.duration} phút',
                            style: LuxeText.caption.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '-${item.consumption.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: LuxeColors.emerald,
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

/// Battery journey bar: the full track, the share the trip will use (glowing
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
    // Remaining at arrival.
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
    // Energy the trip uses: a hatched champagne band.
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
    // Arrival marker.
    final cx = size.width * end * t;
    canvas.drawCircle(
      Offset(cx, size.height / 2),
      7,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
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
  const _PlaceSearchSheet();
  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  final _controller = TextEditingController();
  List<PlaceSuggestion> _results = const [];
  bool _loading = false;
  String? _error;

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
        });
      }
    } catch (e) {
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
          const LuxeSheetHeader(eyebrow: 'Hành trình', title: 'Chọn điểm đến'),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
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
                  color: LuxeColors.emerald,
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
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (_, i) => LuxeReveal(
                  index: i,
                  child: Material(
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
                              accent: LuxeColors.emerald,
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
            ),
          if (_results.isEmpty && !_loading && _error == null)
            const Expanded(
              child: Center(
                child: Text(
                  'Tìm địa điểm hoặc nhấn giữ trên bản đồ để chọn nhanh.',
                  textAlign: TextAlign.center,
                  style: LuxeText.body,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _BatteryBadge extends StatelessWidget {
  final int value;
  const _BatteryBadge({required this.value});
  @override
  Widget build(BuildContext context) => LuxeRing(
    value: value / 100,
    size: 58,
    stroke: 5,
    color: value < 20
        ? LuxeColors.danger
        : value < 40
        ? LuxeColors.champagne
        : LuxeColors.emerald,
    semanticLabel: 'Pin hiện tại $value phần trăm',
    child: ExcludeSemantics(
      child: Text(
        '$value%',
        style: const TextStyle(
          color: LuxeColors.text,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
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
            color: LuxeColors.emerald.withValues(alpha: 0.18),
            border: Border.all(
              color: LuxeColors.emerald.withValues(alpha: 0.5),
            ),
          ),
          child: Center(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: LuxeColors.emerald,
                border: Border.all(color: LuxeColors.platinumHi, width: 2),
                boxShadow: const [
                  BoxShadow(color: LuxeColors.emeraldGlow, blurRadius: 10),
                ],
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
      'Nhấn giữ để chọn điểm',
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

class _SliderLine extends StatelessWidget {
  final IconData icon;
  final String label, suffix;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  const _SliderLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: LuxeColors.platinumMid, size: 18),
      const SizedBox(width: 8),
      SizedBox(
        width: 74,
        child: Text(label, style: LuxeText.caption.copyWith(fontSize: 12)),
      ),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          label: '${value.round()}$suffix',
          onChanged: onChanged,
        ),
      ),
      SizedBox(
        width: 52,
        child: Text(
          '${value.round()}$suffix',
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: LuxeColors.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ],
  );
}
