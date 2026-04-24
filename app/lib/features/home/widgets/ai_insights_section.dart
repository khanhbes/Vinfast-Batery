import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/under_development_notice.dart';

/// ========================================================================
/// AI Insights Section — Dark Premium V3
/// Cards tối với glass border, neon accents
/// ========================================================================

class AiInsightsSection extends StatelessWidget {
  const AiInsightsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.vinfastBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.vinfastBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Insights',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'AI ENGINE',
                      style: TextStyle(
                        color: AppColors.vinfastBlue,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 1. AI Dự đoán độ chai pin
        _AiFeatureCard(
          index: 0,
          icon: Icons.battery_alert_rounded,
          iconColor: AppColors.error,
          title: 'Dự đoán độ chai pin',
          subtitle: 'AI DEGRADATION',
          conclusion: 'Dự đoán mức độ chai pin trong 6 tháng tới dựa trên lịch sử sạc và sử dụng.',
          trendLabel: 'Đang phát triển',
          trendColor: AppColors.warning,
          trendIcon: Icons.construction_rounded,
          onTap: (ctx) => UnderDevelopmentNotice.showDialog(
            ctx,
            featureName: 'AI Dự đoán độ chai pin',
            description: 'Tính năng sử dụng AI để phân tích lịch sử sạc và dự đoán mức độ chai pin trong 6 tháng tới. Đang trong quá trình phát triển và huấn luyện mô hình.',
          ),
        ),

        const SizedBox(height: 12),

        // 2. AI Dự đoán hao hụt pin theo quãng đường
        _AiFeatureCard(
          index: 1,
          icon: Icons.route_rounded,
          iconColor: AppColors.info,
          title: 'Dự đoán hao hụt theo quãng đường',
          subtitle: 'AI RANGE PREDICTION',
          conclusion: 'Ước lượng pin tiêu hao cho mỗi tuyến đường dựa trên thói quen lái xe thực tế.',
          trendLabel: 'Đang phát triển',
          trendColor: AppColors.warning,
          trendIcon: Icons.construction_rounded,
          onTap: (ctx) => UnderDevelopmentNotice.showDialog(
            ctx,
            featureName: 'AI Dự đoán hao hụt pin',
            description: 'Tính năng dự đoán mức tiêu hao pin dựa trên quãng đường, tải trọng, và điều kiện thời tiết. AI sẽ học từ lịch sử chuyến đi của bạn.',
          ),
        ),

        const SizedBox(height: 12),

        // 3. AI Thói quen sử dụng
        _AiFeatureCard(
          index: 2,
          icon: Icons.psychology_rounded,
          iconColor: AppColors.success,
          title: 'Phân tích thói quen sử dụng',
          subtitle: 'AI USAGE HABITS',
          conclusion: 'Phân tích và đưa ra gợi ý tối ưu thói quen sạc, lái xe để kéo dài tuổi thọ pin.',
          trendLabel: 'Đang phát triển',
          trendColor: AppColors.warning,
          trendIcon: Icons.construction_rounded,
          onTap: (ctx) => UnderDevelopmentNotice.showDialog(
            ctx,
            featureName: 'AI Thói quen sử dụng',
            description: 'Tính năng phân tích thói quen sạc và lái xe hàng ngày, đưa ra gợi ý cá nhân hóa để bảo vệ pin và tiết kiệm năng lượng.',
          ),
        ),
      ],
    );
  }
}

// ── AI Feature Card — Dark Glass Design ──
class _AiFeatureCard extends StatelessWidget {
  final int index;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String conclusion;
  final String trendLabel;
  final Color trendColor;
  final IconData trendIcon;
  final void Function(BuildContext context) onTap;

  const _AiFeatureCard({
    required this.index,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.conclusion,
    required this.trendLabel,
    required this.trendColor,
    required this.trendIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(context),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: iconColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: trendColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(trendIcon, size: 12, color: trendColor),
                      const SizedBox(width: 4),
                      Text(
                        trendLabel,
                        style: TextStyle(
                          color: trendColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '"$conclusion"',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppColors.glass,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.textHint,
                    size: 14,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Nhấn để xem chi tiết tính năng',
                      style: TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textHint,
                    size: 16,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: 100 * index)).slideY(begin: 0.1);
  }
}
