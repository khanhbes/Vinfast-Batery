import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../models/achievement.dart';
import 'achievement_medal.dart';

/// Full-screen unlock ceremony. Up to four medals play one after another;
/// a bigger batch (e.g. the first sync of an existing rider) becomes one
/// summary with the rarest medal in front.
abstract final class AchievementUnlockCeremony {
  static Future<void> show(
    BuildContext context,
    List<AchievementDef> unlocked, {
    VoidCallback? onOpenCollection,
  }) {
    if (unlocked.isEmpty) return Future.value();
    final sorted = [...unlocked]
      ..sort((a, b) => b.rarity.index.compareTo(a.rarity.index));
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Thành tựu mới',
      barrierColor: Colors.black.withValues(alpha: 0.86),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, _, _) => Theme(
        data: LuxeTheme.of(context),
        child: _Ceremony(
          medals: sorted,
          summary: sorted.length > 4,
          onOpenCollection: onOpenCollection,
        ),
      ),
      transitionBuilder: (context, a, _, child) =>
          FadeTransition(opacity: a, child: child),
    );
  }
}

class _Ceremony extends StatefulWidget {
  const _Ceremony({
    required this.medals,
    required this.summary,
    this.onOpenCollection,
  });

  final List<AchievementDef> medals;
  final bool summary;
  final VoidCallback? onOpenCollection;

  @override
  State<_Ceremony> createState() => _CeremonyState();
}

