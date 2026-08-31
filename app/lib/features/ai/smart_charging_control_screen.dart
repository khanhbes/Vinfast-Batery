import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/cockpit_design_system.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/debug_error_sheet.dart';
import '../../data/models/smart_charge_history.dart';
import '../../data/models/smart_charging_session.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';
import 'controllers/smart_charging_controller.dart';
import 'smart_charge_history_screen.dart';
import 'widgets/charging_battery_animation.dart';
import 'widgets/charging_connection_banner.dart';
import 'widgets/horizontal_battery_target_selector.dart';
import 'widgets/stop_charging_confirmation_sheet.dart';
import 'widgets/smart_charge_cockpit_theme.dart';

class SmartChargingControlScreen extends ConsumerStatefulWidget {
  const SmartChargingControlScreen({
    super.key,
    required this.vehicleId,
    required this.currentSoc,
    this.embedded = false,
  });
  final String vehicleId;
  final double currentSoc;
  final bool embedded;

  @override
  ConsumerState<SmartChargingControlScreen> createState() => _ScreenState();
}

class _ScreenState extends ConsumerState<SmartChargingControlScreen>
    with WidgetsBindingObserver {
  late final SmartChargingControllerArgs args;
  bool _aiMode = true;

  @override
  void initState() {
    super.initState();
    args = SmartChargingControllerArgs(
      vehicleId: widget.vehicleId,
      currentSoc: widget.currentSoc,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(smartChargingControllerProvider(args).notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smartChargingControllerProvider(args));
    final controller = ref.read(smartChargingControllerProvider(args).notifier);
    final colors = Theme.of(context).colorScheme;

    return SmartChargeCockpitTheme(
      child: Scaffold(
        appBar: widget.embedded
            ? null
            : AppBar(title: const Text('Smart Charge')),
        bottomNavigationBar: state.hasActiveSession
            ? SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    key: const ValueKey('stop-smart-session-button'),
                    onPressed: state.phase == SmartChargingViewPhase.stopping
                        ? null
                        : () => _emergencyOff(controller),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.error,
                      foregroundColor: colors.onError,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.power_settings_new_rounded),
                    label: const Text(
                      'NGẮT NGUỒN NGAY',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              )
            : null,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: controller.refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                // Charger hardware connection status strip
                _StatusStrip(
                  state: state,
                  onSetup: () => Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (_) => const SmartChargerSetupHubScreen(),
                        ),
                      )
                      .then((_) => controller.refresh()),
                ),
                if (!state.connectionState.fullyConnected) ...[
                  const SizedBox(height: 12),
                  ChargingConnectionBanner(
                    state: state.connectionState,
                    onRetry: controller.refresh,
                  ),
                ],

                // Error notification banners with debug view action
                if (state.chargerError != null) ...[
                  const SizedBox(height: 12),
                  _ErrorBannerCard(
                    message: 'Không kết nối được ổ sạc.',
                    detail: state.chargerError,
                    onRetry: controller.refresh,
                  ),
                ],
                if (state.sessionError != null) ...[
                  const SizedBox(height: 12),
                  _ErrorBannerCard(
                    message: 'Không thể đồng bộ phiên sạc.',
                    detail: state.sessionError,
                    onRetry: controller.retrySession,
                  ),
                ],
                if (state.actionError != null) ...[
                  const SizedBox(height: 12),
                  _ErrorBannerCard(
                    message: state.actionError!,
                    detail: state.actionError,
                  ),
                ],
                if (state.safetyWarning != null) ...[
                  const SizedBox(height: 12),
                  _SafetyWarning(message: state.safetyWarning!),
                ],

                const SizedBox(height: 20),

                AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  child: state.hasActiveSession
                      ? _ActiveChargingView(
                          key: const ValueKey('active-session'),
                          state: state,
                          onStop: () =>
                              _stopWithConfirmation(state, controller),
                        )
                      : Column(
                          key: const ValueKey('plan-workspace'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ChargeModeSwitch(
                              aiMode: _aiMode,
                              onChanged: (value) =>
                                  setState(() => _aiMode = value),
                            ),
                            const SizedBox(height: 16),
                            AnimatedSwitcher(
                              duration: CockpitMotion.enabled(context)
                                  ? CockpitMotion.standard
                                  : Duration.zero,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position:
                                          Tween<Offset>(
                                            begin: const Offset(0, .025),
                                            end: Offset.zero,
                                          ).animate(
                                            CurvedAnimation(
                                              parent: animation,
                                              curve: Curves.easeOutCubic,
                                            ),
                                          ),
                                      child: child,
                                    ),
                                  ),
                              child: _aiMode
                                  ? _PlanSection(
                                      key: const ValueKey('ai-mode'),
                                      state: state,
                                      controller: controller,
                                      onStart: () =>
                                          _aiStart(state, controller),
                                    )
                                  : _ManualControlsSection(
                                      key: const ValueKey('timed-mode'),
                                      state: state,
                                      onOn: () => _manualOn(controller),
                                      onOff: () => _emergencyOff(controller),
                                    ),
                            ),
                          ],
                        ),
                ),

                const SizedBox(height: 32),
                _HistorySection(
                  sessions: state.history,
                  status: state.historyStatus,
                  error: state.historyError,
                  syncedAt: state.historySyncedAt,
                  onRetry: controller.retryHistory,
                  onViewAll: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SmartChargeHistoryScreen(
                        controller: controller,
                        initialItems: state.history,
                      ),
                    ),
                  ),
                  onOpen: (session) => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: Colors.transparent,
                    barrierColor: Colors.black.withValues(alpha: .72),
                    builder: (_) => FractionallySizedBox(
                      heightFactor: .96,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                        child: SmartChargeSessionDetailScreen(
                          controller: controller,
                          session: session,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _manualOn(SmartChargingController controller) async {
    const defaultDuration = Duration(hours: 1);
    final duration = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        var selectedMinutes = defaultDuration.inMinutes;
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bật sạc',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Mọi lựa chọn đều cài timer tự ngắt trực tiếp trên Shelly.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      key: const ValueKey('manual-on-now'),
                      onPressed: () => Navigator.pop(context, defaultDuration),
                      icon: const Icon(Icons.bolt_rounded),
                      label: const Text(
                        'BẬT NGAY',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Tự ngắt sau 1 giờ',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'HOẶC CHỌN THỜI GIAN TỰ NGẮT',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                letterSpacing: .5,
                              ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final minutes in const [30, 60, 120, 240, 360, 600])
                        ChoiceChip(
                          label: Text(_duration(minutes)),
                          selected: selectedMinutes == minutes,
                          onSelected: (_) =>
                              setSheetState(() => selectedMinutes = minutes),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      key: const ValueKey('manual-on-custom-duration'),
                      onPressed: () => Navigator.pop(
                        context,
                        Duration(minutes: selectedMinutes),
                      ),
                      icon: const Icon(Icons.timer_outlined),
                      label: Text(
                        'BẬT & TỰ NGẮT SAU ${_duration(selectedMinutes).toUpperCase()}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Hủy'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (duration == null) return;
    final ok = await controller.manualOn(duration);
    if (ok) {
      AppPopup.showSuccess(
        'Đang sạc',
        detail: 'Hẹn giờ ${_duration(duration.inMinutes)}.',
      );
    } else {
      AppPopup.showError('Không thể bật sạc');
    }
  }

  Future<void> _aiStart(
    SmartChargingUiState state,
    SmartChargingController controller,
  ) async {
    final preview = state.preview;
    if (preview == null) return;

    var acknowledged = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Xác nhận bắt đầu sạc'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ổ sạc sẽ bật và tự động tắt lúc ${_time(preview.effectiveStopAt)}.',
              ),
              const SizedBox(height: 10),
              const Text('Pin hiện tại là giá trị ước tính.'),
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: acknowledged,
                onChanged: (value) =>
                    setDialogState(() => acknowledged = value == true),
                title: const Text('Tôi đã hiểu'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: acknowledged
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Bắt đầu sạc'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final ok = await controller.start(confirmed: true);
    if (ok) {
      AppPopup.showSuccess(
        'Đang sạc',
        detail: 'Tự động tắt lúc ${_time(preview.effectiveStopAt)}',
      );
    } else {
      AppPopup.showError('Không thể bật sạc');
    }
  }

  Future<void> _stopWithConfirmation(
    SmartChargingUiState state,
    SmartChargingController controller,
  ) async {
    final session = state.session;
    final remaining =
        state.chargerStatus?.timerRemaining ??
        session?.remaining(state.now) ??
        Duration.zero;
    final decision = await showStopChargingConfirmationSheet(
      context,
      currentSoc:
          session?.estimatedSoc ?? session?.startSoc ?? state.draft.currentSoc,
      targetSoc: session?.targetSoc ?? state.draft.targetSoc,
      remaining: remaining,
    );
    if (decision != null) await _off(controller, reason: decision.reason);
  }

  Future<void> _emergencyOff(SmartChargingController controller) =>
      _off(controller, reason: UserStopReason.safetyConcern);

  Future<void> _off(
    SmartChargingController controller, {
    UserStopReason reason = UserStopReason.none,
  }) async {
    final ok = await controller.stop(reason: reason);
    if (ok) {
      AppPopup.showSuccess('Đã tắt sạc');
    } else {
      AppPopup.showError(
        'Chưa xác nhận được ổ sạc đã tắt',
        detail: 'Hãy kiểm tra ổ sạc trực tiếp.',
      );
    }
  }
}

class _ChargeModeSwitch extends StatelessWidget {
  const _ChargeModeSwitch({required this.aiMode, required this.onChanged});

  final bool aiMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: aiMode ? 'Đang chọn sạc theo AI' : 'Đang chọn sạc hẹn giờ',
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CockpitColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CockpitColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeOption(
              selected: aiMode,
              icon: Icons.auto_awesome_rounded,
              label: 'Sạc theo AI',
              onTap: () => onChanged(true),
            ),
          ),
          Expanded(
            child: _ModeOption(
              selected: !aiMode,
              icon: Icons.timer_outlined,
              label: 'Sạc hẹn giờ',
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: CockpitMotion.enabled(context)
            ? CockpitMotion.standard
            : Duration.zero,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? CockpitColors.emerald.withValues(alpha: .14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? CockpitColors.emerald.withValues(alpha: .28)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? CockpitColors.emerald : CockpitColors.muted,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? CockpitColors.emerald : CockpitColors.muted,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Status strip displaying simplified hardware charger state
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.state, required this.onSetup});
  final SmartChargingUiState state;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final displayState = state.displayState;
    final status = state.chargerStatus;

    Color iconColor;
    IconData iconData;
    String titleText;
    String? subtitleText;

    switch (displayState) {
      case ChargerDisplayState.charging:
        iconColor = Colors.greenAccent.shade400;
        iconData = Icons.bolt_rounded;
        titleText = status?.timerRemaining != null
            ? 'Đang sạc an toàn'
            : 'Đang sạc · chưa xác minh timer';
        final power = status?.powerW ?? 0;
        subtitleText = power > 0
            ? '${status?.transport?.name.toUpperCase() ?? 'SHELLY'} · ${power.toStringAsFixed(0)} W'
            : status?.transport?.name.toUpperCase() ?? 'Đang nhận điện';
        break;
      case ChargerDisplayState.off:
        iconColor = Colors.grey.shade400;
        iconData = Icons.power_off_rounded;
        titleText = 'Đã tắt sạc';
        subtitleText = status?.transport == null
            ? 'Sẵn sàng kích hoạt sạc'
            : '${status!.transport!.name.toUpperCase()} · relay đã xác minh OFF';
        break;
      case ChargerDisplayState.connecting:
        iconColor = Colors.orangeAccent;
        iconData = Icons.sync_rounded;
        titleText = 'Đang kết nối...';
        subtitleText = null;
        break;
      case ChargerDisplayState.offline:
        iconColor = Colors.redAccent;
        iconData = Icons.cloud_off_rounded;
        titleText = 'Mất kết nối';
        subtitleText = 'Không tìm thấy ổ sạc';
        break;
      case ChargerDisplayState.error:
        iconColor = Colors.redAccent;
        iconData = Icons.error_outline_rounded;
        titleText = 'Lỗi kết nối';
        subtitleText = 'Không thể đồng bộ với ổ sạc';
        break;
    }

    return CockpitPanel(
      highlight: displayState == ChargerDisplayState.charging,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(iconData, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleText,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (subtitleText != null)
                      Text(
                        subtitleText,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (!state.capabilities.readyForControl)
                TextButton(onPressed: onSetup, child: const Text('CÀI ĐẶT')),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                status?.timerRemaining != null
                    ? Icons.verified_user_rounded
                    : Icons.shield_outlined,
                size: 16,
                color: status?.timerRemaining != null
                    ? SmartChargeCockpitColors.verified
                    : SmartChargeCockpitColors.muted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  status?.timerRemaining != null
                      ? 'Timer đã cài trên Shelly'
                      : 'Không có timer đang hoạt động',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                state.statusSyncedAt == null
                    ? 'Chưa đồng bộ'
                    : 'Đọc lúc ${DateFormat('HH:mm:ss').format(state.statusSyncedAt!.toLocal())}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Error banner card with "Xem chi tiết" action for debug log inspection
class _ErrorBannerCard extends StatelessWidget {
  const _ErrorBannerCard({required this.message, this.detail, this.onRetry});

  final String message;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.error, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colors.onErrorContainer,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            onPressed: () => DebugErrorSheet.show(
              context,
              error: detail ?? message,
              source: 'SmartCharge',
            ),
            child: const Text('Xem chi tiết', style: TextStyle(fontSize: 12)),
          ),
          if (onRetry != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              tooltip: 'Thử lại',
              onPressed: onRetry,
            ),
        ],
      ),
    );
  }
}

class _SafetyWarning extends StatelessWidget {
  const _SafetyWarning({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: AppRadii.md,
    ),
    child: Row(
      children: [
        Icon(
          Icons.thermostat_rounded,
          color: Theme.of(context).colorScheme.onTertiaryContainer,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onTertiaryContainer,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Target battery planning workspace
class _PlanSection extends StatelessWidget {
  const _PlanSection({
    super.key,
    required this.state,
    required this.controller,
    required this.onStart,
  });

  final SmartChargingUiState state;
  final SmartChargingController controller;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final draft = state.draft;
    final busy =
        state.phase == SmartChargingViewPhase.loading ||
        state.phase == SmartChargingViewPhase.starting;
    final canStart =
        state.preview?.aiChargeEligible == true &&
        state.capabilities.readyForControl &&
        state.connectionState.shellyReachable;

    final currentPercent = draft.currentSoc.round();
    final minTarget = (currentPercent + 1).clamp(1, 99).toDouble();
    final currentTarget = draft.targetSoc.clamp(minTarget, 100.0);

    return CockpitPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current SOC context. The interactive battery below remains the
          // dominant visual; this row only provides provenance and edit access.
          CockpitPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.battery_5_bar_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pin hiện tại',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '~$currentPercent%',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              height: 1.05,
                            ),
                      ),
                      Text(
                        'Hồ sơ xe · ước tính, không phải dữ liệu BMS',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: () => _editSoc(context, draft.currentSoc),
                  icon: const Icon(Icons.edit_outlined, size: 19),
                  tooltip: 'Chỉnh mức pin hiện tại',
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Target Battery Title & Display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Pin muốn sạc tới',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${currentTarget.round()}%',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          HorizontalBatteryTargetSelector(
            key: const ValueKey('target-battery-selector'),
            value: currentTarget,
            currentSoc: draft.currentSoc,
            onChanged: (value) => controller.updateDraft(targetSoc: value),
          ),

          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.add_circle_outline_rounded,
                size: 17,
                color: SmartChargeCockpitColors.verified,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '+${(currentTarget - draft.currentSoc).round()}% cần nạp',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                draft.estimatedCapacityWh > 0
                    ? '~${_energy(draft.estimatedCapacityWh * (currentTarget - draft.currentSoc) / 100)}'
                    : 'Chưa có dung lượng pin',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: draft.estimatedCapacityWh > 0
                      ? SmartChargeCockpitColors.warning
                      : SmartChargeCockpitColors.muted,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Preview Card if calculation succeeded
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: state.preview == null
                ? const SizedBox.shrink(key: ValueKey('no-plan-preview'))
                : _PreviewCard(
                    key: const ValueKey('plan-preview'),
                    preview: state.preview!,
                    tariffVndPerKwh: state.preferences?.tariffVndPerKwh,
                  ),
          ),

          const SizedBox(height: 20),

          // Dominant circular action mirrors the EV cockpit reference while
          // preserving the existing preview/start safety gates.
          Center(
            child: Container(
              width: 132,
              height: 132,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: CockpitColors.emerald.withValues(alpha: .20),
                ),
                boxShadow: CockpitMotion.enabled(context)
                    ? [
                        BoxShadow(
                          color: CockpitColors.emerald.withValues(alpha: .13),
                          blurRadius: 32,
                          spreadRadius: 3,
                        ),
                      ]
                    : const [],
              ),
              child: state.preview == null
                  ? FilledButton(
                      key: const ValueKey('create-plan-button'),
                      onPressed: busy ? null : controller.createPreview,
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: busy
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : const Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.auto_awesome_rounded, size: 22),
                              SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'DỰ ĐOÁN VỚI AI',
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                            ),
                    )
                  : FilledButton(
                      key: const ValueKey('confirm-plan-button'),
                      onPressed: busy || !canStart ? null : onStart,
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bolt_rounded, size: 24),
                        SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'SẠC THEO AI',
                            maxLines: 1,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                      ),
                    ),
            ),
          ),

          if (state.preview != null && !canStart) ...[
            const SizedBox(height: 8),
            Text(
              state.preview!.aiChargeEligible
                  ? 'Hãy hoàn tất cài đặt ổ sạc để bắt đầu sạc.'
                  : 'Dự đoán thời gian chưa khả dụng.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editSoc(BuildContext context, double initial) async {
    var value = initial;
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Chỉnh mức pin hiện tại'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${value.round()}%',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Slider(
                key: const ValueKey('current-soc-slider'),
                value: value,
                min: 0,
                max: 99,
                divisions: 99,
                onChanged: (next) => setState(() => value = next),
              ),
              const SizedBox(height: 6),
              const Text('Pin hiện tại là giá trị ước tính.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, value),
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (result != null) controller.updateDraft(currentSoc: result);
  }
}

/// Simplified clean Preview Card showing duration, stop time, and target pin
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({super.key, required this.preview, this.tariffVndPerKwh});
  final SmartChargingPlanPreview preview;
  final double? tariffVndPerKwh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final energyWh = preview.draft.estimatedCapacityWh > 0
        ? preview.draft.estimatedCapacityWh *
              (preview.draft.targetSoc - preview.draft.currentSoc) /
              100
        : null;
    final costVnd = energyWh == null || tariffVndPerKwh == null
        ? null
        : energyWh / .90 / 1000 * tariffVndPerKwh!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: AppRadii.lg,
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Kế hoạch sạc',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${preview.draft.currentSoc.round()}% → ${preview.draft.targetSoc.round()}%',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PreviewRow(
            label: 'Thời gian dự kiến',
            value: _formatPreviewDuration(preview.predictedMinutes),
            emphasized: true,
          ),
          _PreviewRow(
            label: 'Dự kiến dừng lúc',
            value: _time(preview.effectiveStopAt),
          ),
          _PreviewRow(
            label: 'Điện ước tính cần nạp',
            value: energyWh == null
                ? 'Chưa có dung lượng pin'
                : _energy(energyWh),
          ),
          _PreviewRow(
            label: 'Chi phí dự kiến',
            value: costVnd == null
                ? 'Chưa đặt giá điện'
                : '~${NumberFormat.decimalPattern('vi_VN').format(costVnd)} đ',
          ),
          const SizedBox(height: 6),
          Text(
            preview.personalizationLabel,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (preview.etaCandidates.isNotEmpty) ...[
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Chi tiết dự đoán'),
              children: [
                for (final candidate in preview.etaCandidates)
                  _PreviewRow(
                    label: switch (candidate.source) {
                      'global_ai' => 'Mô hình nền',
                      'physics' => 'Dung lượng và công suất',
                      'personal' => 'Dữ liệu xe này',
                      _ => candidate.source,
                    },
                    value:
                        '${_formatPreviewDuration((candidate.durationSeconds / 60).round())} · ${(candidate.weight * 100).round()}%',
                  ),
              ],
            ),
          ],
          for (final warning in preview.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                warning,
                style: TextStyle(color: colors.error, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Text(
          value,
          style: TextStyle(
            color: emphasized ? Theme.of(context).colorScheme.primary : null,
            fontWeight: emphasized ? FontWeight.w900 : FontWeight.w600,
            fontSize: emphasized ? 16 : 14,
          ),
        ),
      ],
    ),
  );
}

