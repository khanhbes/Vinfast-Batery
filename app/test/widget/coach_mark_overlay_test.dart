import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/services/guide_registry.dart';
import 'package:vinfast_battery/core/widgets/coach_mark_overlay.dart';

CoachMarkStep _step(
  GlobalKey anchor, {
  String id = 'first',
  bool longText = false,
}) => CoachMarkStep(
  id: id,
  titleVi: 'Xem thông tin xe',
  titleEn: 'View your vehicle',
  descriptionVi: 'Mở mục này để xem thông tin.',
  descriptionEn: longText
      ? List.filled(
          14,
          'Check the selected vehicle and the latest battery reading.',
        ).join(' ')
      : 'Check the selected vehicle and the latest battery reading.',
  anchorKey: anchor,
);

Widget _host({
  required Widget child,
  double keyboard = 0,
  double scale = 1,
  bool reducedMotion = true,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      padding: const EdgeInsets.only(top: 24, bottom: 20),
      viewInsets: EdgeInsets.only(bottom: keyboard),
      textScaler: TextScaler.linear(scale),
      disableAnimations: reducedMotion,
    ),
    child: child!,
  ),
  // Match a full-screen OverlayEntry, which is not resized by a route Scaffold.
  home: Scaffold(
    resizeToAvoidBottomInset: false,
    body: SizedBox.expand(child: child),
  ),
);

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('waits for a late anchor without enabling Next or completing', (
    tester,
  ) async {
    final anchor = GlobalKey();
    final mountedAnchor = ValueNotifier(false);
    addTearDown(mountedAnchor.dispose);
    var completed = 0;
    await tester.pumpWidget(
      _host(
        child: ValueListenableBuilder<bool>(
          valueListenable: mountedAnchor,
          builder: (context, visible, _) => Stack(
            children: [
              if (visible)
                Positioned(
                  top: 80,
                  left: 20,
                  child: SizedBox(key: anchor, width: 140, height: 48),
                ),
              Positioned.fill(
                child: CoachMarkOverlay(
                  steps: [_step(anchor)],
                  showDontShowAgain: false,
                  onFinish: () => completed++,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(completed, 0);
    mountedAnchor.value = true;
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Done'));
    expect(completed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('spotlight and background block taps to real controls', (
    tester,
  ) async {
    final anchor = GlobalKey();
    var controlTaps = 0;
    await tester.pumpWidget(
      _host(
        child: Stack(
          children: [
            Positioned(
              top: 60,
              left: 20,
              child: FilledButton(
                key: anchor,
                onPressed: () => controlTaps++,
                child: const Text('Hardware action'),
              ),
            ),
            Positioned.fill(
              child: CoachMarkOverlay(steps: [_step(anchor)], onFinish: () {}),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byKey(anchor)));
    await tester.tapAt(const Offset(4, 400));
    expect(controlTaps, 0);
    expect(
      find.descendant(
        of: find.byType(CoachMarkOverlay),
        matching: find.byType(ModalBarrier),
      ),
      findsOneWidget,
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      '320dp large text + keyboard stays scrollable and clear of target ($brightness)',
      (tester) async {
        _size(tester, const Size(320, 720));
        final anchor = GlobalKey();
        var done = false;
        await tester.pumpWidget(
          _host(
            keyboard: 300,
            scale: 1.5,
            brightness: brightness,
            child: Stack(
              children: [
                Positioned(
                  top: 52,
                  left: 24,
                  child: SizedBox(key: anchor, width: 120, height: 48),
                ),
                Positioned.fill(
                  child: CoachMarkOverlay(
                    steps: [_step(anchor, longText: true)],
                    onFinish: () => done = true,
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tooltip = tester.getRect(
          find.byKey(const ValueKey('coach-tooltip')),
        );
        expect(tooltip.top, greaterThanOrEqualTo(36));
        expect(tooltip.bottom, lessThanOrEqualTo(420));
        expect(tooltip.overlaps(tester.getRect(find.byKey(anchor))), isFalse);
        await tester.ensureVisible(find.text('Done'));
        await tester.pumpAndSettle();
        final doneButton = tester.getRect(find.byType(FilledButton));
        expect(doneButton.height, greaterThanOrEqualTo(48));
        expect(doneButton.bottom, lessThanOrEqualTo(420));
        await tester.tap(find.text('Done'));
        expect(done, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'reveals an offscreen anchor through the actual scrollable layout',
    (tester) async {
      _size(tester, const Size(390, 720));
      final anchor = GlobalKey();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _host(
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: [
                    const SizedBox(height: 1000),
                    SizedBox(key: anchor, height: 48, width: 150),
                    const SizedBox(height: 600),
                  ],
                ),
              ),
              Positioned.fill(
                child: CoachMarkOverlay(
                  steps: [_step(anchor)],
                  onFinish: () {},
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Back/Next use actual anchors and reduced motion settles without decorative loops',
    (tester) async {
      final first = GlobalKey();
      final second = GlobalKey();
      await tester.pumpWidget(
        _host(
          child: Stack(
            children: [
              Positioned(
                top: 60,
                left: 20,
                child: SizedBox(key: first, width: 120, height: 48),
              ),
              Positioned(
                bottom: 40,
                left: 20,
                child: SizedBox(key: second, width: 120, height: 48),
              ),
              Positioned.fill(
                child: CoachMarkOverlay(
                  steps: [
                    _step(first),
                    _step(second, id: 'second'),
                  ],
                  showDontShowAgain: false,
                  onFinish: () {},
                ),
              ),
            ],
          ),
        ),
      );
      expect(await tester.pumpAndSettle(), lessThanOrEqualTo(4));
      expect(
        tester
            .widget<FadeTransition>(
              find
                  .descendant(
                    of: find.byType(CoachMarkOverlay),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value,
        1,
      );
      await tester.tap(find.text('Next'));
      expect(await tester.pumpAndSettle(), lessThanOrEqualTo(4));
      expect(
        tester
            .widget<FadeTransition>(
              find
                  .descendant(
                    of: find.byType(CoachMarkOverlay),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value,
        1,
      );
      expect(find.text('Step 2 of 2'), findsOneWidget);
      expect(
        tester.getSize(find.byType(OutlinedButton)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester
            .getRect(find.byKey(const ValueKey('coach-tooltip')))
            .overlaps(tester.getRect(find.byKey(second))),
        isFalse,
      );
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'show replaces the active overlay and dismiss is safe before mount',
    (tester) async {
      late BuildContext context;
      final anchor = GlobalKey();
      await tester.pumpWidget(
        _host(
          child: Builder(
            builder: (value) {
              context = value;
              return Center(
                child: SizedBox(key: anchor, height: 48, width: 120),
              );
            },
          ),
        ),
      );
      CoachMarkOverlay.show(
        context: context,
        steps: [_step(anchor)],
        onFinish: () {},
      );
      CoachMarkOverlay.dismissActive();
      await tester.pump();
      expect(find.byType(CoachMarkOverlay), findsNothing);
      CoachMarkOverlay.show(
        context: context,
        steps: [_step(anchor)],
        onFinish: () {},
      );
      await tester.pumpAndSettle();
      CoachMarkOverlay.show(
        context: context,
        steps: [_step(anchor)],
        onFinish: () {},
      );
      await tester.pumpAndSettle();
      expect(find.byType(CoachMarkOverlay), findsOneWidget);
      CoachMarkOverlay.dismissActive();
      await tester.pumpAndSettle();
      expect(find.byType(CoachMarkOverlay), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
