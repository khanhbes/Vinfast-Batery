import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/widgets/settings_reveal.dart';
import 'package:vinfast_battery/data/services/server_smart_charger_service.dart';
import 'package:vinfast_battery/features/settings/developer_ai_studio_screen.dart';

class _DatasetService implements ServerSmartChargerService {
  _DatasetService({this.records = const []});
  final List<Map<String, dynamic>> records;
  @override
  Future<Map<String, dynamic>> triggerChargingTimeFineTune({
    double? learningRate,
    int? nEstimators,
    int? maxDepth,
    double? testSplit,
  }) async => {
    'success': true,
    'data': {
      'version': 'charging-time-test-model-with-long-version-2026',
      'metrics': {
        'mape': 7.5,
        'maeSeconds': 390.0,
        'rmseSeconds': 480.0,
        'r2': 0.94,
        'accuracyPct': 92.5,
      },
    },
  };
  @override
  Future<Map<String, dynamic>> pingServer({String? customUrl}) async => {
    'online': true,
    'latencyMs': 10,
  };
  @override
  Future<Map<String, dynamic>> getAiDataset({
    String? vehicleId,
    bool? confirmedOnly,
  }) async => {'records': records};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OfflineDatasetService extends _DatasetService {
  @override
  Future<Map<String, dynamic>> pingServer({String? customUrl}) async => {
    'online': false,
  };
  @override
  Future<Map<String, dynamic>> getAiDataset({
    String? vehicleId,
    bool? confirmedOnly,
  }) async => throw StateError('offline');
}

void main() {
  testWidgets('Offline studio does not fabricate samples or allow training', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: DeveloperAiStudioScreen(service: _OfflineDatasetService()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chưa có mẫu nào trong file dataset.'), findsOneWidget);
    expect(find.textContaining('seed-chg'), findsNothing);
    await tester.tap(find.text('Huấn luyện AI'));
    await tester.pumpAndSettle();
    final run = find.widgetWithText(
      ElevatedButton,
      '⚡ Kích Hoạt Fine-Tune Ngay',
    );
    await tester.scrollUntilVisible(
      run,
      200,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('studio-training')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(run).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final variant in [
    (1.0, Brightness.light),
    (2.0, Brightness.light),
    (1.0, Brightness.dark),
    (2.0, Brightness.dark),
  ]) {
    final (scale, brightness) = variant;
    testWidgets(
      'Studio long record IDs and badges at 320dp / $scale / $brightness',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: DeveloperAiStudioScreen(
              service: _DatasetService(
                records: [
                  {
                    'vehicle_id': 'VF_FELIZ_2025_LONG_VEHICLE_IDENTIFIER',
                    'session_id':
                        'charging-session-with-a-very-long-identifier-2026',
                    'is_user_confirmed': true,
                    'training_excluded': true,
                    'start_soc': 20.0,
                    'actual_end_soc': 100.0,
                    'duration_seconds': 12600.0,
                    'energy_wh': 2600.0,
                  },
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 8; i++) {
          await tester.drag(
            find.byType(ListView).hitTestable(),
            const Offset(0, -150),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.textContaining('2600 Wh'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final variant in [
    (1.0, Brightness.light),
    (2.0, Brightness.light),
    (1.0, Brightness.dark),
    (2.0, Brightness.dark),
  ]) {
    final (scale, brightness) = variant;
    testWidgets(
      'Studio empty dataset and training tab at 320dp / $scale / $brightness',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: DeveloperAiStudioScreen(service: _DatasetService()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Chưa có mẫu nào trong file dataset.'),
          150,
          scrollable: find.descendant(
            of: find.byType(ListView).hitTestable(),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Chưa có mẫu nào trong file dataset.'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Huấn luyện AI'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Huấn luyện AI'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('740 W (Active)'), findsNothing);
        expect(find.text('Kết nối máy chủ AI'), findsOneWidget);
        expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
        final list = find
            .descendant(
              of: find.byType(TabBarView),
              matching: find.byType(ListView),
            )
            .hitTestable();
        for (var i = 0; i < 6; i++) {
          await tester.drag(list, const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        final run = find.widgetWithText(
          ElevatedButton,
          '⚡ Kích Hoạt Fine-Tune Ngay',
        );
        await tester.scrollUntilVisible(
          run,
          150,
          scrollable: find.descendant(
            of: list,
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(run), alignment: 0.5);
        await tester.pumpAndSettle();
        expect(run.hitTestable(), findsOneWidget);
        await tester.tap(run);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('R² Score'),
          150,
          scrollable: find.descendant(
            of: list,
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('R² Score'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('Settings entrance respects reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SettingsReveal(child: Text('Settings')),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(SettingsReveal),
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
      findsNothing,
    );
    expect(find.text('Settings'), findsOneWidget);
  });
}
