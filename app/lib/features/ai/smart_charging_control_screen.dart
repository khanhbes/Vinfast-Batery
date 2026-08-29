import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/debug_error_sheet.dart';
import '../../data/models/smart_charge_history.dart';
import '../../data/models/smart_charging_session.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';
import 'controllers/smart_charging_controller.dart';
import 'smart_charge_history_screen.dart';

class SmartChargingControlScreen extends ConsumerStatefulWidget {
  const SmartChargingControlScreen({
    super.key,
    required this.vehicleId,
    required this.currentSoc,
  });
  final String vehicleId;
  final double currentSoc;

  @override
  ConsumerState<SmartChargingControlScreen> createState() => _ScreenState();
}

class _ScreenState extends ConsumerState<SmartChargingControlScreen>
    with WidgetsBindingObserver {
  late final SmartChargingControllerArgs args;

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

    return Scaffold(
      appBar: AppBar(title: const Text('Smart Charge')),
      bottomNavigationBar: state.hasActiveSession
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                height: 54,
                child: FilledButton.icon(
                  key: const ValueKey('stop-smart-session-button'),
                  onPressed: state.phase == SmartChargingViewPhase.stopping
                      ? null
                      : () => _off(controller),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.power_settings_new_rounded),
                  label: const Text(
                    'DỪNG SẠC',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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

              // Error notification banners with debug view action
              if (state.gatewayError != null) ...[
                const SizedBox(height: 12),
                _ErrorBannerCard(
                  message: 'Không kết nối được ổ sạc.',
                  detail: state.gatewayError,
                  onRetry: controller.refresh,
                ),
              ],
              if (state.actionError != null) ...[
                const SizedBox(height: 12),
                _ErrorBannerCard(
                  message: state.actionError!,
                  detail: state.actionError,
                ),
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
                        onStop: () => _off(controller),
                      )
                    : Column(
                        key: const ValueKey('plan-workspace'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PlanSection(
                            state: state,
                            controller: controller,
                            onStart: () => _aiStart(state, controller),
                          ),
                          const SizedBox(height: 28),
                          _ManualControlsSection(
                            state: state,
                            onOn: () => _manualOn(controller),
                            onOff: () => _off(controller),
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
                onRetry: controller.refresh,
                onViewAll: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SmartChargeHistoryScreen(
                      controller: controller,
                      initialItems: state.history,
                    ),
                  ),
                ),
                onOpen: (session) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SmartChargeSessionDetailScreen(
                      controller: controller,
                      session: session,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _manualOn(SmartChargingController controller) async {
    final duration = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bật sạc có giới hạn',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Ổ sạc sẽ tự động tắt khi hết thời gian, kể cả khi ứng dụng bị đóng.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in const [30, 60, 120, 240, 360, 600])
                    ActionChip(
                      avatar: minutes == 60
                          ? const Icon(Icons.check_circle_rounded, size: 18)
                          : null,
                      label: Text(_duration(minutes)),
                      onPressed: () =>
                          Navigator.pop(context, Duration(minutes: minutes)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
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
              const Text('Mức pin là giá trị ước tính (~).'),
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

  Future<void> _off(SmartChargingController controller) async {
    final ok = await controller.stop();
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
        titleText = 'Đang sạc';
        final power = status?.powerW ?? 0;
        subtitleText = power > 0
            ? 'Đang nhận điện · ${power.toStringAsFixed(0)} W'
            : 'Đang nhận điện';
        break;
      case ChargerDisplayState.off:
        iconColor = Colors.grey.shade400;
        iconData = Icons.power_off_rounded;
        titleText = 'Đã tắt sạc';
        subtitleText = null;
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: AppRadii.lg,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
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
        color: colors.errorContainer.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.error.withOpacity(0.3)),
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

/// Target battery planning workspace
class _PlanSection extends StatelessWidget {
  const _PlanSection({
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
        state.gatewayError == null;

    final currentPercent = draft.currentSoc.round();
    final minTarget = (currentPercent + 1).clamp(1, 99).toDouble();
    final currentTarget = draft.targetSoc.clamp(minTarget, 100.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current Battery Header Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: AppRadii.lg,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pin hiện tại',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '~$currentPercent%',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _editSoc(context, draft.currentSoc),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Chỉnh'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

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
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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

        // Continuous Slider from (currentSoc + 1) to 100%
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            thumbColor: Theme.of(context).colorScheme.primary,
            trackHeight: 6,
          ),
          child: Slider(
            key: const ValueKey('target-battery-slider'),
            value: currentTarget,
            min: minTarget,
            max: 100.0,
            divisions: max(1, (100 - minTarget).round()),
            onChanged: (val) =>
                controller.updateDraft(targetSoc: val.roundToDouble()),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$minTarget%', style: Theme.of(context).textTheme.bodySmall),
              const Text('100%', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Quick preset shortcut chips (80%, 90%, 100%)
        Row(
          children: [
            for (final target in const [80, 90, 100]) ...[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Center(
                      child: Text(
                        '$target%',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    selected: currentTarget.round() == target,
                    disabledColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                    onSelected: currentPercent >= target
                        ? null
                        : (_) => controller.updateDraft(
                            targetSoc: target.toDouble(),
                          ),
                  ),
                ),
              ),
            ],
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
                ),
        ),

        const SizedBox(height: 20),

        // Main CTA Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: state.preview == null
              ? FilledButton.icon(
                  key: const ValueKey('create-plan-button'),
                  onPressed: busy ? null : controller.createPreview,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: const Text(
                    'TÍNH THỜI GIAN SẠC',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                )
              : FilledButton.icon(
                  key: const ValueKey('confirm-plan-button'),
                  onPressed: busy || !canStart ? null : onStart,
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text(
                    'BẮT ĐẦU SẠC',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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
                '~${value.round()}%',
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
              const Text('Mức pin là giá trị ước tính (~).'),
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
  const _PreviewCard({super.key, required this.preview});
  final SmartChargingPlanPreview preview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: AppRadii.lg,
        border: Border.all(color: colors.primary.withOpacity(0.3)),
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
                  color: colors.primary.withOpacity(0.15),
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
    final session = state.session;
    final remaining =
        state.chargerStatus?.timerRemaining ??
        (session != null ? session.remaining(state.now) : Duration.zero);

    final hh = remaining.inHours.toString().padLeft(2, '0');
    final mm = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');

    final powerW = state.chargerStatus?.powerW ?? 0;
    final energyWh =
        state.chargerStatus?.energyWh ?? session?.energyUsedWh ?? 0;

    final startSoc =
        session?.startSoc.round() ?? state.draft.currentSoc.round();
    final targetSoc =
        session?.targetSoc.round() ?? state.draft.targetSoc.round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Live charging badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt_rounded, color: Colors.greenAccent, size: 18),
              SizedBox(width: 6),
              Text(
                'ĐANG SẠC',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Pin progression banner
        Text(
          '~$startSoc% → $targetSoc%',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              // Essential metrics
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Metric(
                    label: 'Công suất',
                    value: '${powerW.toStringAsFixed(0)} W',
                  ),
                  if (session?.effectiveStopAt != null)
                    _Metric(
                      label: 'Tự tắt lúc',
                      value: _time(session!.effectiveStopAt),
                    ),
                  _Metric(
                    label: 'Năng lượng',
                    value: '${energyWh.toStringAsFixed(0)} Wh',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    ],
  );
}

/// Manual controls section
class _ManualControlsSection extends StatelessWidget {
  const _ManualControlsSection({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Điều khiển nguồn thủ công',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
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

    return ListTile(
      minVerticalPadding: 12,
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: CircleAvatar(
        child: Icon(isAi ? Icons.auto_awesome_rounded : Icons.timer_rounded),
      ),
      title: Text(
        '~${session.startSoc.toStringAsFixed(0)}% → ~${endSoc.toStringAsFixed(0)}%',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${DateFormat('dd/MM · HH:mm').format(session.createdAt.toLocal())}\n'
        '${isAi ? 'Sạc AI' : 'Thủ công'} · $energy · ${_compactDuration(duration)}',
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
