import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/widgets/luxe_connection_notice.dart';
import 'package:vinfast_battery/features/ai/widgets/command_progress_strip.dart';

Future<void> _pump(WidgetTester tester, Widget child, double scale) async {
  await tester.binding.setSurfaceSize(const Size(320, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: LuxeTheme.data(),
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: page!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('ON wait: steps, usual time, calm note when slow x$scale', (
      tester,
    ) async {
      var now = DateTime(2026, 10, 18, 9);
      await _pump(
        tester,
        CommandProgressStrip(kind: RelayCommandKind.on, clock: () => now),
        scale,
      );
      expect(find.text('Đang bật sạc'), findsOneWidget);
      expect(find.text('Kiểm tra an toàn và bật ổ có hẹn giờ'), findsOneWidget);
      expect(find.text('· thường 10–20 giây'), findsOneWidget);
      expect(find.byKey(const ValueKey('command-progress-slow')), findsNothing);
      now = now.add(const Duration(seconds: 26));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('26 giây'), findsOneWidget);
      expect(find.byKey(const ValueKey('command-progress-slow')), findsOneWidget);
      expect(find.textContaining('không gửi lại lệnh bật'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('verified closes the wait with a check x$scale', (tester) async {
      await _pump(
        tester,
        const CommandProgressStrip(kind: RelayCommandKind.on, verified: true),
        scale,
      );
      await tester.pumpAndSettle();
      expect(find.text('Đã bật sạc · đã xác minh'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsWidgets);
      expect(find.byKey(const ValueKey('command-progress-elapsed')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('connection notice counts down and retries itself x$scale', (
      tester,
    ) async {
      var now = DateTime(2026, 10, 18, 9);
      var calls = 0;
      await _pump(
        tester,
        LuxeConnectionNotice(
          issue: ConnectionIssue.charger,
          lastGoodAt: DateTime(2026, 10, 18, 8, 55),
          clock: () => now,
          onRetry: () async => calls++,
        ),
        scale,
      );
      expect(find.text('Ổ Shelly đang ngoại tuyến'), findsOneWidget);
      expect(find.text('Lần đọc tốt gần nhất 08:55'), findsOneWidget);
      expect(find.text('Tự thử lại sau 5 giây'), findsOneWidget);
      now = now.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(calls, 1, reason: 'automatic retry at 5 s');
      expect(find.text('Tự thử lại sau 15 giây'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('connection-notice-retry')),
      );
      await tester.tap(find.byKey(const ValueKey('connection-notice-retry')));
      await tester.pump();
      expect(calls, 2, reason: 'manual retry');
      expect(tester.takeException(), isNull);
    });

    testWidgets('retry shows progress while it runs x$scale', (tester) async {
      final done = Completer<void>();
      await _pump(
        tester,
        LuxeConnectionNotice(
          issue: ConnectionIssue.server,
          autoRetry: false,
          onRetry: () => done.future,
        ),
        scale,
      );
      await tester.tap(find.byKey(const ValueKey('connection-notice-retry')));
      await tester.pump();
      expect(find.text('Đang kết nối lại…'), findsOneWidget);
      expect(find.text('Đang thử'), findsOneWidget);
      done.complete();
      await tester.pump();
      expect(find.text('Thử lại ngay'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact strip fits the app bar x$scale', (tester) async {
      await _pump(
        tester,
        LuxeConnectionNotice(
          compact: true,
          issue: ConnectionIssue.internet,
          autoRetry: false,
          nextRetryAt: DateTime.now().add(const Duration(seconds: 30)),
          onRetry: () async {},
        ),
        scale,
      );
      expect(find.text('Mất kết nối Internet'), findsOneWidget);
      expect(find.textContaining('Tự thử lại sau'), findsOneWidget);
      expect(
        find.text('Thử lại'),
        scale > 1.3 ? findsNothing : findsOneWidget,
        reason: 'icon-only button at large text',
      );
      expect(find.byKey(const ValueKey('connection-notice-retry')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
