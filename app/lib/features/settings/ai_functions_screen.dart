import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../data/repositories/ai_insights_repository.dart';

/// ========================================================================
/// AiFunctionsScreen — AI Function Center
/// Hiển thị tất cả tính năng AI kèm trạng thái sẵn sàng
/// Dữ liệu AI từ Firestore AiVehicleInsights (web-managed)
/// ========================================================================
class AiFunctionsScreen extends ConsumerWidget {
  const AiFunctionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    final vehicleAsync = vehicleId.isNotEmpty
        ? ref.watch(vehicleProvider(vehicleId))
        : null;
    final insightAsync = vehicleId.isNotEmpty
        ? ref.watch(aiInsightProvider(vehicleId))
        : null;

    final vehicle = vehicleAsync?.valueOrNull;
    final insight = insightAsync?.valueOrNull;
    final hasModel = vehicle?.hasModelLink ?? false;
    final totalCharges = vehicle?.totalCharges ?? 0;
    final totalTrips = vehicle?.totalTrips ?? 0;

    final insightStatus = insight?.displayStatus ?? 'missing';
    final hasTrained = insight?.hasTrained ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.textSecondary, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AI Function Center',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              )),
                          Text('Dữ liệu AI quản lý từ Web Admin',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),
            ),

            // Insight status banner
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: _InsightStatusBanner(
                  status: insightStatus,
                  hasTrained: hasTrained,
                  updatedAt: insight?.updatedAt,
                ),
              ).animate().fadeIn(delay: 80.ms),
            ),

            // Data summary
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: _DataSummaryRow(
                  totalCharges: totalCharges,
                  totalTrips: totalTrips,
                  hasModel: hasModel,
                  vehicleName: vehicle?.vehicleName ?? 'Chưa chọn xe',
                ),
              ).animate().fadeIn(delay: 140.ms),
            ),

            // Feature list
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  _buildFeatureCards(
                    totalCharges: totalCharges,
                    totalTrips: totalTrips,
                    hasModel: hasModel,
                    insightStatus: insightStatus,
                    hasTrained: hasTrained,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFeatureCards({
    required int totalCharges,
    required int totalTrips,
    required bool hasModel,
    required String insightStatus,
    required bool hasTrained,
  }) {
    final features = [
      _AiFeature(
        icon: Icons.ev_station_rounded,
        iconColor: AppColors.primary,
        name: 'Smart Charging ETA',
        description: 'Dự đoán thời gian sạc dựa trên tốc độ sạc lịch sử và '
            'đường cong charge-rate theo %.',
        status: totalCharges >= 3
            ? _FeatureStatus.active
            : totalCharges > 0
                ? _FeatureStatus.learning
                : _FeatureStatus.needsData,
        detail: totalCharges >= 3
            ? 'Đủ $totalCharges lần sạc'
            : 'Cần sạc thêm ${3 - totalCharges} lần',
      ),
      _AiFeature(
        icon: Icons.route_rounded,
        iconColor: AppColors.info,
        name: 'Route Consumption',
        description: 'Dự báo pin tiêu hao theo insight AI từ web + '
            'fallback on-device.',
        status: hasTrained
            ? _FeatureStatus.active
            : totalTrips >= 3
                ? _FeatureStatus.active
                : totalTrips > 0
                    ? _FeatureStatus.learning
                    : _FeatureStatus.needsData,
        detail: hasTrained
            ? insightStatus == 'available'
                ? 'AI insight + on-device ($totalTrips chuyến)'
                : 'AI insight (stale) + on-device'
            : totalTrips >= 3
                ? 'On-device — chờ AI web'
                : 'Cần đi thêm ${3 - totalTrips} chuyến',
      ),
      _AiFeature(
        icon: Icons.battery_full_rounded,
        iconColor: const Color(0xFFFF9800),
        name: 'AI Capacity / SoH',
        description: 'Tính dung lượng pin khả dụng (Wh, Ah) và sức khỏe pin '
            '(SoH%) từ Firestore AI insight.',
        status: !hasModel
            ? _FeatureStatus.needsModel
            : hasTrained
                ? _FeatureStatus.active
                : totalCharges >= 3
                    ? _FeatureStatus.active
                    : totalCharges > 0
                        ? _FeatureStatus.learning
                        : _FeatureStatus.needsData,
        detail: !hasModel
            ? 'Chưa link model VinFast'
            : hasTrained
                ? 'AI insight ($insightStatus)'
                : 'On-device (chờ AI web)',
      ),
      _AiFeature(
        icon: Icons.trending_down_rounded,
        iconColor: AppColors.error,
        name: 'Degradation Prediction',
        description: 'Dự đoán mức độ chai pin từ AI insight '
            '(web admin train + refresh).',
        status: hasTrained
            ? _FeatureStatus.active
            : totalCharges >= 3
                ? _FeatureStatus.waitingWeb
                : totalCharges > 0
                    ? _FeatureStatus.learning
                    : _FeatureStatus.needsData,
        detail: hasTrained
            ? 'AI insight ($insightStatus)'
            : totalCharges >= 3
                ? 'Đủ data — cần web admin Train'
                : 'Cần sạc thêm ${3 - totalCharges} lần',
      ),
      _AiFeature(
        icon: Icons.analytics_rounded,
        iconColor: const Color(0xFF7C4DFF),
        name: 'Pattern Analysis',
        description: 'Phân tích thói quen sạc/pin từ AI insight cache.',
        status: hasTrained
            ? _FeatureStatus.active
            : totalCharges >= 3
                ? _FeatureStatus.waitingWeb
                : totalCharges > 0
                    ? _FeatureStatus.learning
                    : _FeatureStatus.needsData,
        detail: hasTrained
            ? 'Có ${(totalCharges)} lần sạc'
            : totalCharges >= 3
                ? 'Cần web admin Train'
                : 'Cần sạc thêm ${3 - totalCharges} lần',
      ),
    ];

    return [
      for (int i = 0; i < features.length; i++)
        _AiFeatureCard(feature: features[i])
            .animate()
            .fadeIn(delay: (200 + i * 60).ms)
            .slideY(begin: 0.08),
    ];
  }
}

