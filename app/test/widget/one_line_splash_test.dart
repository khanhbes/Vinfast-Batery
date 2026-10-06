import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/widgets/bootstrap_splash.dart';

void main() {
  Widget host({
    VoidCallback? done,
    bool reduced = false,
    bool animate = true,
    double fontScale = 1,
    Brightness brightness = Brightness.dark,
  }) => MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data: MediaQueryData(
        disableAnimations: reduced,
        textScaler: TextScaler.linear(fontScale),
      ),
      child: BootstrapSplash(
        message: 'technical message must not leak',
        onFinished: done,
        animate: animate,
      ),
    ),
  );

  testWidgets('full 5s timeline completes once and holds visible final brand', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(host(done: () => calls++));
    await tester.pump(); // Establish the ticker frame before advancing time.
    await tester.pump(const Duration(milliseconds: 4999));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(
      const Duration(milliseconds: 16),
    ); // Completion is delivered on the next frame.
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 1);
    expect(find.text('Đang kết nối…'), findsOneWidget);
    expect(find.text('technical message must not leak'), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final name = find.text('VINFAST BATTERY');
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: name, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reduced motion fades for 1s rather than completing immediately',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(host(reduced: true, done: () => calls++));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 999));
      expect(calls, 0);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 16));
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('background pauses timeline; resume and rebuild do not replay', (
    tester,
  ) async {
    var calls = 0;
    void done() => calls++;
    await tester.pumpWidget(host(done: done));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3000));
    await tester.pump(const Duration(milliseconds: 16));
    expect(calls, 1);
    await tester.pumpWidget(host(done: done, brightness: Brightness.light));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('static retry skips drawing and completes safely after build', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(host(animate: false, done: () => calls++));
    await tester.pump();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [320.0, 390.0, 412.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'keyframes render at $width / $brightness / font2 without overflow',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 640));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(host(fontScale: 2, brightness: brightness));
          await tester.pump();
          var elapsed = 0;
          for (final ms in [
            400,
            1100,
            1250,
            1400,
            1650,
            1850,
            2250,
            2450,
            3000,
            3950,
            4500,
            5000,
          ]) {
            await tester.pump(Duration(milliseconds: ms - elapsed));
            elapsed = ms;
            expect(tester.takeException(), isNull, reason: 'frame $ms');
          }
          expect(
            tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
            BootstrapSplash.background,
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
