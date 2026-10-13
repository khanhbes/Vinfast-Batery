import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/luxe_theme.dart';
import '../services/achievement_engine.dart';
import 'achievement_medal.dart';

/// Detail of one achievement: the medal floating with a periodic shine,
/// rarity, points, how to unlock and the progress or unlock date.
abstract final class AchievementDetailSheet {
  static Future<void> show(BuildContext context, AchievementProgress p) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.72),
        builder: (context) => Theme(
          data: LuxeTheme.of(context),
          child: _Sheet(progress: p),
        ),
      );
}

class _Sheet extends StatefulWidget {
  const _Sheet({required this.progress});
  final AchievementProgress progress;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final def = p.def;
    final hidden = def.secret && !p.unlocked;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0C0D0F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: LuxeColors.hairline)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: LuxeColors.hairlineStrong,
              ),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _loop,
              builder: (context, _) {
                final t = _loop.value;
                return Transform.translate(
                  offset: Offset(0, 4 * math.sin(t * 2 * math.pi)),
                  child: AchievementMedal(
                    rarity: def.rarity,
                    icon: def.icon,
                    unlocked: p.unlocked,
                    progress: p.fraction,
                    secret: def.secret,
                    size: 150,
                    shine: t * 3 - 0.6,
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Pill(text: def.rarity.label, color: def.rarity.accent),
                const SizedBox(width: 8),
                _Pill(text: def.category.label, color: LuxeColors.platinumMid),
                const SizedBox(width: 8),
                _Pill(text: '${def.points} điểm', color: LuxeColors.emerald),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              hidden ? 'Thành tựu bí mật' : def.title,
              textAlign: TextAlign.center,
              style: LuxeText.title,
            ),
            const SizedBox(height: 8),
            Text(
              hidden
                  ? 'Điều kiện được giữ kín. Hãy thử những thói quen sạc khác thường để khám phá.'
                  : def.description,
              textAlign: TextAlign.center,
              style: LuxeText.body,
            ),
            const SizedBox(height: 20),
            if (p.unlocked)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    size: 16,
                    color: LuxeColors.emerald,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Mở khóa ngày ${DateFormat('dd/MM/yyyy').format(p.unlockedAt!.toLocal())}',
                    style: const TextStyle(
                      color: LuxeColors.emerald,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            else if (!hidden) ...[
              Row(
                children: [
                  const Text('TIẾN ĐỘ', style: LuxeText.eyebrow),
                  const Spacer(),
                  Text(
                    p.label,
                    style: const TextStyle(
                      color: LuxeColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LuxeProgressBar(value: p.fraction),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Flexible(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

/// Thin emerald bar with a glowing head, animating to [value].
class LuxeProgressBar extends StatelessWidget {
  const LuxeProgressBar({super.key, required this.value, this.height = 6});
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.clamp(0.0, 1.0)),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 900),
    curve: LuxeMotion.enter,
    builder: (context, v, _) => SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height),
                color: const Color(0x14FFFFFF),
              ),
            ),
            Container(
              width: math.max(height, c.maxWidth * v),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height),
                gradient: const LinearGradient(
                  colors: [LuxeColors.emeraldDeep, LuxeColors.emerald],
                ),
                boxShadow: const [
                  BoxShadow(color: LuxeColors.emeraldGlow, blurRadius: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
