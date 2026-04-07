import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';

/// ========================================================================
/// QuickActionMenu — FAB "+" mở BottomSheet menu hành động
/// Dùng chung cho Dashboard và Home
/// ========================================================================

/// Kết quả khi user chọn một action từ menu
enum QuickAction {
  startTrip,
  startCharge,
  manualTrip,
  addCharge,
  routePrediction,
  aiFunctions,
  guide,
}

class QuickActionFab extends StatelessWidget {
  final String? vehicleId;
  final void Function(QuickAction action) onAction;

  const QuickActionFab({
    super.key,
    required this.vehicleId,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    if (vehicleId == null || vehicleId!.isEmpty) return const SizedBox.shrink();

    return FloatingActionButton(
      onPressed: () => _showMenu(context),
      backgroundColor: AppColors.primaryGreen,
      elevation: 4,
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _QuickActionSheet(
        onAction: (action) {
          Navigator.of(ctx).pop();
          onAction(action);
        },
      ),
    );
  }
}

class _QuickActionSheet extends StatelessWidget {
  final void Function(QuickAction action) onAction;

  const _QuickActionSheet({required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                Icon(Icons.flash_on_rounded,
                    color: AppColors.primaryGreen, size: 20),
                SizedBox(width: 8),
                Text('Hành động nhanh',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    )),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),

          // Primary actions
          _MenuItem(
            icon: Icons.navigation_rounded,
            iconColor: AppColors.info,
            label: 'Bắt đầu đi',
            subtitle: 'GPS tracking chuyến đi',
            onTap: () => onAction(QuickAction.startTrip),
          ).animate().fadeIn(delay: 50.ms),
          _MenuItem(
            icon: Icons.bolt_rounded,
            iconColor: AppColors.primaryGreen,
            label: 'Bắt đầu sạc',
            subtitle: 'Smart charging + ETA',
            onTap: () => onAction(QuickAction.startCharge),
          ).animate().fadeIn(delay: 100.ms),
          const Divider(color: AppColors.border, height: 1, indent: 60),

          // Manual input
          _MenuItem(
            icon: Icons.edit_note_rounded,
            iconColor: AppColors.textSecondary,
            label: 'Nhập chuyến đi thủ công',
            subtitle: 'Không cần GPS',
            onTap: () => onAction(QuickAction.manualTrip),
          ).animate().fadeIn(delay: 150.ms),
          _MenuItem(
            icon: Icons.add_circle_outline_rounded,
            iconColor: AppColors.textSecondary,
            label: 'Nhập sạc',
            subtitle: 'Ghi nhật ký sạc thủ công',
            onTap: () => onAction(QuickAction.addCharge),
          ).animate().fadeIn(delay: 200.ms),
          const Divider(color: AppColors.border, height: 1, indent: 60),

          // AI features
          _MenuItem(
            icon: Icons.route_rounded,
            iconColor: const Color(0xFFFF9800),
            label: 'Dự báo lộ trình',
            subtitle: 'Tính pin tiêu hao theo quãng đường',
            onTap: () => onAction(QuickAction.routePrediction),
          ).animate().fadeIn(delay: 250.ms),
          _MenuItem(
            icon: Icons.smart_toy_rounded,
            iconColor: const Color(0xFF7C4DFF),
            label: 'AI Function Center',
            subtitle: 'Xem trạng thái các tính năng AI',
            onTap: () => onAction(QuickAction.aiFunctions),
          ).animate().fadeIn(delay: 300.ms),
          _MenuItem(
            icon: Icons.menu_book_rounded,
            iconColor: AppColors.warning,
            label: 'Hướng dẫn sử dụng',
            subtitle: 'FAQ + AI hoạt động như nào',
            onTap: () => onAction(QuickAction.guide),
          ).animate().fadeIn(delay: 350.ms),

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      )),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}
