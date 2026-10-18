import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/personal_charging_profile.dart';
import 'package:vinfast_battery/data/models/vehicle_learning_status.dart';
import 'package:vinfast_battery/data/services/dashboard_reader.dart';
import 'package:vinfast_battery/data/services/server_smart_charger_service.dart';
import 'package:vinfast_battery/features/ai/widgets/battery_reading_sheet.dart';
import 'package:vinfast_battery/features/ai/widgets/confirm_actual_soc_sheet.dart';
import 'package:vinfast_battery/features/settings/personal_ai_settings_screen.dart';

Map<String, dynamic> _statusJson({int chargePending = 3, int trained = 2}) => {
  'vehicleId': 'car',
  'consentEnabled': true,
  'charge': {
    'pending': chargePending,
    'required': 3,
    'ready': chargePending >= 3,
    'trained': trained,
    'mae': 0.6,
    'whPerPct': 26.15,
    'powerW': 437,
  },
  'trip': {
    'pending': 0,
    'required': 10,
    'ready': false,
    'trained': 0,
    'kmPerPct': 1.2,
    'sources': {'csv': 0, 'trip': 0, 'odo_segment': 0},
    'model': {'refPctPerKm': 0.735, 'source': 'catalog'},
  },
};

class _LearningService implements ServerSmartChargerService {
  final trained = <String>[];
  final imported = <List<Map<String, dynamic>>>[];
  var status = VehicleLearningStatus.fromJson(_statusJson())!;

  @override
  Future<PersonalChargingProfile> getPersonalProfile(String vehicleId) async =>
      PersonalChargingProfile.fromJson({
        'vehicleId': vehicleId,
        'consentEnabled': true,
      });

  @override
  Future<VehicleLearningStatus?> learningStatus(String vehicleId) async =>
      status;

  @override
  Future<({TrainingReport? report, VehicleLearningStatus? status})> trainModel(
    String vehicleId, {
    required String model,
    String mode = 'finetune',
  }) async {
    trained.add('$model/$mode');
    status = VehicleLearningStatus.fromJson(
      _statusJson(chargePending: 0, trained: 5),
    )!;
    return (
      report: TrainingReport.fromJson({
        'decision': 'promoted',
        'mode': mode,
        'used': 5,
        'beforeMae': 1.2,
        'afterMae': 0.6,
      }),
      status: status,
    );
  }

  @override
  Future<({int added, int duplicates, int rejected, VehicleLearningStatus? status})>
  addTripSamples(
    String vehicleId,
    List<Map<String, dynamic>> trips, {
    required String source,
  }) async {
    imported.add(trips);
    return (added: trips.length, duplicates: 0, rejected: 0, status: status);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child, double scale) => ProviderScope(
  child: MaterialApp(
    theme: LuxeTheme.data(),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(320, 640),
        textScaler: TextScaler.linear(scale),
      ),
      child: child,
    ),
  ),
);

class _Opener extends StatefulWidget {
  const _Opener(this.open);
  final Future<Object?> Function(BuildContext context) open;

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  Object? result;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        key: const ValueKey('open'),
        onPressed: () async {
          final value = await widget.open(context);
          setState(() => result = value);
        },
        child: Text('result: $result'),
      ),
    ),
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder target) =>
    tester.scrollUntilVisible(
      target,
      150,
      scrollable: find.byType(Scrollable).first,
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scale in [1.0, 2.0]) {
    testWidgets('dashboard photo fills % and ODO, owner saves x$scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<DashboardReading?> reader({required bool camera}) async =>
          DashboardReadingParser.parse('85%\nODO 1240 km');
      await tester.pumpWidget(
        _app(
          _Opener(
            (context) => BatteryReadingSheet.show(
              context,
              currentOdoKm: 1200,
              reader: reader,
            ),
          ),
          scale,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('reading-camera')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('reading-ocr-result')), findsOneWidget);
      expect(find.text('85'), findsOneWidget);
      expect(find.text('1240'), findsOneWidget);
      final save = find.byKey(const ValueKey('reading-save'));
      await tester.ensureVisible(save);
      await tester.pump();
      await tester.tap(save);
      await _settle(tester);
      for (final part in ['soc: 85.0', 'odoKm: 1240.0', 'source: photo']) {
        expect(find.textContaining(part), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('an ODO lower than last time is refused x$scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          _Opener(
            (context) => BatteryReadingSheet.show(context, currentOdoKm: 1200),
          ),
          scale,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await _settle(tester);
      await tester.enterText(find.byKey(const ValueKey('reading-odo')), '900');
      final save = find.byKey(const ValueKey('reading-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await _settle(tester);
      expect(find.textContaining('nhỏ hơn lần trước'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('confirm sheet reads the dashboard too x$scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<DashboardReading?> reader({required bool camera}) async =>
          DashboardReadingParser.parse('79%\nODO 1234');
      await tester.pumpWidget(
        _app(
          _Opener(
            (context) => ConfirmActualSocSheet.show(
              context,
              estimatedSoc: 100,
              startSoc: 20,
              reader: reader,
            ),
          ),
          scale,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('actual-soc-photo')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('actual-soc-photo-note')), findsOneWidget);
      final save = find.byKey(const ValueKey('actual-soc-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await _settle(tester);
      expect(find.textContaining('soc: 79.0'), findsOneWidget);
      expect(find.textContaining('odoKm: 1234.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AI cá nhân: ready model trains on demand x$scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = _LearningService();
      await tester.pumpWidget(
        _app(
          PersonalAiSettingsScreen(vehicleId: 'car', service: service),
          scale,
        ),
      );
      await _settle(tester);
      final train = find.byKey(const ValueKey('train-lần sạc'));
      await _scrollTo(tester, train);
      expect(find.byKey(const ValueKey('model-card-charge')), findsOneWidget);
      expect(find.text('Đủ dữ liệu mới — nên huấn luyện'), findsOneWidget);
      await tester.ensureVisible(train);
      await tester.pump();
      await tester.tap(train);
      await _settle(tester);
      expect(service.trained, ['charge/finetune']);
      expect(find.text('Đang thu thập dữ liệu'), findsWidgets);
      // The trip model has no new rides: its train button is disabled.
      final tripTrain = find.byKey(const ValueKey('train-chuyến'));
      await _scrollTo(tester, tripTrain);
      expect(tester.widget<ButtonStyleButton>(tripTrain).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('CSV import sends the rows in batches', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _LearningService();
    final csv = StringBuffer('trip_id,distance_km,soc_delta\n');
    for (var i = 0; i < 620; i++) {
      csv.writeln('t$i,5.0,4');
    }
    await tester.pumpWidget(
      _app(
        PersonalAiSettingsScreen(
          vehicleId: 'car',
          service: service,
          pickCsv: () async => csv.toString().codeUnits,
        ),
        1,
      ),
    );
    await _settle(tester);
    final import = find.byKey(const ValueKey('learning-import-csv'));
    await _scrollTo(tester, import);
    await tester.pump();
    await tester.tap(import);
    await _settle(tester);
    expect(service.imported.map((b) => b.length), [500, 120]);
    expect(service.imported.first.first['clientId'], 't0');
    expect(tester.takeException(), isNull);
  });
}
