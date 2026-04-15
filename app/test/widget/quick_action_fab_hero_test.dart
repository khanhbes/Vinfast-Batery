import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinfast_battery/core/widgets/quick_action_menu.dart';

class _FabCollisionHarness extends StatelessWidget {
  const _FabCollisionHarness();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const Scaffold(body: Center(child: Text('Next'))),
                  ),
                );
              },
              child: const Text('Go next'),
            ),
          ),
          Positioned(
            left: 24,
            bottom: 24,
            child: QuickActionFab(
              vehicleId: 'vehicle_1',
              heroTag: 'quick_action_fab_dashboard',
              onAction: (_) {},
            ),
          ),
          Positioned(
            right: 24,
            bottom: 24,
            child: QuickActionFab(
              vehicleId: 'vehicle_1',
              heroTag: 'quick_action_fab_home',
              onAction: (_) {},
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets(
    'two QuickActionFab with distinct hero tags do not throw on route transition',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _FabCollisionHarness()));

      expect(find.byType(FloatingActionButton), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Go next'));
      await tester.pumpAndSettle();

      expect(find.text('Next'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
