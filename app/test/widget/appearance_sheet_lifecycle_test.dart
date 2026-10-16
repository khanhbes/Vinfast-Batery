import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/settings_service.dart';
import 'package:vinfast_battery/features/settings/appearance_sheet.dart';

void main() {
  testWidgets('dismiss while native theme persistence is pending is safe', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final service = SettingsService();
    const channel = MethodChannel('com.vinfast.battery/splash');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    await service.initialize();
    await service.setThemeMode(AppThemeMode.light);
    final pending = Completer<void>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) => pending.future,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => AppearanceSheet(settings: service),
              ),
              child: const Text('Appearance'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Dark Cockpit'), findsNothing);
    expect(find.text('Sáng'), findsNothing);
    // Task 125: Vietnamese only until the content is translated.
    expect(find.text('English'), findsNothing);
    expect(
      find.byKey(const ValueKey('appearance-vietnamese-only')),
      findsOneWidget,
    );
    await tester.tap(find.text('Tiếng Việt'));
    await tester.pump();
    expect(service.getLanguage(), AppLanguage.vietnamese);
    Navigator.of(tester.element(find.byType(AppearanceSheet))).pop();
    await tester.pumpAndSettle();
    pending.complete();
    expect(service.getThemeModeValue(), ThemeMode.dark);
    await tester.pump();
    expect(find.byType(AppearanceSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
