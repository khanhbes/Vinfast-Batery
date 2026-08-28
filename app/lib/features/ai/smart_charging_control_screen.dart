import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_status_widgets.dart';
import '../../data/models/smart_charging_session.dart';
import '../smart_charging/shelly_setup_screen.dart';
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
  ConsumerState<SmartChargingControlScreen> createState() =>
      _SmartChargingControlScreenState();
}

class _SmartChargingControlScreenState
    extends ConsumerState<SmartChargingControlScreen> {
  late final SmartChargingControllerArgs _args;

  @override
  void initState() {
    super.initState();
    _args = SmartChargingControllerArgs(
      vehicleId: widget.vehicleId,
      currentSoc: widget.currentSoc,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smartChargingControllerProvider(_args));
    final controller = ref.read(
      smartChargingControllerProvider(_args).notifier,
    );
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sạc thông minh'),
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
                      : () => _confirmStop(controller),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              40,
            ),
            children: [
              _GatewaySummary(
                state: state,
                onSetup: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const ShellySetupScreen(),
                      ),
                    )
                    .then((_) => controller.refresh()),
              ),
              if (state.gatewayError != null) ...[
                const SizedBox(height: AppSpacing.md),
                AppErrorBanner(
                  message:
                      '${state.gatewayError} AI vẫn có thể dự đoán; hãy kết nối Shelly để bắt đầu sạc.',
                  onRetry: controller.refresh,
                ),
              ],
              if (state.actionError != null) ...[
                const SizedBox(height: AppSpacing.md),
                AppErrorBanner(message: state.actionError!),
              ],
              const SizedBox(height: AppSpacing.xl),
              AnimatedSwitcher(
                duration: reducedMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                switchInCurve: AppMotion.enter,
                switchOutCurve: AppMotion.exit,
                child: state.hasActiveSession
                    ? _ActiveSessionPanel(
                        key: const ValueKey('active-session'),
                        state: state,
                        onStop: () => _confirmStop(controller),
                      )
                    : _PlanWorkspace(
                        key: const ValueKey('plan-workspace'),
                        state: state,
                        controller: controller,
                        onPickTime: () => _pickDeadline(state, controller),
                        onConfirmStart: () => _confirmStart(state, controller),
                      ),
              ),
              if (!state.hasActiveSession &&
                  state.chargerStatus?.relay == true) ...[
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    key: const ValueKey('smart-charging-manual-off'),
                    onPressed: controller.manualOff,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                    icon: const Icon(Icons.power_settings_new_rounded),
                    label: const Text('NGẮT NGUỒN NGAY'),
                  ),
                ),
              ],
              if (state.history.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxl),
                _HistorySection(sessions: state.history),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDeadline(
    SmartChargingUiState state,
    SmartChargingController controller,
  ) async {
    final current = state.draft.hardDeadlineAt;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: 'Chọn thời điểm dừng cứng',
    );
    if (selected == null || !mounted) return;
    var deadline = DateTime(
      state.now.year,
      state.now.month,
      state.now.day,
      selected.hour,
      selected.minute,
    );
    if (!deadline.isAfter(state.now)) {
      deadline = deadline.add(const Duration(days: 1));
    }
    controller.updateDraft(
      hardDeadlineAt: deadline,
      timeMode: ChargingTimeMode.stopTime,
    );
  }

  Future<void> _confirmStart(
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
                'Shelly sẽ bật relay và tự ngắt lúc ${_time(preview.effectiveStopAt)}, kể cả khi app đã đóng.',
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'SOC hiển thị là ước tính (~), không phải dữ liệu BMS.',
                style: TextStyle(color: AppColors.warning),
              ),
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
    if (confirmed == true) await controller.start(confirmed: true);
  }

  Future<void> _confirmStop(SmartChargingController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ngắt nguồn sạc?'),
        content: const Text(
          'App sẽ gửi OFF qua Cloud và LAN, rồi chỉ kết thúc phiên sau khi đọc lại relay đã ngắt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Tiếp tục sạc'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ngắt nguồn'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.stop();
  }
}

