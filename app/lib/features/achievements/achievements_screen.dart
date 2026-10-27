import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/luxe_theme.dart';
import 'controllers/achievements_controller.dart';
import 'models/achievement.dart';
import 'services/achievement_engine.dart';
import 'widgets/achievement_detail_sheet.dart';
import 'widgets/achievement_medal.dart';
import 'widgets/achievement_unlock_ceremony.dart';

/// Thành tựu — the badge collection: rank medallion, up-next strip,
/// category filter and the full medal grid.
class AchievementsScreen extends ConsumerStatefulWidget {
  const AchievementsScreen({super.key});

  @override
  ConsumerState<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends ConsumerState<AchievementsScreen> {
  AchievementCategory? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(achievementsControllerProvider.notifier);
      controller.recordEvent(AchievementEvents.collectionOpened);
      controller.sync();
      _celebrate();
    });
  }

  void _celebrate() {
    final ids = ref
        .read(achievementsControllerProvider.notifier)
        .takeCelebrations();
    if (ids.isEmpty || !mounted) return;
    final defs = [
      for (final d in achievementCatalog)
        if (ids.contains(d.id)) d,
    ];
    AchievementUnlockCeremony.show(context, defs);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(achievementsControllerProvider);
    ref.listen<AchievementsState>(achievementsControllerProvider, (p, n) {
      if (n.pendingCelebrations.isNotEmpty &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _celebrate());
      }
    });
    final items = [
      for (final p in state.all)
        if (_filter == null || p.def.category == _filter) p,
    ];

    return Theme(
      data: LuxeTheme.of(context),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: LuxeColors.background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              const LuxeBackdrop(),
              SafeArea(
                child: RefreshIndicator(
                  color: LuxeColors.emerald,
                  backgroundColor: LuxeColors.raised,
                  onRefresh: () => ref
                      .read(achievementsControllerProvider.notifier)
                      .sync(force: true),
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _header(context, state)),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                        sliver: SliverToBoxAdapter(
                          child: LuxeReveal(child: _RankHero(state: state)),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        sliver: SliverToBoxAdapter(
                          child: LuxeReveal(
                            index: 1,
                            child: _StatsStrip(stats: state.stats),
                          ),
                        ),
                      ),
                      if (state.upNext.isNotEmpty)
                        SliverToBoxAdapter(
                          child: LuxeReveal(
                            index: 2,
                            child: _UpNext(items: state.upNext),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: LuxeReveal(
                          index: 3,
                          child: _CategoryFilter(
                            selected: _filter,
                            state: state,
                            onSelected: (c) => setState(() => _filter = c),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
                        sliver: SliverGrid(
                          // QA 138 (QA-08): tiles grow with the text.
                          gridDelegate:
                              SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 130,
                                mainAxisExtent:
                                    168 +
                                    (MediaQuery.textScalerOf(context).scale(1) -
                                            1) *
                                        40,
                                crossAxisSpacing: 6,
                                mainAxisSpacing: 6,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => LuxeReveal(
                              key: ValueKey(
                                '${_filter?.name}-${items[i].def.id}',
                              ),
                              index: 4 + (i % 9),
                              child: _MedalTile(progress: items[i]),
                            ),
                            childCount: items.length,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AchievementsState state) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 16, 6),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Quay lại',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 4),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thành tựu',
                style: TextStyle(
                  color: LuxeColors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
              Text('Bộ sưu tập huy hiệu', style: LuxeText.caption),
            ],
          ),
        ),
        if (state.syncing)
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: LuxeColors.platinumMid,
            ),
          ),
      ],
    ),
  );
}

/// Rank medallion with an orbit ring (progress to the next rank), a
/// travelling spark and a periodic shine.
class _RankHero extends StatefulWidget {
  const _RankHero({required this.state});
  final AchievementsState state;

  @override
  State<_RankHero> createState() => _RankHeroState();
}

