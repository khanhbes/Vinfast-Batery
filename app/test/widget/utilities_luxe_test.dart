import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/providers/app_providers.dart';
import 'package:vinfast_battery/core/theme/app_theme.dart';
import 'package:vinfast_battery/data/models/user_notification.dart';
import 'package:vinfast_battery/features/home/widgets/luxe_vehicle_hero.dart';
import 'package:vinfast_battery/features/notifications/notification_center_screen.dart';
import 'package:vinfast_battery/features/settings/vehicle_spec_detail_screen.dart';
import 'package:vinfast_battery/features/trip_planner/trip_planner_wrapper.dart';

/// Task 119 — LUXE utility screens.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget home, {double scale = 1}) => MaterialApp(
  theme: AppTheme.darkTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
    child: child!,
  ),
  home: home,
);

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('Notifications group by day and open the LUXE sheet x$scale', (
      tester,
    ) async {
      _phone(tester);
      final controller = StreamController<List<UserNotification>>();
      addTearDown(controller.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsProvider.overrideWith((ref, uid) => controller.stream),
          ],
          child: _app(
            const NotificationCenterScreen(
              initialUid: 'qa',
              accountChanges: Stream.empty(),
            ),
            scale: scale,
          ),
        ),
      );
      controller.add([
        UserNotification(
          id: 'a',
          userId: 'qa',
          type: NotificationType.maintenanceDue,
          title: 'Đến hạn bảo dưỡng',
          message: 'Kiểm tra phanh và lốp.',
          status: NotificationStatus.read,
          createdAt: DateTime.now(),
        ),
        UserNotification(
          id: 'b',
          userId: 'qa',
          type: NotificationType.system,
          title: 'Bản cập nhật mới',
          message: 'Có phiên bản ứng dụng mới.',
          status: NotificationStatus.read,
          createdAt: DateTime.now().subtract(const Duration(days: 4)),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('HÔM NAY'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('TRƯỚC ĐÓ'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('TRƯỚC ĐÓ'), findsOneWidget);
      await tester.ensureVisible(find.text('Đến hạn bảo dưỡng'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đến hạn bảo dưỡng'));
      await tester.pumpAndSettle();
      expect(find.text('Bảo dưỡng'), findsOneWidget);
      final close = find.widgetWithText(OutlinedButton, 'Đóng');
      await tester.ensureVisible(close);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.text('Bảo dưỡng'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Vehicle spec toggles edit mode without overflow x$scale', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _app(
          const VehicleSpecDetailScreen(
            vehicleId: 'v1',
            vehicleData: {
              'nickname': 'Feliz của tôi',
              'licensePlate': '59A1-12345',
              'batteryCapacity': 3500,
              'stateOfHealth': 94,
              'currentOdo': 1200,
            },
          ),
          scale: scale,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('XE CỦA BẠN'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(4));
      expect(find.text('ĐANG SỬA'), findsNothing); // tag keeps sentence case
      expect(find.text('Đang sửa'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Trip planner without a vehicle shows LUXE empty x$scale', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            selectedVehicleIdProvider.overrideWith((ref) => ''),
            vehicleProvider.overrideWith((ref, id) => Stream.value(null)),
          ],
          child: _app(const TripPlannerWrapper(), scale: scale),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chọn xe để lập kế hoạch chuyến đi.'), findsOneWidget);
      expect(find.text('Chọn xe ngay'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Scooter art paints at any battery level', (tester) async {
    for (final level in [0.0, 0.42, 1.0]) {
      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: LuxeScooterArt(level: level),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
