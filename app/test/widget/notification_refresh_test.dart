import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/user_notification.dart';
import 'package:vinfast_battery/features/notifications/notification_center_screen.dart';

UserNotification item(String uid, String title) => UserNotification(
  id: 'fixture',
  userId: uid,
  type: NotificationType.system,
  title: title,
  message: 'Nội dung cập nhật',
  createdAt: DateTime(2026, 10, 6),
);

void main() {
  testWidgets('refresh waits for actual new data, not a fixed delay', (
    tester,
  ) async {
    final reads = <StreamController<List<UserNotification>>>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsProvider.overrideWith((ref, uid) {
            final controller = StreamController<List<UserNotification>>();
            reads.add(controller);
            ref.onDispose(controller.close);
            return controller.stream;
          }),
        ],
        child: const MaterialApp(
          home: NotificationCenterScreen(
            initialUid: 'qa',
            accountChanges: Stream.empty(),
          ),
        ),
      ),
    );
    reads.last.add([item('qa', 'Thông báo trước')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Thông báo trước'), findsOneWidget);
    var completed = false;
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh()
        .then((_) => completed = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(completed, isFalse);
    expect(reads.length, 2);
    reads.last.add([item('qa', 'Thông báo mới')]);
    await tester.pump();
    await tester.pump();
    await refresh;
    expect(completed, isTrue);
    expect(find.text('Thông báo mới'), findsOneWidget);
    expect(find.text('Thông báo trước'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'timeout keeps prior data and a retry, never a false empty state',
    (tester) async {
      final reads = <StreamController<List<UserNotification>>>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsProvider.overrideWith((ref, uid) {
              final controller = StreamController<List<UserNotification>>();
              reads.add(controller);
              ref.onDispose(controller.close);
              return controller.stream;
            }),
          ],
          child: const MaterialApp(
            home: NotificationCenterScreen(
              initialUid: 'qa',
              accountChanges: Stream.empty(),
              refreshTimeout: Duration(seconds: 1),
            ),
          ),
        ),
      );
      reads.last.add([item('qa', 'Dữ liệu đã tải')]);
      await tester.pump();
      await tester.pump();
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await refresh;
      await tester.pump();
      expect(find.text('Dữ liệu đã tải'), findsOneWidget);
      expect(
        find.text('Chưa cập nhật được. Đang hiển thị dữ liệu cũ.'),
        findsOneWidget,
      );
      expect(find.text('Thử lại'), findsOneWidget);
      expect(find.text('Chưa có thông báo'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account change clears previous account data during pending refresh',
    (tester) async {
      final accounts = StreamController<String?>.broadcast(sync: true);
      final reads = <String, StreamController<List<UserNotification>>>{};
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsProvider.overrideWith((ref, uid) {
              final controller = StreamController<List<UserNotification>>();
              reads[uid] = controller;
              ref.onDispose(controller.close);
              return controller.stream;
            }),
          ],
          child: MaterialApp(
            home: NotificationCenterScreen(
              initialUid: 'a',
              accountChanges: accounts.stream,
              refreshTimeout: const Duration(seconds: 1),
            ),
          ),
        ),
      );
      reads['a']!.add([item('a', 'Thông báo A')]);
      await tester.pump();
      await tester.pump();
      var completed = false;
      tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh()
          .then((_) => completed = true);
      await tester.pump();
      accounts.add('b');
      await tester.pump();
      await tester.pump();
      expect(find.text('Thông báo A'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(completed, isTrue);
      await tester.pump();
      expect(
        find.text('Chưa cập nhật được. Đang hiển thị dữ liệu cũ.'),
        findsNothing,
      );
      reads['b']!.add([item('b', 'Thông báo B')]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Thông báo B'), findsOneWidget);
      expect(find.text('Thông báo A'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await accounts.close();
    },
  );
}
