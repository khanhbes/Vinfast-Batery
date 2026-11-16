import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/app_connection.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/widgets/battery_bot_mascot.dart';
import 'package:vinfast_battery/core/widgets/error_state.dart';
import 'package:vinfast_battery/core/widgets/luxe_kit.dart';
import 'package:vinfast_battery/core/widgets/offline_dock.dart';

/// Wi-Fi, never changing (the network is driven by `debugNetwork`).
class _QuietNetwork implements Connectivity {
  @override
  Stream<ConnectivityResult> get onConnectivityChanged =>
      const Stream<ConnectivityResult>.empty();

  @override
  Future<ConnectivityResult> checkConnectivity() async =>
      ConnectivityResult.wifi;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// QA 161 (owner's choice, 16/11/2026): offline is a floating card above
/// the tabs with "Thử lại" (and "Cài đặt mạng" without Internet), a stamp
/// "Ngoại tuyến · cập nhật lúc …" on every page, and one empty look for a
/// page with nothing saved. The check runs without the sign-in token.
void main() {
  late ProbeOutcome outcome;
  late int probes;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    outcome = ProbeOutcome.failed;
    probes = 0;
    AppConnection.instance = AppConnection(
      connectivity: _QuietNetwork(),
      probe: () async {
        probes++;
        return (
          outcome: outcome,
          reason: outcome == ProbeOutcome.failed ? 'hết thời gian chờ' : null,
        );
      },
    );
  });

  tearDown(() {
    AppConnection.instance.stop();
  });

  /// Lets the card's switch animation finish and the old child leave.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> goOffline(WidgetTester tester) async {
    await tester.runAsync(() => AppConnection.instance.start());
    await tester.runAsync(() => AppConnection.instance.check());
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    AppConnection.instance.stop();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  Widget app(Widget home, {double scale = 1}) => MaterialApp(
    theme: LuxeTheme.data(),
    navigatorObservers: [OfflineDock.observer],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: OfflineDock(child: child!),
    ),
    home: home,
  );

  group('AppConnection', () {
    test('one failed check is ignored, the second says why', () async {
      await AppConnection.instance.start();
      expect(AppConnection.instance.value.offline, isFalse);
      await AppConnection.instance.check();
      final link = AppConnection.instance.value;
      expect(link.issue.toString(), contains('server'));
      expect(link.reason, 'hết thời gian chờ');
      expect(link.nextProbeAt, isNotNull);
    });

    test('an answer from the server brings it back at once', () async {
      await AppConnection.instance.start();
      await AppConnection.instance.check();
      expect(AppConnection.instance.value.offline, isTrue);
      AppConnection.instance.sawServer();
      final link = AppConnection.instance.value;
      expect(link.offline, isFalse);
      expect(link.recoveredAt, isNotNull);
      expect(link.lastOnlineAt, isNotNull);
    });

    test('no network is said at once, without a server check', () async {
      outcome = ProbeOutcome.ready;
      await AppConnection.instance.start();
      final before = probes;
      AppConnection.instance.debugNetwork(online: false);
      expect(
        AppConnection.instance.value.issue.toString(),
        contains('internet'),
      );
      expect(probes, before);
      AppConnection.instance.debugNetwork(online: true);
      await Future<void>.delayed(Duration.zero);
      expect(AppConnection.instance.value.offline, isFalse);
    });

    test('a page swap keeps the check running (two holders)', () async {
      outcome = ProbeOutcome.ready;
      await AppConnection.instance.start();
      await AppConnection.instance.start();
      AppConnection.instance.stop();
      expect(AppConnection.instance.started, isTrue);
    });
  });

  test('the stamp says how old the page is', () {
    final now = DateTime(2026, 11, 16, 14, 30);
    expect(
      OfflineStamp.text(DateTime(2026, 11, 16, 14, 5), now: now),
      'Ngoại tuyến · cập nhật lúc 14:05',
    );
    expect(
      OfflineStamp.text(DateTime(2026, 11, 15, 9, 2), now: now),
      'Ngoại tuyến · cập nhật lúc 09:02 15/11',
    );
    expect(
      OfflineStamp.text(null, now: now),
      'Ngoại tuyến · đang dùng dữ liệu đã lưu',
    );
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the floating card at 320 dp x$scale', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(
          const LuxeScaffold(title: 'Bảo dưỡng', body: SizedBox.expand()),
          scale: scale,
        ),
      );
      expect(find.byKey(const ValueKey('offline-card')), findsNothing);
      await goOffline(tester);
      await settle(tester);
      expect(find.text('Chưa liên lạc được máy chủ'), findsOneWidget);
      expect(find.textContaining('Lý do: hết thời gian chờ.'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      expect(find.text('Cài đặt mạng'), findsNothing);
      // QA 162: Pinova Bot tells it.
      expect(find.byType(BatteryBotMascot), findsOneWidget);
      expect(find.textContaining('Mình chưa gọi được máy chủ'), findsOneWidget);
      // The page keeps its content, marked as old.
      expect(find.byKey(const ValueKey('offline-stamp')), findsOneWidget);
      expect(tester.takeException(), isNull);
      final retry = tester.getSize(find.byKey(const ValueKey('offline-retry')));
      expect(retry.height, greaterThanOrEqualTo(48));

      // The cross folds it into a pill; the pill opens it again.
      await tester.tap(find.byKey(const ValueKey('offline-close')));
      await settle(tester);
      expect(find.text('Ngoại tuyến'), findsOneWidget);
      expect(find.text('Chưa liên lạc được máy chủ'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('offline-pill-tap')));
      await settle(tester);
      expect(find.text('Chưa liên lạc được máy chủ'), findsOneWidget);
      await finish(tester);
    });
  }

  testWidgets('without Internet the card offers the network settings', (
    tester,
  ) async {
    await tester.pumpWidget(app(const Scaffold(body: SizedBox.expand())));
    outcome = ProbeOutcome.ready;
    await tester.runAsync(() => AppConnection.instance.start());
    AppConnection.instance.debugNetwork(online: false);
    await settle(tester);
    expect(find.text('Mất kết nối Internet'), findsOneWidget);
    expect(find.text('Cài đặt mạng'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('back online: "Đã kết nối lại", then nothing', (tester) async {
    await tester.pumpWidget(app(const Scaffold(body: SizedBox.expand())));
    await goOffline(tester);
    await settle(tester);
    AppConnection.instance.sawServer();
    await settle(tester);
    expect(find.text('Đã kết nối lại'), findsOneWidget);
    expect(find.byType(BatteryBotMascot), findsOneWidget);
    await tester.pump(OfflineDock.recoveredFor);
    await settle(tester);
    expect(find.text('Đã kết nối lại'), findsNothing);
    expect(find.byKey(const ValueKey('offline-card')), findsNothing);
    await finish(tester);
  });

  testWidgets('the card hides under a sheet', (tester) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const SizedBox(height: 200),
                ),
                child: const Text('Mở'),
              ),
            ),
          ),
        ),
      ),
    );
    await goOffline(tester);
    await settle(tester);
    expect(find.text('Chưa liên lạc được máy chủ'), findsOneWidget);
    await tester.tap(find.text('Mở'));
    await tester.pump();
    await settle(tester);
    expect(find.text('Chưa liên lạc được máy chủ'), findsNothing);
    await finish(tester);
  });

  testWidgets('a page that could not load shows the same cloud and reloads '
      'by itself', (tester) async {
    var reloads = 0;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ErrorState.fromError(
            error: Exception('x'),
            prefix: 'Không tải được lịch bảo dưỡng',
            onRetry: () => reloads++,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('offline-empty')), findsNothing);
    await goOffline(tester);
    await settle(tester);
    expect(find.byKey(const ValueKey('offline-empty')), findsOneWidget);
    expect(find.text('Không tải được lịch bảo dưỡng'), findsOneWidget);
    AppConnection.instance.sawServer();
    await tester.pump();
    expect(reloads, 1);
    await finish(tester);
  });

  testWidgets('a tab inside a stamped page is not stamped twice', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const OfflineStamped(
          child: LuxeScaffold(title: 'Trong tab', body: SizedBox.expand()),
        ),
      ),
    );
    await goOffline(tester);
    await settle(tester);
    expect(find.byKey(const ValueKey('offline-stamp')), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a server-only action says it needs the connection', (
    tester,
  ) async {
    await tester.pumpWidget(app(const Scaffold(body: SizedBox.expand())));
    expect(OnlineGate.allows('bật sạc'), isTrue);
    await goOffline(tester);
    expect(OnlineGate.offline, isTrue);
    await finish(tester);
  });
}
