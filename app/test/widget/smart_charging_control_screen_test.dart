import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charger_status.dart';
import 'package:vinfast_battery/data/models/smart_charger_capabilities.dart';
import 'package:vinfast_battery/data/models/smart_charge_history.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/data/models/smart_charger_binding.dart';
import 'package:vinfast_battery/data/services/shelly_connection_coordinator.dart';
import 'package:vinfast_battery/data/services/charging_prediction_adapter.dart';
import 'package:vinfast_battery/data/services/smart_charger_service.dart';
import 'package:vinfast_battery/core/widgets/app_popup.dart';
import 'package:vinfast_battery/features/ai/controllers/smart_charging_controller.dart';
import 'package:vinfast_battery/features/ai/smart_charging_control_screen.dart';
import 'package:vinfast_battery/features/ai/widgets/timed_charging_section_v2.dart';
import 'package:vinfast_battery/core/widgets/luxe_slide_to_confirm.dart';

LuxeSlideToConfirm startSlider(WidgetTester tester) =>
    tester.widget<LuxeSlideToConfirm>(
      find.byKey(const ValueKey('start-charge-slider')),
    );

Future<void> slideToConfirm(WidgetTester tester) async {
  final knob = find.byKey(LuxeSlideToConfirm.knobKey);
  await tester.ensureVisible(knob);
  await tester.pump();
  await tester.drag(knob, const Offset(800, 0));
  await tester.pump();
}

