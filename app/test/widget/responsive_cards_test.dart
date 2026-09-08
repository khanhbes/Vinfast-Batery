import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/widgets/responsive_card_grid.dart';
import 'package:vinfast_battery/core/widgets/stat_card.dart';
import 'package:vinfast_battery/core/widgets/empty_state.dart';
import 'package:vinfast_battery/core/widgets/error_state.dart';

void main() {
  for (final width in [320.0, 360.0, 375.0, 412.0, 768.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('cards fit $width at $scale and align within each row', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ResponsiveCardGrid(
                      children: [
                        for (var i = 0; i < 4; i++)
                          StatCard(
                            key: ValueKey(i),
                            icon: Icons.bolt,
                            iconColor: Colors.green,
                            title: i.isEven
                                ? 'Pin'
                                : 'Thời gian sạc trung bình mỗi phiên',
                            value: i.isEven ? '100%' : '123456.7 Wh',
                            subtitle: i.isEven
                                ? null
                                : 'Dữ liệu do người dùng xác nhận',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final rects = [
          for (var i = 0; i < 4; i++) tester.getRect(find.byKey(ValueKey(i))),
        ];
        for (final rect in rects) {
          expect(rect.left, greaterThanOrEqualTo(20));
          expect(rect.right, lessThanOrEqualTo(width - 20 + .01));
          expect(rect.width, closeTo(rects.first.width, .01));
          for (final other in rects.where((r) => r.top == rect.top)) {
            expect(rect.height, closeTo(other.height, .01));
          }
        }
      });
    }
  }
  for (final error in [true, false]) {
    testWidgets('short viewport keeps ${error ? "retry" : "add"} reachable', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 240));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: error
                  ? ErrorState(
                      message:
                          'Không thể tải dữ liệu. Vui lòng kiểm tra kết nối.',
                      retryLabel: 'Kết nối và thử lại',
                      onRetry: () => tapped = true,
                    )
                  : EmptyState(
                      title: 'Chưa có phiên sạc',
                      message: 'Thêm dữ liệu để xem thống kê.',
                      actionLabel: 'Thêm phiên sạc mới',
                      onAction: () => tapped = true,
                    ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final button = find.byWidgetPredicate((w) => w is ButtonStyleButton);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
