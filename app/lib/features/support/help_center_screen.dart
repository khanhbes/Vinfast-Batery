import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/providers/vehicle_context_provider.dart';
import '../../core/providers/entitlement_provider.dart';
import '../../core/providers/vehicle_providers.dart';
import '../../core/services/pinova_api.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../core/widgets/luxe_submit_button.dart';
import '../../core/widgets/vehicle_picker_sheet.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';
import 'app_diagnostics.dart';
import 'support_repository.dart';

final appDiagnosticsProvider = Provider<AppDiagnostics>(
  (ref) => const AppDiagnostics(),
);

/// Trợ giúp & khắc phục sự cố (QA 135, every plan): a self-check with fix
/// buttons, answers to common problems and a ticket to the Pinova team
/// with the check attached.
class HelpCenterScreen extends ConsumerStatefulWidget {
  const HelpCenterScreen({super.key, this.initialTicketId});

  /// Opened from a reply notification.
  final String? initialTicketId;

  static Future<void> open(BuildContext context, {String? ticketId}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HelpCenterScreen(initialTicketId: ticketId),
        ),
      );

  @override
  ConsumerState<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends ConsumerState<HelpCenterScreen>
    with WidgetsBindingObserver {
  DiagnosticsReport? _report;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
    final ticket = widget.initialTicketId;
    if (ticket != null && ticket.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) SupportTicketScreen.open(context, ticket);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the system settings: show the new permission state.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final vehicleId = ref.read(selectedVehicleIdProvider);
    String? vehicleName;
    try {
      vehicleName = ref.read(vehicleContextProvider).displayName;
    } on Object {
      vehicleName = null;
    }
    try {
      final report = await ref
          .read(appDiagnosticsProvider)
          .run(
            vehicleId: vehicleId,
            vehicleName: vehicleName,
            plan: ref.read(entitlementProvider),
          );
      if (mounted) setState(() => _report = report);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _fix(CheckFix fix) async {
    switch (fix) {
      case CheckFix.retry:
        await _check();
      case CheckFix.signIn:
        AppPopup.showWarning(
          'Đăng xuất ở tab Cài đặt rồi đăng nhập lại để làm mới phiên.',
        );
      case CheckFix.chooseVehicle:
        await VehiclePickerSheet.show(context, ref);
        await _check();
      case CheckFix.openShellySetup:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SmartChargerSetupHubScreen(),
          ),
        );
        await _check();
      case CheckFix.allowNotifications:
        await Permission.notification.request();
        await _check();
      case CheckFix.allowCamera:
        await Permission.camera.request();
        await _check();
      case CheckFix.allowBackground:
        await Permission.ignoreBatteryOptimizations.request();
        await _check();
      case CheckFix.openAppSettings:
        await openAppSettings();
    }
  }

  Future<void> _contact() async {
    final sent = await SupportComposeSheet.show(
      context,
      diagnostics: _report?.snapshot,
    );
    if (sent == true) ref.invalidate(supportTicketsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final tickets = ref.watch(supportTicketsProvider);
    return LuxeScaffold(
      title: 'Trợ giúp',
      body: RefreshIndicator(
        color: LuxeColors.emerald,
        onRefresh: () async {
          ref.invalidate(supportTicketsProvider);
          await _check();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            _Summary(report: report, checking: _checking, onRecheck: _check),
            const LuxeSectionLabel('Kiểm tra nhanh'),
            if (report == null)
              const LuxeSettingsGroup(
                children: [
                  LuxeSettingsRow(
                    icon: Icons.manage_search_rounded,
                    title: 'Đang kiểm tra…',
                  ),
                ],
              )
            else
              LuxeSettingsGroup(
                children: [
                  for (final check in report.checks)
                    _CheckRow(
                      key: ValueKey('help-check-${check.id}'),
                      check: check,
                      onFix: check.fix == null ? null : () => _fix(check.fix!),
                    ),
                ],
              ),
            const LuxeSectionLabel('Liên hệ đội Pinova'),
            LuxeSettingsGroup(
              children: [
                LuxeSettingsRow(
                  key: const ValueKey('help-contact'),
                  icon: Icons.support_agent_rounded,
                  title: 'Gửi yêu cầu hỗ trợ',
                  subtitle:
                      'Mô tả vấn đề; kết quả kiểm tra ở trên được đính kèm để '
                      'đội hỗ trợ xử lý nhanh hơn',
                  onTap: _contact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            tickets.when(
              data: (items) => items.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const LuxeSectionLabel('Yêu cầu của bạn'),
                        LuxeSettingsGroup(
                          children: [
                            for (final t in items)
                              LuxeSettingsRow(
                                key: ValueKey('help-ticket-${t.id}'),
                                icon: t.status == 'answered'
                                    ? Icons.mark_chat_read_rounded
                                    : Icons.chat_bubble_outline_rounded,
                                accent: t.unread ? LuxeColors.emerald : null,
                                title: t.subject,
                                subtitle:
                                    '${t.category.label} · ${t.statusLabel}',
                                badge: t.unread
                                    ? const LuxeTag(
                                        'Mới',
                                        color: LuxeColors.emerald,
                                      )
                                    : null,
                                onTap: () async {
                                  await SupportTicketScreen.open(context, t.id);
                                  ref.invalidate(supportTicketsProvider);
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
              loading: () => const SizedBox.shrink(),
              // Offline: the checks above still help; nothing to list.
              error: (_, _) => const SizedBox.shrink(),
            ),
            const LuxeSectionLabel('Câu hỏi thường gặp'),
            const _Faq(),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.report,
    required this.checking,
    required this.onRecheck,
  });
  final DiagnosticsReport? report;
  final bool checking;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final problems = report?.problems ?? 0;
    final warnings = report?.warnings ?? 0;
    final color = report == null
        ? LuxeColors.platinumMid
        : problems > 0
        ? LuxeColors.danger
        : warnings > 0
        ? LuxeColors.champagne
        : LuxeColors.emerald;
    final title = report == null
        ? 'Đang kiểm tra app…'
        : problems > 0
        ? 'Có $problems vấn đề cần xử lý'
        : warnings > 0
        ? 'Hoạt động, $warnings mục nên xem'
        : 'Mọi thứ đều ổn';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: color.withValues(alpha: 0.07),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            problems > 0
                ? Icons.error_outline_rounded
                : warnings > 0
                ? Icons.info_outline_rounded
                : Icons.verified_rounded,
            color: color,
            size: 30,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  key: const ValueKey('help-summary'),
                  style: LuxeText.item,
                ),
                const SizedBox(height: 2),
                const Text(
                  'Bấm nút bên cạnh từng mục để sửa ngay.',
                  style: LuxeText.caption,
                ),
              ],
            ),
          ),
          checking
              ? const SizedBox.square(
                  dimension: 48,
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: LuxeColors.emerald,
                    ),
                  ),
                )
              : IconButton(
                  tooltip: 'Kiểm tra lại',
                  onPressed: onRecheck,
                  icon: const Icon(Icons.refresh_rounded),
                ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({super.key, required this.check, required this.onFix});
  final DiagnosticCheck check;
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (check.status) {
      CheckStatus.ok => (Icons.check_circle_rounded, LuxeColors.emerald),
      CheckStatus.warn => (Icons.info_rounded, LuxeColors.champagne),
      CheckStatus.fail => (Icons.cancel_rounded, LuxeColors.danger),
      CheckStatus.unknown => (Icons.help_rounded, LuxeColors.platinumMid),
    };
    // The fix button sits under the text: beside it, it squeezed the
    // explanation to a few letters per line at 320 dp with large text.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeSettingsRow(
          icon: icon,
          accent: color,
          title: check.title,
          subtitle: check.detail,
          trailing: const SizedBox.shrink(),
        ),
        if (onFix != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(70, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: onFix,
                child: Text(check.fixLabel ?? 'Sửa'),
              ),
            ),
          ),
      ],
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq();

  static const _items = <(String, String)>[
    (
      'Vuốt để sạc nhưng ổ không bật',
      'Ổ phải đang trực tuyến và đang tắt. Kiểm tra mục "Ổ sạc Shelly" ở trên; '
          'nếu ổ mất mạng, rút ra cắm lại và đợi 1–2 phút. App không gửi lệnh '
          'bật lần hai để tránh bật nhầm — hãy đọc lại trạng thái rồi thử lại.',
    ),
    (
      'Quét đồng hồ đọc sai số',
      'Đưa cả màn hình xe vào khung, tránh chói đèn, giữ máy yên 1–2 giây. '
          'App chỉ điền sẵn: bạn luôn xem lại và sửa số trước khi Lưu.',
    ),
    (
      'Thời gian sạc dự đoán lệch',
      'Sau mỗi lần sạc, nhập % thật trên đồng hồ xe. Sau vài lần, dự đoán sát '
          'hơn cho đúng chiếc xe và bộ sạc của bạn.',
    ),
    (
      'Không nhận được thông báo sạc xong',
      'Bật quyền Thông báo và tắt tối ưu pin cho Pinova (mục "Chạy nền" ở '
          'trên). Một số máy cần cho phép "Tự khởi động".',
    ),
    (
      'Sạc có an toàn khi tôi đóng app?',
      'Có. Máy chủ theo dõi phiên sạc và ổ Shelly luôn có hẹn giờ tự ngắt, kể '
          'cả khi điện thoại hay máy chủ mất kết nối.',
    ),
    (
      'Gói Premium và mã khuyến mãi',
      'Cài đặt → Pinova Premium: dùng thử 7 ngày, xem quyền lợi và nhập mã. '
          'An toàn sạc và trợ giúp luôn miễn phí.',
    ),
  ];

  @override
  Widget build(BuildContext context) => LuxeSettingsGroup(
    children: [
      for (final (q, a) in _items)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            iconColor: LuxeColors.muted,
            collapsedIconColor: LuxeColors.dim,
            title: Text(
              q,
              style: const TextStyle(
                color: LuxeColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(a, style: LuxeText.body),
              ),
            ],
          ),
        ),
    ],
  );
}

