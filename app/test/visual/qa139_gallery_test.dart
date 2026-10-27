import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/providers/app_providers.dart';
import 'package:vinfast_battery/core/providers/entitlement_provider.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/theme/plan_style.dart';
import 'package:vinfast_battery/core/widgets/luxe_kit.dart';
import 'package:vinfast_battery/data/models/entitlement.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/repositories/charge_log_repository.dart';
import 'package:vinfast_battery/features/achievements/achievements_screen.dart';
import 'package:vinfast_battery/features/ai/ai_models_screen.dart';
import 'package:vinfast_battery/features/ai/models/function_call_action.dart';
import 'package:vinfast_battery/features/ai/widgets/action_confirmation_card.dart';
import 'package:vinfast_battery/features/ai/widgets/battery_reading_sheet.dart';
import 'package:vinfast_battery/features/ai/widgets/confirm_actual_soc_sheet.dart';
import 'package:vinfast_battery/features/ai/widgets/edit_target_sheet.dart';
import 'package:vinfast_battery/features/ai/widgets/start_charge_confirmation_sheet.dart';
import 'package:vinfast_battery/features/ai/widgets/stop_charging_confirmation_sheet.dart';
import 'package:vinfast_battery/features/auth/getting_started_screen.dart';
import 'package:vinfast_battery/features/auth/login_screen.dart';
import 'package:vinfast_battery/features/auth/onboarding_chat_screen.dart';
import 'package:vinfast_battery/features/auth/register_screen.dart';
import 'package:vinfast_battery/features/battery_monitor/battery_health_screen.dart';
import 'package:vinfast_battery/features/battery_monitor/battery_monitor_screen.dart';
import 'package:vinfast_battery/features/more/more_screen.dart';
import 'package:vinfast_battery/features/overview/overview_screen.dart';
import 'package:vinfast_battery/features/premium/premium_gate.dart';
import 'package:vinfast_battery/features/premium/premium_screen.dart';
import 'package:vinfast_battery/features/settings/appearance_screen.dart';
import 'package:vinfast_battery/features/settings/assistant_memory_screen.dart';
import 'package:vinfast_battery/features/settings/delete_account_sheet.dart';
import 'package:vinfast_battery/features/settings/guide_screen.dart';
import 'package:vinfast_battery/features/settings/settings_screen.dart';
import 'package:vinfast_battery/features/settings/vehicle_garage_screen.dart';
import 'package:vinfast_battery/features/smart_charging/night_charging_screen.dart';
import 'package:vinfast_battery/features/smart_charging/shelly_connect_screen.dart';
import 'package:vinfast_battery/features/support/help_center_screen.dart';
import 'package:vinfast_battery/features/trip_planner/trip_planner_screen.dart';

/// QA 139 (UI review, 26/10/2026): screenshots of every screen that builds
/// without Firebase, per plan, width and text size, plus the text colours
/// and boxes for the contrast check. Not part of the normal suite: it runs
/// only with QA139_OUT (folder for the PNG/JSON) and QA139_FONTS (Flutter's
/// material_fonts folder, so text renders in Roboto instead of boxes).
final _out = Platform.environment['QA139_OUT'];
final _fonts = Platform.environment['QA139_FONTS'];
final _only = Platform.environment['QA139_ONLY'];

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

/// Opens a sheet over an empty page once the first frame is up.
class _Opener extends StatefulWidget {
  const _Opener(this.open);
  final Future<void> Function(BuildContext context) open;

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.open(context);
    });
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: LuxeColors.background, child: SizedBox.expand());
}

FunctionCallAction _action(String tool, String status, String title) =>
    FunctionCallAction(
      callId: 'c-$tool-$status',
      toolName: tool,
      args: const {},
      status: status,
      cardData: ActionConfirmationCardData(
        title: title,
        description: 'VinFast Feliz · Shelly Plug S',
        estimatedTime: '30 phút',
        safetyNote:
            'Chỉ báo bật thành công sau khi đọc lại thấy ổ đã bật và hẹn giờ đang chạy.',
      ),
    );

