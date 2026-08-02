import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/services/sync_service.dart';
import '../../core/theme/app_colors.dart';
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
      _message(e.toString().replaceFirst('Exception: ', ''), error: true);
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
      _message(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _searchDestination() async {
    final place = await showModalBottomSheet<PlaceSuggestion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      useSafeArea: true,
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
      _message('Không thể dự đoán: $e', error: true);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.errorDark : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _origin ?? const LatLng(10.8231, 106.6297);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(child: _map(center)),
            SliverToBoxAdapter(child: _routeSummary()),
            SliverToBoxAdapter(child: _conditions()),
            SliverToBoxAdapter(child: _action()),
            if (_prediction != null)
              SliverToBoxAdapter(child: _result(_prediction!)),
            if (_history.isNotEmpty) SliverToBoxAdapter(child: _recent()),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
    child: Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lập kế hoạch chuyến đi',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Tuyến đường thật · dự đoán bằng AI',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        _BatteryBadge(value: widget.vehicle.currentBattery),
      ],
    ),
  ).animate().fadeIn(duration: 300.ms).slideY(begin: -.08);

  Widget _map(LatLng center) => Container(
    height: 310,
    margin: const EdgeInsets.symmetric(horizontal: 16),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
    child: Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 14,
            onLongPress: (_, point) => _selectPoint(point),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.vinfast.vinfast_battery',
            ),
            if (_route != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _route!.geometry,
                    strokeWidth: 5,
                    color: AppColors.vinfastBlue,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (_origin != null)
                  Marker(
                    point: _origin!,
                    width: 38,
                    height: 38,
                    child: const _MapPin(
                      icon: Icons.my_location_rounded,
                      color: AppColors.vinfastBlue,
                    ),
                  ),
                if (_destination != null)
                  Marker(
                    point: _destination!,
                    width: 42,
                    height: 42,
                    child: const _MapPin(
                      icon: Icons.flag_rounded,
                      color: AppColors.error,
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Material(
            color: AppColors.card.withValues(alpha: .94),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _searchDestination,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      color: AppColors.primary,
                      size: 21,
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
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textTertiary,
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
          child: FloatingActionButton.small(
            heroTag: 'trip_location',
            onPressed: _locating ? null : _locate,
            backgroundColor: AppColors.card,
            foregroundColor: AppColors.primary,
            child: _locating
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
          ),
        ),
        if (_routing)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x55000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        const Positioned(left: 12, bottom: 12, child: _MapHint()),
      ],
    ),
  ).animate().fadeIn(delay: 80.ms, duration: 400.ms);

  Widget _routeSummary() {
    final route = _route;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              label: 'QUÃNG ĐƯỜNG',
              value: route == null
                  ? '—'
                  : '${route.distanceKm.toStringAsFixed(1)} km',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Metric(
              label: 'THỜI GIAN',
              value: route == null ? '—' : '${route.durationMin.round()} phút',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Metric(
              label: 'PIN HIỆN TẠI',
              value: '${widget.vehicle.currentBattery}%',
            ),
          ),
        ],
      ),
    );
  }

  Widget _conditions() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
    child: Column(
      children: [
        InkWell(
          onTap: () => setState(() => _showConditions = !_showConditions),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.tune_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Điều kiện chuyến đi',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${_temperature.round()}° · ${_payloadController.text} kg',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                AnimatedRotation(
                  turns: _showConditions ? .5 : 0,
                  duration: 200.ms,
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: 220.ms,
          crossFadeState: _showConditions
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: _conditionBody(),
        ),
      ],
    ),
  );

  Widget _conditionBody() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('PHONG CÁCH LÁI'),
        const SizedBox(height: 8),
        Row(
          children: [
            _Choice(
              'eco',
              'Êm',
              Icons.eco_rounded,
              _drivingStyle,
              (v) => setState(() => _drivingStyle = v),
            ),
            _Choice(
              'normal',
              'Thường',
              Icons.route_rounded,
              _drivingStyle,
              (v) => setState(() => _drivingStyle = v),
            ),
            _Choice(
              'sport',
              'Nhanh',
              Icons.bolt_rounded,
              _drivingStyle,
              (v) => setState(() => _drivingStyle = v),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _SectionLabel('THỜI TIẾT'),
        const SizedBox(height: 8),
        Row(
          children: [
            _Choice(
              'sunny',
              'Nắng',
              Icons.wb_sunny_outlined,
              _weather,
              (v) => setState(() => _weather = v),
            ),
            _Choice(
              'cloudy',
              'Mây',
              Icons.cloud_outlined,
              _weather,
              (v) => setState(() => _weather = v),
            ),
            _Choice(
              'rain',
              'Mưa',
              Icons.water_drop_outlined,
              _weather,
              (v) => setState(() => _weather = v),
            ),
          ],
        ),
        const SizedBox(height: 14),
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
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Tổng tải trọng (người + hành lý)',
            suffixText: 'kg',
            prefixIcon: const Icon(Icons.scale_rounded),
            filled: true,
            fillColor: AppColors.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _action() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
    child: SizedBox(
      height: 56,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _route == null || _predicting ? null : _predict,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.vinfastBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: _predicting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.auto_awesome_rounded),
        label: Text(
          _predicting ? 'AI đang tính toán...' : 'Dự đoán pin tiêu thụ',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
    ),
  );

  Widget _result(TripPredictionModel p) {
    final color = p.isSafe ? AppColors.success : AppColors.warning;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${p.consumption.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: color,
                        fontSize: 42,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Còn lại',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '${p.endBattery.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: p.endBattery / 100,
              minHeight: 8,
              backgroundColor: AppColors.surfaceVariant,
              color: color,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                p.isSafe ? Icons.check_circle_rounded : Icons.warning_rounded,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.safetyText,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (p.reasoningText?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              p.reasoningText!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: .08);
  }

  Widget _recent() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('DỰ ĐOÁN GẦN ĐÂY'),
        const SizedBox(height: 12),
        for (final item in _history)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.route_rounded,
                    color: AppColors.primary,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.to,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${item.distance.toStringAsFixed(1)} km · ${item.duration} phút',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '-${item.consumption.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
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
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .68,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Chọn điểm đến',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            onSubmitted: (_) => _search(),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Tên đường, địa điểm, quận...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                onPressed: _search,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const LinearProgressIndicator()
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.error))
          else
            Expanded(
              child: ListView.separated(
                itemCount: _results.length,
                separatorBuilder: (_, _) =>
                    const Divider(color: AppColors.border),
                itemBuilder: (_, i) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    _results[i].name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, _results[i]),
                ),
              ),
            ),
          if (_results.isEmpty && !_loading && _error == null)
            const Expanded(
              child: Center(
                child: Text(
                  'Tìm địa điểm hoặc nhấn giữ trên bản đồ để chọn nhanh.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, height: 1.5),
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.battery_charging_full_rounded,
          color: AppColors.success,
          size: 17,
        ),
        const SizedBox(width: 5),
        Text(
          '$value%',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

class _MapPin extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _MapPin({required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
    ),
    child: Icon(icon, color: Colors.white, size: 18),
  );
}

class _MapHint extends StatelessWidget {
  const _MapHint();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.card.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(9),
    ),
    child: const Text(
      'Nhấn giữ để chọn điểm',
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 9,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: .7,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: AppColors.textTertiary,
      fontSize: 9,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
    ),
  );
}

class _Choice extends StatelessWidget {
  final String value, label, selected;
  final IconData icon;
  final ValueChanged<String> onChanged;
  const _Choice(
    this.value,
    this.label,
    this.icon,
    this.selected,
    this.onChanged,
  );
  @override
  Widget build(BuildContext context) {
    final active = value == selected;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: 180.ms,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primaryContainer
                  : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: active ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: active
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
      Icon(icon, color: AppColors.textSecondary, size: 18),
      const SizedBox(width: 8),
      SizedBox(
        width: 74,
        child: Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          activeColor: AppColors.primary,
          onChanged: onChanged,
        ),
      ),
      SizedBox(
        width: 52,
        child: Text(
          '${value.round()}$suffix',
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}
