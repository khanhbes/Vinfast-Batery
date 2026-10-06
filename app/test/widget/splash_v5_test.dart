import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinfast_battery/core/widgets/bootstrap_splash.dart';

void main() {
  group('V5 Light Engraving Splash', () {
    Widget buildSplash({
      bool animate = true,
      VoidCallback? onFinished,
      bool disableAnimations = false,
    }) {
      return MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: MaterialApp(
          home: BootstrapSplash(
            message: 'Đang khởi động...',
            animate: animate,
            onFinished: onFinished,
          ),
        ),
      );
    }

    testWidgets('renders without overflow at 320px width', (tester) async {
      // Simulate a compact 320×568 screen (iPhone SE)
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildSplash());
      // Pump through initial frames — no overflow errors should occur
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 1500));

      // If we get here without RenderFlex overflow, test passes
      expect(tester.takeException(), isNull);
    });

    testWidgets('completes in duration and fires onFinished', (tester) async {
      bool finished = false;
      await tester.pumpWidget(buildSplash(onFinished: () => finished = true));

      // Pump in increments to ensure ticker advances through all phases
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      // Extra pumps to fire post-frame callbacks
      await tester.pump();
      await tester.pump();

      expect(finished, isTrue);
    });

    testWidgets('reduce motion skips to logo and fires callback', (
      tester,
    ) async {
      bool finished = false;
      await tester.pumpWidget(
        buildSplash(disableAnimations: true, onFinished: () => finished = true),
      );

      // Reduce motion: jumps to 80%, waits 1s
      await tester.pump(const Duration(milliseconds: 1100));

      expect(finished, isTrue);
    });

    testWidgets('animate=false shows final state immediately', (tester) async {
      bool finished = false;
      await tester.pumpWidget(
        buildSplash(animate: false, onFinished: () => finished = true),
      );

      // Controller value = 1 immediately → status listener fires
      await tester.pump();

      expect(finished, isTrue);
      final branding = find.text('VINFAST BATTERY');
      for (final opacity in tester.widgetList<Opacity>(
        find.ancestor(of: branding, matching: find.byType(Opacity)),
      )) {
        expect(opacity.opacity, greaterThan(0));
      }
      await tester.pump(const Duration(seconds: 9));
      final waiting = find.text('Đang kết nối…');
      expect(waiting, findsOneWidget);
      for (final opacity in tester.widgetList<Opacity>(
        find.ancestor(of: waiting, matching: find.byType(Opacity)),
      )) {
        expect(opacity.opacity, greaterThan(0));
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('displays branding text elements', (tester) async {
      await tester.pumpWidget(buildSplash());

      // Pump to Nhịp 4 where typography appears (~3500ms)
      await tester.pump(const Duration(milliseconds: 3800));

      // Verify brand text is present in the widget tree
      expect(find.text('VINFAST BATTERY'), findsOneWidget);
      expect(find.text('Hiểu pin · Sạc thông minh'), findsOneWidget);
    });
  });
}
