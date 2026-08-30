import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charger_status.dart';
import 'package:vinfast_battery/data/models/smart_charger_capabilities.dart';
import 'package:vinfast_battery/data/models/smart_charge_history.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/data/services/charging_prediction_adapter.dart';
import 'package:vinfast_battery/data/services/smart_charger_service.dart';
import 'package:vinfast_battery/features/ai/controllers/smart_charging_controller.dart';
import 'package:vinfast_battery/features/ai/smart_charging_control_screen.dart';

void main() {
  testWidgets('renders user-friendly terminology and target slider', (
    tester,
  ) async {
    final controller = harness();
    await tester.pumpWidget(app(controller));

    // Phase 8, 9 & 10 assertions
    expect(find.text('Pin hiện tại'), findsOneWidget);
    expect(find.text('Pin muốn sạc tới'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('target-battery-selector')),
      findsOneWidget,
    );
    expect(find.text('80%'), findsWidgets);
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('100%'), findsWidgets);
    expect(find.byKey(const ValueKey('create-plan-button')), findsOneWidget);
    expect(find.text('TÍNH THỜI GIAN SẠC'), findsOneWidget);
  });

  testWidgets('fits 320dp width without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(harness()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports large text scale and scroll', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
        child: app(harness()),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates clean preview with duration and stop time', (
    tester,
  ) async {
    final controller = harness();
    await tester.pumpWidget(app(controller));

    final createButton = find.byKey(const ValueKey('create-plan-button'));
    await tester.ensureVisible(createButton);
    await tester.pump();
    await tester.tap(createButton);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('plan-preview')), findsOneWidget);
    expect(find.text('Thời gian dự kiến'), findsOneWidget);
    expect(find.text('Dự kiến dừng lúc'), findsOneWidget);
    expect(find.text('1 giờ 0 phút'), findsOneWidget);
    expect(find.text('BẮT ĐẦU SẠC'), findsOneWidget);
  });

  testWidgets('requires estimated SOC acknowledgement before start', (
    tester,
  ) async {
    final controller = harness();
    await tester.pumpWidget(app(controller));

    final createButton = find.byKey(const ValueKey('create-plan-button'));
    await tester.ensureVisible(createButton);
    await tester.pump();
    await tester.tap(createButton);
    await tester.pump();

    final confirmButton = find.byKey(const ValueKey('confirm-plan-button'));
    await tester.ensureVisible(confirmButton);
    await tester.pump();
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(find.text('Xác nhận bắt đầu sạc'), findsOneWidget);
    final startButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Bắt đầu sạc'),
    );
    expect(startButton.onPressed, isNull);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();

    final enabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Bắt đầu sạc'),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('Shelly error displays error banner with details view', (
    tester,
  ) async {
    final controller = harness();
    controller.seed(
      controller.state.copyWith(gatewayError: 'Không thể kết nối ổ sạc'),
    );
    await tester.pumpWidget(app(controller));

    expect(find.text('Không kết nối được ổ sạc.'), findsOneWidget);
    expect(find.text('Xem chi tiết'), findsOneWidget);
  });

  testWidgets('active session displays live countdown and stop button', (
    tester,
  ) async {
    final controller = harness();
    controller.seed(
      controller.state.copyWith(
        phase: SmartChargingViewPhase.active,
        chargerStatus: const SmartChargerStatus(
          online: true,
          relay: true,
          powerW: 402,
          voltageV: 220,
          currentA: 1.8,
          frequencyHz: 50,
          temperatureC: 32,
          energyWh: 500,
        ),
        session: sampleSession(),
      ),
    );
    await tester.pumpWidget(app(controller));

    expect(find.text('ĐANG SẠC'), findsWidgets);
    expect(find.byKey(const ValueKey('session-countdown')), findsOneWidget);
    expect(find.text('402 W'), findsOneWidget);
    expect(find.text('NGẮT NGUỒN NGAY'), findsOneWidget);
  });

  testWidgets('charger display state maps correctly to UI indicators', (
    tester,
  ) async {
    final controller = harness();
    // Test offline state
    controller.seed(
      controller.state.copyWith(
        chargerStatus: const SmartChargerStatus(
          online: false,
          relay: false,
          powerW: 0,
          voltageV: 0,
          currentA: 0,
          frequencyHz: 0,
          temperatureC: null,
          energyWh: 0,
        ),
      ),
    );
    await tester.pumpWidget(app(controller));
    expect(find.text('Mất kết nối'), findsOneWidget);

    // Test online relay off state
    controller.seed(
      controller.state.copyWith(
        chargerStatus: const SmartChargerStatus(
          online: true,
          relay: false,
          powerW: 0,
          voltageV: 230,
          currentA: 0,
          frequencyHz: 50,
          temperatureC: null,
          energyWh: 0,
        ),
      ),
    );
    await tester.pumpWidget(app(controller));
    expect(find.text('Đã tắt sạc'), findsOneWidget);
  });

  testWidgets('history is visible and cleanly formatted', (tester) async {
    final controller = harness();
    controller.seed(
      controller.state.copyWith(history: [sampleSession(state: 'completed')]),
    );
    await tester.pumpWidget(app(controller));
    await tester.scrollUntilVisible(find.text('Lịch sử gần đây'), 300);
    expect(find.text('20% → 25%'), findsOneWidget);
    expect(find.text('Hoàn thành'), findsOneWidget);
  });
}