Widget _botCards() => ListView(
  padding: const EdgeInsets.all(16),
  children: [
    for (final (tool, status, title) in const [
      (ActionConfirmationCard.energizingTool, 'pending', 'Bật sạc 30 phút'),
      ('stop_charging', 'pending', 'Dừng sạc'),
      ('app_update_battery', 'confirmed', 'Cập nhật pin 64 %'),
      ('stop_charging', 'blocked', 'Dừng sạc'),
      ('start_timed_charging', 'unknown', 'Bật sạc 30 phút'),
      ('app_update_odo', 'cancelled', 'Cập nhật ODO 5 019 km'),
    ])
      ActionConfirmationCard(
        action: _action(tool, status, title),
        onConfirm: () {},
        onCancel: () {},
      ),
  ],
);

typedef _Shot = ({String id, String name, PlanTier tier, Widget Function() build});

final List<_Shot> _shots = [
  (id: 'more', name: 'Cài đặt', tier: PlanTier.free, build: () => const MoreScreen()),
  (id: 'premium', name: 'Pinova Premium', tier: PlanTier.free, build: () => const PremiumScreen()),
  (id: 'overview', name: 'Tổng quan', tier: PlanTier.free, build: () => const OverviewScreen()),
  (id: 'garage', name: 'Xe của tôi', tier: PlanTier.free, build: () => const VehicleGarageScreen()),
  (id: 'settings', name: 'Cài đặt hệ thống', tier: PlanTier.free, build: () => const SettingsScreen()),
  (id: 'appearance', name: 'Giao diện', tier: PlanTier.free, build: () => const AppearanceScreen()),
  (id: 'achievements', name: 'Thành tựu', tier: PlanTier.free, build: () => const AchievementsScreen()),
  (id: 'help', name: 'Trợ giúp', tier: PlanTier.free, build: () => const HelpCenterScreen()),
  (id: 'guide', name: 'Hướng dẫn sử dụng', tier: PlanTier.free, build: () => const GuideScreen()),
  (id: 'memory', name: 'Pinova Bot nhớ gì', tier: PlanTier.free, build: () => const AssistantMemoryScreen()),
  (id: 'monitor', name: 'Theo dõi pin', tier: PlanTier.free, build: () => BatteryMonitorScreen(vehicle: _car)),
  (id: 'aimodels', name: 'Mô hình AI', tier: PlanTier.free, build: () => const AiModelsScreen()),
  (id: 'shelly', name: 'Kết nối Shelly', tier: PlanTier.free, build: () => const ShellyConnectScreen()),
  (id: 'login', name: 'Đăng nhập', tier: PlanTier.free, build: () => const LoginScreen()),
  (id: 'register', name: 'Đăng ký', tier: PlanTier.free, build: () => const RegisterScreen()),
  (id: 'start', name: 'Bắt đầu', tier: PlanTier.free, build: () => GettingStartedScreen(onCreateAccount: () {}, onSignIn: () {})),
  (id: 'survey', name: 'Khảo sát', tier: PlanTier.free, build: () => const OnboardingChatScreen()),
  (id: 'trip', name: 'Lộ trình (Pro)', tier: PlanTier.pro, build: () => TripPlannerScreen(vehicle: _car)),
  (id: 'health', name: 'Pin chai (Pro)', tier: PlanTier.pro, build: () => const BatteryHealthScreen(vehicleId: 'car')),
  (id: 'night', name: 'Sạc đêm (Ultra)', tier: PlanTier.ultra, build: () => const NightChargingScreen(vehicleId: 'car', currentSoc: 31)),
  (id: 'botcards', name: 'Thẻ Pinova Bot', tier: PlanTier.free, build: _botCards),
  (
    id: 'sheet-start',
    name: 'Sheet bắt đầu sạc',
    tier: PlanTier.free,
    build: () => _Opener(
      (c) => StartChargeConfirmationSheet.show(
        c,
        currentSoc: 31,
        targetSoc: 85,
        estimatedMinutes: 95,
        stopTime: '22:40',
        isAiMode: true,
      ),
    ),
  ),
  (
    id: 'sheet-stop',
    name: 'Sheet dừng sạc',
    tier: PlanTier.free,
    build: () => _Opener(
      (c) => showStopChargingConfirmationSheet(
        c,
        currentSoc: 58,
        targetSoc: 85,
        remaining: const Duration(minutes: 47),
        targetMode: true,
      ),
    ),
  ),
  (
    id: 'sheet-target',
    name: 'Sheet đổi mục tiêu',
    tier: PlanTier.pro,
    build: () => _Opener(
      (c) => EditTargetSheet.show(
        c,
        currentSoc: 58,
        currentTarget: 85,
        onSubmit: (_) async => null,
      ),
    ),
  ),
  (
    id: 'sheet-reading',
    name: 'Sheet % pin và ODO',
    tier: PlanTier.free,
    build: () => _Opener(
      (c) => BatteryReadingSheet.show(c, initialSoc: 31, currentOdoKm: 5019),
    ),
  ),
  (
    id: 'sheet-actual',
    name: 'Sheet xác nhận % thực tế',
    tier: PlanTier.free,
    build: () => _Opener(
      (c) => ConfirmActualSocSheet.show(
        c,
        estimatedSoc: 82,
        startSoc: 31,
        currentOdoKm: 5019,
      ),
    ),
  ),
  (
    id: 'sheet-upgrade',
    name: 'Sheet nâng cấp',
    tier: PlanTier.free,
    build: () => _Opener(
      (c) => PremiumGate.showUpgrade(c, PremiumFeature.values.first),
    ),
  ),
  (
    id: 'sheet-delete',
    name: 'Sheet xóa tài khoản',
    tier: PlanTier.free,
    build: () => _Opener(
      (c) => showLuxeSheet<void>(c, builder: (_) => const DeleteAccountSheet()),
    ),
  ),
];

