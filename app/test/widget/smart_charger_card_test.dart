import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charger_status.dart';
import 'package:vinfast_battery/features/ai/widgets/smart_charger_card.dart';

const onlineOff = SmartChargerStatus(
  online: true,
  relay: false,
  powerW: 0,
  voltageV: 228.9,
  currentA: 0,
  frequencyHz: 49.8,
  temperatureC: 46.2,
  energyWh: 10,
);

Widget card({
  SmartChargerStatus? status,
  String? error,
  bool loading = false,
  bool commandBusy = false,
  VoidCallback? onTurnOn,
  VoidCallback? onTurnOff,
  VoidCallback? onOpenSmartCharging,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SmartChargerCard(
          status: status,
          error: error,
          loading: loading,
          commandBusy: commandBusy,
          lastUpdated: DateTime(2026, 8, 27, 19),
          onRefresh: () {},
          onTurnOn: onTurnOn ?? () {},
          onTurnOff: onTurnOff ?? () {},
          onOpenSmartCharging: onOpenSmartCharging,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders not configured state', (tester) async {
    await tester.pumpWidget(card(error: 'Smart Charger chưa được cấu hình.'));
    expect(find.text('⚪ Shelly chưa kết nối'), findsOneWidget);
  });

  testWidgets('renders loading state', (tester) async {
    await tester.pumpWidget(card(loading: true));
    expect(find.text('Đang kết nối...'), findsOneWidget);
  });

  testWidgets('renders online relay off telemetry and invokes ON', (
    tester,
  ) async {
    var called = false;
    await tester.pumpWidget(
      card(status: onlineOff, onTurnOn: () => called = true),
    );
    expect(find.text('⚪ Đã ngắt nguồn'), findsOneWidget);
    expect(find.text('0.0 W'), findsOneWidget);
    expect(find.text('0.000 A'), findsOneWidget);
    expect(find.text('228.9 V'), findsOneWidget);
    expect(find.text('49.8 Hz'), findsOneWidget);
    expect(find.text('46.2 °C'), findsOneWidget);
    expect(find.text('Energy 10 Wh'), findsOneWidget);
    await tester.tap(find.text('BẬT NGUỒN SẠC'));
    expect(called, isTrue);
  });

  testWidgets('renders relay on and invokes OFF', (tester) async {
    var called = false;
    const status = SmartChargerStatus(
      online: true,
      relay: true,
      powerW: 400,
      voltageV: 229,
      currentA: 1.7,
      frequencyHz: 50,
      temperatureC: null,
      energyWh: 20,
    );
    await tester.pumpWidget(
      card(status: status, onTurnOff: () => called = true),
    );
    expect(find.text('🟢 Đang cấp nguồn'), findsOneWidget);
    await tester.tap(find.text('NGẮT NGUỒN'));
    expect(called, isTrue);
  });

  testWidgets('renders offline state', (tester) async {
    await tester.pumpWidget(card(error: 'Không thể kết nối Shelly'));
    expect(find.text('🔴 Không kết nối được Shelly'), findsOneWidget);
    expect(find.text('THỬ LẠI'), findsOneWidget);
  });

  testWidgets('busy state disables command', (tester) async {
    var called = false;
    await tester.pumpWidget(
      card(status: onlineOff, commandBusy: true, onTurnOn: () => called = true),
    );
    await tester.tap(find.byKey(const ValueKey('smart-charger-on')));
    expect(called, isFalse);
  });

  testWidgets('opens dedicated smart charging setup', (tester) async {
    var called = false;
    await tester.pumpWidget(
      card(status: onlineOff, onOpenSmartCharging: () => called = true),
    );
    await tester.tap(find.byKey(const ValueKey('open-smart-charging')));
    expect(called, isTrue);
  });
}