Widget app(HarnessController controller) => ProviderScope(
  overrides: [
    smartChargingControllerProvider.overrideWith((ref, args) => controller),
  ],
  child: const MaterialApp(
    home: SmartChargingControlScreen(vehicleId: 'VF-001', currentSoc: 20),
  ),
);

HarnessController harness() {
  final value = HarnessController();
  value.seed(
    value.state.copyWith(
      phase: SmartChargingViewPhase.editing,
      historyStatus: SmartChargeHistoryStatus.empty,
      capabilities: const SmartChargerCapabilities(
        canReadStatus: true,
        canManualOn: true,
        canManualOff: true,
        supportsDeviceTimer: true,
        canReadPower: true,
        canConfigureSafeBoot: true,
        cloudAvailable: true,
        lanAvailable: true,
        safeBootVerified: true,
        noLoadTestVerified: true,
        readyForControl: true,
      ),
      chargerStatus: const SmartChargerStatus(
        online: true,
        relay: false,
        powerW: 0,
        voltageV: 230,
        currentA: 0,
        frequencyHz: 50,
        temperatureC: null,
        energyWh: 100,
      ),
    ),
  );
  return value;
}

class HarnessController extends SmartChargingController {
  HarnessController()
    : super(
        vehicleId: 'VF-001',
        currentSoc: 20,
        estimatedCapacityWh: 3000,
        service: WidgetFakeService(),
        predictionAdapter: ChargingPredictionAdapter(
          predictionCall:
              ({
                required vehicleId,
                required currentBattery,
                required targetBattery,
                ambientTempC,
                bool strictAi = false,
              }) async => {
                'success': true,
                'data': {
                  'predictedDurationMin': 60,
                  'modelSource': 'ai_model',
                  'confidence': 88,
                },
              },
        ),
        clock: _clock,
        autoInitialize: false,
      );

  void seed(SmartChargingUiState value) => state = value;
}

class WidgetFakeService extends SmartChargerService {
  WidgetFakeService() : super(baseUrl: 'http://gateway', tokenProvider: _token);

  @override
  Future<SmartChargingSession> startAutomaticSession(
    SmartChargingSessionRequest request, {
    required String idempotencyKey,
  }) async => sampleSession();

  @override
  Future<SmartChargingSession> stopSession(
    String sessionId, {
    int? expectedVersion,
  }) async => sampleSession(state: 'cancelled');
}

DateTime _clock() => DateTime.parse('2030-01-01T03:00:00Z');
Future<String?> _token() async => 'token';

SmartChargingSession sampleSession({String state = 'active'}) =>
    SmartChargingSession.fromJson({
      'session_id': 'session-1',
      'vehicle_id': 'VF-001',
      'state': state,
      'strategy': 'smart_combined',
      'start_soc': 20,
      'target_soc': 80,
      'predicted_minutes': 60,
      'prediction_source': 'ai_model',
      'created_at': '2030-01-01T03:00:00Z',
      'updated_at': '2030-01-01T03:00:00Z',
      'started_at': '2030-01-01T03:00:00Z',
      'ai_stop_at': '2030-01-01T04:00:00Z',
      'hard_deadline_at': '2030-01-01T05:00:00Z',
      'effective_stop_at': '2030-01-01T04:00:00Z',
      'absolute_safety_stop_at': '2030-01-01T07:00:00Z',
      'relay_verified': true,
      'energy_used_wh': 120,
      'energy_quality': 'good',
      'estimated_soc': 25,
      'shadow_mode': true,
      'version': 2,
    });
