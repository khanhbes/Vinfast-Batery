import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/pinova_api.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/entitlement.dart';
import 'package:vinfast_battery/data/models/shelly_connection_state.dart';
import 'package:vinfast_battery/data/models/smart_charger_status.dart';
import 'package:vinfast_battery/data/services/shelly_connection_coordinator.dart';
import 'package:vinfast_battery/features/support/app_diagnostics.dart';
import 'package:vinfast_battery/features/support/help_center_screen.dart';
import 'package:vinfast_battery/features/support/support_repository.dart';

/// QA 135: Trợ giúp & khắc phục sự cố — self-check, tickets, replies.
class _Probe extends DiagnosticsProbe {
  const _Probe({
    this.ready = 200,
    this.notifications = PermissionStatus.granted,
    this.camera = PermissionStatus.granted,
    this.shellySnapshot = const ShellyConnectionSnapshot(
      state: ShellyConnectionFlowState.connected,
      isLinked: true,
    ),
  });

  final int? ready;
  final PermissionStatus notifications;
  final PermissionStatus camera;
  final ShellyConnectionSnapshot shellySnapshot;

  @override
  Future<String> appVersion() async => '1.3.0+197';
  @override
  bool isAndroid() => true;
  @override
  String platform() => 'android 15';
  @override
  Future<bool> online() async => true;
  @override
  Future<int?> serverReady() async => ready;
  @override
  bool signedIn() => true;
  @override
  Future<PermissionStatus?> permission(Permission permission) async =>
      permission == Permission.notification
      ? notifications
      : permission == Permission.camera
      ? camera
      : PermissionStatus.granted;
  @override
  ShellyConnectionSnapshot shelly() => shellySnapshot;
}

class _FakeSupport extends SupportRepository {
  _FakeSupport() : super(api: PinovaApi());
  final created = <Map<String, Object?>>[];
  final tickets = <SupportTicket>[];

  @override
  Future<SupportTicket> create({
    required SupportCategory category,
    required String subject,
    required String message,
    Map<String, Object?>? diagnostics,
  }) async {
    created.add({
      'category': category.id,
      'subject': subject,
      'diagnostics': diagnostics,
    });
    final ticket = SupportTicket.fromMap({
      'id': 't${created.length}',
      'subject': subject,
      'category': category.id,
      'message': message,
      'status': 'open',
    });
    tickets.add(ticket);
    return ticket;
  }

  @override
  Future<List<SupportTicket>> mine() async => tickets;

  @override
  Future<SupportTicket> get(String id) async => SupportTicket.fromMap({
    'id': id,
    'subject': 'Quét sai',
    'category': 'scan',
    'message': 'Đồng hồ 68% nhưng app đọc 8%.',
    'status': 'answered',
    'replies': [
      {'by': 'admin', 'text': 'Đã sửa trong bản mới, cảm ơn bạn.'},
    ],
  });

  @override
  Future<SupportTicket> reply(String id, String text) async {
    final base = await get(id);
    return SupportTicket(
      id: id,
      subject: base.subject,
      category: base.category,
      message: base.message,
      status: 'open',
      createdAt: null,
      updatedAt: null,
      replies: [
        ...base.replies,
        SupportReply(at: null, fromAdmin: false, text: text),
      ],
      unread: false,
    );
  }
}

