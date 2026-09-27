import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/data/models/smart_charge_history.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/features/ai/controllers/smart_charging_controller.dart';
import 'package:vinfast_battery/features/ai/smart_charge_history_screen.dart';

class _HistoryRequest {
  _HistoryRequest(this.cursor, this.strategy, this.allVehicles);
  final String? cursor;
  final ChargingStrategy? strategy;
  final bool allVehicles;
  final result = Completer<SmartChargeHistoryPage>();
}

class _DeferredController extends SmartChargingController {
  _DeferredController(String vehicleId)
    : super(vehicleId: vehicleId, currentSoc: 20, autoInitialize: false);

  final requests = <_HistoryRequest>[];
  final telemetryRequests = <Completer<List<SmartChargeTelemetryPoint>>>[];

  @override
  Future<SmartChargeHistoryPage> getHistoryPage({
    int limit = 20,
    String? cursor,
    ChargingStrategy? strategy,
    bool allVehicles = false,
  }) {
    final request = _HistoryRequest(cursor, strategy, allVehicles);
    requests.add(request);
    return request.result.future;
  }

  @override
  Future<List<SmartChargeTelemetryPoint>> getTelemetry(
    String sessionId, {
    String? after,
    int limit = 120,
  }) {
    final request = Completer<List<SmartChargeTelemetryPoint>>();
    telemetryRequests.add(request);
    return request.future;
  }
}

SmartChargingSession _session(String id, {String vehicleId = 'vehicle-a'}) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, 1, 8);
  return SmartChargingSession(
    sessionId: id,
    vehicleId: vehicleId,
    state: ChargingSessionState.completed,
    strategy: ChargingStrategy.aiTarget,
    startSoc: 20,
    targetSoc: 80,
    predictedMinutes: 20,
    predictionSource: 'model',
    createdAt: start,
    updatedAt: start.add(const Duration(minutes: 20)),
    startedAt: start,
    stoppedAt: start.add(const Duration(minutes: 20)),
    aiStopAt: start.add(const Duration(minutes: 20)),
    hardDeadlineAt: start.add(const Duration(hours: 10)),
    effectiveStopAt: start.add(const Duration(minutes: 20)),
    absoluteSafetyStopAt: start.add(const Duration(hours: 10)),
    shadowMode: false,
    version: 1,
    estimatedCapacityWh: 3000,
    energyUsedWh: 100,
  );
}

Finder _row(String id) => find.byKey(ValueKey('history-session-$id'));

