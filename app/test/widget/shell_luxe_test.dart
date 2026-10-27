import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/app_theme.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/widgets/app_navigation_bar.dart';
import 'package:vinfast_battery/core/widgets/empty_state.dart';
import 'package:vinfast_battery/core/widgets/error_state.dart';
import 'package:vinfast_battery/core/widgets/loading_skeleton.dart';
import 'package:vinfast_battery/core/widgets/luxe_kit.dart';

/// Task 117 — global LUXE theme, shell and shared state views.
Widget _host(
  Widget child, {
  double scale = 1,
  bool reduce = true,
  Widget? bottom,
}) => MaterialApp(
  theme: AppTheme.darkTheme,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduce,
      ),
      child: Scaffold(body: child, bottomNavigationBar: bottom),
    ),
  ),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('App theme is the dark LUXE theme', () {
    final theme = AppTheme.darkTheme;
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, LuxeColors.background);
    expect(theme.colorScheme.primary, LuxeColors.platinumHi); // QA 139
    expect(identical(theme, LuxeTheme.data()), isTrue);
    expect(
      theme.pageTransitionsTheme.builders[TargetPlatform.android],
      isA<LuxePageTransitionsBuilder>(),
    );
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('Nav bar glides and fits 320dp at x$scale', (tester) async {
      _phone(tester);
      var selected = 0;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _host(
            const SizedBox.expand(),
            scale: scale,
            bottom: AppNavigationBar(
              selectedIndex: selected,
              onSelected: (i) => setState(() => selected = i),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Sạc pin'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      final align = tester.widget<AnimatedAlign>(find.byType(AnimatedAlign));
      expect(align.alignment, const Alignment(-1 + 2 * 1 / 3, 0));
      for (var i = 0; i < 4; i++) {
        final size = tester.getSize(
          find.byKey(ValueKey('navigation-destination-$i')),
        );
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('State views fit 320dp at x$scale', (tester) async {
      _phone(tester);
      var retried = 0;
      for (final view in <Widget>[
        EmptyState(
          icon: Icons.history_rounded,
          title: 'Chưa chọn phương tiện',
          message: 'Vui lòng chọn xe VinFast của bạn để xem lịch sử sạc pin.',
          actionLabel: 'Chọn xe ngay',
          onAction: () {},
        ),
        ErrorState(message: 'Chưa tải được lịch sử', onRetry: () => retried++),
        const SingleChildScrollView(
          child: LoadingSkeleton(layout: SkeletonLayout.list),
        ),
      ]) {
        await tester.pumpWidget(_host(view, scale: scale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(
        _host(
          ErrorState(message: 'Lỗi', onRetry: () => retried++),
          scale: scale,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thử lại'));
      expect(retried, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Empty art and count-up settle once with motion on', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            LuxeEmptyArt(icon: Icons.inbox_rounded),
            LuxeCountUp(value: 42, suffix: '%', style: TextStyle()),
            LuxeRing(value: 0.6, size: 80),
          ],
        ),
        reduce: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('42%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sparkline draws nothing for fewer than two real points', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            LuxeSparkline(points: [double.nan, 3]),
            LuxeSparkline(points: [1, 2, 3]),
          ],
        ),
      ),
    );
    final paints = find.descendant(
      of: find.byType(LuxeSparkline),
      matching: find.byType(CustomPaint),
    );
    expect(paints, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Segmented exposes selection and reports changes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var value = 'day';
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _host(
          LuxeSegmented<String>(
            segments: const [('day', 'Ngày'), ('week', 'Tuần')],
            selected: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.text('Ngày')),
      isSemantics(isSelected: true),
    );
    await tester.tap(find.text('Tuần'));
    await tester.pumpAndSettle();
    expect(value, 'week');
    handle.dispose();
  });

  testWidgets('LuxeAppBar back button keeps a 48dp target', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LuxeScaffold(
                  title: 'Thông số xe',
                  body: SizedBox.expand(),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final back = find.byTooltip('Quay lại');
    expect(back, findsOneWidget);
    expect(tester.getSize(back).width, greaterThanOrEqualTo(48));
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('Thông số xe'), findsNothing);
  });
}
