import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/services/assistant_context_coordinator.dart';
import 'package:vinfast_battery/core/widgets/floating_battery_bot.dart';

void main() {
  testWidgets('FloatingBatteryBot renders in tree and toggles bubble',
      (tester) async {
    final coordinator = AssistantContextCoordinator();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assistantContextCoordinatorProvider.overrideWith((ref) => coordinator),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                FloatingBatteryBot(),
              ],
            ),
          ),
        ),
      ),
    );

    // Ban đầu nút bot hiển thị nhưng không có bong bóng thoại
    expect(find.byType(FloatingBatteryBot), findsOneWidget);
    expect(find.text('Bong bóng thoại test'), findsNothing);

    // Kích hoạt hiển thị bong bóng
    coordinator.showBubble('Bong bóng thoại test');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Bong bóng thoại test'), findsOneWidget);

    // Chạm vào nút đóng icon để đóng bong bóng
    final closeIcon = find.byIcon(Icons.close);
    expect(closeIcon, findsOneWidget);
    await tester.tap(closeIcon);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(coordinator.isBubbleVisible, isFalse);
    expect(find.text('Bong bóng thoại test'), findsNothing);
  });
}
