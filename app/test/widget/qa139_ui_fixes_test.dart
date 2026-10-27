import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/providers/app_providers.dart';
import 'package:vinfast_battery/core/providers/entitlement_provider.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/theme/plan_style.dart';
import 'package:vinfast_battery/core/widgets/app_popup.dart';
import 'package:vinfast_battery/core/widgets/luxe_kit.dart';
import 'package:vinfast_battery/data/models/entitlement.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/repositories/charge_log_repository.dart';
import 'package:vinfast_battery/features/ai/widgets/history_luxe_widgets.dart';
import 'package:vinfast_battery/features/ai/widgets/luxe_soc_dial.dart';
import 'package:vinfast_battery/features/battery_monitor/battery_health_screen.dart';
import 'package:vinfast_battery/features/home/widgets/luxe_dashboard_cards.dart';
import 'package:vinfast_battery/features/premium/premium_gate.dart';
import 'package:vinfast_battery/features/settings/vehicle_garage_screen.dart';

/// QA 139 (UI review, 26–27/10/2026): fixes for UX-01…19 and the QA 138
/// leftovers (QA-13, 14, 15, 19, 20).
final _car = VehicleModel(
  vehicleId: 'car',
  vehicleName: 'VinFast Feliz',
  ownerUid: 'u1',
  currentOdo: 5019,
  currentBattery: 31,
  stateOfHealth: 97,
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

const _health = BatteryHealth(
  nominalCapacityWh: 2000,
  estimate: HealthValue(
    sohPct: 92,
    capacityWh: 1840,
    samples: 6,
    confidence: 'medium',
  ),
);

Widget _app(
  Widget child, {
  PlanTier tier = PlanTier.free,
  double scale = 1,
  BatteryHealth? health = _health,
}) => ProviderScope(
  overrides: [
    chargeLogRepositoryProvider.overrideWithValue(_Repo()),
    selectedVehicleIdProvider.overrideWith((ref) => 'car'),
    entitlementProvider.overrideWith(() => _Plan(tier)),
    batteryHealthProvider.overrideWith(
      (ref, id) async => health ?? const BatteryHealth(),
    ),
  ],
  child: MaterialApp(
    theme: LuxeTheme.data(tier: tier),
    navigatorKey: AppPopup.navigatorKey,
    builder: (context, page) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: page!,
    ),
    home: Scaffold(body: child),
  ),
);

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Every Dart file under lib/, without comments.
Map<String, String> _sources() => {
  for (final f in Directory('lib').listSync(recursive: true))
    if (f is File && f.path.endsWith('.dart'))
      f.path.replaceAll('\\', '/'): f
          .readAsStringSync()
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^\s*//.*$'), ''))
          .join('\n'),
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppPopup.resetForTesting();
  });

  Future<void> narrow(WidgetTester tester, {double width = 320}) async {
    tester.view
      ..physicalSize = Size(width, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('UX-01, UX-13: locked entries', () {
    testWidgets('a locked tile is as wide as its neighbours', (tester) async {
      await narrow(tester, width: 412);
      Widget tile(String label) => Container(
        key: ValueKey(label),
        padding: const EdgeInsets.all(8),
        color: LuxeColors.raised,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [const Icon(Icons.route_rounded), Text(label)],
        ),
      );
      await tester.pumpWidget(
        _app(
          Row(
            children: [
              Expanded(
                child: PremiumLocked(
                  feature: PremiumFeature.tripEstimate,
                  child: tile('Lộ trình'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: tile('Bảo dưỡng xe')),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('Lộ trình'))).width,
        tester.getSize(find.byKey(const ValueKey('Bảo dưỡng xe'))).width,
      );
    });

    test('locked text stays readable (grey, 80 % brightness)', () {
      Color locked(Color c) {
        final grey =
            (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) *
            PremiumLocked.lockedBrightness;
        return Color.from(alpha: 1, red: grey, green: grey, blue: grey);
      }

      expect(
        _contrast(locked(LuxeColors.muted), LuxeColors.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(locked(LuxeColors.text), LuxeColors.background),
        greaterThanOrEqualTo(7),
      );
    });
  });

  group('UX-02, UX-03, UX-16: colour', () {
    test('Free accents in platinum; status colours never follow the plan', () {
      expect(PlanStyle.free.accent, isNot(LuxeColors.emerald));
      for (final tier in PlanTier.values) {
        expect(LuxeTheme.data(tier: tier).colorScheme.error, LuxeColors.danger);
      }
    });

    test('ink reads on every aurora stop (price on the Ultra pill)', () {
      for (final stop in PlanColors.aurora) {
        expect(
          _contrast(PlanColors.ink, stop),
          greaterThanOrEqualTo(4.5),
          reason: '$stop',
        );
      }
    });

    testWidgets('the SoC dial takes the plan accent, not emerald', (
      tester,
    ) async {
      await narrow(tester, width: 412);
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: LuxeSocDial(
              current: 31,
              target: 85,
              onCurrentChanged: (_) {},
              onTargetChanged: (_) {},
            ),
          ),
          tier: PlanTier.pro,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<LuxeDialPainter>()
          .first;
      expect(painter.accent, PlanStyle.pro.accentColors);
      expect(painter.accent, isNot(contains(LuxeColors.emerald)));
      expect(find.text('MỤC TIÊU SẠC'), findsOneWidget);
    });

    test('field hints are muted, not dim (UX-18)', () {
      final theme = LuxeTheme.data();
      expect(theme.inputDecorationTheme.hintStyle?.color, LuxeColors.muted);
      expect(
        _contrast(LuxeColors.muted, LuxeColors.raised),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('Dung lượng pin on the Overview (Pro/Ultra)', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Pro sees the estimated capacity at 320 dp x$scale', (
        tester,
      ) async {
        await narrow(tester);
        await tester.pumpWidget(
          _app(
            const SingleChildScrollView(
              child: LuxeBatteryCapacityCard(vehicleId: 'car'),
            ),
            tier: PlanTier.pro,
            scale: scale,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('92%'), findsOneWidget);
        expect(find.text('Pin còn tốt'), findsOneWidget);
        expect(
          find.textContaining('Còn khoảng 92% dung lượng'),
          findsOneWidget,
        );
        expect(find.byType(PremiumLocked), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Free sees it locked with the PRO tag', (tester) async {
      await narrow(tester);
      await tester.pumpWidget(
        _app(
          const SingleChildScrollView(
            child: LuxeBatteryCapacityCard(vehicleId: 'car'),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('premium-locked-battery_health')),
        findsOneWidget,
      );
      expect(find.text('Dung lượng pin còn lại'), findsOneWidget);
      expect(find.text('92%'), findsNothing);
    });

    testWidgets('Pro without enough charges is told what to do', (
      tester,
    ) async {
      await narrow(tester);
      await tester.pumpWidget(
        _app(
          const SingleChildScrollView(
            child: LuxeBatteryCapacityCard(vehicleId: 'car'),
          ),
          tier: PlanTier.pro,
          health: const BatteryHealth(nominalCapacityWh: 2000),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Chưa đủ dữ liệu'), findsOneWidget);
    });

    testWidgets('the stats strip shows capacity, or the typed SoH', (
      tester,
    ) async {
      await narrow(tester, width: 412);
      await tester.pumpWidget(
        _app(LuxeStatsStrip(vehicle: _car), tier: PlanTier.pro),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('92%'), findsOneWidget);
      expect(find.text('dung lượng pin'), findsOneWidget);

      // A fresh scope: Riverpod keeps the first overrides on an update.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(LuxeStatsStrip(vehicle: _car)));
      await tester.pump();
      expect(find.text('97%'), findsOneWidget);
      expect(find.text('SoH bạn nhập'), findsOneWidget);
    });
  });

  group('UX-05, UX-06: sheets and notices', () {
    testWidgets('kit sheets share one barrier', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showLuxeSheet<void>(
                context,
                builder: (_) => const SizedBox(height: 80),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final barriers = tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .map((b) => b.color);
      expect(barriers, contains(luxeSheetBarrier));
    });

    testWidgets('app messages show as toasts; private text is replaced', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const SizedBox()));
      AppPopup.showMessage(
        'Không lưu được xe đã chọn. Vui lòng thử lại.',
        kind: AppNoticeKind.error,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Không lưu được xe đã chọn. Vui lòng thử lại.'),
        findsOneWidget,
      );
      final icon = tester.widget<Icon>(
        find.byIcon(Icons.error_outline_rounded),
      );
      expect(icon.color, LuxeColors.danger, reason: 'errors are rose (UX-04)');
      AppPopup.dismiss();
      await tester.pump();

      AppPopup.showMessage('Đã gửi tới a@b.vn', kind: AppNoticeKind.success);
      await tester.pumpAndSettle();
      expect(find.textContaining('a@b.vn'), findsNothing);
      AppPopup.dismiss();
      await tester.pump();

      AppPopup.showWarning('Cảnh báo an toàn sạc');
      await tester.pumpAndSettle();
      final warn = tester.widget<Icon>(
        find.byIcon(Icons.warning_amber_rounded),
      );
      expect(warn.color, LuxeColors.champagne);
      AppPopup.dismiss();
      await tester.pump();
    });
  });

  group('QA-20: folds under reduce motion', () {
    for (final reduced in [true, false]) {
      testWidgets('LuxeFold, reduce motion $reduced', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: const LuxeFold(child: SizedBox(height: 40)),
            ),
          ),
        );
        expect(
          find.byType(AnimatedSize),
          reduced ? findsNothing : findsOneWidget,
        );
      });
    }
  });

  group('UX-17: one unit and one duration style in History', () {
    test('energy is always kWh, durations are written out', () {
      expect(historyEnergy(576), '0.58 kWh');
      expect(historyEnergy(1970), '1.97 kWh');
      expect(
        historyDuration(const Duration(hours: 12, minutes: 18)),
        '12 giờ 18 phút',
      );
      expect(historyDuration(const Duration(hours: 2)), '2 giờ');
      expect(historyDuration(const Duration(minutes: 45)), '45 phút');
    });
  });

  group('UX-19: one add control in the garage', () {
    testWidgets('no floating button over the empty state', (tester) async {
      await narrow(tester);
      await tester.pumpWidget(_app(const VehicleGarageScreen(), scale: 2));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      if (find.text('Chưa có xe nào').evaluate().isNotEmpty) {
        expect(find.byType(FloatingActionButton), findsNothing);
      }
      expect(find.byTooltip('Thêm xe mới'), findsNothing);
    });
  });

  group('source rules (ratchets for the review)', () {
    final src = _sources();
    bool theme(String p) => p.startsWith('lib/core/theme/');

    test('icons are Material Rounded (UX-10)', () {
      final bad = [
        for (final e in src.entries)
          if (RegExp(r'Icons\.\w+_outlined\b').hasMatch(e.value)) e.key,
      ];
      expect(bad, isEmpty);
    });

    test('no legacy colour aliases outside the theme (UX-07)', () {
      final bad = [
        for (final e in src.entries)
          if (!theme(e.key) &&
              RegExp(r'\b(CockpitColors|AppColors)\.').hasMatch(e.value))
            e.key,
      ];
      expect(bad, isEmpty);
    });

    test('hard-coded colours do not grow (UX-07: 485 → 300)', () {
      var n = 0;
      for (final e in src.entries) {
        if (!theme(e.key)) {
          n += RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)').allMatches(e.value).length;
        }
      }
      expect(n, lessThanOrEqualTo(300));
    });

    test('no "≈" or three-dot ellipsis in UI text (QA-14, UX-14)', () {
      final bad = <String>[];
      for (final e in src.entries) {
        for (final m in RegExp(r"'([^'\n]*)'").allMatches(e.value)) {
          final t = m.group(1)!;
          if (t.contains('≈') || t.contains('...')) bad.add('${e.key}: $t');
        }
      }
      expect(bad, isEmpty);
    });

    test('short notices go through AppPopup (UX-06)', () {
      final bad = [
        for (final e in src.entries)
          if (e.value.contains('showSnackBar(') &&
              !e.key.endsWith('core/widgets/app_popup.dart') &&
              !e.key.endsWith('core/widgets/debug_error_sheet.dart'))
            e.key,
      ];
      expect(bad, isEmpty);
    });

    test('endless loops only where something really happens (QA-13)', () {
      const allowed = {
        'lib/core/widgets/battery_bot_mascot.dart', // thinking, listening
        'lib/core/widgets/bootstrap_splash.dart', // app starting
        'lib/core/widgets/global_charging_pill.dart', // charging
        'lib/core/widgets/luxe_kit.dart', // shimmer while loading
        'lib/features/achievements/widgets/achievement_unlock_ceremony.dart',
        'lib/features/ai/assistant_sheet.dart', // typing dots
        'lib/features/ai/smart_charging_control_screen.dart', // relay ON
        'lib/features/ai/widgets/active_charging_card_v2.dart', // charging
        'lib/features/ai/widgets/breathing_bot_avatar.dart', // streaming
        'lib/features/ai/widgets/streaming_text_widget.dart', // streaming
        'lib/features/ai/widgets/timed_charging_section_v2.dart', // sending
        'lib/features/ai/widgets/typing_indicator_dots.dart', // typing
        'lib/features/smart_charging/shelly_connect_screen.dart', // scanning
        'lib/data/services/smart_charge_telemetry_foreground_service.dart',
      };
      final bad = [
        for (final e in src.entries)
          if (RegExp(r'\.repeat\(').hasMatch(e.value) &&
              !allowed.contains(e.key))
            e.key,
      ];
      expect(bad, isEmpty);
    });

    test('no AnimatedSize with a zero duration (QA-20)', () {
      final bad = [
        for (final e in src.entries)
          if (RegExp(
            r'AnimatedSize\(\s*duration:[^,]*Duration\.zero',
          ).hasMatch(e.value))
            e.key,
      ];
      expect(bad, isEmpty);
    });

    test('font sizes sit on the LuxeText scale (UX-08)', () {
      final bad = <String>[];
      for (final e in src.entries) {
        for (final m in RegExp(
          r'fontSize:\s*(\d+(?:\.\d+)?)(?![\d.])',
        ).allMatches(e.value)) {
          final v = double.parse(m.group(1)!);
          // Below 10: chart and painter labels sized to their canvas.
          if (v >= 10 && !LuxeText.scale.contains(v)) bad.add('${e.key}: $v');
        }
      }
      expect(bad, isEmpty);
    });

    test('% is written next to its number (QA-15)', () {
      final bad = <String>[];
      for (final e in src.entries) {
        for (final m in RegExp(r"'([^'\n]*)'").allMatches(e.value)) {
          if (RegExp(r'[0-9}] %').hasMatch(m.group(1)!)) {
            bad.add('${e.key}: ${m.group(1)}');
          }
        }
      }
      expect(bad, isEmpty);
    });
  });
}
