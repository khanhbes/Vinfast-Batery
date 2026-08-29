import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/vehicle_model.dart';

class RangePredictionCard extends StatefulWidget {
  final VehicleModel vehicle;
  const RangePredictionCard({super.key, required this.vehicle});
  @override
  State<RangePredictionCard> createState() => _RangePredictionCardState();
}

class _RangePredictionCardState extends State<RangePredictionCard> {
  double? range, low, high, confidence;
  bool loading = true, offline = false;
  @override
  void initState() {
    super.initState();
    predict();
  }

  @override
  void didUpdateWidget(covariant RangePredictionCard old) {
    super.didUpdateWidget(old);
    if (old.vehicle.currentBattery != widget.vehicle.currentBattery ||
        old.vehicle.stateOfHealth != widget.vehicle.stateOfHealth)
      predict();
  }

  Future<void> predict() async {
    if (mounted) setState(() => loading = true);
    final v = widget.vehicle;
    final response = await ApiService().predictRemainingRange(
      batteryPercent: v.currentBattery,
      stateOfHealth: v.stateOfHealth,
      baseEfficiencyKmPerPercent: v.defaultEfficiency,
    );
    final data = response['data'] is Map
        ? Map<String, dynamic>.from(response['data'])
        : response;
    if (!mounted) return;
    if (response['success'] == true && data['estimatedRangeKm'] != null) {
      setState(() {
        range = (data['estimatedRangeKm'] as num).toDouble();
        low = (data['rangeLowKm'] as num).toDouble();
        high = (data['rangeHighKm'] as num).toDouble();
        confidence = (data['confidence'] as num).toDouble();
        offline = false;
        loading = false;
      });
    } else {
      final fallback =
          (v.currentBattery - 5).clamp(0, 100) *
          v.defaultEfficiency *
          (v.stateOfHealth / 100);
      setState(() {
        range = fallback;
        low = fallback * .88;
        high = fallback * 1.12;
        confidence = .72;
        offline = true;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = widget.vehicle.currentBattery.clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF071B2B),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.route_rounded,
                  color: AppColors.success,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QUÃNG ĐƯỜNG CÒN LẠI',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Dự đoán theo điều kiện thực tế',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (offline)
                const Tooltip(
                  message: 'Dự đoán dự phòng trên thiết bị',
                  child: Icon(
                    Icons.cloud_off_rounded,
                    color: Colors.white54,
                    size: 19,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 7,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation(AppColors.success),
            ),
          ),
          const SizedBox(height: 18),
          if (loading)
            const SizedBox(
              height: 56,
              child: Align(
                alignment: Alignment.centerLeft,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.success,
                ),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  range!.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    height: .95,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 6, bottom: 4),
                  child: Text(
                    'km',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${low!.toStringAsFixed(0)}–${high!.toStringAsFixed(0)} km',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tin cậy ${(confidence! * 100).round()}% · dự phòng 5%',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    ).animate().fadeIn(duration: 450.ms).slideY(begin: .08);
  }
}
