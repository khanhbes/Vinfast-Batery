import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/app_status_widgets.dart';
import '../../data/models/smart_charging_session.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';
import 'controllers/smart_charging_controller.dart';

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
    final controller = ref.read(
      smartChargingControllerProvider(args).notifier,
    );
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Charge'),
        actions: [
          IconButton(
            tooltip: 'Làm mới trạng thái',
            onPressed: state.refreshing ? null : controller.refresh,
            icon: state.refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: state.hasActiveSession
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                height: 56,
                child: FilledButton.icon(
                  key: const ValueKey('stop-smart-session-button'),
                  onPressed: state.phase == SmartChargingViewPhase.stopping
                      ? null
                      : () => _off(controller),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  ),
                  icon: const Icon(Icons.power_settings_new_rounded),
                  label: const Text('NGẮT NGUỒN NGAY'),
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
              if (state.gatewayError != null) ...[
                const SizedBox(height: 12),
                AppErrorBanner(
                  message:
                      '${state.gatewayError} AI vẫn có thể dự đoán; hãy kết nối Shelly để điều khiển sạc.',
                  onRetry: controller.refresh,
                ),
              ],
              if (state.actionError != null) ...[
                const SizedBox(height: 12),
                AppErrorBanner(message: state.actionError!),
              ],
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                child: state.hasActiveSession
                    ? _Active(key: const ValueKey('active-session'), state: state)
                    : Column(
                        key: const ValueKey('plan-workspace'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ManualControls(
                            state: state,
                            onOn: () => _manualOn(controller),
                            onOff: () => _off(controller),
                          ),
                          const SizedBox(height: 30),
                          _Plan(
                            state: state,
                            controller: controller,
                            onStart: () => _aiStart(state, controller),
                          ),
                        ],
                      ),
              ),
              if (state.history.isNotEmpty) ...[
                const SizedBox(height: 32),
                _History(sessions: state.history),
              ],
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
              Text('Bật sạc có giới hạn', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Timer được cài trực tiếp trên Shelly nên thiết bị vẫn tự OFF khi app đóng hoặc mất kết nối.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in const [30, 60, 120, 240, 360])
                    ActionChip(
                      avatar: minutes == 60
                          ? const Icon(Icons.check_circle_rounded, size: 18)
                          : null,
                      label: Text(_duration(minutes)),
                      onPressed: () => Navigator.pop(
                        context,
                        Duration(minutes: minutes),
                      ),
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
        'Đã bật sạc',
        detail: 'Timer ${_duration(duration.inMinutes)} đã được xác minh.',
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
                'Shelly sẽ bật relay và tự OFF lúc ${_time(preview.effectiveStopAt)}, kể cả khi app đóng.',
              ),
              const SizedBox(height: 8),
              const Text('SOC là ước tính (~), không phải dữ liệu BMS.'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: acknowledged,
                onChanged: (value) =>
                    setDialogState(() => acknowledged = value == true),
                title: const Text('Tôi hiểu SOC là giá trị ước tính'),
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
              child: const Text('Bật nguồn sạc'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final ok = await controller.start(confirmed: true);
    if (ok) {
      AppPopup.showSuccess('Sạc theo AI đã bắt đầu', detail: 'Timer đã được xác minh trên Shelly.');
    } else {
      AppPopup.showError('Không thể bắt đầu Sạc theo AI');
    }
  }

  Future<void> _off(SmartChargingController controller) async {
    final ok = await controller.stop();
    if (ok) {
      AppPopup.showSuccess('Đã ngắt nguồn', detail: 'Relay OFF đã được xác minh.');
    } else {
      AppPopup.showError(
        'Không xác minh được OFF',
        detail: 'Hãy kiểm tra Shelly hoặc ngắt nguồn vật lý ngay.',
      );
    }
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.state, required this.onSetup});
  final SmartChargingUiState state;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = state.chargerStatus;
    final online = status?.online == true && state.gatewayError == null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: AppRadii.lg,
      ),
      child: Row(
        children: [
          Icon(
            online ? Icons.ev_station_rounded : Icons.power_off_rounded,
            color: online ? colors.primary : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status?.deviceName ?? 'Shelly chưa kết nối',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  online
                      ? '${status?.transport?.name.toUpperCase()} · ${status?.relay == true ? 'Relay ON' : 'Relay OFF'} · ${status?.powerW.toStringAsFixed(0)} W'
                      : state.capabilities.provider == 'integrator'
                          ? 'Easy chưa có capability điều khiển an toàn'
                          : 'Cloud chính · LAN dự phòng',
                  style: Theme.of(context).textTheme.bodySmall,
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

class _ManualControls extends StatelessWidget {
  const _ManualControls({
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
        Text('Điều khiển nguồn', style: Theme.of(context).textTheme.titleLarge),
        Text(
          'Mọi lệnh bật đều có timer an toàn trên thiết bị.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('manual-on-button'),
                onPressed: state.capabilities.readyForControl ? onOn : null,
                icon: const Icon(Icons.power_rounded),
                label: const Text('BẬT SẠC'),
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

class _Plan extends StatelessWidget {
  const _Plan({
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
    final busy = state.phase == SmartChargingViewPhase.loading ||
        state.phase == SmartChargingViewPhase.starting;
    final canStart = state.preview?.aiChargeEligible == true &&
        state.capabilities.readyForControl &&
        state.gatewayError == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'Mục tiêu',
          subtitle: 'AI trên web tính ETA; Shelly chịu trách nhiệm tự ngắt.',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SOC hiện tại · Ước tính', style: Theme.of(context).textTheme.bodyMedium),
                  Text(
                    '~${draft.currentSoc.round()}%',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  Text('Ước tính, không phải dữ liệu BMS', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => _editSoc(context, draft.currentSoc),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Chỉnh'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('SOC mục tiêu', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final target in const [80, 90, 100])
              ChoiceChip(
                label: Text('$target%'),
                selected: draft.targetSoc.round() == target,
                onSelected: (_) => controller.updateDraft(targetSoc: target.toDouble()),
              ),
          ],
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Nâng cao'),
          subtitle: const Text('Dừng không muộn hơn'),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final minutes in const [30, 60, 120])
                  ActionChip(
                    label: Text(_duration(minutes)),
                    onPressed: () => controller.updateDraft(
                      hardDeadlineAt: state.now.add(Duration(minutes: minutes)),
                      timeMode: ChargingTimeMode.duration,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: state.preview == null
              ? const SizedBox.shrink(key: ValueKey('no-plan-preview'))
              : _Preview(
                  key: const ValueKey('plan-preview'),
                  preview: state.preview!,
                ),
        ),
        const SizedBox(height: 18),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: const Text('DỰ ĐOÁN VỚI AI'),
                )
              : FilledButton.icon(
                  key: const ValueKey('confirm-plan-button'),
                  onPressed: busy || !canStart ? null : onStart,
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('SẠC THEO AI'),
                ),
        ),
        if (state.preview != null && !canStart) ...[
          const SizedBox(height: 8),
          Text(
            state.preview!.aiChargeEligible
                ? 'Hoàn tất kiểm tra Shelly trong Settings để mở Sạc theo AI.'
                : 'Model AI chưa sẵn sàng; ETA chỉ mang tính tham khảo.',
            style: Theme.of(context).textTheme.bodySmall,
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
          title: const Text('Chỉnh SOC hiện tại'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('~${value.round()}%', style: Theme.of(context).textTheme.headlineMedium),
              Slider(
                key: const ValueKey('current-soc-slider'),
                value: value,
                min: 0,
                max: 99,
                divisions: 99,
                onChanged: (next) => setState(() => value = next),
              ),
              const Text('Giá trị này là ước tính, không phải dữ liệu BMS.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, value), child: const Text('Lưu')),
          ],
        ),
      ),
    );
    if (result != null) controller.updateDraft(currentSoc: result);
  }
}

class _Preview extends StatelessWidget {
  const _Preview({super.key, required this.preview});
  final SmartChargingPlanPreview preview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: AppRadii.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Kế hoạch sạc', style: TextStyle(fontWeight: FontWeight.w800))),
              AppStatusChip(
                label: preview.aiChargeEligible ? 'AI' : 'Dự phòng',
                color: preview.aiChargeEligible ? colors.primary : colors.tertiary,
                icon: preview.aiChargeEligible ? Icons.auto_awesome_rounded : Icons.functions_rounded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Row(label: 'Thời lượng', value: '${preview.predictedMinutes} phút'),
          _Row(label: 'Dừng hiệu lực', value: _time(preview.effectiveStopAt), emphasized: true),
          _Row(label: 'Model', value: '${preview.modelKey} · ${preview.modelVersion}'),
          _Row(
            label: 'Phân tích lúc',
            value: preview.analyzedAt == null
                ? '—'
                : DateFormat('dd/MM HH:mm:ss')
                    .format(preview.analyzedAt!.toLocal()),
          ),
          _Row(
            label: 'Nguồn / tin cậy',
            value: preview.predictionConfidence == null
                ? preview.predictionSource
                : '${preview.predictionSource} · ${preview.predictionConfidence!.toStringAsFixed(0)}%',
          ),
          for (final warning in preview.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(warning, style: TextStyle(color: colors.tertiary)),
            ),
        ],
      ),
    );
  }
}

class _Active extends StatelessWidget {
  const _Active({super.key, required this.state});
  final SmartChargingUiState state;

  @override
  Widget build(BuildContext context) {
    final session = state.session!;
    final remaining = state.chargerStatus?.timerRemaining ?? session.remaining(state.now);
    final hh = remaining.inHours.toString().padLeft(2, '0');
    final mm = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return Semantics(
      liveRegion: true,
      label: 'Phiên sạc đang hoạt động, còn $hh giờ $mm phút',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(title: 'Đang sạc', subtitle: 'Timer đã cài trên Shelly'),
          const SizedBox(height: 22),
          Text(
            '$hh:$mm:$ss',
            key: const ValueKey('session-countdown'),
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text('timer còn lại trên thiết bị', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 22),
          Wrap(
            spacing: 22,
            runSpacing: 16,
            children: [
              _Metric(label: 'SOC ước tính', value: session.estimatedSoc == null ? '~--%' : '~${session.estimatedSoc!.toStringAsFixed(0)}%'),
              _Metric(label: 'Công suất', value: '${(state.chargerStatus?.powerW ?? 0).toStringAsFixed(0)} W'),
              _Metric(label: 'Điện áp', value: '${(state.chargerStatus?.voltageV ?? 0).toStringAsFixed(1)} V'),
              _Metric(label: 'Dòng điện', value: '${(state.chargerStatus?.currentA ?? 0).toStringAsFixed(2)} A'),
              _Metric(
                label: 'Nhiệt độ',
                value: state.chargerStatus?.temperatureC == null
                    ? '—'
                    : '${state.chargerStatus!.temperatureC!.toStringAsFixed(1)} °C',
              ),
              _Metric(label: 'Năng lượng', value: '${(state.chargerStatus?.energyWh ?? session.energyUsedWh).toStringAsFixed(0)} Wh'),
              _Metric(label: 'Dừng lúc', value: _time(session.effectiveStopAt)),
              _Metric(label: 'Model', value: session.strategy == ChargingStrategy.manualTimed ? 'Timer thủ công' : session.modelVersion),
            ],
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
  Widget build(BuildContext context) => SizedBox(
    width: 132,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.emphasized = false});
  final String label;
  final String value;
  final bool emphasized;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: emphasized ? Theme.of(context).colorScheme.primary : null,
              fontWeight: emphasized ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _History extends StatelessWidget {
  const _History({required this.sessions});
  final List<SmartChargingSession> sessions;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const AppSectionHeader(title: 'Lịch sử gần đây', subtitle: 'Mới nhất trước · dùng chung ChargeLogs.'),
      for (final session in sessions.take(5))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.history_rounded),
          title: Text('${session.startSoc.toStringAsFixed(0)} → ${session.targetSoc.toStringAsFixed(0)}%'),
          subtitle: Text('${DateFormat('dd/MM HH:mm').format(session.createdAt.toLocal())} · ${session.modelVersion}'),
          trailing: Text(session.state.wireValue, style: Theme.of(context).textTheme.bodySmall),
        ),
    ],
  );
}

String _time(DateTime value) => DateFormat('HH:mm').format(value.toLocal());
String _duration(int minutes) => minutes < 60 ? '$minutes phút' : '${minutes ~/ 60} giờ';
