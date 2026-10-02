import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/auth/auth_gate.dart';
import 'package:vinfast_battery/main.dart' show firebaseInitErrorProvider;

void main() {
  testWidgets(
    'AuthGate shows error screen when firebaseInitErrorProvider has an error',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseInitErrorProvider.overrideWith(
              (ref) => Exception('Firebase bootstrap timeout'),
            ),
          ],
          child: const MaterialApp(home: AuthGate()),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('Chưa thể mở ứng dụng'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'AuthGate shows BootstrapSplash when first mounted and initializing',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AuthGate())),
      );

      // Initial frame renders splash screen
      expect(find.text('VinFast Battery'), findsOneWidget);
      expect(find.text('QUẢN LÝ PIN VÀ SẠC XE ĐIỆN'), findsOneWidget);
      // Splash exposes the real bootstrap message only; it must not show a
      // fabricated percentage while Firebase is still resolving.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
