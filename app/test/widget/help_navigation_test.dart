import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/providers/app_providers.dart';
import 'package:vinfast_battery/navigation/app_navigation.dart';

void main() {
  testWidgets('Help action reveals root shell and selects its actual tab', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Root shell')),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => AppNavigation.openTab(context, 2),
            child: const Text('Open history'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Root shell').hitTestable(), findsNothing);
    await tester.tap(find.text('Open history'));
    await tester.pumpAndSettle();
    expect(container.read(currentTabProvider), 2);
    expect(find.text('Root shell').hitTestable(), findsOneWidget);
    expect(navigator.currentState!.canPop(), isFalse);
  });
}