class _GatewaySummary extends StatelessWidget {
  const _GatewaySummary({required this.state, required this.onSetup});
  final SmartChargingUiState state;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final status = state.chargerStatus;
    final online = status?.online == true && state.gatewayError == null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadii.lg,
      ),
      child: Row(
        children: [
          Icon(
            Icons.ev_station_rounded,
            color: online ? AppColors.primary : AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status?.deviceName ?? 'Shelly chưa kết nối',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  online
                      ? '${status?.transport?.name.toUpperCase()} · ${status?.relay == true ? 'Relay ON' : 'Relay OFF'} · ${status?.powerW.toStringAsFixed(0)} W'
                      : 'Cloud chính · LAN dự phòng',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (!online)
            TextButton(onPressed: onSetup, child: const Text('Kết nối')),
        ],
      ),
    );
  }
}

class _PlanWorkspace extends StatelessWidget {
  const _PlanWorkspace({
    super.key,
    required this.state,
    required this.controller,
    required this.onPickTime,
    required this.onConfirmStart,
  });

  final SmartChargingUiState state;
  final SmartChargingController controller;
  final VoidCallback onPickTime;
  final VoidCallback onConfirmStart;

  @override
  Widget build(BuildContext context) {
    final draft = state.draft;
    final busy =
        state.phase == SmartChargingViewPhase.loading ||
        state.phase == SmartChargingViewPhase.starting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'Mục tiêu',
          subtitle: 'Nhập SOC đang thấy trên xe và mức bạn muốn đạt.',
        ),
        const SizedBox(height: AppSpacing.md),
        _SocControl(
          label: 'SOC hiện tại · Ước tính',
          value: draft.currentSoc,
          valueKey: const ValueKey('current-soc-slider'),
          onChanged: (value) => controller.updateDraft(currentSoc: value),
        ),
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            for (final target in const [80, 90, 100])
              ChoiceChip(
                label: Text('$target%'),
                selected: draft.targetSoc.round() == target,
                onSelected: (_) =>
                    controller.updateDraft(targetSoc: target.toDouble()),
              ),
          ],
        ),
        _SocControl(
          label: 'SOC mục tiêu',
          value: draft.targetSoc,
          valueKey: const ValueKey('target-soc-slider'),
          onChanged: (value) => controller.updateDraft(targetSoc: value),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: const Text('Nâng cao'),
          subtitle: const Text('Dừng không muộn hơn, nguồn AI và chiến lược'),
          children: [
            const Divider(height: AppSpacing.xxl),
            const AppSectionHeader(
              title: 'Thời điểm dừng cứng',
              subtitle: 'Timer Shelly sẽ không được arm vượt quá mốc này.',
            ),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<ChargingTimeMode>(
              segments: const [
                ButtonSegment(
                  value: ChargingTimeMode.duration,
                  icon: Icon(Icons.timelapse_rounded),
                  label: Text('Khoảng thời gian'),
                ),
                ButtonSegment(
                  value: ChargingTimeMode.stopTime,
                  icon: Icon(Icons.schedule_rounded),
                  label: Text('Giờ dừng'),
                ),
              ],
              selected: {draft.timeMode},
              onSelectionChanged: (value) =>
                  controller.updateDraft(timeMode: value.first),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final preset in const [30, 60, 120])
                  ChoiceChip(
                    label: Text(
                      preset == 60
                          ? '1 giờ'
                          : preset == 120
                          ? '2 giờ'
                          : '30 phút',
                    ),
                    selected:
                        _roughlyMinutesFromNow(
                          draft.hardDeadlineAt,
                          state.now,
                        ) ==
                        preset,
                    onSelected: (_) => controller.updateDraft(
                      hardDeadlineAt: state.now.add(Duration(minutes: preset)),
                      timeMode: ChargingTimeMode.duration,
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(_time(draft.hardDeadlineAt)),
                  onPressed: onPickTime,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(
              title: 'Chiến lược',
              subtitle: 'Kết hợp thông minh được khuyến nghị cho đa số phiên.',
            ),
            const SizedBox(height: AppSpacing.sm),
            RadioGroup<ChargingStrategy>(
              groupValue: draft.strategy,
              onChanged: (value) => controller.updateDraft(strategy: value),
              child: Column(
                children: [
                  for (final strategy in ChargingStrategy.values)
                    RadioListTile<ChargingStrategy>(
                      contentPadding: EdgeInsets.zero,
                      value: strategy,
                      title: Text(_strategyLabel(strategy)),
                      subtitle: Text(_strategyDescription(strategy)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: state.preview == null
              ? const SizedBox.shrink(key: ValueKey('no-plan-preview'))
              : _PreviewPanel(
                  key: const ValueKey('plan-preview-animated'),
                  preview: state.preview!,
                  controller: controller,
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
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
                  onPressed: busy || state.gatewayError != null
                      ? null
                      : onConfirmStart,
                  icon: state.phase == SmartChargingViewPhase.starting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.power_rounded),
                  label: const Text('BẮT ĐẦU SẠC & TỰ NGẮT'),
                ),
        ),
      ],
    );
  }
}

class _SocControl extends StatelessWidget {
  const _SocControl({
    required this.label,
    required this.value,
    required this.valueKey,
    required this.onChanged,
  });
  final String label;
  final double value;
  final Key valueKey;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    value: '${value.round()} phần trăm',
    slider: true,
    child: Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                Slider(
                  key: valueKey,
                  value: value.clamp(0, 100),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${value.round()}%',
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 58,
            child: Text(
              '~${value.round()}%',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    super.key,
    required this.preview,
    required this.controller,
  });
  final SmartChargingPlanPreview preview;
  final SmartChargingController controller;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('plan-preview'),
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: const BoxDecoration(
      color: AppColors.card,
      borderRadius: AppRadii.lg,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: AppSectionHeader(title: 'Xem trước kế hoạch'),
            ),
            AppStatusChip(
              label: preview.isPhysicsFallback ? 'Vật lý dự phòng' : 'AI',
              color: preview.isPhysicsFallback
                  ? AppColors.warning
                  : AppColors.primary,
              icon: preview.isPhysicsFallback
                  ? Icons.functions_rounded
                  : Icons.auto_awesome_rounded,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _MetricRow(
          label: 'AI dự kiến',
          value:
              '${preview.predictedMinutes} phút · ${_time(preview.aiStopAt)}',
        ),
        _MetricRow(
          label: 'Hạn dừng cứng',
          value: _time(preview.draft.hardDeadlineAt),
        ),
        _MetricRow(
          label: 'Dừng hiệu lực',
          value: _time(preview.effectiveStopAt),
          emphasized: true,
        ),
        _MetricRow(
          label: 'Nguồn / độ tin cậy',
          value: preview.predictionConfidence == null
              ? preview.predictionSource
              : '${preview.predictionSource} · ${preview.predictionConfidence!.toStringAsFixed(0)}%',
        ),
        if (preview.warning != null) ...[
          const SizedBox(height: AppSpacing.sm),
          AppErrorBanner(message: preview.warning!),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              TextButton(
                onPressed: () => controller.updateDraft(
                  hardDeadlineAt: preview.aiStopAt.add(
                    const Duration(minutes: 10),
                  ),
                ),
                child: const Text('Nới hạn dừng'),
              ),
              TextButton(
                onPressed: () =>
                    controller.updateDraft(strategy: ChargingStrategy.deadline),
                child: const Text('Ưu tiên thời gian'),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _ActiveSessionPanel extends StatelessWidget {
  const _ActiveSessionPanel({
    super.key,
    required this.state,
    required this.onStop,
  });
  final SmartChargingUiState state;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final session = state.session!;
    final remaining =
        state.chargerStatus?.timerRemaining ?? session.remaining(state.now);
    final hh = remaining.inHours.toString().padLeft(2, '0');
    final mm = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return Semantics(
      liveRegion: true,
      label: 'Phiên sạc đang hoạt động, còn $hh giờ $mm phút',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: AppSectionHeader(
                  title: 'Đang sạc',
                  subtitle: 'Timer đã cài trên Shelly',
                ),
              ),
              AppStatusChip(
                label:
                    state.chargerStatus?.transport?.name.toUpperCase() ??
                    'TỰ ĐỘNG',
                color: AppColors.success,
                icon: Icons.shield_rounded,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            '$hh:$mm:$ss',
            key: const ValueKey('session-countdown'),
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const Text(
            'timer còn lại trên thiết bị',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: [
              _ActiveMetric(
                label: 'SOC ước tính',
                value: session.estimatedSoc == null
                    ? '~--%'
                    : '~${session.estimatedSoc!.toStringAsFixed(0)}%',
              ),
              _ActiveMetric(
                label: 'Năng lượng',
                value:
                    '${(state.chargerStatus?.energyWh ?? session.energyUsedWh).toStringAsFixed(0)} Wh',
              ),
              _ActiveMetric(
                label: 'Công suất',
                value:
                    '${(state.chargerStatus?.powerW ?? 0).toStringAsFixed(0)} W',
              ),
              _ActiveMetric(
                label: 'Điện áp',
                value:
                    '${(state.chargerStatus?.voltageV ?? 0).toStringAsFixed(1)} V',
              ),
              _ActiveMetric(
                label: 'Dòng điện',
                value:
                    '${(state.chargerStatus?.currentA ?? 0).toStringAsFixed(2)} A',
              ),
              _ActiveMetric(
                label: 'Dừng lúc',
                value: _time(session.effectiveStopAt),
              ),
              _ActiveMetric(
                label: 'Chiến lược',
                value: _strategyLabel(session.strategy),
              ),
            ],
          ),
          if (session.wouldHaveTurnedOffAt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AppStatusChip(
              label:
                  'Đã tới mốc dự kiến lúc ${_time(session.wouldHaveTurnedOffAt!)}',
              color: AppColors.warning,
              icon: Icons.timer_off_rounded,
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _ActiveMetric extends StatelessWidget {
  const _ActiveMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 132,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ],
    ),
  );
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });
  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: emphasized ? AppColors.primary : AppColors.textPrimary,
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.sessions});
  final List<SmartChargingSession> sessions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const AppSectionHeader(
        title: 'Lịch sử gần đây',
        subtitle: 'Mới nhất trước · dùng chung dữ liệu ChargeLogs.',
      ),
      const SizedBox(height: AppSpacing.sm),
      for (final session in sessions.take(5)) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            session.state == ChargingSessionState.completed
                ? Icons.check_circle_outline_rounded
                : Icons.history_rounded,
            color: session.state == ChargingSessionState.completed
                ? AppColors.success
                : AppColors.textSecondary,
          ),
          title: Text(
            '${session.startSoc.toStringAsFixed(0)} → ${session.targetSoc.toStringAsFixed(0)}%',
          ),
          subtitle: Text(
            '${DateFormat('dd/MM HH:mm').format(session.createdAt.toLocal())} · ${_strategyLabel(session.strategy)}',
          ),
          trailing: Text(
            session.state.wireValue,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    ],
  );
}

String _time(DateTime value) => DateFormat('HH:mm').format(value.toLocal());

int _roughlyMinutesFromNow(DateTime value, DateTime now) =>
    value.difference(now).inMinutes;

String _strategyLabel(ChargingStrategy strategy) => switch (strategy) {
  ChargingStrategy.targetSoc => 'Theo SOC mục tiêu',
  ChargingStrategy.deadline => 'Theo thời gian',
  ChargingStrategy.smartCombined => 'Kết hợp thông minh',
};

String _strategyDescription(ChargingStrategy strategy) => switch (strategy) {
  ChargingStrategy.targetSoc => 'Dùng ETA AI làm mốc dừng dự kiến.',
  ChargingStrategy.deadline => 'Ưu tiên đúng thời điểm dừng cứng.',
  ChargingStrategy.smartCombined => 'Dừng ở mốc sớm hơn giữa AI và deadline.',
};