// =============================================================================
// Insight Status Banner (replaces old API Status Banner)
// =============================================================================

class _InsightStatusBanner extends StatelessWidget {
  final String status;
  final bool hasTrained;
  final String? updatedAt;

  const _InsightStatusBanner({
    required this.status,
    required this.hasTrained,
    this.updatedAt,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color borderColor;
    final IconData icon;
    final String text;

    if (!hasTrained) {
      bg = AppColors.warning.withValues(alpha: 0.08);
      borderColor = AppColors.warning.withValues(alpha: 0.2);
      icon = Icons.hourglass_empty_rounded;
      text = 'Chưa có AI insight — chờ web admin Train';
    } else if (status == 'available') {
      bg = AppColors.primary.withValues(alpha: 0.08);
      borderColor = AppColors.primary.withValues(alpha: 0.2);
      icon = Icons.cloud_done_rounded;
      text = 'AI insight sẵn sàng';
    } else {
      bg = AppColors.warning.withValues(alpha: 0.08);
      borderColor = AppColors.warning.withValues(alpha: 0.2);
      icon = Icons.update_rounded;
      text = 'AI insight cần refresh từ web';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: hasTrained
                  ? (status == 'available'
                      ? AppColors.primary
                      : AppColors.warning)
                  : AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                )),
          ),
          if (updatedAt != null)
            Text(
              updatedAt!.length > 16 ? updatedAt!.substring(0, 16) : updatedAt!,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Data Summary Row
// =============================================================================

class _DataSummaryRow extends StatelessWidget {
  final int totalCharges;
  final int totalTrips;
  final bool hasModel;
  final String vehicleName;

  const _DataSummaryRow({
    required this.totalCharges,
    required this.totalTrips,
    required this.hasModel,
    required this.vehicleName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vehicleName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _miniStat(Icons.bolt_rounded, '$totalCharges sạc',
                        AppColors.primary),
                    const SizedBox(width: 14),
                    _miniStat(
                        Icons.route_rounded, '$totalTrips chuyến', AppColors.info),
                    const SizedBox(width: 14),
                    _miniStat(
                      Icons.memory_rounded,
                      hasModel ? 'Linked' : 'No model',
                      hasModel ? AppColors.primary : AppColors.textTertiary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(text,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            )),
      ],
    );
  }
}

// =============================================================================
// Feature models + card widget
// =============================================================================

enum _FeatureStatus {
  active,
  learning,
  needsData,
  needsModel,
  waitingWeb,
}

class _AiFeature {
  final IconData icon;
  final Color iconColor;
  final String name;
  final String description;
  final _FeatureStatus status;
  final String detail;

  _AiFeature({
    required this.icon,
    required this.iconColor,
    required this.name,
    required this.description,
    required this.status,
    required this.detail,
  });
}

class _AiFeatureCard extends StatelessWidget {
  final _AiFeature feature;

  const _AiFeatureCard({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: feature.iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(feature.icon, color: feature.iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(feature.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                    _statusBadge(feature.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(feature.description,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11.5,
                      height: 1.3,
                    )),
                const SizedBox(height: 6),
                Text(feature.detail,
                    style: TextStyle(
                      color: _statusColor(feature.status),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(_FeatureStatus status) {
    final (String label, Color color) = switch (status) {
      _FeatureStatus.active => ('Hoạt động', AppColors.primary),
      _FeatureStatus.learning => ('Đang học', AppColors.info),
      _FeatureStatus.needsData => ('Cần data', AppColors.textTertiary),
      _FeatureStatus.needsModel => ('Cần link', AppColors.warning),
      _FeatureStatus.waitingWeb => ('Chờ web', AppColors.warning),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          )),
    );
  }

  Color _statusColor(_FeatureStatus status) {
    return switch (status) {
      _FeatureStatus.active => AppColors.primary,
      _FeatureStatus.learning => AppColors.info,
      _FeatureStatus.needsData => AppColors.textTertiary,
      _FeatureStatus.needsModel => AppColors.warning,
      _FeatureStatus.waitingWeb => AppColors.warning,
    };
  }
}
