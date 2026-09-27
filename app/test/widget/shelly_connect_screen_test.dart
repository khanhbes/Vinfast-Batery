import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/data/services/shelly_connection_coordinator.dart';
import 'package:vinfast_battery/features/smart_charging/shelly_connect_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'developerModeUnlocked': false});
    await ShellyConnectionCoordinator.shared.restore();
  });

  testWidgets('renders safe connection recovery without exposing identifiers', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ShellyConnectScreen()));
    // Allow async _restore() to complete
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Renders the setup shell and gives recovery choices when cloud restore
    // cannot be checked in this unauthenticated widget test.
    expect(find.text('Smart Charger'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.text('Qua Bước 2: Cloud'), findsOneWidget);
    expect(find.text('Qua Bước 3: Mã Admin'), findsOneWidget);

    // Strict Normal Mode security assertion: Never leaks technical credentials
    expect(find.text('Authorization Cloud Key'), findsNothing);
    expect(find.text('Device ID'), findsNothing);
    expect(find.text('Server URI'), findsNothing);
    expect(find.text('RPC endpoint'), findsNothing);
    expect(find.textContaining('ID:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('developer shortcut is hidden when developer mode is locked', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'developerModeUnlocked': false});

    await tester.pumpWidget(const MaterialApp(home: ShellyConnectScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.tune_rounded), findsNothing);
    expect(
      find.text('Mở cấu hình kỹ thuật nâng cao (Developer)'),
      findsNothing,
    );
  });

  testWidgets('developer shortcut appears when developer mode is unlocked', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'developerModeUnlocked': true});

    await tester.pumpWidget(const MaterialApp(home: ShellyConnectScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // AppBar developer shortcut action icon
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

    // Bottom banner scrolled into view
    final banner = find.text('Mở cấu hình kỹ thuật nâng cao (Developer)');
    await tester.scrollUntilVisible(banner, 150);
    expect(banner, findsOneWidget);
  });

  testWidgets(
    'can switch between Flow 1, Flow 2 (Cloud) and Flow 3 (Admin Code)',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ShellyConnectScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      // Restore failure must leave Cloud and administrator setup recoverable.
      final cloudStep = find.text('Qua Bước 2: Cloud');
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(cloudStep);
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('Kết nối từ xa qua Shelly Cloud'), findsOneWidget);
      expect(find.text('Mã xác thực Shelly Cloud'), findsOneWidget);
      final mainScrollable = find.byType(Scrollable).first;
      final cloudSearchBtn = find.text('Tìm thiết bị trên Cloud');
      await tester.scrollUntilVisible(
        cloudSearchBtn,
        100,
        scrollable: mainScrollable,
      );
      expect(cloudSearchBtn, findsOneWidget);

      // Switch to Flow 3 (Admin Code) via the visible step tab.
      final adminTab = find.text('3. Mã Admin');
      await tester.drag(find.byType(ListView).first, const Offset(0, 260));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.ensureVisible(adminTab);
      await tester.tap(adminTab);
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('Nhập mã kết nối từ Admin'), findsOneWidget);
      expect(find.text('Xác nhận mã kết nối'), findsOneWidget);

      // Enter short code and verify validation message
      await tester.enterText(find.byType(TextField), 'AB');
      await tester.tap(find.text('Xác nhận mã kết nối'));
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('Mã kết nối phải có đúng 6 ký tự.'), findsOneWidget);

      // Scroll back to top and switch to Flow 1 via step tab
      await tester.fling(mainScrollable, const Offset(0, 500), 1000);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('1. Wi-Fi gần'));
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('Tìm và kết nối Shelly'), findsOneWidget);
    },
  );
}