/// New ticket: category, subject, message and (on by default) the check.
class SupportComposeSheet extends ConsumerStatefulWidget {
  const SupportComposeSheet({
    super.key,
    this.diagnostics,
    this.initialSubject,
    this.initialMessage,
    this.initialCategory,
  });

  final Map<String, Object?>? diagnostics;
  final String? initialSubject;
  final String? initialMessage;
  final SupportCategory? initialCategory;

  static Future<bool?> show(
    BuildContext context, {
    Map<String, Object?>? diagnostics,
    String? subject,
    String? message,
    SupportCategory? category,
  }) => showLuxeSheet<bool>(
    context,
    builder: (_) => SupportComposeSheet(
      diagnostics: diagnostics,
      initialSubject: subject,
      initialMessage: message,
      initialCategory: category,
    ),
  );

  @override
  ConsumerState<SupportComposeSheet> createState() =>
      _SupportComposeSheetState();
}

class _SupportComposeSheetState extends ConsumerState<SupportComposeSheet> {
  late final _subject = TextEditingController(text: widget.initialSubject);
  late final _message = TextEditingController(text: widget.initialMessage);
  late SupportCategory _category =
      widget.initialCategory ?? SupportCategory.charging;
  bool _attach = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<bool> _send() async {
    final subject = _subject.text.trim();
    final message = _message.text.trim();
    if (subject.length < 3 || message.length < 10) {
      setState(
        () => _error = 'Nhập tiêu đề (≥ 3 ký tự) và mô tả (≥ 10 ký tự).',
      );
      return false;
    }
    setState(() => _error = null);
    try {
      await ref
          .read(supportRepositoryProvider)
          .create(
            category: _category,
            subject: subject,
            message: message,
            diagnostics: _attach ? widget.diagnostics : null,
          );
    } on PinovaApiException catch (error) {
      setState(
        () => _error = error.offline
            ? 'Cần kết nối mạng để gửi. Bản nháp vẫn còn ở đây.'
            : (error.message ?? 'Chưa gửi được. Hãy thử lại.'),
      );
      return false;
    }
    Future.delayed(const Duration(milliseconds: 950), () {
      if (!mounted) return;
      Navigator.of(context).pop(true);
      AppPopup.showSuccess(
        'Đã gửi cho đội Pinova',
        detail: 'Trả lời sẽ hiện trong Trợ giúp và Trung tâm thông báo.',
      );
    });
    return true;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LuxeSheetHeader(
            eyebrow: 'Mọi gói',
            title: 'Gửi yêu cầu hỗ trợ',
            caption: 'Đội Pinova trả lời trong app và qua thông báo.',
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<SupportCategory>(
            key: const ValueKey('support-category'),
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Vấn đề về'),
            dropdownColor: LuxeColors.raised,
            items: [
              for (final c in SupportCategory.values)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _category = value ?? _category),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('support-subject'),
            controller: _subject,
            enabled: !_busy,
            maxLength: 120,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Tiêu đề'),
          ),
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('support-message'),
            controller: _message,
            enabled: !_busy,
            minLines: 4,
            maxLines: 8,
            maxLength: 4000,
            decoration: const InputDecoration(
              labelText: 'Mô tả vấn đề',
              hintText: 'Bạn đã làm gì, app hiện gì, xảy ra lúc nào…',
              alignLabelWithHint: true,
            ),
          ),
          if (widget.diagnostics != null)
            SwitchListTile(
              key: const ValueKey('support-attach'),
              contentPadding: EdgeInsets.zero,
              value: _attach,
              onChanged: _busy ? null : (v) => setState(() => _attach = v),
              title: const Text('Đính kèm kết quả kiểm tra'),
              subtitle: const Text(
                'Phiên bản, quyền, kết nối, trạng thái ổ sạc. Không gồm mật '
                'khẩu hay mã bí mật.',
                style: LuxeText.caption,
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            LuxeNotice(
              icon: Icons.error_outline_rounded,
              color: LuxeColors.danger,
              message: _error!,
            ),
          ],
          const SizedBox(height: 14),
          LuxeSubmitButton(
            key: const ValueKey('support-send'),
            label: 'Gửi yêu cầu',
            busyLabel: 'Đang gửi…',
            doneLabel: 'Đã gửi',
            icon: Icons.send_rounded,
            onPressed: _send,
            onBusyChanged: (busy) => setState(() => _busy = busy),
          ),
        ],
      ),
    ),
  );
}

