import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/smart_charge_history.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/features/ai/controllers/smart_charging_controller.dart';
import 'package:vinfast_battery/features/ai/smart_charge_history_screen.dart';
import 'package:vinfast_battery/features/ai/widgets/history_luxe_widgets.dart';

class _Controller extends SmartChargingController {
  _Controller(this.pages, {this.points = const []})
    : super(vehicleId: 'vehicle-a', currentSoc: 20, autoInitialize: false);

  final List<SmartChargingSession> pages;
  final List<SmartChargeTelemetryPoint> points;

  @override
  Future<SmartChargeHistoryPage> getHistoryPage({
    int limit = 20,
    String? cursor,
    ChargingStrategy? strategy,
    bool allVehicles = false,
  }) async => SmartChargeHistoryPage(items: pages);

  @override
  Future<List<SmartChargeTelemetryPoint>> getTelemetry(
    String sessionId, {
    String? after,
    int limit = 120,
  }) async => after == null ? points : const [];
}

SmartChargingSession _session(
  String id,
  DateTime start, {
  ChargingSessionState state = ChargingSessionState.completed,
  ChargingStrategy strategy = ChargingStrategy.aiTarget,
  String quality = 'good',
  double? cost,
}) => SmartChargingSession(
  sessionId: id,
  vehicleId: 'vehicle-a',
  state: state,
  strategy: strategy,
  startSoc: 22,
  targetSoc: 85,
  predictedMinutes: 70,
  predictionSource: 'model',
  createdAt: start,
  updatedAt: start.add(const Duration(minutes: 70)),
  startedAt: start,
  stoppedAt: state.isTerminal ? start.add(const Duration(minutes: 70)) : null,
  aiStopAt: start.add(const Duration(minutes: 70)),
  hardDeadlineAt: start.add(const Duration(hours: 10)),
  effectiveStopAt: start.add(const Duration(minutes: 70)),
  absoluteSafetyStopAt: start.add(const Duration(hours: 10)),
  shadowMode: false,
  version: 1,
  estimatedCapacityWh: 3000,
  energyUsedWh: 1840,
  energyQuality: quality,
  estimatedSoc: 78,
  estimatedCostVnd: cost,
);

List<SmartChargeTelemetryPoint> _points(DateTime start) => [
  for (var i = 0; i < 40; i++)
    SmartChargeTelemetryPoint(
      timestamp: start.add(Duration(minutes: i * 2)),
      elapsedSeconds: i * 120,
      powerAverageW: 900 + (i % 7) * 30,
      powerMinimumW: 880,
      powerMaximumW: 1100,
      voltageV: 229.5,
      currentA: 4.1,
      energyWh: i * 31.0,
      relay: true,
      temperatureC: 31,
    ),
];

