import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/luxe_theme.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/services/range_estimator.dart';

class RangePredictionCard extends StatefulWidget {
  const RangePredictionCard({
    super.key,
    required this.vehicle,
    this.predictRange,
  });
  final VehicleModel vehicle;
  final Future<Map<String, dynamic>> Function(VehicleModel)? predictRange;
  @override
  State<RangePredictionCard> createState() => _RangePredictionCardState();
}

class _RangePredictionCardState extends State<RangePredictionCard> {
  double? range, low, high, confidence;
  bool loading = true, offline = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    predict();
  }

  @override
  void didUpdateWidget(covariant RangePredictionCard old) {
    super.didUpdateWidget(old);
    if (old.vehicle.vehicleId != widget.vehicle.vehicleId ||
        old.vehicle.currentBattery != widget.vehicle.currentBattery ||
        old.vehicle.stateOfHealth != widget.vehicle.stateOfHealth ||
        old.vehicle.defaultEfficiency != widget.vehicle.defaultEfficiency ||
        old.predictRange != widget.predictRange) {
      predict();
    }
  }

  double? _number(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;

  Future<void> predict() async {
    final request = ++_request;
    final vehicle = widget.vehicle;
    setState(() {
      loading = true;
      range = low = high = confidence = null;
    });
    // Default: the shared on-device formula. Overview no longer calls the
    // legacy AI server on every render (AGENTS 3.7, Task 125); a server
    // predictor can still be injected.
    final predictor = widget.predictRange;
    Map<String, dynamic> response;
    try {
      response = predictor == null ? const {} : await predictor(vehicle);
    } catch (_) {
      response = {};
    }
    if (!mounted || request != _request) return;
    final payload = response['data'];
    final data = payload is Map ? payload : response;
    final estimate = _number(data['estimatedRangeKm']);
    final valid =
        response['success'] == true && estimate != null && estimate >= 0;
    setState(() {
      offline = !valid;
      loading = false;
      if (valid) {
        range = estimate;
        final lower = _number(data['rangeLowKm']);
        final upper = _number(data['rangeHighKm']);
        if (lower != null &&
            upper != null &&
            lower >= 0 &&
            lower <= estimate &&
            upper >= estimate) {
          low = lower;
          high = upper;
        }
        final score = _number(data['confidence']);
        confidence = score != null && score >= 0 && score <= 1 ? score : null;
      } else {
        // Shared local formula; no invented confidence or interval.
        range = estimateRangeKm(vehicle);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppReveal(
      child: LuxeGlass(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quãng đường còn lại', style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              loading
                  ? 'Đang tính dự đoán…'
                  : offline
                  ? 'Ước tính trên thiết bị'
                  : 'Dự đoán từ máy chủ AI',
              style: text.bodySmall,
            ),
            const SizedBox(height: 16),
            if (loading)
              const LinearProgressIndicator()
            else ...[
              Wrap(
                spacing: 20,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    range == null
                        ? 'Chưa đủ dữ liệu'
                        : '${range!.toStringAsFixed(1)} km',
                    style: text.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (low != null && high != null)
                    Text(
                      '${low!.toStringAsFixed(0)}–${high!.toStringAsFixed(0)} km',
                      style: text.titleMedium,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                confidence == null
                    ? 'Chưa có độ tin cậy được kiểm chứng'
                    : 'Độ tin cậy ${(confidence! * 100).round()}%',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 6),
              Text(
                offline
                    ? 'Tính từ mức pin, SoH và quãng đường cơ sở; trừ 5% pin dự phòng. '
                          'Không phải kết quả AI hay dữ liệu đo thực tế.'
                    : 'Quãng đường thực tế phụ thuộc tải trọng, tốc độ và điều kiện vận hành.',
                style: text.bodySmall,
              ),
              if (offline && widget.predictRange != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: predict,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Thử lại với máy chủ'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
