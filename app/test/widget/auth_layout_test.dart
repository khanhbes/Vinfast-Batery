import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/auth/login_screen.dart';
import 'package:vinfast_battery/features/auth/register_screen.dart';

void main() {
  for (final register in [false, true]) {
    for (final width in [320.0, 412.0]) {
      testWidgets(
        'auth register=$register at $width with large text and keyboard',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 568));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 240),
                ),
                child: child!,
              ),
              home: register ? const RegisterScreen() : const LoginScreen(),
            ),
          );
          await tester.pump(const Duration(seconds: 2));
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byType(ElevatedButton));
          await tester.pump(const Duration(seconds: 2));
          expect(find.byType(ElevatedButton).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
