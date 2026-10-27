import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/pinova_api.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/utils/number_text.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../data/models/entitlement.dart';
import '../premium/premium_gate.dart';

/// What `/api/learning/<vehicle>/health` returns (QA 135).
class BatteryHealth {
  const BatteryHealth({
    this.nominalCapacityWh,
    this.estimate,
    this.test,
    this.trend = const [],
    this.vehicleSohPct,
    this.testMaxStartPct = 30,
  });

  final double? nominalCapacityWh;
  final HealthValue? estimate;
  final HealthValue? test;
  final List<(DateTime?, double)> trend;
  final double? vehicleSohPct;
  final double testMaxStartPct;

  static BatteryHealth fromMap(Map<String, dynamic> map) => BatteryHealth(
    nominalCapacityWh: (map['nominalCapacityWh'] as num?)?.toDouble(),
    estimate: HealthValue.fromMap(map['estimate']),
    test: HealthValue.fromMap(map['test']),
    trend: [
      for (final p in (map['trend'] as List? ?? const []))
        if (p is Map && p['sohPct'] is num)
          (
            DateTime.tryParse(p['at']?.toString() ?? ''),
            (p['sohPct'] as num).toDouble(),
          ),
    ],
    vehicleSohPct: (map['vehicleSohPct'] as num?)?.toDouble(),
    testMaxStartPct: (map['testMaxStartPct'] as num?)?.toDouble() ?? 30,
  );
}

class HealthValue {
  const HealthValue({
    required this.sohPct,
    required this.capacityWh,
    this.samples,
    this.confidence,
    this.startPct,
    this.at,
  });

  final double sohPct;
  final double capacityWh;
  final int? samples;

  /// low | medium | high (estimate only).
  final String? confidence;
  final double? startPct;
  final DateTime? at;

  String get confidenceLabel => switch (confidence) {
    'high' => 'Tin cậy cao',
    'medium' => 'Tin cậy vừa',
    _ => 'Tin cậy thấp',
  };

  static HealthValue? fromMap(Object? raw) {
    if (raw is! Map || raw['sohPct'] is! num) return null;
    return HealthValue(
      sohPct: (raw['sohPct'] as num).toDouble(),
      capacityWh: (raw['capacityWh'] as num?)?.toDouble() ?? 0,
      samples: (raw['samples'] as num?)?.toInt(),
      confidence: raw['confidence']?.toString(),
      startPct: (raw['startPct'] as num?)?.toDouble(),
      at: DateTime.tryParse(raw['at']?.toString() ?? ''),
    );
  }
}

final batteryHealthProvider = FutureProvider.autoDispose
    .family<BatteryHealth, String>((ref, vehicleId) async {
      final data = await PinovaApi().get(
        '/api/learning/${Uri.encodeComponent(vehicleId)}/health',
      );
      return BatteryHealth.fromMap(data);
    });

