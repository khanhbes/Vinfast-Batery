import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/ai/assistant_sheet.dart';

void main() {
  testWidgets('InteractiveAssistantSheet renders and handles user interactions',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: InteractiveAssistantSheet(),
          ),
        ),
      ),
    );

    // Dùng pump có khoảng thời gian cố định vì Mascot có animation lặp liên tục
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Kiểm tra header và thông điệp chào mừng
    expect(find.text('BatteryBot Copilot'), findsOneWidget);
    expect(find.text('AI Trợ lý'), findsOneWidget);
    expect(
      find.textContaining('Chào bạn! Mình là BatteryBot'),
      findsOneWidget,
    );

    // Kiểm tra quick action chips
    expect(find.text('Xem pin ở đâu?'), findsOneWidget);

    // Chạm vào chip để gửi câu hỏi
    await tester.tap(find.text('Xem pin ở đâu?'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    // Đã có câu hỏi người dùng, phản hồi của Bot và nút hành động chuyển tab
    expect(find.text('Xem pin ở đâu?'), findsNWidgets(2)); // 1 ở chip, 1 ở tin nhắn
    expect(find.textContaining('Tổng quan'), findsAtLeastNWidgets(1));
    expect(find.text('Xem màn hình Tổng quan'), findsOneWidget);

    // Kiểm tra gửi thông tin nhạy cảm bị cảnh báo
    final textField = find.byKey(const Key('assistant_input_field'));
    expect(textField, findsOneWidget);

    await tester.enterText(textField, 'đây là cloud key bí mật 123456');
    final sendButton = find.byKey(const Key('assistant_send_button'));
    expect(sendButton, findsOneWidget);
    await tester.tap(sendButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    final sensitiveWarning =
        find.textContaining('không nên gửi mật khẩu hay khóa truy cập');
    final messageScrollable = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      sensitiveWarning,
      100,
      scrollable: messageScrollable,
    );
    expect(sensitiveWarning, findsOneWidget);
  });
}
