import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/services/guide_registry.dart';
import 'package:vinfast_battery/core/services/guide_tour_coordinator.dart';
import 'package:vinfast_battery/core/widgets/coach_mark_overlay.dart';
import 'package:vinfast_battery/features/settings/guide_screen.dart';
import 'package:vinfast_battery/navigation/app_navigation.dart';

void main() {
  tearDown(CoachMarkOverlay.dismissActive);

  testWidgets(
    'pending guide survives more than 120 real frames; no busy loop',
    (tester) async {
      final coordinator = GuideTourCoordinator()..activateAccount('qa');
      var ready = false;
      var shows = 0;
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      coordinator.request(
        uid: 'qa',
        ready: () => ready,
        show: () {
          shows++;
          return null;
        },
      );
      for (var i = 0; i < 150; i++) {
        tester.binding.scheduleFrame();
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(shows, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      ready = true;
      tester.binding
          .scheduleFrame(); // Anchor attachment causes a real layout frame.
      await tester.pump();
      expect(shows, 1);
      coordinator.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account switch cancels pending guide without showing old account',
    (tester) async {
      final coordinator = GuideTourCoordinator()..activateAccount('a');
      var shows = 0;
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      coordinator.request(
        uid: 'a',
        ready: () => true,
        show: () {
          shows++;
          return null;
        },
      );
      coordinator.activateAccount('b');
      await tester.pump();
      expect(shows, 0);
      coordinator.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'safety modal suspends overlay; ready again resumes without duplicate',
    (tester) async {
      final coordinator = GuideTourCoordinator()..activateAccount('qa');
      final navigator = GlobalKey<NavigatorState>();
      var ready = true;
      var shows = 0;
      OverlayEntry? current;
      coordinator.entryIsActive = (entry) => identical(current, entry);
      coordinator.dismissOverlay = () {
        current?.remove();
        current = null;
      };
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox()),
      );
      coordinator.request(
        uid: 'qa',
        ready: () => ready,
        show: () {
          shows++;
          current = OverlayEntry(builder: (_) => const Text('Tour'));
          navigator.currentState!.overlay!.insert(current!);
          return current;
        },
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Tour'), findsOneWidget);
      expect(shows, 1);
      ready = false;
      tester.binding.scheduleFrame();
      await tester.pump();
      await tester.pump();
      expect(find.text('Tour'), findsNothing);
      ready = true;
      tester.binding.scheduleFrame();
      await tester.pump();
      await tester.pump();
      expect(find.text('Tour'), findsOneWidget);
      expect(shows, 2);
      coordinator.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'actual Guide replay button routes to shell and inserts into Navigator overlay',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final coordinator = GuideTourCoordinator()..activateAccount('qa');
      var finishes = 0;
      final steps = GuideRegistry.getOverviewTourSteps();
      coordinator.dismissOverlay = CoachMarkOverlay.dismissActive;
      coordinator.entryIsActive = CoachMarkOverlay.isActive;
      coordinator.onReplay = () => coordinator.request(
        uid: 'qa',
        manual: true,
        ready: () => steps.every((s) => s.anchorKey.currentContext != null),
        show: () => CoachMarkOverlay.show(
          context: navigator.currentContext!,
          overlay: navigator.currentState!.overlay,
          steps: steps,
          showDontShowAgain: false,
          onFinish: () => finishes++,
          onSkip: () {},
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            guideTourCoordinatorProvider.overrideWithValue(coordinator),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Scaffold(
              body: Column(
                children: [
                  for (final step in steps)
                    SizedBox(
                      key: step.anchorKey,
                      height: 48,
                      child: const Text('Control'),
                    ),
                  Builder(
                    builder: (context) => TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const GuideScreen(),
                        ),
                      ),
                      child: const Text('Help'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Help'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('Start tour'));
      await tester.pump();
      // Route dismissal and spotlight measure on separate layout frames.
      // Do not pumpAndSettle: a mascot may legitimately keep its own ticker.
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(GuideScreen), findsNothing);
      expect(find.byType(CoachMarkOverlay), findsOneWidget);
      expect(finishes, 0);
      CoachMarkOverlay.dismissActive();
      coordinator.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