/// Active Charging view when relay is ON
class _ActiveChargingView extends StatelessWidget {
  const _ActiveChargingView({
    super.key,
    required this.state,
    required this.onStop,
  });

  final SmartChargingUiState state;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final timerIsVerified =
        state.session?.timerVerified == true ||
        state.chargerStatus?.timerRemaining != null;
    final verifiedColor = timerIsVerified
        ? colors.primary
        : SmartChargeCockpitColors.warning;
    final session = state.session;
    final remaining =
        state.chargerStatus?.timerRemaining ??
        (session != null ? session.remaining(state.now) : Duration.zero);

    final hh = remaining.inHours.toString().padLeft(2, '0');
    final mm = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');

    final powerW = state.chargerStatus?.powerW ?? 0;
    final energyWh = session?.energyUsedWh ?? 0;
    final status = state.chargerStatus;
    final costVnd = session?.estimatedCostVnd;

    final startSoc =
        session?.startSoc.round() ?? state.draft.currentSoc.round();
    final targetSoc =
        session?.targetSoc.round() ?? state.draft.targetSoc.round();

    return CockpitPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live charging badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: verifiedColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: verifiedColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_rounded, color: verifiedColor, size: 18),
                const SizedBox(width: 6),
                Text(
                  'ĐANG SẠC',
                  style: TextStyle(
                    color: verifiedColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Mục tiêu ~$targetSoc% · SOC là giá trị ước tính',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: SmartChargeCockpitColors.text,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 16),

          ChargingBatteryAnimationV3(
            currentSoc: session?.estimatedSoc ?? startSoc.toDouble(),
            targetSoc: targetSoc.toDouble(),
            sampleRevision: session?.updatedAt.millisecondsSinceEpoch ?? 0,
          ),

          const SizedBox(height: 16),

          // Countdown timer card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: AppRadii.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Còn khoảng',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$hh:$mm:$ss',
                  key: const ValueKey('session-countdown'),
                  style: CockpitTypography.numbers(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                // Essential metrics
                Wrap(
                  spacing: 22,
                  runSpacing: 16,
                  children: [
                    _Metric(
                      label: 'Công suất',
                      value: '${powerW.toStringAsFixed(0)} W',
                    ),
                    _Metric(
                      label: 'Điện áp',
                      value: status == null
                          ? '—'
                          : '${status.voltageV.toStringAsFixed(1)} V',
                    ),
                    _Metric(
                      label: 'Dòng điện',
                      value: status == null
                          ? '—'
                          : '${status.currentA.toStringAsFixed(2)} A',
                    ),
                    _Metric(
                      label: 'Nhiệt độ',
                      value: status?.temperatureC == null
                          ? '—'
                          : '${status!.temperatureC!.toStringAsFixed(1)} °C',
                    ),
                    if (session?.effectiveStopAt != null)
                      _Metric(
                        label: 'Tự tắt lúc',
                        value: _time(session!.effectiveStopAt),
                      ),
                    _Metric(label: 'Năng lượng', value: _energy(energyWh)),
                    _Metric(
                      label: 'Chi phí tạm tính',
                      value: costVnd == null
                          ? 'Chưa đặt giá điện'
                          : '${NumberFormat.decimalPattern('vi_VN').format(costVnd)} đ',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      session?.timerVerified == true ||
                              status?.timerRemaining != null
                          ? Icons.verified_rounded
                          : Icons.warning_amber_rounded,
                      size: 17,
                      color:
                          session?.timerVerified == true ||
                              status?.timerRemaining != null
                          ? SmartChargeCockpitColors.verified
                          : SmartChargeCockpitColors.warning,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        session?.timerVerified == true ||
                                status?.timerRemaining != null
                            ? 'Timer đã cài trên Shelly'
                            : 'Chưa xác minh timer thiết bị',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (state.livePowerSamples.length >= 2) ...[
            const SizedBox(height: 14),
            _LivePowerSparkline(samples: state.livePowerSamples),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('DỪNG PHIÊN'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 2),
      Text(value, style: CockpitTypography.numbers(fontSize: 15)),
    ],
  );
}

class _LivePowerSparkline extends StatelessWidget {
  const _LivePowerSparkline({required this.samples});
  final List<double> samples;

  @override
  Widget build(BuildContext context) {
    final visible = samples.length > 180
        ? samples.sublist(samples.length - 180)
        : samples;
    return Semantics(
      label:
          'Biểu đồ công suất 15 phút gần nhất, hiện tại ${visible.last.toStringAsFixed(0)} watt',
      child: Container(
        height: 104,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(
          color: SmartChargeCockpitColors.elevated,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CÔNG SUẤT · 15 PHÚT GẦN NHẤT',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: SmartChargeCockpitColors.muted,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LineChart(
                LineChartData(
                  minY: 0,
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var index = 0; index < visible.length; index++)
                          FlSpot(index.toDouble(), visible[index]),
                      ],
                      isCurved: true,
                      curveSmoothness: .22,
                      barWidth: 2.5,
                      color: SmartChargeCockpitColors.verified,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: SmartChargeCockpitColors.verified.withValues(
                          alpha: .10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Manual controls section
class _ManualControlsSection extends StatelessWidget {
  const _ManualControlsSection({
    super.key,
    required this.state,
    required this.onOn,
    required this.onOff,
  });

  final SmartChargingUiState state;
  final VoidCallback onOn;
  final VoidCallback onOff;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return CockpitPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sạc hẹn giờ',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'Bật ngay với timer mặc định 1 giờ, hoặc chọn thời gian tự ngắt trực tiếp trên Shelly.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: CockpitColors.muted),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('manual-on-button'),
                  onPressed: state.capabilities.readyForControl ? onOn : null,
                  icon: const Icon(Icons.power_rounded),
                  label: const Text('BẬT SẠC'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('smart-charging-manual-off'),
                  onPressed: onOff,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: error,
                    side: BorderSide(color: error),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.power_settings_new_rounded),
                  label: const Text('TẮT SẠC'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// History section showing previous charging sessions
class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.sessions,
    required this.status,
    required this.error,
    required this.syncedAt,
    required this.onRetry,
    required this.onViewAll,
    required this.onOpen,
  });

  final List<SmartChargingSession> sessions;
  final SmartChargeHistoryStatus status;
  final String? error;
  final DateTime? syncedAt;
  final VoidCallback onRetry;
  final VoidCallback onViewAll;
  final ValueChanged<SmartChargingSession> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final syncText = syncedAt == null
        ? 'Chưa đồng bộ'
        : 'Đồng bộ lần cuối ${DateFormat('HH:mm').format(syncedAt!.toLocal())}';

    return Semantics(
      container: true,
      label: 'Lịch sử Smart Charge gần đây',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Lịch sử gần đây',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                syncText,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (status == SmartChargeHistoryStatus.loading && sessions.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (status == SmartChargeHistoryStatus.error && sessions.isEmpty)
            _HistoryMessage(
              icon: Icons.cloud_off_rounded,
              title: 'Chưa thể đồng bộ lịch sử',
              message: error ?? 'Dữ liệu sạc sẽ được thử đồng bộ lại.',
              actionLabel: 'Thử lại lịch sử',
              onAction: onRetry,
            )
          else if (sessions.isEmpty)
            const _HistoryMessage(
              icon: Icons.electric_bolt_rounded,
              title: 'Chưa có phiên sạc',
              message: 'Phiên Smart Charge hoàn tất sẽ xuất hiện tại đây.',
            )
          else ...[
            if (status == SmartChargeHistoryStatus.stale || error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Đang hiển thị dữ liệu đã lưu trên thiết bị.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.tertiary),
                ),
              ),
            for (final session in sessions.take(3))
              _RecentSessionTile(
                session: session,
                onTap: () => onOpen(session),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onViewAll,
                icon: const Icon(Icons.history_rounded),
                label: const Text('XEM TOÀN BỘ LỊCH SỬ'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentSessionTile extends StatelessWidget {
  const _RecentSessionTile({required this.session, required this.onTap});

  final SmartChargingSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = (session.stoppedAt ?? session.updatedAt).difference(
      session.startedAt ?? session.createdAt,
    );
    final isAi = session.strategy != ChargingStrategy.manualTimed;
    final endSoc = session.estimatedSoc ?? session.targetSoc;
    final energy = session.energyUsedWh >= 1000
        ? '${(session.energyUsedWh / 1000).toStringAsFixed(2)} kWh'
        : '${session.energyUsedWh.toStringAsFixed(0)} Wh';
    final cost = session.estimatedCostVnd == null
        ? 'Chưa có giá điện'
        : '${NumberFormat.decimalPattern('vi_VN').format(session.estimatedCostVnd)} đ';

    return ListTile(
      minVerticalPadding: 12,
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: CircleAvatar(
        child: Icon(isAi ? Icons.auto_awesome_rounded : Icons.timer_rounded),
      ),
      title: Text(
        '${session.startSoc.toStringAsFixed(0)}% → ${endSoc.toStringAsFixed(0)}%',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${DateFormat('dd/MM · HH:mm').format(session.createdAt.toLocal())}\n'
        '${isAi ? 'Sạc AI' : 'Thủ công'} · $energy · $cost · ${_compactDuration(duration)}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            session.state == ChargingSessionState.completed
                ? 'Hoàn thành'
                : 'Đã dừng',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Center(
      child: Column(
        children: [
          Icon(icon, size: 34, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

String _compactDuration(Duration value) {
  final minutes = value.inMinutes.clamp(0, 10 * 60);
  final hours = minutes ~/ 60;
  final remaining = minutes % 60;
  if (hours == 0) return '$remaining phút';
  return remaining == 0 ? '$hours giờ' : '$hours giờ $remaining phút';
}

String _time(DateTime value) => DateFormat('HH:mm').format(value.toLocal());
String _energy(double wh) => wh >= 1000
    ? '${(wh / 1000).toStringAsFixed(2)} kWh'
    : '${wh.toStringAsFixed(0)} Wh';
String _duration(int minutes) =>
    minutes < 60 ? '$minutes phút' : '${minutes ~/ 60} giờ';

String _formatPreviewDuration(int totalMinutes) {
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h > 0) {
    return '$h giờ $m phút';
  }
  return '$m phút';
}