/// One ticket: the question, the team's answers, a reply box.
class SupportTicketScreen extends ConsumerStatefulWidget {
  const SupportTicketScreen({super.key, required this.ticketId});
  final String ticketId;

  static Future<void> open(BuildContext context, String ticketId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SupportTicketScreen(ticketId: ticketId),
        ),
      );

  @override
  ConsumerState<SupportTicketScreen> createState() =>
      _SupportTicketScreenState();
}

class _SupportTicketScreenState extends ConsumerState<SupportTicketScreen> {
  SupportTicket? _ticket;
  String? _error;
  final _reply = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ticket = await ref
          .read(supportRepositoryProvider)
          .get(widget.ticketId);
      if (mounted) setState(() => (_ticket = ticket, _error = null));
    } on PinovaApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.offline
              ? 'Cần kết nối mạng để xem yêu cầu.'
              : (error.message ?? 'Chưa tải được yêu cầu.'),
        );
      }
    }
  }

  Future<bool> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return false;
    try {
      final ticket = await ref
          .read(supportRepositoryProvider)
          .reply(widget.ticketId, text);
      if (!mounted) return true;
      _reply.clear();
      setState(() => _ticket = ticket);
      return true;
    } on PinovaApiException catch (error) {
      AppPopup.showWarning(error.message ?? 'Chưa gửi được trả lời.');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;
    return LuxeScaffold(
      title: 'Yêu cầu hỗ trợ',
      body: ticket == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator(color: LuxeColors.emerald)
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: LuxeNotice(
                        message: _error!,
                        action: TextButton(
                          onPressed: _load,
                          child: const Text('Thử lại'),
                        ),
                      ),
                    ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                Text(
                  ticket.subject,
                  style: LuxeText.title.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    LuxeTag(ticket.category.label),
                    LuxeTag(
                      ticket.statusLabel,
                      color: ticket.status == 'answered'
                          ? LuxeColors.emerald
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Bubble(
                  text: ticket.message,
                  fromAdmin: false,
                  at: ticket.createdAt,
                ),
                for (final r in ticket.replies)
                  _Bubble(text: r.text, fromAdmin: r.fromAdmin, at: r.at),
                const SizedBox(height: 16),
                if (ticket.status == 'closed')
                  const LuxeNotice(
                    message:
                        'Yêu cầu đã đóng. Nếu vẫn cần giúp, hãy gửi yêu cầu mới.',
                  )
                else ...[
                  TextField(
                    key: const ValueKey('support-reply'),
                    controller: _reply,
                    enabled: !_busy,
                    minLines: 2,
                    maxLines: 6,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      labelText: 'Trả lời đội hỗ trợ',
                    ),
                  ),
                  LuxeSubmitButton(
                    key: const ValueKey('support-reply-send'),
                    label: 'Gửi trả lời',
                    doneLabel: 'Đã gửi',
                    outlined: true,
                    onPressed: _send,
                    onBusyChanged: (busy) => setState(() => _busy = busy),
                  ),
                ],
              ],
            ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.fromAdmin, this.at});
  final String text;
  final bool fromAdmin;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final local = at?.toLocal();
    final when = local == null
        ? ''
        : ' · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} '
              '${local.day}/${local.month}';
    return Align(
      alignment: fromAdmin ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: fromAdmin
              ? LuxeColors.emerald.withValues(alpha: 0.08)
              : LuxeColors.glassStrong,
          border: Border.all(
            color: fromAdmin
                ? LuxeColors.emerald.withValues(alpha: 0.3)
                : LuxeColors.hairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${fromAdmin ? 'Đội Pinova' : 'Bạn'}$when',
              style: LuxeText.caption.copyWith(
                fontSize: 11.5,
                color: fromAdmin ? LuxeColors.emerald : LuxeColors.muted,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              text,
              style: const TextStyle(
                color: LuxeColors.text,
                fontSize: 14.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Copy a ticket id for the owner (e.g. when calling the shop).
Future<void> copyTicketId(String id) async {
  await Clipboard.setData(ClipboardData(text: id));
  AppPopup.showSuccess('Đã sao chép mã yêu cầu');
}