typedef _Variant = ({String id, PlanTier? tier, Size size, double scale, bool motion});

/// Free at every size and text scale; Pro and Ultra at the common phone.
const List<_Variant> _variants = [
  (id: 'f412x1', tier: PlanTier.free, size: Size(412, 915), scale: 1, motion: false),
  (id: 'p412x1', tier: PlanTier.pro, size: Size(412, 915), scale: 1, motion: false),
  (id: 'u412x1', tier: PlanTier.ultra, size: Size(412, 915), scale: 1, motion: false),
  (id: 'f412x1.3', tier: PlanTier.free, size: Size(412, 915), scale: 1.3, motion: false),
  (id: 'f412x2', tier: PlanTier.free, size: Size(412, 915), scale: 2, motion: false),
  (id: 'f320x1', tier: PlanTier.free, size: Size(320, 640), scale: 1, motion: false),
  (id: 'f320x2', tier: PlanTier.free, size: Size(320, 640), scale: 2, motion: false),
];

const _dpr = 2.0;
final _boundary = GlobalKey();

/// Styles that replace (not merge into) the inherited text style have no
/// family; a phone draws them in Roboto, the test engine in its box font.
ThemeData _roboto(ThemeData t) {
  TextStyle? r(TextStyle? s) => (s ?? const TextStyle()).copyWith(
    fontFamily: 'Roboto',
  );
  ButtonStyle? b(ButtonStyle? s) => (s ?? const ButtonStyle()).copyWith(
    textStyle: WidgetStateProperty.resolveWith(
      (states) => r(s?.textStyle?.resolve(states)),
    ),
  );
  return t.copyWith(
    textTheme: t.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: t.primaryTextTheme.apply(fontFamily: 'Roboto'),
    filledButtonTheme: FilledButtonThemeData(style: b(t.filledButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: b(t.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(style: b(t.textButtonTheme.style)),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: b(t.elevatedButtonTheme.style),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: b(t.segmentedButtonTheme.style),
    ),
    appBarTheme: t.appBarTheme.copyWith(
      titleTextStyle: r(t.appBarTheme.titleTextStyle),
      toolbarTextStyle: r(t.appBarTheme.toolbarTextStyle),
    ),
    snackBarTheme: t.snackBarTheme.copyWith(
      contentTextStyle: r(t.snackBarTheme.contentTextStyle),
    ),
    chipTheme: t.chipTheme.copyWith(labelStyle: r(t.chipTheme.labelStyle)),
    listTileTheme: t.listTileTheme.copyWith(
      titleTextStyle: r(t.listTileTheme.titleTextStyle),
      subtitleTextStyle: r(t.listTileTheme.subtitleTextStyle),
    ),
    dialogTheme: t.dialogTheme.copyWith(
      titleTextStyle: r(t.dialogTheme.titleTextStyle),
      contentTextStyle: r(t.dialogTheme.contentTextStyle),
    ),
    tabBarTheme: t.tabBarTheme.copyWith(
      labelStyle: r(t.tabBarTheme.labelStyle),
      unselectedLabelStyle: r(t.tabBarTheme.unselectedLabelStyle),
    ),
    inputDecorationTheme: t.inputDecorationTheme.copyWith(
      labelStyle: r(t.inputDecorationTheme.labelStyle),
      hintStyle: r(t.inputDecorationTheme.hintStyle),
      helperStyle: r(t.inputDecorationTheme.helperStyle),
      floatingLabelStyle: r(t.inputDecorationTheme.floatingLabelStyle),
    ),
  );
}

Widget _app(_Shot shot, _Variant v) {
  // A screen that needs a plan keeps it; the plan variants restyle the rest.
  final tier = shot.tier != PlanTier.free ? shot.tier : v.tier!;
  return ProviderScope(
    overrides: [
      chargeLogRepositoryProvider.overrideWithValue(_Repo()),
      selectedVehicleIdProvider.overrideWith((ref) => 'car'),
      entitlementProvider.overrideWith(() => _Plan(tier)),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _roboto(LuxeTheme.data(tier: tier)),
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(v.scale),
          disableAnimations: !v.motion,
        ),
        child: RepaintBoundary(
          key: _boundary,
          child: PlanMotionHost(running: false, child: page!),
        ),
      ),
      home: Scaffold(body: shot.build()),
    ),
  );
}

