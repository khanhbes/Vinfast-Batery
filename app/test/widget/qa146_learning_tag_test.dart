import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/personal_charging_profile.dart';
import 'package:vinfast_battery/data/models/vehicle_learning_status.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/services/server_smart_charger_service.dart';
import 'package:vinfast_battery/features/ai/widgets/prediction_card_v2.dart';
import 'package:vinfast_battery/features/settings/personal_ai_settings_screen.dart';

Map<String, dynamic> _learning(
  String state, {
  int charges = 2,
  double gain = 60,
}) => {
  'state': state,
  'charges': charges,
  'needCharges': 5,
  'gainPct': gain,
  'needGainPct': 100,
  'done': state != 'learning',
};

VehicleLearningStatus _status(
  Map<String, dynamic>? learning, {
  bool trainAllowed = true,
}) => VehicleLearningStatus.fromJson({
  'vehicleId': 'car',
  'consentEnabled': true,
  'trainAllowed': trainAllowed,
  'charge': {
    'pending': 2,
    'required': 2,
    'ready': true,
    'trained': 0,
    'learning': ?learning,
  },
  'trip': {'pending': 0, 'required': 10, 'ready': false, 'trained': 0},
})!;

class _Service implements ServerSmartChargerService {
  _Service(this.status);
  final VehicleLearningStatus status;

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('tag text', () {
    test('a vehicle without its own charges is learning', () {
      expect(
        _status(_learning('learning')).chargeLearningTag,
        'Đang học · 2/5 lần sạc',
      );
      expect(
        _status(
          _learning('learning', charges: 6, gain: 75),
        ).chargeLearningTag,
        'Đang học · đã nạp 75/100%',
      );
    });

    test('enough data: only Ultra can apply it', () {
      expect(
        _status(_learning('enough')).chargeLearningTag,
        'Đủ dữ liệu · bấm Huấn luyện',
      );
      expect(
        _status(_learning('enough'), trainAllowed: false).chargeLearningTag,
        'Đủ dữ liệu · Ultra để áp dụng',
      );
    });

    test('no tag once learned, when off, or with an older server', () {
      expect(_status(_learning('learned')).chargeLearningTag, isNull);
      expect(_status(_learning('off')).chargeLearningTag, isNull);
      expect(_status(null).chargeLearningTag, isNull);
    });
  });

  group('capacity has one reading', () {
    test('the corrected value wins over the older fields', () {
      expect(
        VehicleModel.capacityWhFrom({
          'nominalCapacityWh': 2400,
          'batteryCapacityWh': 2600,
          'batteryCapacity': 2600,
        }),
        2400,
      );
    });

    test('older vehicles still read, and nothing is invented', () {
      expect(VehicleModel.capacityWhFrom({'batteryCapacity': 2600}), 2600);
      expect(
        VehicleModel.capacityWhFrom({
          'nominalCapacityWh': 0,
          'batteryCapacityWh': '2340',
        }),
        2340,
      );
      expect(VehicleModel.capacityWhFrom({}), 0);
    });
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('prediction card shows the tag at 320 dp, text x$scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: LuxeTheme.data(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 640),
              textScaler: TextScaler.linear(scale),
            ),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: PredictionCardV2(
                  durationMinutes: 120,
                  stopTime: '21:30',
                  fromSoc: 20,
                  toSoc: 80,
                  personalizationLabel:
                      'Ước tính theo dung lượng xe · nhập % sau sạc để app học',
                  learningTag: 'Đủ dữ liệu · Ultra để áp dụng',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('prediction-learning-tag')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('AI cá nhân shows the tag at 320 dp, text x$scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: LuxeTheme.data(),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 1600),
                textScaler: TextScaler.linear(scale),
              ),
              child: PersonalAiSettingsScreen(
                vehicleId: 'car',
                service: _Service(_status(_learning('learning'))),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.byKey(const ValueKey('model-learning-tag')), findsOneWidget);
      expect(find.text('Đang học · 2/5 lần sạc'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a vehicle that learned shows no tag', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LuxeTheme.data(),
          home: PersonalAiSettingsScreen(
            vehicleId: 'car',
            service: _Service(_status(_learning('learned'))),
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byKey(const ValueKey('model-card-charge')), findsOneWidget);
    expect(find.byKey(const ValueKey('model-learning-tag')), findsNothing);
  });
}
