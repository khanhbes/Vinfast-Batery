import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/providers/app_providers.dart';
import 'package:vinfast_battery/core/providers/entitlement_provider.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/entitlement.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/repositories/charge_log_repository.dart';
import 'package:vinfast_battery/features/achievements/achievements_screen.dart';
import 'package:vinfast_battery/features/ai/ai_models_screen.dart';
import 'package:vinfast_battery/features/ai/smart_charging_control_screen.dart';
import 'package:vinfast_battery/features/auth/getting_started_screen.dart';
import 'package:vinfast_battery/features/auth/login_screen.dart';
import 'package:vinfast_battery/features/auth/onboarding_chat_screen.dart';
import 'package:vinfast_battery/features/auth/password_reset_screen.dart';
import 'package:vinfast_battery/features/auth/register_screen.dart';
import 'package:vinfast_battery/features/battery_monitor/battery_health_screen.dart';
import 'package:vinfast_battery/features/battery_monitor/battery_monitor_screen.dart';
import 'package:vinfast_battery/features/maintenance/maintenance_screen.dart';
import 'package:vinfast_battery/features/more/more_screen.dart';
import 'package:vinfast_battery/features/notifications/notification_center_screen.dart';
import 'package:vinfast_battery/features/overview/overview_screen.dart';
import 'package:vinfast_battery/features/premium/premium_screen.dart';
import 'package:vinfast_battery/features/settings/appearance_screen.dart';
import 'package:vinfast_battery/features/settings/assistant_memory_screen.dart';
import 'package:vinfast_battery/features/settings/guide_screen.dart';
import 'package:vinfast_battery/features/settings/personal_ai_settings_screen.dart';
import 'package:vinfast_battery/features/settings/profile_screen.dart';
import 'package:vinfast_battery/features/settings/settings_screen.dart';
import 'package:vinfast_battery/features/settings/vehicle_garage_screen.dart';
import 'package:vinfast_battery/features/smart_charging/night_charging_screen.dart';
import 'package:vinfast_battery/features/smart_charging/shelly_connect_screen.dart';
import 'package:vinfast_battery/features/smart_charging/smart_charger_setup_hub_screen.dart';
import 'package:vinfast_battery/features/support/help_center_screen.dart';
import 'package:vinfast_battery/features/trip_planner/trip_planner_screen.dart';

/// QA 138 review (26/10/2026): every screen at the narrowest phone width
/// (320 dp) with text ×1 and ×2 — no overflow, no exception, no timer left
/// running after the screen closes — plus 48 dp labelled tap targets.
///
/// Screens that read Firebase directly cannot be built here; they are
/// checked on the phone. Open findings stay listed (skipped) until fixed:
/// remove a line from [_openIssues] when its fix lands.
const _needsFirebase = {
  'Sạc pin',
  'Bảo dưỡng',
  'Hồ sơ',
  'Thông báo',
  'Thiết lập Shelly',
  'AI cá nhân',
};
// QA-08 (fixed): Cài đặt, Giao diện, Thành tựu at x2 and the trip map label.
const _openIssues = <String>{};
final _car = VehicleModel(
  vehicleId: 'car',
  vehicleName: 'VinFast Feliz',
  ownerUid: 'u1',
  currentOdo: 5019,
  currentBattery: 31,
);

class _Repo implements ChargeLogRepository {
  @override
  Stream<VehicleModel?> watchVehicle(String vehicleId) => Stream.value(_car);

  @override
  Future<VehicleModel?> getVehicle(String vehicleId) async => _car;