class _RankHeroState extends State<_RankHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      // QA 139 (QA-13): one pass when shown; no endless decorative loop.
      _loop.forward();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final rank = state.rank;
    final next = rank.next;
    return LuxeGlass(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      child: Column(
        children: [
          SizedBox.square(
            dimension: 176,
            child: AnimatedBuilder(
              animation: _loop,
              builder: (context, _) {
                final t = _loop.value;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size.square(176),
                      painter: _OrbitPainter(
                        progress: state.rankProgress,
                        color: rank.rarity.accent,
                        t: t,
                      ),
                    ),
                    AchievementMedal(
                      rarity: rank.rarity,
                      icon: Icons.workspace_premium_rounded,
                      size: 128,
                      shine: t * 2.4 - 0.6,
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (b) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [rank.rarity.metal[0], rank.rarity.metal[1]],
            ).createShader(b),
            child: Text(
              rank.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w300,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(end: state.points.toDouble()),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 1200),
            curve: LuxeMotion.enter,
            builder: (context, v, _) => Text(
              '${v.round()} điểm · ${state.unlockedCount}/${state.total} huy hiệu',
              style: const TextStyle(
                color: LuxeColors.text,
                fontSize: 14,
                fontFeatures: [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 14),
          LuxeProgressBar(value: state.rankProgress),
          const SizedBox(height: 8),
          Text(
            next == null
                ? 'Bạn đã đạt hạng cao nhất'
                : 'Còn ${next.minPoints - state.points} điểm để lên ${next.name}',
            style: LuxeText.caption,
          ),
        ],
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.progress, required this.color, required this.t});
  final double progress;
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = LuxeColors.hairline,
    );
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    if (sweep > 0.01) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.sweep(
            c,
            [LuxeColors.emeraldDeep, LuxeColors.emerald, color],
            const [0.0, 0.7, 1.0],
            TileMode.clamp,
            -math.pi / 2,
            -math.pi / 2 + sweep,
          ),
      );
    }
    // A spark travelling the full orbit.
    final a = -math.pi / 2 + t * 2 * math.pi;
    final p = c + Offset(math.cos(a), math.sin(a)) * r;
    canvas.drawCircle(
      p,
      5,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(p, 1.8, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.t != t || old.progress != progress || old.color != color;
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.stats});
  final AchievementStats stats;

  @override
  Widget build(BuildContext context) {
    final cells = [
      (stats.kwh.toStringAsFixed(stats.kwh < 10 ? 1 : 0), 'kWh đã nạp'),
      ('${stats.sessions}', 'phiên sạc'),
      (
        '${stats.co2Kg.toStringAsFixed(stats.co2Kg < 10 ? 1 : 0)} kg',
        'CO₂ giảm',
      ),
      ('${stats.currentWeekStreak}', 'tuần liên tiếp'),
    ];
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: LuxeGlass(
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      cells[i].$1,
                      style: const TextStyle(
                        color: LuxeColors.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w300,
                        fontFeatures: [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      cells[i].$2,
                      style: const TextStyle(
                        color: LuxeColors.dim,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _UpNext extends StatelessWidget {
  const _UpNext({required this.items});
  final List<AchievementProgress> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 22, 20, 10),
        child: Text('SẮP MỞ KHÓA', style: LuxeText.eyebrow),
      ),
      SizedBox(
        // QA 138 (QA-08): grows with the text size.
        height: 118 + (MediaQuery.textScalerOf(context).scale(1) - 1) * 80,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final p = items[i];
            return SizedBox(
              width: 236,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => AchievementDetailSheet.show(context, p),
                  child: LuxeGlass(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        AchievementMedal(
                          rarity: p.def.rarity,
                          icon: p.def.icon,
                          unlocked: false,
                          progress: p.fraction,
                          size: 60,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                p.def.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: LuxeColors.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p.label,
                                style: const TextStyle(
                                  color: LuxeColors.muted,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              LuxeProgressBar(value: p.fraction, height: 4),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({
    required this.selected,
    required this.state,
    required this.onSelected,
  });
  final AchievementCategory? selected;
  final AchievementsState state;
  final ValueChanged<AchievementCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    String count(AchievementCategory? c) {
      final all = state.all.where((p) => c == null || p.def.category == c);
      return '${all.where((p) => p.unlocked).length}/${all.length}';
    }

    Widget chip(AchievementCategory? c, String label, IconData icon) {
      final on = selected == c;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: () {
              HapticFeedback.selectionClick();
              onSelected(c);
            },
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                gradient: on
                    ? const LinearGradient(
                        colors: [LuxeColors.platinumHi, LuxeColors.platinum],
                      )
                    : null,
                color: on ? null : LuxeColors.glass,
                border: Border.all(
                  color: on ? Colors.transparent : LuxeColors.hairline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: on ? LuxeColors.shell : LuxeColors.muted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$label  ${count(c)}',
                    style: TextStyle(
                      color: on ? LuxeColors.shell : LuxeColors.text,
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 62,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
        children: [
          chip(null, 'Tất cả', Icons.grid_view_rounded),
          for (final c in AchievementCategory.values) chip(c, c.label, c.icon),
        ],
      ),
    );
  }
}

class _MedalTile extends StatelessWidget {
  const _MedalTile({required this.progress});
  final AchievementProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final hidden = p.def.secret && !p.unlocked;
    return Semantics(
      button: true,
      label:
          '${hidden ? 'Thành tựu bí mật' : p.def.title}, ${p.def.rarity.label}, ${p.unlocked ? 'đã mở khóa' : p.label}',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          splashColor: p.def.rarity.accent.withValues(alpha: 0.12),
          onTap: () {
            HapticFeedback.selectionClick();
            AchievementDetailSheet.show(context, p);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Column(
              children: [
                AchievementMedal(
                  rarity: p.def.rarity,
                  icon: p.def.icon,
                  unlocked: p.unlocked,
                  progress: p.fraction,
                  secret: p.def.secret,
                  size: 76,
                ),
                const SizedBox(height: 8),
                Text(
                  hidden ? '???' : p.def.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.unlocked ? LuxeColors.text : LuxeColors.muted,
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: p.unlocked ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  p.unlocked
                      ? p.def.rarity.label
                      : (hidden ? 'Bí mật' : p.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.unlocked ? p.def.rarity.accent : LuxeColors.dim,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