void main() {
  setUp(() => ShellyConnectionCoordinator.shared.activateAccount(null));
  tearDown(AppPopup.dismiss);
  testWidgets('renders user-friendly terminology and target slider', (
    tester,
  ) async {
    final controller = harness();
    await tester.pumpWidget(app(controller));

    // Phase 8, 9 & 10 assertions
    expect(find.text('Mức pin hiện tại'), findsOneWidget);
    expect(find.text('MỤC TIÊU SẠC'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('target-battery-selector')),
      findsOneWidget,
    );
    expect(find.text('80%'), findsWidgets);
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('100%'), findsWidgets);
    expect(find.byKey(const ValueKey('create-plan-button')), findsOneWidget);
    expect(find.text('DỰ ĐOÁN THỜI GIAN SẠC'), findsOneWidget);
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

  testWidgets('timed mode fits 320dp at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: app(harness()),
      ),
    );
    await tester.tap(find.text('Sạc hẹn giờ'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual ON offers immediate and timed safe choices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = harness();
    publishControlConnection(controller);
    await tester.pumpWidget(app(controller));

    await tester.tap(find.text('Sạc hẹn giờ'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ngay lập tức'), findsOneWidget);
    expect(find.text('10 giờ'), findsNothing);
    expect(find.text('Sạc nhanh'), findsNothing);
    expect(find.text('Tiêu chuẩn'), findsNothing);
    expect(find.text('Khuyến dùng'), findsNothing);

    final immediate = find.byKey(const ValueKey('timed-preset--1'));
    await tester.ensureVisible(immediate);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(immediate);
    await tester.pump();
    expect(find.text('Bắt đầu ngay · tự ngắt sau 6 giờ'), findsOneWidget);

    final manualOn = find.byKey(const ValueKey('timed-charge-start-button'));
    await tester.ensureVisible(manualOn);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(manualOn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Xác nhận bắt đầu sạc'), findsOneWidget);
    expect(find.text('Sạc hẹn giờ'), findsWidgets);
    expect(find.text('6 giờ 0 phút'), findsOneWidget);
    expect(startSlider(tester).enabled, isFalse);

    final acknowledgement = find.byType(Checkbox);
    await tester.ensureVisible(acknowledgement);
    await tester.pump();
    await tester.tap(acknowledgement);
    await tester.pump();
    await slideToConfirm(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.lastManualDuration, const Duration(hours: 6));
    // QA 135: the target sent is the % shown on this confirmation, never
    // the AI-mode draft target.
    expect(
      controller.lastManualTarget,
      greaterThanOrEqualTo(controller.state.draft.currentSoc.roundToDouble()),
    );
    expect(controller.lastManualTarget, lessThanOrEqualTo(100));
    AppPopup.dismiss();
    await tester.pump();
  });

  testWidgets('creates clean preview with duration and stop time', (
    tester,
  ) async {
    final controller = harness();
    publishControlConnection(controller);
    await tester.pumpWidget(app(controller));

    final createButton = find.byKey(const ValueKey('create-plan-button'));
    await tester.ensureVisible(createButton);
    await tester.pump();
    await tester.tap(createButton);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('plan-preview')), findsOneWidget);
    expect(find.text('Kế hoạch sạc'), findsOneWidget);
    expect(find.textContaining('Dự kiến dừng lúc'), findsOneWidget);
    // One duration wording on every surface (Task 122).
    expect(find.text('1 giờ'), findsOneWidget);
    expect(find.text('SẠC THEO DỰ ĐOÁN'), findsOneWidget);
  });

  testWidgets('requires estimated SOC acknowledgement before start', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = harness();
    publishControlConnection(controller);
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Xác nhận bắt đầu sạc'), findsOneWidget);
    expect(startSlider(tester).enabled, isFalse);
    // A full slide before the acknowledgement must not start anything.
    await slideToConfirm(tester);
    expect(find.text('Xác nhận bắt đầu sạc'), findsOneWidget);

    final acknowledgement = find.byType(Checkbox);
    await tester.ensureVisible(acknowledgement);
    await tester.pump();
    await tester.tap(acknowledgement);
    await tester.pump();

    expect(startSlider(tester).enabled, isTrue);
  });

  testWidgets(
    'Shelly background error stays in the non-blocking status strip',
    (tester) async {
      final controller = harness();
      controller.seed(
        controller.state.copyWith(gatewayError: 'Không thể kết nối ổ sạc'),
      );
      await tester.pumpWidget(app(controller));
      await tester.pump();
      await tester.pump();

      // Background refresh failures must not open an overlay: the tab bar and
      // Smart Charger controls remain usable while the connection strip carries
      // the current state.
      expect(find.text('Kết nối Shelly chưa ổn định'), findsNothing);
      expect(find.text('CHI TIẾT'), findsNothing);
      expect(find.byTooltip('Đóng thông báo'), findsNothing);
      expect(find.text('Không kết nối được ổ sạc.'), findsNothing);
    },
  );

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
    expect(find.text('Dừng sạc'), findsOneWidget);
  });

  testWidgets('transport online alone never contradicts unlinked Settings', (
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
    expect(find.text('Chưa kết nối Shelly'), findsOneWidget);

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
    expect(find.text('Chưa kết nối Shelly'), findsOneWidget);
    expect(find.textContaining('Shelly trực tuyến'), findsNothing);
    controller.seed(
      controller.state.copyWith(
        capabilities: SmartChargerCapabilities.unavailable,
      ),
    );
    await tester.pumpWidget(app(controller));
    expect(find.text('Chưa kết nối Shelly'), findsOneWidget);
  });

  testWidgets(
    'header follows the shared verified connection and unknown state',
    (tester) async {
      final coordinator = ShellyConnectionCoordinator.shared;
      coordinator.activateAccount('qa-header');
      final controller = harness();
      const binding = SmartChargerBinding(
        deviceId: 'qa-device',
        displayName: 'Shelly QA',
        model: 'S3PL-00112EU',
        provider: 'vault_cloud',
        mode: SmartChargerConnectionMode.serverCloud,
        powerMeterVerified: true,
        safeBootVerified: true,
        noLoadTestVerified: true,
      );
      coordinator.updateServerSnapshot(
        uid: 'qa-header',
        vehicleId: 'VF-001',
        binding: binding,
        status: SmartChargerStatus.fromJson({
          'online': true,
          'relay': false,
          'device_id': 'qa-device',
        }),
      );
      await tester.pumpWidget(app(controller));
      expect(find.text('Đã kết nối Shelly'), findsOneWidget);
      coordinator.markControlUnknown(
        uid: 'qa-header',
        vehicleId: 'VF-001',
        deviceId: 'qa-device',
      );
      await tester.pump();
      expect(
        find.text('Đã liên kết · Chưa xác minh trạng thái'),
        findsOneWidget,
      );
      expect(find.text('Đã kết nối Shelly'), findsNothing);
      coordinator.activateAccount(null);
    },
  );

  testWidgets(
    'timed readiness and reason follow shared link and unknown state',
    (tester) async {
      final controller = harness();
      await tester.pumpWidget(app(controller));
      await tester.tap(find.text('Sạc hẹn giờ'));
      await tester.pump(const Duration(milliseconds: 300));
      TimedChargingSectionV2 section() =>
          tester.widget(find.byType(TimedChargingSectionV2));
      expect(section().readyForControl, isFalse);
      publishControlConnection(
        controller,
        mode: SmartChargerConnectionMode.advancedDirect,
      );
      await tester.pump();
      expect(section().readyForControl, isFalse);
      expect(
        section().disabledReason,
        contains('Liên kết cũ chưa cho phép điều khiển qua máy chủ'),
      );
      // UX107-01: the reason and a setup action sit next to the locked CTA.
      expect(section().onOpenSetup, isNotNull);
      expect(
        find.byKey(const ValueKey('timed-charge-locked-reason')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('timed-charge-open-setup')),
        findsOneWidget,
      );
      publishControlConnection(controller);
      await tester.pump();
      expect(section().readyForControl, isTrue);
      expect(
        find.byKey(const ValueKey('timed-charge-open-setup')),
        findsNothing,
      );
      ShellyConnectionCoordinator.shared.markControlUnknown(
        uid: 'qa-controls',
        vehicleId: 'VF-001',
        deviceId: 'qa-device',
      );
      await tester.pump();
      expect(section().readyForControl, isFalse);
      expect(
        section().disabledReason,
        contains('Chưa xác minh được trạng thái ổ cắm'),
      );
      expect(controller.lastManualDuration, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history is visible and cleanly formatted', (tester) async {
    final controller = harness();
    controller.seed(
      controller.state.copyWith(history: [sampleSession(state: 'completed')]),
    );
    await tester.pumpWidget(app(controller));
    await tester.scrollUntilVisible(find.text('Lịch sử gần đây'), 300);
    expect(find.text('20%'), findsWidgets);
    // Not confirmed by the owner: the estimate carries a "~" (QA 128).
    expect(find.text('~25%'), findsOneWidget);
    expect(find.text('Hoàn thành'), findsOneWidget);
  });
}

