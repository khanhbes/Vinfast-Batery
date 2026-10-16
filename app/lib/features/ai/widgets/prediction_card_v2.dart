import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../data/services/charge_estimator.dart';

/// AI charging plan: duration as the hero figure, the automatic stop time
/// and the model provenance. Energy/cost estimates are intentionally not
/// shown (no BMS, the user enters both levels).
class PredictionCardV2 extends StatelessWidget {
  const PredictionCardV2({
    super.key,
    required this.durationMinutes,
    required this.stopTime,
    required this.fromSoc,
    required this.toSoc,
    required this.personalizationLabel,
    this.warnings = const [],
  });

  final int durationMinutes;
  final String stopTime;
  final int fromSoc;
  final int toSoc;
  final String personalizationLabel;
  final List<String> warnings;

  String get _duration =>
      formatChargeDuration(Duration(minutes: durationMinutes));

  @override
  Widget build(BuildContext context) {
    return LuxeGlass(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: LuxeColors.emerald,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Kế hoạch sạc',
                  style: TextStyle(
                    color: LuxeColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$fromSoc% → $toSoc%',
                style: const TextStyle(
                  color: LuxeColors.muted,
                  fontSize: 13,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LuxeMetalText(
            _duration,
            style: const TextStyle(
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w300,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.power_settings_new_rounded,
                size: 14,
                color: LuxeColors.emerald,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Dự kiến dừng lúc $stopTime · rơ-le tự ngắt',
                  style: const TextStyle(color: LuxeColors.muted, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.insights_rounded,
                size: 14,
                color: LuxeColors.platinumMid,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  personalizationLabel,
                  style: const TextStyle(color: LuxeColors.dim, fontSize: 12),
                ),
              ),
            ],
          ),
          for (final warning in warnings) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: LuxeColors.champagne,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    warning,
                    style: const TextStyle(
                      color: LuxeColors.muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
