import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/under_development_notice.dart';

/// ========================================================================
/// Quick Actions Floating V3 — Dark Premium Design
/// Nổi bên phải, dark glass labels
/// ========================================================================

class QuickActionsFloating extends StatefulWidget {
  final VoidCallback? onCharge;
  final VoidCallback? onStation;
  final VoidCallback? onHistory;
  final VoidCallback? onEmergency;

  const QuickActionsFloating({
    super.key,
    this.onCharge,
    this.onStation,
    this.onHistory,
    this.onEmergency,
  });

  @override
  State<QuickActionsFloating> createState() => _QuickActionsFloatingState();
}

class _QuickActionsFloatingState extends State<QuickActionsFloating>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      _isExpanded ? _controller.forward() : _controller.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Action buttons (visible when expanded)
        AnimatedOpacity(
          opacity: _isExpanded ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_isExpanded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _ActionButton(
                  icon: Icons.bolt_rounded,
                  label: 'Sạc ngay',
                  color: AppColors.warning,
                  onTap: widget.onCharge ?? () {
                    UnderDevelopmentNotice.showDialog(
                      context,
                      featureName: 'Sạc nhanh',
                    );
                  },
                ),
                const SizedBox(height: 10),
                _ActionButton(
                  icon: Icons.location_on_rounded,
                  label: 'Trạm sạc',
                  color: AppColors.info,
                  onTap: widget.onStation ?? () {
                    UnderDevelopmentNotice.showDialog(
                      context,
                      featureName: 'Tìm trạm sạc gần nhất',
                    );
                  },
                ),
                const SizedBox(height: 10),
                _ActionButton(
                  icon: Icons.history_rounded,
                  label: 'Lịch sử',
                  color: AppColors.success,
                  onTap: widget.onHistory ?? () {},
                ),
                const SizedBox(height: 10),
                _ActionButton(
                  icon: Icons.sos_rounded,
                  label: 'Cứu hộ',
                  color: AppColors.error,
                  onTap: widget.onEmergency ?? () {
                    UnderDevelopmentNotice.showDialog(
                      context,
                      featureName: 'Cứu hộ khẩn cấp',
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),

        // Main FAB
        GestureDetector(
          onTap: _toggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.vinfastBlue,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppColors.vinfastBlue.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: AnimatedRotation(
              turns: _isExpanded ? 0.125 : 0,
              duration: const Duration(milliseconds: 250),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }
}