/// % pin chai (QA 135, Pro): how much of its rated capacity the battery
/// still holds, estimated from the charges whose % the owner confirmed,
/// plus a guided test that measures it in one charge. The scooter sends no
/// cell data, so this stays an estimate (champagne, never emerald).
class BatteryHealthScreen extends ConsumerWidget {
  const BatteryHealthScreen({super.key, required this.vehicleId});
  final String vehicleId;

  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    String vehicleId,
  ) async {
    if (!PremiumGate.check(context, ref, PremiumFeature.batteryHealth)) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BatteryHealthScreen(vehicleId: vehicleId),
      ),
    );
  }

  @override
  // QA 136: however this screen is reached (a tile, Pinova Bot, a
  // notification), outside the plan it shows Pinova Premium instead.
  Widget build(BuildContext context, WidgetRef ref) => PremiumRequired(
    feature: PremiumFeature.batteryHealth,
    child: Consumer(builder: (context, ref, _) => _screen(context, ref)),
  );

  Widget _screen(BuildContext context, WidgetRef ref) {
    final async = ref.watch(batteryHealthProvider(vehicleId));
    return LuxeScaffold(
      title: '% pin chai',
      body: RefreshIndicator(
        color: LuxeColors.emerald,
        onRefresh: () => ref.refresh(batteryHealthProvider(vehicleId).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: CircularProgressIndicator(color: LuxeColors.emerald),
                ),
              ),
              error: (error, _) => LuxeNotice(
                icon: Icons.cloud_off_rounded,
                color: LuxeColors.champagne,
                message: error is PinovaApiException && error.notDeployed
                    ? 'Máy chủ chưa cập nhật tính năng này.'
                    : error is PinovaApiException && error.message != null
                    ? error.message!
                    : 'Chưa tải được dữ liệu pin. Kéo xuống để thử lại.',
              ),
              data: (health) => _Body(health: health),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.health});
  final BatteryHealth health;

  @override
  Widget build(BuildContext context) {
    final best = health.test ?? health.estimate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Hero(health: health, value: best),
        if (health.trend.length >= 2) ...[
          const LuxeSectionLabel('Theo từng lần sạc'),
          LuxeSparkline(
            points: [for (final (_, v) in health.trend) v],
            height: 90,
            color: LuxeColors.champagne,
            semanticLabel: '% pin còn lại theo từng lần sạc',
          ),
        ],
        const LuxeSectionLabel('Bài kiểm tra pin'),
        _TestCard(health: health),
        const SizedBox(height: 16),
        const LuxeNotice(
          message:
              'Xe không gửi dữ liệu cell pin, nên đây là ước tính từ điện năng '
              'ổ Shelly đo và % bạn đọc trên đồng hồ (hiệu suất sạc khoảng 90%). '
              'Pin mới thường 95–100%; dưới 70% nên đưa xe đi kiểm tra.',
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.health, required this.value});
  final BatteryHealth health;
  final HealthValue? value;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (health.nominalCapacityWh == null) {
      return const LuxeNotice(
        icon: Icons.info_outline_rounded,
        color: LuxeColors.champagne,
        message:
            'Xe chưa có dung lượng pin danh định trong danh mục, nên chưa tính '
            'được % pin chai.',
      );
    }
    if (v == null) {
      return const LuxeNotice(
        key: ValueKey('health-need-data'),
        icon: Icons.hourglass_empty_rounded,
        color: LuxeColors.champagne,
        message:
            'Chưa đủ dữ liệu. Sau mỗi lần sạc, nhập % trên đồng hồ xe (hoặc '
            'làm bài kiểm tra bên dưới) để app ước tính.',
      );
    }
    final fade = (100 - v.sohPct).clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: LuxeColors.raised,
        border: Border.all(color: LuxeColors.hairlineStrong),
      ),
      child: Row(
        children: [
          LuxeRing(
            value: (v.sohPct / 100).clamp(0.0, 1.0),
            size: 104,
            color: LuxeColors.champagne,
            child: Text(
              '${v.sohPct.round()}%',
              key: const ValueKey('health-soh'),
              style: const TextStyle(
                color: LuxeColors.text,
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fade < 1
                      ? 'Pin gần như mới'
                      : 'Đã chai khoảng ${fade.round()}%',
                  style: LuxeText.item,
                ),
                const SizedBox(height: 4),
                Text(
                  'Còn khoảng ${groupThousands(v.capacityWh)} Wh / '
                  '${groupThousands(health.nominalCapacityWh!)} Wh danh định',
                  style: LuxeText.caption,
                ),
                const SizedBox(height: 8),
                LuxeTag(
                  health.test != null
                      ? 'Từ bài kiểm tra'
                      : '${v.confidenceLabel} · ${v.samples ?? 0} lần sạc',
                  color: LuxeColors.champagne,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({required this.health});
  final BatteryHealth health;

  @override
  Widget build(BuildContext context) {
    final test = health.test;
    final max = health.testMaxStartPct.round();
    final steps = [
      ('Đi xe đến khi pin còn ≤ $max%', Icons.two_wheeler_rounded),
      (
        'Quét đồng hồ hoặc nhập % lúc bắt đầu sạc',
        Icons.document_scanner_rounded,
      ),
      (
        'Sạc đến 100% (tab Sạc pin), để máy chủ tự ngắt khi pin đầy',
        Icons.battery_charging_full_rounded,
      ),
      ('App tính dung lượng thật từ điện năng đã nạp', Icons.insights_rounded),
    ];
    return LuxeSettingsGroup(
      children: [
        for (final (i, (text, icon)) in steps.indexed)
          LuxeSettingsRow(icon: icon, title: '${i + 1}. $text'),
        if (test != null)
          LuxeSettingsRow(
            key: const ValueKey('health-test-result'),
            icon: Icons.verified_rounded,
            accent: LuxeColors.champagne,
            title: 'Lần kiểm tra gần nhất: ${test.sohPct.round()}%',
            subtitle:
                'Từ ${test.startPct?.round() ?? '?'}% lên đầy'
                '${test.at == null ? '' : ' · ${test.at!.toLocal().day}/${test.at!.toLocal().month}/${test.at!.toLocal().year}'}',
          ),
      ],
    );
  }
}
