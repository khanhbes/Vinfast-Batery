import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/settings/guide_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'renders concise guide at 320dp and 1.5 font scale ($brightness)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            supportedLocales: const [Locale('vi'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.5),
                disableAnimations: false,
              ),
              child: child!,
            ),
            home: const GuideScreen(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1));

        expect(find.text('Quick guide'), findsOneWidget);
        final guideScroll = find.byType(Scrollable).first;
        for (final title in [
          'View your vehicle and battery',
          'Start or stop charging',
          'View charging history',
          'Settings and vehicles',
        ]) {
          final titleFinder = find.text(title);
          await tester.scrollUntilVisible(
            titleFinder,
            120,
            scrollable: guideScroll,
          );
          expect(titleFinder, findsOneWidget);
        }
        expect(find.text('AI'), findsNothing);

        final shellyTitle = find.text('Connect Shelly Smart Charge');
        await tester.scrollUntilVisible(
          shellyTitle,
          120,
          scrollable: guideScroll,
        );
        await tester.tap(shellyTitle);
        await tester.pump(const Duration(milliseconds: 1));
        expect(find.text('Start Shelly setup'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