Future<void> _loadFonts() async {
  final dir = _fonts!;
  // Text without a family falls back to the test font (boxes); on a phone
  // it is Roboto, so both names get Roboto here.
  for (final family in ['Roboto', 'FlutterTest']) {
    final roboto = FontLoader(family);
    for (final f in [
      'roboto-thin',
      'roboto-light',
      'roboto-regular',
      'roboto-medium',
      'roboto-bold',
      'roboto-black',
    ]) {
      roboto.addFont(
        Future.value(
          ByteData.sublistView(File('$dir/$f.ttf').readAsBytesSync()),
        ),
      );
    }
    await roboto.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('$dir/materialicons-regular.otf').readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}

String _hex(Color c) =>
    c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();

/// The first explicit colour in the span tree (the paragraph's main ink).
Color? _spanColor(InlineSpan span) {
  Color? found;
  span.visitChildren((s) {
    final c = s.style?.color;
    if (c != null) {
      found = c;
      return false;
    }
    return true;
  });
  return found;
}

List<Map<String, Object?>> _texts(Size viewport) {
  final out = <Map<String, Object?>>[];
  void visit(RenderObject node) {
    if (node is RenderParagraph && node.attached && node.hasSize) {
      final text = node.text.toPlainText().trim();
      if (text.isNotEmpty) {
        final rect = MatrixUtils.transformRect(
          node.getTransformTo(null),
          Offset.zero & node.size,
        );
        final screen = Offset.zero & viewport;
        if (rect.overlaps(screen) && rect.width > 1 && rect.height > 1) {
          final span = node.text;
          final style =
              span is TextSpan &&
                  span.text == null &&
                  span.children?.length == 1
              ? span.children!.single.style
              : span.style;
          final size = style?.fontSize ?? 14;
          out.add({
            't': text.length > 60 ? '${text.substring(0, 60)}…' : text,
            'x': rect.left,
            'y': rect.top,
            'w': rect.width,
            'h': rect.height,
            'color': switch (_spanColor(node.text)) {
              final c? => _hex(c),
              null => null,
            },
            'size': node.textScaler.scale(size),
            'weight': (style?.fontWeight ?? FontWeight.w400).value,
          });
        }
      }
    }
    node.visitChildren(visit);
  }

  for (final view in RendererBinding.instance.renderViews) {
    visit(view);
  }
  return out;
}

/// Screens re-wrap their subtree in `LuxeTheme.of(context)`, so the theme
/// patch above does not reach every label: give each paragraph a Roboto
/// root (explicit families such as the icon font still win).
Future<void> _forceRoboto(WidgetTester tester) async {
  var changed = false;
  void visit(RenderObject node) {
    if (node is RenderParagraph) {
      final root = node.text;
      final marked =
          root is TextSpan &&
          root.text == null &&
          root.style?.fontFamily == 'Roboto' &&
          root.children?.length == 1;
      if (!marked) {
        node.text = TextSpan(
          style: const TextStyle(fontFamily: 'Roboto'),
          children: [root],
        );
        changed = true;
      }
    }
    node.visitChildren(visit);
  }

  for (final view in RendererBinding.instance.renderViews) {
    visit(view);
  }
  if (changed) await tester.pump();
}

Future<void> _capture(WidgetTester tester, String file, Size viewport) async {
  await _forceRoboto(tester);
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final texts = _texts(viewport);
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _dpr);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_out/png/$file.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  File('$_out/png/$file.json').writeAsStringSync(
    jsonEncode({'dpr': _dpr, 'w': viewport.width, 'h': viewport.height, 'texts': texts}),
  );
}