Future<void> _mount(
  WidgetTester tester,
  _DeferredController controller, {
  String ownerUid = 'account-a',
  List<SmartChargingSession> initialItems = const [],
}) => tester.pumpWidget(
  MaterialApp(
    home: SmartChargeHistoryScreen(
      controller: controller,
      ownerUid: ownerUid,
      initialItems: initialItems,
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> useLargeViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('initial pending is loading, first failure is not empty', (
    tester,
  ) async {
    await useLargeViewport(tester);
    final controller = _DeferredController('vehicle-a');
    addTearDown(controller.dispose);
    await _mount(tester, controller);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Chưa có phiên Smart Charge hoàn tất'), findsNothing);
    controller.requests.single.result.completeError(StateError('offline'));
    await tester.pump();
    expect(find.text('Không thể đồng bộ lịch sử sạc.'), findsOneWidget);
    expect(find.text('Chưa có phiên Smart Charge hoàn tất'), findsNothing);
    await tester.tap(find.text('THỬ LẠI'));
    controller.requests.last.result.complete(
      const SmartChargeHistoryPage(items: []),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chưa có phiên Smart Charge hoàn tất'), findsOneWidget);
  });

  testWidgets('latest refresh wins when responses arrive in reverse order', (
    tester,
  ) async {
    await useLargeViewport(tester);
    final controller = _DeferredController('vehicle-a');
    addTearDown(controller.dispose);
    await _mount(tester, controller);
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final second = refresh.onRefresh();
    controller.requests[1].result.complete(
      SmartChargeHistoryPage(items: [_session('new')]),
    );
    await second;
    await tester.pumpAndSettle();
    controller.requests[0].result.complete(
      SmartChargeHistoryPage(items: [_session('old')]),
    );
    await tester.pumpAndSettle();
    expect(_row('new'), findsOneWidget);
    expect(_row('old'), findsNothing);
  });

  testWidgets('new query clears old items and ignores previous query failure', (
    tester,
  ) async {
    await useLargeViewport(tester);
    final controller = _DeferredController('vehicle-a');
    addTearDown(controller.dispose);
    await _mount(tester, controller, initialItems: [_session('old')]);
    await tester.tap(find.text('Tất cả xe'));
    await tester.pump();
    expect(controller.requests.last.allVehicles, isTrue);
    expect(_row('old'), findsNothing);
    controller.requests.last.result.complete(
      SmartChargeHistoryPage(items: [_session('new')]),
    );
    await tester.pumpAndSettle();
    controller.requests.first.result.completeError(StateError('old failure'));
    await tester.pumpAndSettle();
    expect(_row('new'), findsOneWidget);
    expect(find.text('Không thể đồng bộ lịch sử sạc.'), findsNothing);
  });

  testWidgets('old page cannot append after a newer refresh', (tester) async {
    await useLargeViewport(tester);
    final controller = _DeferredController('vehicle-a');
    addTearDown(controller.dispose);
    await _mount(tester, controller);
    controller.requests.first.result.complete(
      SmartChargeHistoryPage(
        items: [_session('initial')],
        nextCursor: 'page-2',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('TẢI THÊM'));
    await tester.pump();
    expect(controller.requests[1].cursor, 'page-2');
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final fresh = refresh.onRefresh();
    controller.requests[2].result.complete(
      SmartChargeHistoryPage(items: [_session('fresh')]),
    );
    await fresh;
    await tester.pumpAndSettle();
    controller.requests[1].result.complete(
      SmartChargeHistoryPage(items: [_session('stale-page')]),
    );
    await tester.pumpAndSettle();
    expect(_row('fresh'), findsOneWidget);
    expect(_row('initial'), findsNothing);
    expect(_row('stale-page'), findsNothing);
  });

  testWidgets('UID changes clear cache even if controller is reused', (
    tester,
  ) async {
    await useLargeViewport(tester);
    final controller = _DeferredController('vehicle-a');
    addTearDown(controller.dispose);
    await _mount(tester, controller, initialItems: [_session('old-account')]);
    await _mount(
      tester,
      controller,
      ownerUid: 'account-b',
      initialItems: [_session('old-account')],
    );
    expect(_row('old-account'), findsNothing);
    controller.requests[1].result.complete(
      SmartChargeHistoryPage(items: [_session('new-account')]),
    );
    await tester.pumpAndSettle();
    controller.requests[0].result.complete(
      SmartChargeHistoryPage(items: [_session('late-old-account')]),
    );
    await tester.pumpAndSettle();
    expect(_row('new-account'), findsOneWidget);
    expect(_row('late-old-account'), findsNothing);
  });

  testWidgets('vehicle/controller changes discard old request and cache', (
    tester,
  ) async {
    await useLargeViewport(tester);
    final first = _DeferredController('vehicle-a');
    final second = _DeferredController('vehicle-b');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await _mount(tester, first, initialItems: [_session('old-vehicle')]);
    await _mount(tester, second);
    expect(_row('old-vehicle'), findsNothing);
    second.requests.single.result.complete(
      SmartChargeHistoryPage(
        items: [_session('new-vehicle', vehicleId: 'vehicle-b')],
      ),
    );
    await tester.pumpAndSettle();
    first.requests.single.result.completeError(StateError('late error'));
    await tester.pumpAndSettle();
    expect(_row('new-vehicle'), findsOneWidget);
    expect(find.text('Không thể đồng bộ lịch sử sạc.'), findsNothing);
  });

  testWidgets(
    'failed same-context refresh retains cached rows with stale notice',
    (tester) async {
      await useLargeViewport(tester);
      final controller = _DeferredController('vehicle-a');
      addTearDown(controller.dispose);
      await _mount(tester, controller, initialItems: [_session('cached')]);
      controller.requests.single.result.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(_row('cached'), findsOneWidget);
      expect(
        find.textContaining('Không thể đồng bộ lịch sử sạc.'),
        findsOneWidget,
      );
      expect(find.text('Chưa có phiên Smart Charge hoàn tất'), findsNothing);
    },
  );

  testWidgets('late completion after dispose does not setState', (
    tester,
  ) async {
    final controller = _DeferredController('vehicle-a');
    addTearDown(controller.dispose);
    await _mount(tester, controller);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    controller.requests.single.result.completeError(StateError('late failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail context change ignores previous telemetry error', (
    tester,
  ) async {
    await useLargeViewport(tester);
    final controller = _DeferredController('vehicle-a');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SmartChargeSessionDetailScreen(
          controller: controller,
          session: _session('old'),
          ownerUid: 'a',
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SmartChargeSessionDetailScreen(
          controller: controller,
          session: _session('new'),
          ownerUid: 'b',
        ),
      ),
    );
    controller.telemetryRequests[1].complete([]);
    await tester.pumpAndSettle();
    controller.telemetryRequests[0].completeError(StateError('late telemetry'));
    await tester.pumpAndSettle();
    expect(find.text('Không thể tải dữ liệu biểu đồ.'), findsNothing);
    expect(find.text('Phiên này chưa có telemetry chi tiết.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same detail closes its data when the account changes', (
    tester,
  ) async {
    await useLargeViewport(tester);
    final controller = _DeferredController('vehicle-a');
    addTearDown(controller.dispose);
    final session = _session('private-session');
    await tester.pumpWidget(
      MaterialApp(
        home: SmartChargeSessionDetailScreen(
          controller: controller,
          session: session,
          ownerUid: 'a',
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SmartChargeSessionDetailScreen(
          controller: controller,
          session: session,
          ownerUid: 'b',
        ),
      ),
    );
    expect(controller.telemetryRequests, hasLength(1));
    controller.telemetryRequests.single.complete([]);
    await tester.pumpAndSettle();
    expect(
      find.text('Tài khoản đã thay đổi. Hãy mở lại lịch sử sạc.'),
      findsOneWidget,
    );
    expect(find.text('private-session'), findsNothing);
    expect(find.text('Tổng quan phiên sạc'), findsNothing);
  });
}