SmartChargerStatus _status({required bool online}) => SmartChargerStatus(
  online: online,
  relay: false,
  powerW: 0,
  voltageV: 230,
  currentA: 0,
  frequencyHz: 50,
  temperatureC: 30,
  energyWh: 0,
);

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  double scale, {
  _Probe probe = const _Probe(),
  _FakeSupport? support,
  double height = 2400,
}) async {
  await tester.binding.setSurfaceSize(Size(320, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDiagnosticsProvider.overrideWithValue(AppDiagnostics(probe: probe)),
        supportRepositoryProvider.overrideWithValue(support ?? _FakeSupport()),
      ],
      child: MaterialApp(
        theme: LuxeTheme.data(),
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: page!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('checks name the real problem and offer the right fix', () async {
    final report = await AppDiagnostics(
      probe: _Probe(
        ready: 503,
        notifications: PermissionStatus.permanentlyDenied,
        camera: PermissionStatus.denied,
        shellySnapshot: ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connected,
          isLinked: true,
          status: _status(online: false),
        ),
      ),
    ).run(vehicleId: '', vehicleName: null, plan: const Entitlement());
    final byId = {for (final c in report.checks) c.id: c};
    expect(byId['network']!.status, CheckStatus.fail);
    expect(byId['network']!.fix, CheckFix.retry);
    expect(byId['vehicle']!.fix, CheckFix.chooseVehicle);
    expect(byId['shelly']!.status, CheckStatus.fail);
    expect(byId['shelly']!.fix, CheckFix.openShellySetup);
    // Permanently denied can only be changed in the system settings.
    expect(byId['notifications']!.fix, CheckFix.openAppSettings);
    expect(byId['camera']!.status, CheckStatus.warn);
    expect(byId['camera']!.fix, CheckFix.allowCamera);
    expect(report.problems, 3);
    expect(report.snapshot['serverReady'], 503);
    expect(report.snapshot['checksFailed'], ['network', 'shelly', 'notifications']);
    expect(report.snapshot.keys.any((k) => k.toLowerCase().contains('token')), isFalse);
  });

  test('a healthy phone reports no problems', () async {
    final report = await AppDiagnostics(
      probe: _Probe(
        shellySnapshot: ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connected,
          isLinked: true,
          status: _status(online: true),
        ),
      ),
    ).run(vehicleId: 'v1', vehicleName: 'Feliz', plan: const Entitlement());
    expect(report.problems, 0);
    expect(report.warnings, 0);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('help center fits 320 dp at text ×$scale', (tester) async {
      await _pump(
        tester,
        const HelpCenterScreen(),
        scale,
        probe: const _Probe(ready: 0),
        height: scale == 1 ? 2400 : 5200,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('help-summary')), findsOneWidget);
      expect(find.byKey(const ValueKey('help-check-network')), findsOneWidget);
      expect(find.text('Thử lại'), findsWidgets);
      expect(find.byKey(const ValueKey('help-contact')), findsOneWidget);
      expect(find.text('CÂU HỎI THƯỜNG GẶP'), findsOneWidget);
    });
  }

  testWidgets('a ticket validates, attaches the check and is listed', (
    tester,
  ) async {
    final support = _FakeSupport();
    await _pump(tester, const HelpCenterScreen(), 1, support: support);
    await tester.tap(find.byKey(const ValueKey('help-contact')));
    await tester.pump(const Duration(milliseconds: 600));
    final send = find.byKey(const ValueKey('support-send'));
    await tester.ensureVisible(send);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(send);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Nhập tiêu đề'), findsOneWidget);
    expect(support.created, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('support-subject')),
      'Không nhận thông báo',
    );
    await tester.enterText(
      find.byKey(const ValueKey('support-message')),
      'Sạc xong nhưng không thấy thông báo nào.',
    );
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pump(const Duration(milliseconds: 300));
    expect(support.created, hasLength(1));
    final diagnostics = support.created.single['diagnostics']! as Map;
    expect(diagnostics['appVersion'], '1.3.0+197');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Không nhận thông báo'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('ticket thread shows the team reply at ×$scale', (tester) async {
      await _pump(
        tester,
        const SupportTicketScreen(ticketId: 't1'),
        scale,
        height: scale == 1 ? 1400 : 2600,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Đã sửa trong bản mới, cảm ơn bạn.'), findsOneWidget);
      expect(find.text('Đã trả lời'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('support-reply')),
        'Cảm ơn!',
      );
      await tester.tap(find.byKey(const ValueKey('support-reply-send')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Cảm ơn!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
