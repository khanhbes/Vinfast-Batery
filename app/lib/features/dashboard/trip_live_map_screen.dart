import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_popup.dart';
import '../../data/services/trip_tracking_service.dart';
import '../../data/services/background_service_config.dart';

/// Màn hình map full-screen hiển thị vị trí realtime khi đang tracking chuyến đi.
class TripLiveMapScreen extends StatefulWidget {
  const TripLiveMapScreen({super.key});

  @override
  State<TripLiveMapScreen> createState() => _TripLiveMapScreenState();
}

class _TripLiveMapScreenState extends State<TripLiveMapScreen> {
  final _tripService = TripTrackingService();
  final _mapController = MapController();
  StreamSubscription<TripLiveSnapshot>? _snapshotSub;
  Timer? _uiTimer;

  TripLiveSnapshot _snapshot = const TripLiveSnapshot();
  bool _followCamera = true;
  bool _mapReady = false;
  double _lastKnownZoom = 16;

  /// Watchdog: thời điểm nhận GPS update cuối cùng
  DateTime _lastGpsUpdate = DateTime.now();
  bool _isGpsStale = false;
  bool _isReloadingGps = false;
  static const _staleThreshold = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _snapshot = _tripService.currentSnapshot;

    _snapshotSub = _tripService.snapshotStream.listen((snap) {
      if (!mounted) return;
      final posChanged = snap.latitude != _snapshot.latitude ||
          snap.longitude != _snapshot.longitude;
      if (posChanged && snap.latitude != null) {
        _lastGpsUpdate = DateTime.now();
        _isGpsStale = false;
      }
      setState(() => _snapshot = snap);

      if (_followCamera && snap.latitude != null && snap.longitude != null) {
        _safeMoveMap(LatLng(snap.latitude!, snap.longitude!));
      }
    });

    // Timer fallback: refresh elapsed + stale watchdog mỗi giây
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_tripService.isTracking) return;
      final stale = DateTime.now().difference(_lastGpsUpdate) > _staleThreshold;
      setState(() {
        _snapshot = _tripService.currentSnapshot;
        _isGpsStale = stale;
      });
    });
  }

  @override
  void dispose() {
    _snapshotSub?.cancel();
    _uiTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPosition = _snapshot.latitude != null && _snapshot.longitude != null;
    final center = hasPosition
        ? LatLng(_snapshot.latitude!, _snapshot.longitude!)
        : const LatLng(21.0285, 105.8542); // Hà Nội default

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Map ──
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 16,
              onMapReady: () {
                _mapReady = true;
              },
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture) _followCamera = false;
                _lastKnownZoom = pos.zoom;
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.vinfast.battery',
              ),
              // Polyline route
              if (_snapshot.routePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _snapshot.routePoints,
                      strokeWidth: 4,
                      color: AppColors.info,
                    ),
                  ],
                ),
              // Current position marker
              if (hasPosition)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(_snapshot.latitude!, _snapshot.longitude!),
                      width: 40,
                      height: 40,
                      child: _CurrentPositionMarker(),
                    ),
                  ],
                ),
            ],
          ),

          // ── Top Safe Area: Back button ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: _CircleButton(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),

          // ── Re-center button ──
          if (!_followCamera)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 16,
              child: _CircleButton(
                icon: Icons.my_location_rounded,
                color: AppColors.info,
                onTap: () {
                  _followCamera = true;
                  if (hasPosition) {
                    _safeMoveMap(LatLng(_snapshot.latitude!, _snapshot.longitude!));
                  }
                },
              ),
            ),

          // ── GPS stale warning banner ──
          if (_isGpsStale)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.gps_off_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'GPS mất tín hiệu',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _isReloadingGps ? null : _reloadGps,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _isReloadingGps
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Reload GPS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Bottom overlay: Stats + Stop button ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomPanel(
              snapshot: _snapshot,
              elapsedText: _tripService.elapsedText,
              payloadLabel: _tripService.payload.label,
              onStop: _confirmStopTrip,
            ),
          ),
        ],
      ),
    );
  }

  /// Force reload GPS: lấy vị trí hiện tại + reset watchdog
  Future<void> _reloadGps() async {
    setState(() => _isReloadingGps = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _lastGpsUpdate = DateTime.now();
      _tripService.injectPosition(pos);
      if (mounted) {
        setState(() {
          _isGpsStale = false;
          _isReloadingGps = false;
          _snapshot = _tripService.currentSnapshot;
        });
        if (_followCamera) {
          _safeMoveMap(LatLng(pos.latitude, pos.longitude));
        }
      }
    } catch (e) {
      debugPrint('❌ Reload GPS failed: $e');
      AppPopup.showError('Reload GPS thất bại: $e');
      if (mounted) setState(() => _isReloadingGps = false);
    }
  }

  void _safeMoveMap(LatLng target) {
    if (!_mapReady) return;
    try {
      _mapController.move(target, _lastKnownZoom);
    } catch (e) {
      debugPrint('Map move failed: $e');
    }
  }

  Future<void> _confirmStopTrip() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Kết thúc chuyến đi?',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ConfirmRow(label: 'Quãng đường', value: '${_snapshot.totalDistance.toStringAsFixed(1)} km'),
            _ConfirmRow(label: 'Pin tiêu thụ', value: '-${_snapshot.batteryConsumed}%'),
            _ConfirmRow(label: 'Thời gian', value: _tripService.elapsedText),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Tiếp tục đi', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Kết thúc', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await _tripService.stopTrip();
      BackgroundServiceConfig.sendCommand('stopTrip');
      if (mounted) Navigator.of(context).pop(true); // pop với result=true báo Dashboard refresh
    } catch (e) {
      AppPopup.showError('Kết thúc chuyến đi thất bại: $e');
    }
  }
}

// =============================================================================
// Bottom Panel — Stats overlay + Stop button
// =============================================================================

class _BottomPanel extends StatelessWidget {
  final TripLiveSnapshot snapshot;
  final String elapsedText;
  final String payloadLabel;
  final VoidCallback onStop;

  const _BottomPanel({
    required this.snapshot,
    required this.elapsedText,
    required this.payloadLabel,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background.withValues(alpha: 0.0),
            AppColors.background.withValues(alpha: 0.85),
            AppColors.background,
          ],
          stops: const [0.0, 0.3, 0.5],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Stats card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.navigation_rounded, color: AppColors.info, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Đang di chuyển 🛵',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            payloadLabel,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      elapsedText,
                      style: const TextStyle(
                        color: AppColors.info,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatColumn(
                      label: 'Quãng đường',
                      value: '${snapshot.totalDistance.toStringAsFixed(1)} km',
                      color: AppColors.info,
                    ),
                    _StatColumn(
                      label: 'Pin',
                      value: '${snapshot.currentBattery}%',
                      color: AppColors.primary,
                    ),
                    _StatColumn(
                      label: 'Tiêu thụ',
                      value: '-${snapshot.batteryConsumed}%',
                      color: AppColors.warning,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Stop button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onStop,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
              icon: const Icon(Icons.stop_rounded, size: 22),
              label: const Text(
                'Kết thúc chuyến đi',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatColumn({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
        ),
      ],
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;

  const _ConfirmRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _CurrentPositionMarker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.info.withValues(alpha: 0.2),
      ),
      child: Center(
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.info,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppColors.info.withValues(alpha: 0.4),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: color ?? AppColors.textSecondary, size: 20),
      ),
    );
  }
}