class _CeremonyState extends State<_Ceremony> with TickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );
  late final AnimationController _rays = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );
  int _index = 0;
  bool _hapticDone = false;
  bool _secondHapticDone = false;
  bool _reduced = false;
  bool _started = false;

  AchievementDef get _def => widget.medals[_index];
  int get _steps => widget.summary ? 1 : widget.medals.length;

  @override
  void initState() {
    super.initState();
    _t.addListener(() {
      if (!_hapticDone && _t.value >= 0.42) {
        _hapticDone = true;
        HapticFeedback.heavyImpact();
      }
      // Rare metals get a second, lighter tap as the shine crosses.
      if (!_secondHapticDone &&
          _t.value >= 0.55 &&
          _def.rarity.index >= AchievementRarity.gold.index) {
        _secondHapticDone = true;
        HapticFeedback.lightImpact();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) {
      _t.value = 1;
    } else {
      _t.forward();
      _rays.repeat();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    _rays.dispose();
    super.dispose();
  }

  void _next() {
    if (_index + 1 < _steps) {
      setState(() {
        _index++;
        _hapticDone = false;
        _secondHapticDone = false;
      });
      if (_reduced) {
        _t.value = 1;
      } else {
        _t.forward(from: 0);
      }
    } else {
      Navigator.of(context).pop();
    }
  }

  double _phase(double a, double b, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((_t.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final def = _def;
    final metal = def.rarity.metal;
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: Listenable.merge([_t, _rays]),
        builder: (context, _) {
          final flip = _phase(0.05, 0.55);
          final scale = 0.25 + 0.75 * _phase(0.05, 0.5, Curves.elasticOut);
          return SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final medal = math.min(c.maxWidth * 0.52, 220.0);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Rotating rays in the medal's metal.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: _phase(0.0, 0.35),
                          child: CustomPaint(
                            painter: _RaysPainter(
                              color: metal[1],
                              turn: _rays.value,
                              centreY: c.maxHeight * 0.36,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _BurstPainter(
                            t: _phase(0.38, 1.0, Curves.linear),
                            colors: [metal[0], metal[1], LuxeColors.emerald],
                            centre: Offset(c.maxWidth / 2, c.maxHeight * 0.36),
                            seed: _index,
                          ),
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        SizedBox(height: c.maxHeight * 0.36 - medal / 2),
                        Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0016)
                            ..rotateY(math.pi * (1 - flip))
                            ..scaleByDouble(scale, scale, 1, 1),
                          child: AchievementMedal(
                            rarity: def.rarity,
                            icon: def.icon,
                            size: medal,
                            shine: _phase(0.52, 0.86) * 2 - 0.5,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: _copy(def),
                          ),
                        ),
                        _actions(),
                      ],
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _rise(double a, double b, Widget child) {
    final t = _phase(a, b);
    return Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
    );
  }

  Widget _copy(AchievementDef def) {
    if (widget.summary) {
      final points = widget.medals.fold<int>(0, (s, d) => s + d.points);
      return Column(
        children: [
          _rise(
            0.45,
            0.7,
            const Text(
              'BỘ SƯU TẬP MỞ RỘNG',
              textAlign: TextAlign.center,
              style: LuxeText.eyebrow,
            ),
          ),
          const SizedBox(height: 10),
          _rise(
            0.5,
            0.75,
            Text(
              'Mở khóa ${widget.medals.length} thành tựu',
              textAlign: TextAlign.center,
              style: LuxeText.title,
            ),
          ),
          const SizedBox(height: 8),
          _rise(
            0.55,
            0.8,
            Text(
              '+$points điểm · từ lịch sử sạc của bạn',
              textAlign: TextAlign.center,
              style: LuxeText.body,
            ),
          ),
          const SizedBox(height: 18),
          _rise(
            0.6,
            0.9,
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in widget.medals.take(8))
                  AchievementMedal(rarity: d.rarity, icon: d.icon, size: 42),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        _rise(
          0.45,
          0.7,
          Text(
            def.secret ? 'THÀNH TỰU BÍ MẬT' : 'THÀNH TỰU MỚI',
            textAlign: TextAlign.center,
            style: LuxeText.eyebrow.copyWith(color: def.rarity.accent),
          ),
        ),
        const SizedBox(height: 10),
        _rise(
          0.5,
          0.75,
          Text(def.title, textAlign: TextAlign.center, style: LuxeText.title),
        ),
        const SizedBox(height: 10),
        _rise(
          0.55,
          0.8,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: def.rarity.accent.withValues(alpha: 0.6),
                  ),
                  color: def.rarity.accent.withValues(alpha: 0.12),
                ),
                child: Text(
                  def.rarity.label,
                  style: TextStyle(
                    color: def.rarity.metal[0],
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '+${def.points} điểm',
                style: const TextStyle(
                  color: LuxeColors.emerald,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _rise(
          0.6,
          0.85,
          Text(
            def.description,
            textAlign: TextAlign.center,
            style: LuxeText.body,
          ),
        ),
      ],
    );
  }

  Widget _actions() => _rise(
    0.7,
    0.95,
    Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _next,
              child: Text(
                _index + 1 < _steps
                    ? 'Tiếp theo  ${_index + 1}/$_steps'
                    : 'Tuyệt vời',
              ),
            ),
          ),
          if (widget.onOpenCollection != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onOpenCollection!();
              },
              child: const Text('Xem bộ sưu tập'),
            ),
        ],
      ),
    ),
  );
}

class _RaysPainter extends CustomPainter {
  _RaysPainter({
    required this.color,
    required this.turn,
    required this.centreY,
  });
  final Color color;
  final double turn;
  final double centreY;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, centreY);
    final r = size.longestSide;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(turn * 2 * math.pi);
    const n = 14;
    for (var i = 0; i < n; i++) {
      final a = i / n * 2 * math.pi;
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(math.cos(a - 0.07) * r, math.sin(a - 0.07) * r)
        ..lineTo(math.cos(a + 0.07) * r, math.sin(a + 0.07) * r)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 0.6)),
      );
    }
    canvas.restore();
    canvas.drawCircle(
      c,
      size.width * 0.45,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: size.width * 0.45)),
    );
  }

  @override
  bool shouldRepaint(_RaysPainter old) =>
      old.turn != turn || old.color != color;
}

/// Metal dust bursting out of the medal and drifting down.
class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.t,
    required this.colors,
    required this.centre,
    required this.seed,
  });
  final double t;
  final List<Color> colors;
  final Offset centre;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final rnd = math.Random(17 + seed);
    for (var i = 0; i < 46; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final speed = 120 + rnd.nextDouble() * 260;
      final ease = Curves.easeOutCubic.transform(t);
      final p =
          centre +
          Offset(math.cos(a), math.sin(a)) * speed * ease +
          Offset(0, 140 * t * t);
      final fade = (1 - t).clamp(0.0, 1.0);
      final color = colors[i % colors.length];
      final radius = 1.2 + rnd.nextDouble() * 2.6;
      if (i.isEven) {
        canvas.drawCircle(
          p,
          radius,
          Paint()..color = color.withValues(alpha: fade),
        );
      } else {
        // Thin glints.
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(a + t * 4);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: radius * 3, height: 1.2),
          Paint()..color = color.withValues(alpha: fade),
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.seed != seed;
}
