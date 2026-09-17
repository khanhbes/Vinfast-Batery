import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/auth/auth_gate.dart';
import 'package:vinfast_battery/main.dart' show firebaseInitErrorProvider;

void main() {
  testWidgets('AuthGate shows error screen when firebaseInitErrorProvider has an error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseInitErrorProvider.overrideWith((ref) => Exception('Firebase bootstrap timeout')),
        ],
        child: const MaterialApp(
          home: AuthGate(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Không khởi tạo được Firebase'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AuthGate shows BootstrapSplash when first mounted and initializing', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AuthGate(),
        ),
      ),
    );

    // Initial frame renders splash screen
    expect(find.text('EV Battery'), findsOneWidget);
    expect(find.text('HỆ SINH THÁI PIN THÔNG MINH'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