  @override
  Future<List<VehicleModel>> getAllVehicles() async => [_car];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Plan extends EntitlementNotifier {
  _Plan(this.tier);
  final PlanTier tier;

  @override
  Entitlement build() => Entitlement.fromMap({
    'tier': tier.id,
    'status': tier == PlanTier.free ? 'none' : 'active',
    'trialAvailable': tier == PlanTier.free,
    'features': {
      for (final f in PremiumFeature.values) f.id: tier.covers(f.tier),
    },
    'enforced': true,
  });

  @override
  Future<void> refresh() async {}
}

typedef _Screen = ({String name, PlanTier tier, Widget Function() build});

final List<_Screen> _screens = [
  (name: 'Cài đặt', tier: PlanTier.free, build: () => const MoreScreen()),
  (
    name: 'Pinova Premium',
    tier: PlanTier.free,
    build: () => const PremiumScreen(),
  ),
  (name: 'Tổng quan', tier: PlanTier.free, build: () => const OverviewScreen()),
  (
    name: 'Sạc pin',
    tier: PlanTier.free,
    build: () =>
        const SmartChargingControlScreen(vehicleId: 'car', currentSoc: 31),
  ),
  (
    name: 'Bảo dưỡng',
    tier: PlanTier.free,
    build: () => const MaintenanceScreen(),
  ),
  (name: 'Hồ sơ', tier: PlanTier.free, build: () => const ProfileScreen()),
  (
    name: 'Xe của tôi',
    tier: PlanTier.free,
    build: () => const VehicleGarageScreen(),
  ),
  (
    name: 'Cài đặt hệ thống',
    tier: PlanTier.free,
    build: () => const SettingsScreen(),
  ),
  (
    name: 'Giao diện',
    tier: PlanTier.free,
    build: () => const AppearanceScreen(),
  ),
  (
    name: 'Thành tựu',
    tier: PlanTier.free,
    build: () => const AchievementsScreen(),
  ),
  (
    name: 'Trợ giúp',
    tier: PlanTier.free,
    build: () => const HelpCenterScreen(),
  ),
  (
    name: 'Hướng dẫn sử dụng',
    tier: PlanTier.free,
    build: () => const GuideScreen(),
  ),
  (
    name: 'Pinova Bot nhớ gì',
    tier: PlanTier.free,
    build: () => const AssistantMemoryScreen(),
  ),
  (
    name: 'Thông báo',
    tier: PlanTier.free,
    build: () => const NotificationCenterScreen(),
  ),
  (
    name: 'Theo dõi pin',
    tier: PlanTier.free,
    build: () => BatteryMonitorScreen(vehicle: _car),
  ),
  (
    name: 'Mô hình AI',
    tier: PlanTier.free,
    build: () => const AiModelsScreen(),
  ),
  (
    name: 'Kết nối Shelly',
    tier: PlanTier.free,
    build: () => const ShellyConnectScreen(),
  ),
  (
    name: 'Thiết lập Shelly',
    tier: PlanTier.free,
    build: () => const SmartChargerSetupHubScreen(),
  ),
  (name: 'Đăng nhập', tier: PlanTier.free, build: () => const LoginScreen()),
  (name: 'Đăng ký', tier: PlanTier.free, build: () => const RegisterScreen()),
  (
    name: 'Quên mật khẩu',
    tier: PlanTier.free,
    build: () => const PasswordResetScreen(),
  ),
  (
    name: 'Bắt đầu',
    tier: PlanTier.free,
    build: () => GettingStartedScreen(onCreateAccount: () {}, onSignIn: () {}),
  ),
  (
    name: 'Khảo sát',
    tier: PlanTier.free,
    build: () => const OnboardingChatScreen(),
  ),
  (
    name: 'Lộ trình (Pro)',
    tier: PlanTier.pro,
    build: () => TripPlannerScreen(vehicle: _car),
  ),
  (
    name: 'Pin chai (Pro)',
    tier: PlanTier.pro,
    build: () => const BatteryHealthScreen(vehicleId: 'car'),
  ),
  (
    name: 'Sạc đêm (Ultra)',
    tier: PlanTier.ultra,
    build: () => const NightChargingScreen(vehicleId: 'car', currentSoc: 31),
  ),
  (
    name: 'AI cá nhân',
    tier: PlanTier.free,
    build: () => const PersonalAiSettingsScreen(vehicleId: 'car'),
  ),
];

Widget _app(_Screen screen, double scale) => ProviderScope(
  overrides: [
    chargeLogRepositoryProvider.overrideWithValue(_Repo()),
    selectedVehicleIdProvider.overrideWith((ref) => 'car'),
    entitlementProvider.overrideWith(() => _Plan(screen.tier)),
  ],
  child: MaterialApp(
    theme: LuxeTheme.data(),
    builder: (context, page) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: page!,
    ),
    home: Scaffold(body: screen.build()),
  ),
);

/// Pumps the screen, scrolls it to the end and returns every framework
/// error (overflow, build exception) with its first lines.
Future<List<String>> _render(WidgetTester tester, Widget app) async {
  final problems = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final lines = details.exceptionAsString().trim().split('\n');
    final where = RegExp(r'lib/[\w/]+\.dart:\d+:\d+')
        .allMatches(details.toString())
        .map((m) => m.group(0))
        .toSet()
        .take(3)
        .join(', ');
    problems.add('${lines.take(3).join(' | ')} @ $where');
  };
  try {
    await tester.pumpWidget(app);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isNotEmpty) {
      for (var i = 0; i < 14; i++) {
        await tester.drag(
          scrollable.first,
          const Offset(0, -420),
          warnIfMissed: false,
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
  } finally {
    FlutterError.onError = previous;
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  return problems;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final screen in _screens) {
    final firebase = _needsFirebase.contains(screen.name);
    for (final scale in const [1.0, 2.0]) {
      final name = '320 dp, chữ ×$scale: ${screen.name}';
      testWidgets(name, skip: firebase || _openIssues.contains(name), (
        tester,
      ) async {
        tester.view
          ..physicalSize = const Size(320, 640)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final problems = await _render(tester, _app(screen, scale));
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }
    final tapName = 'vùng chạm ≥ 48 dp và có nhãn: ${screen.name}';
    testWidgets(tapName, skip: firebase || _openIssues.contains(tapName), (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(320, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(screen, 1));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      final failures = <String>[];
      for (final guideline in [
        androidTapTargetGuideline,
        labeledTapTargetGuideline,
      ]) {
        try {
          await expectLater(tester, meetsGuideline(guideline));
        } on TestFailure catch (error) {
          failures.add(error.message ?? '$guideline');
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      semantics.dispose();
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }
}
