import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/ai_prediction_service.dart';
import '../home/home_screen.dart';

/// ========================================================================
/// AiFunctionsScreen — AI Function Center
/// Hiển thị tất cả tính năng AI kèm trạng thái sẵn sàng
/// ========================================================================
class AiFunctionsScreen extends ConsumerStatefulWidget {
  const AiFunctionsScreen({super.key});

  @override
  ConsumerState<AiFunctionsScreen> createState() => _AiFunctionsScreenState();
}

class _AiFunctionsScreenState extends ConsumerState<AiFunctionsScreen> {
  bool _apiAvailable = false;
  bool _checkingApi = true;

  @override
  void initState() {
    super.initState();
    _checkApiStatus();
  }

  Future<void> _checkApiStatus() async {
    final aiService = ref.read(aiPredictionServiceProvider);
    final ok = await aiService.isAvailable();
    if (mounted) setState(() { _apiAvailable = ok; _checkingApi = false; });
  }

  @override
  Widget build(BuildContext context) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    final vehicleAsync = vehicleId.isNotEmpty
        ? ref.watch(vehicleProvider(vehicleId))
        : null;

    final vehicle = vehicleAsync?.valueOrNull;
    final hasModel = vehicle?.hasModelLink ?? false;
    final totalCharges = vehicle?.totalCharges ?? 0;
    final totalTrips = vehicle?.totalTrips ?? 0;

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
                          Text('Trạng thái các tính năng AI',
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

            // API status banner
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: _ApiStatusBanner(
                  checking: _checkingApi,
                  available: _apiAvailable,
                  onRetry: _checkApiStatus,
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
                    apiOnline: _apiAvailable,
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
    required bool apiOnline,
  }) {
    final features = [
      _AiFeature(
        icon: Icons.ev_station_rounded,
        iconColor: AppColors.primaryGreen,
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
        description: 'Dự báo pin tiêu hao cho quãng đường dự kiến, '
            'tính theo hiệu suất lịch sử.',
        status: totalTrips >= 3
            ? _FeatureStatus.active
            : totalTrips > 0
                ? _FeatureStatus.learning
                : _FeatureStatus.needsData,
        detail: totalTrips >= 3
            ? 'Đủ $totalTrips chuyến đi'
            : 'Cần đi thêm ${3 - totalTrips} chuyến',
      ),
      _AiFeature(
        icon: Icons.battery_full_rounded,
        iconColor: const Color(0xFFFF9800),
        name: 'AI Capacity / SoH',
        description: 'Tính dung lượng pin khả dụng (Wh, Ah) và sức khỏe pin '
            '(SoH%) bằng Hybrid AI Engine.',
        status: !hasModel
            ? _FeatureStatus.needsModel
            : totalCharges >= 3
                ? (apiOnline ? _FeatureStatus.active : _FeatureStatus.active)
                : totalCharges > 0
                    ? _FeatureStatus.learning
                    : _FeatureStatus.needsData,
        detail: !hasModel
            ? 'Chưa link model VinFast'
            : apiOnline
                ? 'AI API + on-device'
                : 'On-device (API offline)',
      ),
      _AiFeature(
        icon: Icons.trending_down_rounded,
        iconColor: AppColors.error,
        name: 'Degradation Prediction',
        description: 'Dự đoán mức độ chai pin theo thời gian bằng AI API '
            '(Flask backend).',
        status: !apiOnline
            ? _FeatureStatus.apiOffline
            : totalCharges >= 3
                ? _FeatureStatus.active
                : totalCharges > 0
                    ? _FeatureStatus.learning
                    : _FeatureStatus.needsData,
        detail: !apiOnline
            ? 'Cần kết nối AI API'
            : totalCharges >= 3
                ? 'Đủ dữ liệu + API online'
                : 'Cần sạc thêm ${3 - totalCharges} lần',
      ),
      _AiFeature(
        icon: Icons.analytics_rounded,
        iconColor: const Color(0xFF7C4DFF),
        name: 'Pattern Analysis',
        description: 'Phân tích thói quen sạc/pin và đề xuất cải thiện.',
        status: !apiOnline
            ? _FeatureStatus.apiOffline
            : totalCharges >= 3
                ? _FeatureStatus.active
                : totalCharges > 0
                    ? _FeatureStatus.learning
                    : _FeatureStatus.needsData,
        detail: !apiOnline
            ? 'Cần kết nối AI API'
            : totalCharges >= 3
                ? 'Đang hoạt động'
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
// API Status Banner
// =============================================================================

class _ApiStatusBanner extends StatelessWidget {
  final bool checking;
  final bool available;
  final VoidCallback onRetry;

  const _ApiStatusBanner({
    required this.checking,
    required this.available,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color borderColor;
    final IconData icon;
    final String text;

    if (checking) {
      bg = AppColors.info.withValues(alpha: 0.08);
      borderColor = AppColors.info.withValues(alpha: 0.2);
      icon = Icons.sync_rounded;
      text = 'Đang kiểm tra AI API...';
    } else if (available) {
      bg = AppColors.primaryGreen.withValues(alpha: 0.08);
      borderColor = AppColors.primaryGreen.withValues(alpha: 0.2);
      icon = Icons.cloud_done_rounded;
      text = 'AI API online — Flask backend kết nối OK';
    } else {
      bg = AppColors.warning.withValues(alpha: 0.08);
      borderColor = AppColors.warning.withValues(alpha: 0.2);
      icon = Icons.cloud_off_rounded;
      text = 'AI API offline — dùng tính toán on-device';
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
          checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.info))
              : Icon(icon,
                  size: 18,
                  color: available ? AppColors.primaryGreen : AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                )),
          ),
          if (!checking && !available)
            GestureDetector(
              onTap: onRetry,
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.refresh_rounded,
                    color: AppColors.textSecondary, size: 20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(vehicleName,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 8),
          Row(
            children: [
              _DataChip(
                icon: Icons.bolt_rounded,
                label: '$totalCharges sạc',
                active: totalCharges >= 3,
              ),
              const SizedBox(width: 8),
              _DataChip(
                icon: Icons.directions_car_rounded,
                label: '$totalTrips chuyến',
                active: totalTrips >= 3,
              ),
              const SizedBox(width: 8),
              _DataChip(
                icon: Icons.link_rounded,
                label: hasModel ? 'Đã link' : 'Chưa link',
                active: hasModel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DataChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _DataChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primaryGreen : AppColors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}

// =============================================================================
// Feature Card
// =============================================================================

enum _FeatureStatus { active, learning, needsData, needsModel, apiOffline }

class _AiFeature {
  final IconData icon;
  final Color iconColor;
  final String name;
  final String description;
  final _FeatureStatus status;
  final String detail;

  const _AiFeature({
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: feature.iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(feature.icon,
                  color: feature.iconColor, size: 22),
            ),
            const SizedBox(width: 14),
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
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            )),
                      ),
                      _StatusBadge(status: feature.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(feature.description,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.4,
                      )),
                  const SizedBox(height: 8),
                  Text(feature.detail,
                      style: TextStyle(
                        color: _statusColor(feature.status),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final _FeatureStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Color _statusColor(_FeatureStatus status) => switch (status) {
      _FeatureStatus.active => AppColors.primaryGreen,
      _FeatureStatus.learning => AppColors.warning,
      _FeatureStatus.needsData => AppColors.info,
      _FeatureStatus.needsModel => const Color(0xFFFF9800),
      _FeatureStatus.apiOffline => AppColors.error,
    };

String _statusLabel(_FeatureStatus status) => switch (status) {
      _FeatureStatus.active => 'Đang hoạt động',
      _FeatureStatus.learning => 'Đang học',
      _FeatureStatus.needsData => 'Cần thêm dữ liệu',
      _FeatureStatus.needsModel => 'Cần link model',
      _FeatureStatus.apiOffline => 'API offline',
    };
