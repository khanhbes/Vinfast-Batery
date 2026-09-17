import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vinfast_battery/features/more/more_screen.dart';

void main() {
  testWidgets('MoreScreen renders Driver Profile Hub sections properly',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MoreScreen(),
          ),
        ),
      ),
    );

    // Allow entrance animations to settle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Section headers
    expect(find.text('PHƯƠNG TIỆN & SẠC'), findsOneWidget);
    expect(find.text('HỆ THỐNG & TRÍ TUỆ AI'), findsOneWidget);
    expect(find.text('HỖ TRỢ & TÀI KHOẢN'), findsOneWidget);

    // Key action tiles
    expect(find.text('Garage xe của tôi'), findsOneWidget);
    expect(find.text('Sạc thông minh Shelly'), findsOneWidget);
    expect(find.text('Lộ trình sạc'), findsOneWidget);
    expect(find.text('Trợ lý AI & Dự báo Pin'), findsOneWidget);
    expect(find.text('Bảo dưỡng xe'), findsOneWidget);
    expect(find.text('Cài đặt hệ thống'), findsOneWidget);
    expect(find.text('Cẩm nang & Cứu hộ 24/7'), findsOneWidget);
    expect(find.text('Trung tâm thông báo'), findsOneWidget);

    // Sign out button & branding footer
    expect(find.text('Đăng xuất tài khoản'), findsOneWidget);
    expect(find.textContaining('VinFast Battery'), findsOneWidget);
  });
}