/// The page's own scroller (a CustomScrollView), not a nested one inside a
/// row that is disposed once scrolled away (QA 128: chips no longer add a
/// horizontal scroller that used to come first).
Finder _vertical() => find
    .descendant(
      of: find.byType(CustomScrollView).first,
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  setUpAll(() => initializeDateFormatting('vi'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host(Widget child, {double scale = 1}) => MaterialApp(
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: c!,
    ),
    home: child,
  );

  Future<void> phone(
    WidgetTester tester, {
    double width = 320,
    double height = 1400,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 0, 30);
  final yesterday = today.subtract(const Duration(days: 1));
  // Both inside the current month, so the default month view lists them.
  final sameMonth = now.day >= 2;

  for (final scale in [1.0, 2.0]) {
    testWidgets('timeline groups days and fits 320dp at text $scale', (
      tester,
    ) async {
      await phone(tester);
      final controller = _Controller([
        _session('a', today, cost: 5400),
        _session(
          'b',
          today.add(const Duration(minutes: 5)),
          strategy: ChargingStrategy.manualTimed,
          state: ChargingSessionState.cancelled,
        ),
        if (sameMonth) _session('c', yesterday, quality: 'partial'),
        _session(
          'live',
          today.add(const Duration(minutes: 10)),
          state: ChargingSessionState.active,
        ),
      ]);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(SmartChargeHistoryScreen(controller: controller), scale: scale),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('ĐANG SẠC'), findsOneWidget);
      final list = _vertical();
      Future<void> reach(Finder f) async {
        await tester.scrollUntilVisible(f, 200, scrollable: list);
        await tester.pumpAndSettle();
        expect(f, findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      // Newest first: the timed session (b, +5 min) sits above a; reach in
      // display order since scrollUntilVisible only scrolls one way.
      await reach(find.text('HÔM NAY'));
      await reach(find.text('Sạc hẹn giờ'));
      await reach(find.text('Đã dừng'));
      await reach(find.byKey(const ValueKey('history-session-a')));
      if (sameMonth) {
        await reach(find.text('HÔM QUA'));
        await reach(find.byKey(const ValueKey('history-session-c')));
      }
      expect(
        find.byKey(const ValueKey('history-session-live')),
        findsNothing,
        reason: 'the active session lives in its own card, not the timeline',
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('an active filter is always visible and one tap clears it', (
    tester,
  ) async {
    await phone(tester);
    final controller = _Controller([
      _session('ai', today),
      _session(
        'timer',
        today.add(const Duration(minutes: 5)),
        strategy: ChargingStrategy.manualTimed,
      ),
    ]);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(SmartChargeHistoryScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    final list = _vertical();
    expect(find.byKey(const ValueKey('history-active-filter')), findsNothing);
    final timerChip = find.text('Hẹn giờ');
    await tester.ensureVisible(timerChip);
    await tester.tap(timerChip);
    await tester.pumpAndSettle();
    // Task 127: a chip scrolled out of view made a whole month look empty.
    expect(find.byKey(const ValueKey('history-active-filter')), findsOneWidget);
    expect(find.textContaining('Đang lọc: Hẹn giờ'), findsOneWidget);
    expect(find.byKey(const ValueKey('history-session-ai')), findsNothing);
    final clear = find.byKey(const ValueKey('history-clear-filter'));
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-active-filter')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('history-session-ai')),
      200,
      scrollable: list,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty history animates once and offers the charge tab', (
    tester,
  ) async {
    await phone(tester, width: 400, height: 760);
    var started = 0;
    final controller = _Controller(const []);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        SmartChargeHistoryScreen(
          controller: controller,
          onStartCharging: () => started++,
        ),
      ),
    );
    // pumpAndSettle returning proves the illustration does not loop forever.
    await tester.pumpAndSettle();
    // Wrapped filter chips push the empty state lower (QA 128).
    await tester.scrollUntilVisible(
      find.byType(HistoryEmptyArt),
      200,
      scrollable: _vertical(),
    );
    expect(find.byType(HistoryEmptyArt), findsOneWidget);
    expect(find.text('Chưa có phiên Smart Charge hoàn tất'), findsOneWidget);
    // A vertical drag that starts on the summary card (which listens for
    // horizontal month swipes) must still scroll the page.
    final title = find.text('Chưa có phiên Smart Charge hoàn tất');
    final before = tester.getTopLeft(title).dy;
    await tester.drag(find.text('Chi phí'), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dy, lessThan(before - 100));
    await tester.ensureVisible(find.text('Bắt đầu phiên sạc đầu tiên'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bắt đầu phiên sạc đầu tiên'));
    expect(started, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('month arrows move the ring and stop at the current month', (
    tester,
  ) async {
    await phone(tester, width: 400);
    final controller = _Controller(const []);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(SmartChargeHistoryScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    final next = find.byTooltip('Tháng sau');
    final previous = find.byTooltip('Tháng trước');
    String title(DateTime m) =>
        'Tháng ${m.month.toString().padLeft(2, '0')} · ${m.year}';
    expect(find.text(title(now)), findsOneWidget);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text(title(now)), findsOneWidget, reason: 'no future months');
    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(find.text(title(DateTime(now.year, now.month - 1))), findsOneWidget);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text(title(now)), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('session detail sheet fits 320dp at text $scale', (
      tester,
    ) async {
      await phone(tester);
      final start = DateTime(2030, 3, 10, 21);
      final controller = _Controller(const [], points: _points(start));
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          SmartChargeSessionDetailScreen(
            controller: controller,
            session: _session('detail', start, cost: 5400),
            ownerUid: 'a',
            asSheet: true,
          ),
          scale: scale,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('78%'), findsOneWidget);
      expect(find.text('Mục tiêu đặt trước: 85%'), findsOneWidget);
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Tổng quan phiên sạc'),
        200,
        scrollable: list,
      );
      expect(find.text('detail'), findsNothing, reason: 'technical collapsed');
      await tester.scrollUntilVisible(
        find.text('Thông số kỹ thuật & AI'),
        200,
        scrollable: list,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thông số kỹ thuật & AI'));
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('detail keeps metered energy without telemetry (QA 135)', (
    tester,
  ) async {
    // The list showed 1.97 kWh while the detail tile said "—".
    await phone(tester);
    final start = DateTime(2030, 3, 10, 21);
    final controller = _Controller(const []);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        SmartChargeSessionDetailScreen(
          controller: controller,
          session: _session('no-telemetry', start, quality: 'partial'),
          ownerUid: 'a',
          asSheet: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Điện từ lưới'),
      200,
      scrollable: list,
    );
    final tile = find.ancestor(
      of: find.text('Điện từ lưới'),
      matching: find.byType(LuxeGlass),
    );
    expect(
      find.descendant(of: tile.first, matching: find.text('1.84 kWh')),
      findsOneWidget,
    );
    // 1840 Wh over 70 minutes.
    expect(find.text('1.58 kW'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
