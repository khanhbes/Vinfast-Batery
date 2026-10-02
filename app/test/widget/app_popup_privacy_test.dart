import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/utils/app_error_formatter.dart';
import 'package:vinfast_battery/core/utils/error_mapper.dart';
import 'package:vinfast_battery/core/widgets/app_popup.dart';

void main() {
  setUp(AppPopup.resetForTesting);
  tearDown(AppPopup.resetForTesting);

  Widget host({VoidCallback? onTab, double scale = 1}) => MaterialApp(
    navigatorKey: AppPopup.navigatorKey,
    scaffoldMessengerKey: AppPopup.messengerKey,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: const Center(child: Text('Nội dung')),
      bottomNavigationBar: TextButton(
        onPressed: onTab ?? () {},
        child: const Text('Mở tab Lịch sử'),
      ),
    ),
  );

  testWidgets(
    'errors discard short private values in visible text and semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(host());
        AppPopup.showError('uid=private-user', detail: 'key=private-key');
        await tester.pumpAndSettle();
        expect(find.text(AppErrorFormatter.fallback), findsOneWidget);
        expect(find.textContaining('private'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('private')), findsNothing);
      } finally {
        AppPopup.dismiss();
        semantics.dispose();
      }
    },
  );

  testWidgets('success and info cannot bypass redaction', (tester) async {
    await tester.pumpWidget(host());
    AppPopup.showSuccess('Đã chọn private-device', detail: 'IP: 192.0.2.4');
    await tester.pumpAndSettle();
    expect(find.text('Thông báo'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    expect(find.textContaining('192.0.2.4'), findsNothing);
    AppPopup.dismiss();
    await tester.pump();
    AppPopup.showInfo('secret-token', detail: 'internal.lan');
    await tester.pumpAndSettle();
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining('internal'), findsNothing);
    AppPopup.dismiss();
    await tester.pump();
  });

  testWidgets('safety copy remains specific and keeps navigation tappable', (
    tester,
  ) async {
    var tapped = false;
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(scale: 1.5, onTab: () => tapped = true));
    AppPopup.showWarning(
      'Cảnh báo an toàn sạc',
      detail: 'Dòng điện đang cao (11.5 A).',
      persistent: true,
    );
    await tester.pumpAndSettle();
    expect(find.text('Dòng điện đang cao (11.5 A).'), findsOneWidget);
    await tester.tap(find.text('Mở tab Lịch sử'));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unrecognized safety detail never suggests relay OFF', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    AppPopup.showWarning(
      'Cảnh báo an toàn sạc',
      detail: 'private-token',
      persistent: true,
    );
    await tester.pumpAndSettle();
    expect(find.text(AppNoticeCopy.safetyFallback), findsOneWidget);
    expect(find.text('private-token'), findsNothing);
  });

  testWidgets(
    'dismissed category stays quiet until recovery or failure window',
    (tester) async {
      var now = DateTime(2026, 9, 27);
      AppPopup.resetForTesting(clock: () => now);
      await tester.pumpWidget(host());
      void show(double current) => AppPopup.showWarning(
        'Cảnh báo an toàn sạc',
        detail: 'Dòng điện đang cao (${current.toStringAsFixed(1)} A).',
        persistent: true,
      );
      show(11.5);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Đóng thông báo'));
      await tester.pump();
      now = now.add(const Duration(seconds: 3));
      AppPopup.clearShownErrors();
      show(11.6);
      await tester.pumpAndSettle();
      expect(find.text('Cảnh báo an toàn sạc'), findsNothing);
      now = now.add(const Duration(seconds: 61));
      show(11.7);
      await tester.pumpAndSettle();
      expect(find.text('Cảnh báo an toàn sạc'), findsOneWidget);
      AppPopup.dismiss();
      AppPopup.resetError(
        'Cảnh báo an toàn sạc',
        detail: 'Dòng điện đang cao (11.7 A).',
      );
      show(11.8);
      await tester.pumpAndSettle();
      expect(find.text('Dòng điện đang cao (11.8 A).'), findsOneWidget);
      AppPopup.dismiss();
      await tester.pump();
    },
  );

  testWidgets(
    'explicit retry keeps its callback and does not say debug details',
    (tester) async {
      var retried = false;
      await tester.pumpWidget(host());
      AppPopup.showError(
        'Không thể xuất báo cáo',
        detail: 'permission-denied uid=private',
        action: () => retried = true,
        userInitiated: true,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thử lại'));
      expect(retried, isTrue);
      expect(find.text('Chi tiết'), findsNothing);
      expect(find.textContaining('private'), findsNothing);
      AppPopup.dismiss();
      await tester.pump();
    },
  );

  testWidgets('unexpected errors never expose debug details', (tester) async {
    await tester.pumpWidget(host());
    AppPopup.showError(
      'Lỗi không mong muốn',
      error: ArgumentError('No host specified in URI /api/private'),
      stackTrace: StackTrace.current,
    );
    await tester.pumpAndSettle();
    expect(find.text('Chi tiết'), findsNothing);
    expect(find.textContaining('No host specified'), findsNothing);
    expect(find.textContaining('/api/private'), findsNothing);
    AppPopup.dismiss();
    await tester.pump();
  });
}
