import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/features/auth/login_screen.dart';
import 'package:vinfast_battery/features/auth/auth_gate.dart';
import 'package:vinfast_battery/features/auth/password_reset_screen.dart';
import 'package:vinfast_battery/features/auth/register_screen.dart';
import 'package:vinfast_battery/main.dart' show firebaseInitErrorProvider;

void main() {
  testWidgets('login fields begin blank and reset copy is account-neutral', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(fields.length, 2);
    expect(
      fields.every((field) => field.controller?.text.isEmpty ?? true),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: PasswordResetScreen()));
    await tester.pump();
    expect(
      find.text('Nhập email để nhận hướng dẫn đặt lại mật khẩu.'),
      findsOneWidget,
    );
    expect(
      find.text('Đã ghi nhận yêu cầu. Hãy kiểm tra hộp thư đến và thư rác.'),
      findsNothing,
    );
    expect(find.textContaining('nếu địa chỉ này có tài khoản'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final register in [false, true]) {
    for (final width in [320.0, 412.0]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'auth register=$register $brightness at $width with large text and keyboard',
          (tester) async {
            await tester.binding.setSurfaceSize(Size(width, 568));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(useMaterial3: true, brightness: brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.5),
                    viewInsets: const EdgeInsets.only(bottom: 240),
                  ),
                  child: child!,
                ),
                home: register ? const RegisterScreen() : const LoginScreen(),
              ),
            );
            await tester.pump(const Duration(seconds: 2));
            expect(tester.takeException(), isNull);
            final primaryAction = find.byType(FilledButton);
            await tester.ensureVisible(primaryAction);
            await tester.pump(const Duration(seconds: 2));
            expect(primaryAction.hitTestable(), findsOneWidget);
            expect(
              tester.getSize(primaryAction).height,
              greaterThanOrEqualTo(48),
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }

  testWidgets('register retains five field validations and labelled controls', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
    expect(find.byType(TextFormField), findsNWidgets(5));
    final primaryAction = find.byType(FilledButton);
    await tester.ensureVisible(primaryAction);
    await tester.tap(primaryAction);
    await tester.pump();

    for (final message in [
      'Vui lòng nhập họ tên',
      'Vui lòng nhập email',
      'Vui lòng nhập số điện thoại',
      'Vui lòng nhập mật khẩu',
      'Vui lòng xác nhận mật khẩu',
    ]) {
      expect(find.text(message), findsOneWidget);
    }
    for (final label in [
      'Quay lại đăng nhập',
      'Hiện mật khẩu',
      'Hiện mật khẩu xác nhận',
    ]) {
      final control = find.byTooltip(label);
      expect(control, findsOneWidget);
      final size = tester.getSize(control);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final brightness in Brightness.values) {
    testWidgets('bootstrap error adapts to $brightness and large text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseInitErrorProvider.overrideWith(
              (ref) => Exception('Firebase diagnostic text must stay private'),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true, brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.5),
                viewInsets: const EdgeInsets.only(bottom: 240),
              ),
              child: child!,
            ),
            home: const AuthGate(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Chưa thể mở ứng dụng'), findsOneWidget);
      expect(find.textContaining('Firebase'), findsNothing);
      final retry = find.widgetWithText(FilledButton, 'Thử lại');
      await tester.ensureVisible(retry);
      await tester.pump();
      expect(retry.hitTestable(), findsOneWidget);
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
