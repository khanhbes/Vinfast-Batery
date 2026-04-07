import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/trip_log_model.dart';
import '../../data/services/route_prediction_service.dart';
import '../../data/repositories/trip_log_repository.dart';
import '../home/home_screen.dart';

/// Card dự báo tiêu hao pin lộ trình (mock distance)
class RoutePredictionCard extends ConsumerStatefulWidget {
  const RoutePredictionCard({super.key});

  @override
  ConsumerState<RoutePredictionCard> createState() => _RoutePredictionCardState();
}

class _RoutePredictionCardState extends ConsumerState<RoutePredictionCard> {
  final _destinationCtrl = TextEditingController();
  final _distanceCtrl = TextEditingController();
  PayloadType _payload = PayloadType.onePerson;
  RoutePredictionResult? _result;
  bool _expanded = false;

  @override
  void dispose() {
    _destinationCtrl.dispose();
    _distanceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.info.withValues(alpha: 0.08),
            AppColors.card,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          // Header
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.route_rounded,
                        color: AppColors.info, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dự báo lộ trình',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            )),
                        Text('Kiểm tra pin có đủ đi không',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            )),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more_rounded,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),

          // Expandable content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildForm(),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 500.ms);
  }

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // Destination
          TextField(
            controller: _destinationCtrl,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Điểm đến (VD: Đại học Bách Khoa)',
              hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13),
              prefixIcon: const Icon(Icons.place_rounded,
                  color: AppColors.textSecondary, size: 18),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Distance
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _distanceCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Khoảng cách (km)',
                    hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13),
                    prefixIcon: const Icon(Icons.straighten_rounded,
                        color: AppColors.textSecondary, size: 18),
                    suffixText: 'km',
                    suffixStyle: const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Payload
          Row(
            children: [
              const Icon(Icons.people_alt_rounded,
                  color: AppColors.textSecondary, size: 16),
              const SizedBox(width: 8),
              ...PayloadType.values.map((p) {
                final sel = p == _payload;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _payload = p;
                      _result = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.info.withValues(alpha: 0.15) : AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: sel ? AppColors.info : AppColors.border),
                      ),
                      child: Text(p.label,
                        style: TextStyle(
                          color: sel ? AppColors.info : AppColors.textSecondary,
                          fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                );
              }),
              const Spacer(),
              // Predict button
              GestureDetector(
                onTap: _predict,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.info, Color(0xFF64B5F6)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Dự báo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      )),
                ),
              ),
            ],
          ),

          // Result
          if (_result != null) ...[
            const SizedBox(height: 16),
            _buildResult(_result!),
          ],
        ],
      ),
    );
  }

  void _predict() async {
    final distance = double.tryParse(_distanceCtrl.text);
    if (distance == null || distance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nhập khoảng cách hợp lệ (km)'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final vehicleId = ref.read(selectedVehicleIdProvider);
    final vehicle = await ref.read(vehicleProvider(vehicleId).future);
    if (vehicle == null) return;

    List<TripLogModel> trips = [];
    try {
      trips = await ref.read(tripLogRepositoryProvider).getRecentTrips(vehicleId);
    } catch (_) {}

    final result = RoutePredictionService.predict(
      distanceKm: distance,
      currentBattery: vehicle.currentBattery,
      payload: _payload,
      trips: trips,
      defaultEfficiency: vehicle.defaultEfficiency,
    );

    setState(() => _result = result);
  }

  Widget _buildResult(RoutePredictionResult result) {
    final color = result.isEnough ? AppColors.primaryGreen : AppColors.error;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Status
          Row(
            children: [
              Icon(
                result.isEnough
                    ? Icons.check_circle_rounded
                    : Icons.warning_rounded,
                color: color,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.isEnough
                      ? 'Đủ pin để đi ${result.distanceKm.toStringAsFixed(1)} km!'
                      : 'Không đủ pin! Cần sạc thêm.',
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Details
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem('Tiêu hao', '-${result.estimatedBatteryDrain}%', AppColors.warning),
              _statItem('Còn lại', '${result.remainingBattery}%',
                  result.remainingBattery >= 20 ? AppColors.primaryGreen : AppColors.error),
              _statItem('Hiệu suất', '${result.efficiencyUsed.toStringAsFixed(2)} km/%',
                  AppColors.info),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
        Text(label,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
      ],
    );
  }
}