ScrollableState? _mainScroll(WidgetTester tester) {
  ScrollableState? best;
  var area = 0.0;
  for (final s in tester.stateList<ScrollableState>(find.byType(Scrollable))) {
    if (axisDirectionToAxis(s.axisDirection) != Axis.vertical) continue;
    final box = s.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) continue;
    final a = box.size.width * box.size.height;
    if (a > area && s.position.maxScrollExtent > 0) {
      area = a;
      best = s;
    }
  }
  return best;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  // Asset images and fonts decode on real time.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(() async {
    if (_out == null) return;
    Directory('$_out/png').createSync(recursive: true);
    await _loadFonts();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final index = <Map<String, Object?>>[];
  tearDownAll(() {
    if (_out == null) return;
    File('$_out/index.json').writeAsStringSync(jsonEncode(index));
  });

  for (final shot in _shots) {
    final only = _only;
    if (only != null && !only.split(',').contains(shot.id)) continue;
    for (final v in _variants) {
      // Plan-bound screens are shown once per size, not per plan.
      if (shot.tier != PlanTier.free && v.tier != PlanTier.free) continue;
      testWidgets('${shot.id} ${v.id}', skip: _out == null, (tester) async {
        tester.view
          ..physicalSize = v.size * _dpr
          ..devicePixelRatio = _dpr;
        addTearDown(tester.view.reset);
        final errors = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(
          d.exceptionAsString().split('\n').take(2).join(' | '),
        );
        final frames = <String>[];
        try {
          await tester.pumpWidget(_app(shot, v));
          await _settle(tester);
          final pages = v.size.width > 400 && v.scale == 1 ? 5 : 3;
          for (var page = 0; page < pages; page++) {
            final file = '${shot.id}__${v.id}__$page';
            await _capture(tester, file, v.size);
            frames.add(file);
            final scroll = _mainScroll(tester);
            if (scroll == null) break;
            final p = scroll.position;
            if (p.pixels >= p.maxScrollExtent - 1) break;
            p.jumpTo((p.pixels + v.size.height * 0.8).clamp(0, p.maxScrollExtent));
            await _settle(tester);
          }
        } finally {
          FlutterError.onError = previous;
        }
        index.add({
          'shot': shot.id,
          'name': shot.name,
          'variant': v.id,
          'tier': (shot.tier != PlanTier.free ? shot.tier : v.tier!).id,
          'frames': frames,
          'errors': errors,
        });
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
      });
    }
  }
}
