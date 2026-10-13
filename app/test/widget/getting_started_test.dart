import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/features/auth/getting_started_screen.dart';
import 'package:vinfast_battery/features/auth/login_screen.dart';
import 'package:vinfast_battery/features/auth/onboarding_chat_screen.dart';

void main() {
  setUp(GettingStartedPrefs.debugReset);

  Widget host(
    Widget home, {
    double textScale = 1,
    bool reduced = false,
  }) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduced,
      ),
      child: child!,
    ),
    home: home,
  );

  for (final (width, height, scale) in [
    (320.0, 568.0, 1.5),
    (412.0, 915.0, 1.0),
  ]) {
    testWidgets('intro pages fit at ${width}x$height text $scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, height));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        host(
          GettingStartedScreen(onCreateAccount: () {}, onSignIn: () {}),
          textScale: scale,
        ),
      );
      for (var page = 0; page < 3; page++) {
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull, reason: 'page $page');
        final cta = find.byType(FilledButton);
        expect(cta.hitTestable(), findsOneWidget);
        expect(tester.getSize(cta).height, greaterThanOrEqualTo(48));
        if (page < 2) {
          await tester.tap(cta);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 700));
        }
      }
      expect(find.text('Tạo tài khoản'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('skip jumps to the last page and actions call back', (
    tester,
  ) async {
    var created = 0, signedIn = 0;
    await tester.pumpWidget(
      host(
        GettingStartedScreen(
          onCreateAccount: () => created++,
          onSignIn: () => signedIn++,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Bỏ qua'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Tạo tài khoản'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    expect(created, 1);
    await tester.tap(find.textContaining('Tôi đã có tài khoản'));
    expect(signedIn, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion shows final illustrations without looping', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        GettingStartedScreen(onCreateAccount: () {}, onSignIn: () {}),
        reduced: true,
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('Hiểu rõ\nviên pin của bạn'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first run shows intro; sign-in marks it seen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    expect(await GettingStartedPrefs.seen(), isFalse);
    await tester.pumpWidget(host(const SignedOutEntry(), reduced: true));
    await tester.pump();
    expect(find.byType(GettingStartedScreen), findsOneWidget);
    await tester.tap(find.textContaining('Tôi đã có tài khoản'));
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(GettingStartedPrefs.key), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('returning user goes straight to login', (tester) async {
    SharedPreferences.setMockInitialValues({GettingStartedPrefs.key: true});
    await GettingStartedPrefs.seen();
    await tester.pumpWidget(host(const SignedOutEntry(), reduced: true));
    await tester.pump();
    expect(find.byType(GettingStartedScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('BatteryBot speech drops emoji and keeps the message', () {
    expect(
      OnboardingStepFrame.cleanSpeech('Quãng đường lý tưởng! 🛵⚡ Đẹp nhất. 🏆'),
      'Quãng đường lý tưởng! Đẹp nhất.',
    );
  });
}