Widget app(HarnessController controller) => ProviderScope(
  overrides: [
    smartChargingControllerProvider.overrideWith((ref, args) => controller),
  ],
  child: MaterialApp(
    navigatorKey: AppPopup.navigatorKey,
    scaffoldMessengerKey: AppPopup.messengerKey,
    home: const SmartChargingControlScreen(vehicleId: 'VF-001', currentSoc: 20),
  ),
);

void publishControlConnection(
  HarnessController controller, {
  SmartChargerConnectionMode mode = SmartChargerConnectionMode.serverCloud,
}) {
  final coordinator = ShellyConnectionCoordinator.shared;
  coordinator.activateAccount('qa-controls');
  coordinator.updateServerSnapshot(
    uid: 'qa-controls',
    vehicleId: 'VF-001',
    binding: SmartChargerBinding(
      deviceId: 'qa-device',
      displayName: 'Shelly QA',
      model: 'S3PL-00112EU',
      provider: 'vault_cloud',
      mode: mode,
      powerMeterVerified: true,
      safeBootVerified: true,
      noLoadTestVerified: true,
    ),
    status: SmartChargerStatus.fromJson({
      'online': true,
      'relay': false,
      'device_id': 'qa-device',
    }),
    capabilities: controller.state.capabilities,
  );
}

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
          localOnly: false,
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

  Duration? lastManualDuration;
  double? lastManualTarget;

  @override
  Future<bool> manualOn(Duration duration, {double? targetSoc}) async {
    lastManualDuration = duration;
    lastManualTarget = targetSoc;
    return true;
  }

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
