import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charger_status.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/data/services/charging_prediction_adapter.dart';
import 'package:vinfast_battery/data/services/smart_charger_service.dart';
import 'package:vinfast_battery/features/ai/controllers/smart_charging_controller.dart';
import 'package:vinfast_battery/features/ai/smart_charging_control_screen.dart';

void main() {
  testWidgets('renders simple form with advanced controls collapsed', (
    tester,
  ) async {
    final controller = harness();
    await tester.pumpWidget(app(controller));
    expect(find.text('Mục tiêu'), findsOneWidget);
    expect(find.text('SOC hiện tại · Ước tính'), findsOneWidget);
    expect(find.text('Nâng cao'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.byKey(const ValueKey('create-plan-button')), findsOneWidget);
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

  testWidgets('creates preview with source and effective stop', (tester) async {
    final controller = harness();
    await tester.pumpWidget(app(controller));
    final createButton = find.byKey(const ValueKey('create-plan-button'));
    await tester.ensureVisible(createButton);
    await tester.pump();
    await tester.tap(createButton);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('plan-preview')), findsOneWidget);
    expect(find.text('Dừng hiệu lực'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
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
      find.widgetWithText(FilledButton, 'Bật nguồn sạc'),
    );
    expect(startButton.onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    final enabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Bật nguồn sạc'),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('Shelly error explains AI preview remains available', (
    tester,
  ) async {
    final controller = harness();
    controller.seed(controller.state.copyWith(gatewayError: 'Gateway offline'));
    await tester.pumpWidget(app(controller));
    expect(find.textContaining('AI vẫn có thể dự đoán'), findsOneWidget);
    expect(find.byKey(const ValueKey('create-plan-button')), findsOneWidget);
  });

  testWidgets('active session labels estimated SOC and exposes immediate OFF', (
    tester,
  ) async {
    final controller = harness();
    controller.seed(
      controller.state.copyWith(
        phase: SmartChargingViewPhase.active,
        session: sampleSession(),
      ),
    );
    await tester.pumpWidget(app(controller));
    expect(find.byKey(const ValueKey('session-countdown')), findsOneWidget);
    expect(find.text('~25%'), findsOneWidget);
    expect(find.textContaining('Timer đã cài trên Shelly'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('stop-smart-session-button')),
      findsOneWidget,
    );
  });

  testWidgets('history is newest-first and visible', (tester) async {
    final controller = harness();
    controller.seed(
      controller.state.copyWith(history: [sampleSession(state: 'completed')]),
    );
    await tester.pumpWidget(app(controller));
    await tester.scrollUntilVisible(find.text('Lịch sử gần đây'), 300);
    expect(find.text('20 → 80%'), findsOneWidget);
    expect(find.text('completed'), findsOneWidget);
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
        service: WidgetFakeService(),
        predictionAdapter: ChargingPredictionAdapter(
          predictionCall:
              ({
                required vehicleId,
                required currentBattery,
                required targetBattery,
                ambientTempC,
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
