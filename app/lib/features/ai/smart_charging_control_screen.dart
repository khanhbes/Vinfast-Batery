import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_connection_notice.dart';
import '../../core/utils/app_error_formatter.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/debug_error_sheet.dart';
import '../../data/models/shelly_connection_state.dart';
import '../../data/models/smart_charging_session.dart';
import '../../data/services/charge_estimator.dart';
import '../../data/services/shelly_connection_coordinator.dart';
import '../auth/auth_providers.dart';
import '../achievements/achievements_screen.dart';
import '../achievements/controllers/achievements_controller.dart';
import '../achievements/models/achievement.dart';
import '../achievements/services/achievement_signals.dart';
import 'services/learning_flow.dart';
import '../achievements/widgets/achievement_unlock_ceremony.dart';
import '../achievements/widgets/achievements_teaser_card.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';
import 'controllers/smart_charging_controller.dart';
import 'smart_charge_history_screen.dart';
import 'widgets/active_charging_card_v2.dart';
import 'widgets/ai_charge_button.dart';
import 'widgets/charge_mode_switcher_v2.dart';
import 'widgets/command_progress_strip.dart';
import 'widgets/confirm_actual_soc_sheet.dart';
import 'widgets/edit_current_battery_sheet.dart';
import 'widgets/luxe_soc_dial.dart';
import 'widgets/soc_range_input.dart';
import '../../core/providers/appearance_provider.dart';
import '../../core/providers/entitlement_provider.dart';
import '../../data/models/entitlement.dart';
import '../premium/premium_gate.dart';
import '../../data/models/app_appearance.dart';
import 'widgets/edit_target_sheet.dart';
import 'widgets/prediction_card_v2.dart';
import 'widgets/recent_sessions_section_v2.dart';
import 'widgets/start_charge_confirmation_sheet.dart';
import 'widgets/stop_charging_confirmation_sheet.dart';
import 'widgets/timed_charging_section_v2.dart';
import '../../core/services/guide_registry.dart';

/// Sạc pin — luxe platinum/emerald workspace.
///
/// There is no BMS feed: the user enters the level read off the scooter
/// (platinum knob) and the level to charge to (emerald knob). Control
/// authority never comes from presentation: every start/stop still goes
/// through the controller's fresh backend checks.
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
  bool _initialNoticesScheduled = false;

  /// A relay command that just succeeded: shown as "đã xác minh" for a
  /// moment so the end of the wait is as clear as its start (QA 130).
  RelayCommandKind? _verified;
  Timer? _verifiedTimer;

  StreamSubscription<ShellyConnectionSnapshot>? _connectionEvents;

  @override
  void initState() {
    super.initState();
    args = SmartChargingControllerArgs(
      vehicleId: widget.vehicleId,
      currentSoc: widget.currentSoc,
    );
    WidgetsBinding.instance.addObserver(this);
    _noteConnection(ShellyConnectionCoordinator.shared.current);
    _connectionEvents = ShellyConnectionCoordinator.shared.states.listen(
      _noteConnection,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _consumeChargeTarget(ref.read(pendingChargeTargetSocProvider));
      final achievements = ref.read(achievementsControllerProvider.notifier);
      achievements.ingest(
        ref.read(smartChargingControllerProvider(args)).history,
      );
      achievements.sync();
    });
  }

  /// Target from the trip planner / BatteryBot: pre-fill only (Task 126).
  void _consumeChargeTarget(({String vehicleId, double targetSoc})? pending) {
    if (pending == null || pending.vehicleId != widget.vehicleId) return;
    ref.read(pendingChargeTargetSocProvider.notifier).state = null;
    // QA 135: during a target charge it is a new target for that charge.
    final running = ref.read(smartChargingControllerProvider(args)).session;
    if (running != null && !running.state.isTerminal && running.isTargetMode) {
      final controller = ref.read(
        smartChargingControllerProvider(args).notifier,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _editTarget(
          running.estimatedSoc ?? running.startSoc,
          running.targetSoc.round(),
          controller,
          suggested: pending.targetSoc.round(),
        );
      });
      return;
    }
    ref
        .read(smartChargingControllerProvider(args).notifier)
        .updateDraft(targetSoc: pending.targetSoc.clamp(1, 100).toDouble());
    if (!_aiMode) setState(() => _aiMode = true);
  }

  @override
  void didUpdateWidget(covariant SmartChargingControlScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // One controller per vehicle (Task 122): a new battery reading updates
    // the existing controller instead of creating a second polling instance.
    if (oldWidget.currentSoc != widget.currentSoc &&
        oldWidget.vehicleId == widget.vehicleId) {
      ref
          .read(smartChargingControllerProvider(args).notifier)
          .syncCurrentSoc(widget.currentSoc);
    }
  }

  @override
  void dispose() {
    _connectionEvents?.cancel();
    _verifiedTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Explore achievements for a verified Shelly link.
  void _noteConnection(ShellyConnectionSnapshot c) {
    if (c.isLinked && c.state == ShellyConnectionFlowState.connected) {
      AchievementSignals.instance.emit(AchievementEvents.shellyLinked);
    }
    if (c.serverBinding?.noLoadTestVerified == true ||
        c.capabilities?.noLoadTestVerified == true) {
      AchievementSignals.instance.emit(AchievementEvents.safetyVerified);
    }
  }

  void _openAchievements() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const AchievementsScreen()));

  /// Plays waiting unlock ceremonies while this screen is the visible one.
  void _celebrate() {
    if (!mounted ||
        !TickerMode.valuesOf(context).enabled ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    final ids = ref
        .read(achievementsControllerProvider.notifier)
        .takeCelebrations();
    if (ids.isEmpty) return;
    AchievementUnlockCeremony.show(context, [
      for (final d in achievementCatalog)
        if (ids.contains(d.id)) d,
    ], onOpenCollection: _openAchievements);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(smartChargingControllerProvider(args).notifier).refresh();
    }
  }

  void _openSetup(SmartChargingController controller) => Navigator.of(context)
      .push(
        MaterialPageRoute<void>(
          builder: (_) => const SmartChargerSetupHubScreen(),
        ),
      )
      .then((_) => controller.refresh(force: true));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smartChargingControllerProvider(args));
    final controller = ref.read(smartChargingControllerProvider(args).notifier);
    final reduced = MediaQuery.disableAnimationsOf(context);
    // Outgoing animated children keep the mode they were built with.
    final aiMode = _aiMode;

    ref.listen<({String vehicleId, double targetSoc})?>(
      pendingChargeTargetSocProvider,
      (_, next) => _consumeChargeTarget(next),
    );
    ref.listen<SmartChargingUiState>(
      smartChargingControllerProvider(args),
      (previous, next) => _showStateNotices(previous, next),
    );
    ref.listen<int>(currentTabProvider, (previous, next) {
      if (next == 1) {
        controller.refresh();
        WidgetsBinding.instance.addPostFrameCallback((_) => _celebrate());
      }
    });
    ref.listen<AchievementsState>(achievementsControllerProvider, (p, n) {
      if (n.pendingCelebrations.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _celebrate());
      }
    });
    if (!_initialNoticesScheduled) {
      _initialNoticesScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showStateNotices(null, state);
      });
    }

    return Theme(
      data: LuxeTheme.of(context),
      child: Scaffold(
        backgroundColor: LuxeColors.background,
        appBar: widget.embedded
            ? null
            : AppBar(
                title: const Text('Sạc pin'),
                backgroundColor: LuxeColors.background,
              ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const LuxeBackdrop(),
            SafeArea(
              child: RefreshIndicator(
                color: LuxeColors.emerald,
                backgroundColor: LuxeColors.raised,
                onRefresh: () => controller.refresh(force: true),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
                  children: [
                    StreamBuilder<ShellyConnectionSnapshot>(
                      stream: ShellyConnectionCoordinator.shared.states,
                      initialData: ShellyConnectionCoordinator.shared.current,
                      builder: (context, snapshot) => LuxeReveal(
                        child: _LuxeChargeHeader(
                          state: state,
                          connection: snapshot.data,
                          onSetup: () => _openSetup(controller),
                          settling: _verified != null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // A failed read when no charge runs: one notice with
                    // retry, the same as the app bar strip (QA 130).
                    if (state.gatewayError != null &&
                        !state.hasActiveSession &&
                        _commandKind(state) == null) ...[
                      LuxeConnectionNotice(
                        key: const ValueKey('charge-connection-notice'),
                        issue: _issueFor(state),
                        lastGoodAt:
                            state.connectionState.lastSuccessfulStatusAt ??
                            state.statusSyncedAt,
                        onRetry: () => controller.refresh(force: true),
                      ),
                      const SizedBox(height: 12),
                    ],
                    AnimatedSwitcher(
                      duration: reduced
                          ? Duration.zero
                          : const Duration(milliseconds: 280),
                      switchInCurve: LuxeMotion.enter,
                      child: switch ((_commandKind(state), _verified)) {
                        (final kind?, _) => Padding(
                          key: const ValueKey('command-in-flight'),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: CommandProgressStrip(kind: kind),
                        ),
                        (null, final done?) => Padding(
                          key: const ValueKey('command-verified'),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: CommandProgressStrip(
                            kind: done,
                            verified: true,
                          ),
                        ),
                        _ => const SizedBox.shrink(
                          key: ValueKey('command-idle'),
                        ),
                      },
                    ),
                    AnimatedSwitcher(
                      duration: reduced
                          ? Duration.zero
                          : const Duration(milliseconds: 320),
                      switchInCurve: LuxeMotion.enter,
                      child: state.hasActiveSession
                          ? _buildActiveCharging(state, controller)
                          : Column(
                              key: const ValueKey('plan-workspace'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                LuxeReveal(
                                  index: 1,
                                  child: KeyedSubtree(
                                    key: GuideRegistry.keyChargeMode,
                                    child: ChargeModeSwitcherV2(
                                      isAiMode: _aiMode,
                                      onChanged: (value) =>
                                          setState(() => _aiMode = value),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                AnimatedSwitcher(
                                  duration: reduced
                                      ? Duration.zero
                                      : const Duration(milliseconds: 260),
                                  switchInCurve: LuxeMotion.enter,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position: Tween<Offset>(
                                            begin: Offset(
                                              child.key ==
                                                      const ValueKey('ai-mode')
                                                  ? -0.04
                                                  : 0.04,
                                              0,
                                            ),
                                            end: Offset.zero,
                                          ).animate(animation),
                                          child: child,
                                        ),
                                      ),
                                  child:
                                      StreamBuilder<ShellyConnectionSnapshot>(
                                        key: ValueKey(
                                          aiMode ? 'ai-mode' : 'timed-mode',
                                        ),
                                        stream: ShellyConnectionCoordinator
                                            .shared
                                            .states,
                                        initialData: ShellyConnectionCoordinator
                                            .shared
                                            .current,
                                        builder: (context, snapshot) {
                                          final connection =
                                              snapshot.data ??
                                              ShellyConnectionCoordinator
                                                  .shared
                                                  .current;
                                          return aiMode
                                              ? _buildAiPlan(
                                                  context,
                                                  state,
                                                  controller,
                                                  connection,
                                                )
                                              : _buildTimed(
                                                  state,
                                                  controller,
                                                  connection,
                                                );
                                        },
                                      ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 32),
                    LuxeReveal(
                      index: 4,
                      child: RecentSessionsSectionV2(
                        sessions: state.history,
                        syncedAt: state.historySyncedAt,
                        onViewAll: () {
                          AchievementSignals.instance.emit(
                            AchievementEvents.historyViewed,
                          );
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => Consumer(
                                builder: (context, routeRef, _) =>
                                    SmartChargeHistoryScreen(
                                      controller: controller,
                                      ownerUid: routeRef.watch(
                                        currentUidProvider,
                                      ),
                                      initialItems: state.history,
                                      onStartCharging: () =>
                                          Navigator.of(context).maybePop(),
                                    ),
                              ),
                            ),
                          );
                        },
                        onOpen: (session) => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          backgroundColor: Colors.transparent,
                          barrierColor: luxeSheetBarrier,
                          builder: (_) => FractionallySizedBox(
                            heightFactor: .96,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(28),
                              ),
                              child: Consumer(
                                builder: (context, routeRef, _) =>
                                    SmartChargeSessionDetailScreen(
                                      controller: controller,
                                      ownerUid: routeRef.watch(
                                        currentUidProvider,
                                      ),
                                      session: session,
                                    ),
                              ),
                            ),
                          ),
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

  // ── AI plan: dial → presets → plan → CTA → journey ──
  Widget _buildAiPlan(
    BuildContext context,
    SmartChargingUiState state,
    SmartChargingController controller,
    ShellyConnectionSnapshot connection,
  ) {
    final draft = state.draft;
    final busy =
        state.phase == SmartChargingViewPhase.loading ||
        state.phase == SmartChargingViewPhase.starting;
    final preview = state.preview;
    // QA 135: charging to a % with automatic cut-off is Pro; Free keeps the
    // forecast and starts a verified timed charge of that length instead.
    final targetAllowed = ref.watch(
      entitlementProvider.select(
        (plan) => plan.allows(PremiumFeature.targetCharging),
      ),
    );
    final targetLocked =
        !targetAllowed && preview != null && preview.isTargetMode;
    final canStart =
        !targetLocked &&
        preview?.isDisplayOnly == false &&
        (preview?.aiChargeEligible == true ||
            preview?.isPhysicsFallback == true) &&
        state.capabilities.readyForControl &&
        _sharedConnectionReady(connection) &&
        state.connectionState.shellyReachable;
    final full = draft.currentSoc >= 100;
    final currentTarget = draft.targetSoc.clamp(
      (draft.currentSoc.ceil() + 1).clamp(1, 99).toDouble(),
      100.0,
    );
    // Task 122: a display-only forecast never energizes on its own, but it
    // can pre-fill the verified timed start (slide-to-confirm, device timer).
    final timedReady =
        _sharedConnectionReady(connection) &&
        state.capabilities.readyForControl &&
        state.capabilities.canManualOn &&
        !busy &&
        state.phase != SmartChargingViewPhase.stopping;
    final forecastDuration = preview == null
        ? null
        : Duration(
            minutes: preview.predictedMinutes.clamp(
              1,
              ChargeEstimator.maxMinutes,
            ),
          );
    final timedFromForecast =
        preview != null &&
        !canStart &&
        (preview.isDisplayOnly || targetLocked) &&
        timedReady;
    final powerSource = controller.lastEstimatePowerSource;
    final powerW = controller.lastEstimatePowerW;
    final String label;
    final String? note;
    if (preview == null) {
      label = 'DỰ ĐOÁN THỜI GIAN SẠC';
      note = null;
    } else if (canStart && preview.isTargetMode) {
      label = 'SẠC ĐẾN ${currentTarget.round()}%';
      final ceiling = preview.safetyCeilingAt;
      note = ceiling == null
          ? 'Máy chủ tự ngắt khi ước tính đạt ${currentTarget.round()}%'
          : 'Máy chủ tự ngắt khi ước tính đạt ${currentTarget.round()}% · '
                'Shelly tự tắt muộn nhất ${formatClock(ceiling)}';
    } else if (canStart) {
      label = 'SẠC THEO DỰ ĐOÁN';
      note = null;
    } else if (timedFromForecast) {
      label =
          'SẠC HẸN GIỜ ${formatChargeDuration(forecastDuration!).toUpperCase()}';
      note = targetLocked
          ? 'Sạc đến % tự ngắt thuộc gói Pro. Gói Free sạc hẹn giờ đúng '
                'thời gian dự đoán, Shelly tự ngắt.'
          : powerSource == null || powerW == null
          ? 'Ước tính tham khảo · Shelly tự ngắt theo hẹn giờ'
          : 'Ước tính theo ${powerSource.label} (khoảng ${powerW.round()} W) · '
                'Shelly tự ngắt theo hẹn giờ';
    } else {
      label = 'DỰ ĐOÁN LẠI';
      note = preview.isDisplayOnly
          ? 'Dự đoán tham khảo · Kết nối Shelly để sạc hẹn giờ theo dự đoán'
          : (preview.aiChargeEligible || preview.isPhysicsFallback)
          ? 'Hoàn tất cài đặt ổ sạc'
          : 'Chưa khả dụng';
    }

    final pending = controller.pendingActualSoc;
    return Column(
      key: const ValueKey('ai-mode-v2'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending != null) ...[
          _PendingActualSocCard(
            session: pending,
            onTap: () => _askActualSoc(pending),
          ),
          const SizedBox(height: 14),
        ],
        LuxeReveal(
          index: 2,
          child: LuxeGlass(
            key: GuideRegistry.keyChargeSocInput,
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('NHẬP MỨC PIN', style: LuxeText.eyebrow),
                ),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    'Kéo núm tối theo số pin trên xe, núm sáng tới mức muốn sạc.',
                    style: LuxeText.caption,
                  ),
                ),
                const SizedBox(height: 6),
                // QA 131: the owner's Charge layout (Cài đặt → Giao diện).
                if (ref.watch(effectiveAppearanceProvider).charge ==
                    ChargeStyle.dial)
                  LuxeSocDial(
                    key: const ValueKey('target-battery-selector'),
                    current: draft.currentSoc,
                    target: currentTarget,
                    enabled: !busy,
                    etaLabel: preview == null
                        ? null
                        : _shortDuration(preview.predictedMinutes),
                    onCurrentChanged: (value) =>
                        controller.updateDraft(currentSoc: value),
                    onTargetChanged: (value) =>
                        controller.updateDraft(targetSoc: value),
                    onEditCurrent: () => EditCurrentBatterySheet.show(
                      context,
                      initialPercent: draft.currentSoc,
                      onSave: (value) =>
                          controller.updateDraft(currentSoc: value),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                    child: SocRangeInput(
                      key: const ValueKey('target-battery-selector'),
                      style: ref.watch(effectiveAppearanceProvider).charge,
                      current: draft.currentSoc,
                      target: currentTarget,
                      enabled: !busy,
                      etaLabel: preview == null
                          ? null
                          : _shortDuration(preview.predictedMinutes),
                      onCurrentChanged: (value) =>
                          controller.updateDraft(currentSoc: value),
                      onTargetChanged: (value) =>
                          controller.updateDraft(targetSoc: value),
                      onEditCurrent: () => EditCurrentBatterySheet.show(
                        context,
                        initialPercent: draft.currentSoc,
                        onSave: (value) =>
                            controller.updateDraft(currentSoc: value),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                _TargetPresets(
                  target: currentTarget,
                  enabled: !busy && !full,
                  minimum: draft.currentSoc,
                  onSelected: (value) =>
                      controller.updateDraft(targetSoc: value),
                ),
              ],
            ),
          ),
        ),
        LuxeFold(
          duration: const Duration(milliseconds: 360),
          child: preview == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: LuxeReveal(
                    child: PredictionCardV2(
                      key: const ValueKey('plan-preview'),
                      durationMinutes: preview.predictedMinutes,
                      stopTime: _time(preview.effectiveStopAt),
                      fromSoc: draft.currentSoc.round(),
                      toSoc: currentTarget.round(),
                      personalizationLabel: preview.personalizationLabel,
                      warnings: preview.warnings,
                      rangeLabel: _rangeLabel(preview),
                      stopLine: preview.isTargetMode
                          ? 'Đạt khoảng ${currentTarget.round()}% lúc '
                                '${_time(preview.effectiveStopAt)} · máy chủ tự ngắt'
                          : null,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 18),
        LuxeReveal(
          index: 3,
          key: GuideRegistry.keyChargeStart,
          child: AIChargeButton(
            key: preview == null
                ? const ValueKey('create-plan-button')
                : const ValueKey('confirm-plan-button'),
            label: label,
            emphasis: canStart,
            enabled: !busy && !full,
            busy: state.phase == SmartChargingViewPhase.loading,
            onPressed: preview == null
                ? controller.createPreview
                : canStart
                ? () => _aiStart(state, controller)
                : timedFromForecast
                ? () => _startTimedCharge(state, controller, forecastDuration!)
                : controller.createPreview,
          ),
        ),
        if (targetLocked)
          Center(
            child: TextButton.icon(
              key: const ValueKey('target-premium-button'),
              onPressed: () => PremiumGate.showUpgrade(
                context,
                PremiumFeature.targetCharging,
              ),
              icon: const Icon(Icons.workspace_premium_rounded, size: 18),
              label: const Text('Mở Sạc đến % tự ngắt (Pro)'),
            ),
          ),
        if (timedFromForecast)
          Center(
            child: TextButton.icon(
              key: const ValueKey('re-forecast-button'),
              onPressed: busy ? null : controller.createPreview,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Dự đoán lại'),
            ),
          ),
        if (note != null || full) ...[
          const SizedBox(height: 10),
          Text(
            full
                ? 'Pin đang đầy. Nhập lại mức pin thực tế trên xe để lên kế hoạch.'
                : note!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: LuxeColors.champagne,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 18),
        LuxeReveal(
          index: 4,
          child: Consumer(
            builder: (context, ref, _) => AchievementsTeaserCard(
              state: ref.watch(achievementsControllerProvider),
              onTap: _openAchievements,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimed(
    SmartChargingUiState state,
    SmartChargingController controller,
    ShellyConnectionSnapshot connection,
  ) {
    final ready =
        _sharedConnectionReady(connection) &&
        state.capabilities.readyForControl &&
        state.capabilities.canManualOn &&
        state.phase != SmartChargingViewPhase.starting &&
        state.phase != SmartChargingViewPhase.stopping &&
        state.phase != SmartChargingViewPhase.loading;
    return TimedChargingSectionV2(
      key: const ValueKey('timed-mode'),
      disabledReason:
          connection.controlBlockedMessage ??
          state.capabilities.controlBlockedMessage ??
          (!_sharedConnectionReady(connection)
              ? 'Hãy kết nối Shelly qua Thiết lập trước khi bật sạc.'
              : null),
      readyForControl: ready,
      onStart: (duration) => _startTimedCharge(state, controller, duration),
      onOff: () => _emergencyOff(controller),
      onOpenSetup: () => _openSetup(controller),
    );
  }

  void _maybeFlashVerified(
    SmartChargingUiState? previous,
    SmartChargingUiState next,
  ) {
    final was = previous?.phase;
    final ok = next.actionError == null;
    RelayCommandKind? done;
    if (was == SmartChargingViewPhase.starting &&
        next.phase != SmartChargingViewPhase.starting &&
        ok &&
        next.hasActiveSession) {
      done = RelayCommandKind.on;
    } else if (was == SmartChargingViewPhase.stopping &&
        next.phase != SmartChargingViewPhase.stopping &&
        ok &&
        !next.hasActiveSession) {
      done = RelayCommandKind.off;
    }
    if (done == null || !mounted) return;
    setState(() => _verified = done);
    _verifiedTimer?.cancel();
    _verifiedTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _verified = null);
    });
  }

  /// Estimated % when a timed charge ends, from the learned Wh per 1 % and
  /// charging power (same model as the Charge tab); current % if unknown.
  int _timedEndSoc(SmartChargingUiState state, Duration duration) {
    final current = state.draft.currentSoc;
    final learned = ref
        .read(learnedModelsProvider(widget.vehicleId))
        .valueOrNull;
    final capacity = state.draft.estimatedCapacityWh;
    final whPerPct =
        learned?.whPerPct ??
        (capacity > 0 ? capacity / 100 / ChargeEstimator.efficiency : null);
    final powerW = learned?.powerW ?? state.preferences?.chargePowerW;
    if (whPerPct == null || whPerPct <= 0 || powerW == null || powerW <= 0) {
      return current.round();
    }
    final gained = powerW * duration.inSeconds / 3600 / whPerPct;
    return math.min(100.0, current + gained).round();
  }

  ConnectionIssue _issueFor(SmartChargingUiState state) {
    final link = state.connectionState;
    if (!link.internetAvailable) return ConnectionIssue.internet;
    if (!link.shellyReachable) return ConnectionIssue.charger;
    return ConnectionIssue.server;
  }

  RelayCommandKind? _commandKind(SmartChargingUiState state) =>
      switch (state.phase) {
        SmartChargingViewPhase.starting => RelayCommandKind.on,
        SmartChargingViewPhase.stopping =>
          state.session?.lastError == offPendingReadbackCode
              ? RelayCommandKind.offAwaitingReadback
              : RelayCommandKind.off,
        _ => null,
      };

  Widget _buildActiveCharging(
    SmartChargingUiState state,
    SmartChargingController controller,
  ) {
    final session = state.session;
    final status = state.chargerStatus;
    final estimate = state.remainingEstimate;
    final targetMode = session?.isTargetMode == true;
    // Count the hardware timer down between polls (Task 125). A target
    // charge ends at the estimate; its Shelly timer is only the ceiling.
    final remaining = state.displayRemaining ?? Duration.zero;
    final startSoc =
        session?.startSoc.round() ?? state.draft.currentSoc.round();
    final targetSoc =
        session?.targetSoc.round() ?? state.draft.targetSoc.round();
    final estimatedSoc = session?.estimatedSoc ?? startSoc.toDouble();
    // "Stops at" follows the same source as the countdown: the hardware
    // timer when Shelly reports it, otherwise the session plan (Task 122).
    final timer = status?.timerRemainingAt(state.now);
    final stopAt = targetMode
        ? state.now.add(remaining)
        : timer != null && timer > Duration.zero
        ? state.now.add(timer)
        : session?.effectiveStopAt ?? state.now;
    final ceilingAt = timer != null && timer > Duration.zero
        ? state.now.add(timer)
        : session?.effectiveStopAt;
    final String? estimateNote;
    if (targetMode) {
      estimateNote =
          'Máy chủ tự ngắt khi ước tính đạt $targetSoc%'
          '${ceilingAt == null ? '' : ' · Shelly tự tắt muộn nhất ${formatClock(ceilingAt)}'}';
    } else {
      estimateNote = estimate == null || targetSoc <= estimatedSoc.round()
          ? null
          : 'Đạt $targetSoc% sau khoảng ${formatChargeDuration(estimate.duration)} '
                '· khoảng ${formatClock(estimate.finishAt)} '
                '(${estimate.powerW.round()} W đo thực tế)';
    }

    final card = ActiveChargingCardV2(
      key: const ValueKey('active-session-v2'),
      style: ref.watch(effectiveAppearanceProvider).charge,
      currentPercent: estimatedSoc,
      targetPercent: targetSoc.toDouble(),
      remaining: remaining,
      completionTime: _time(stopAt),
      countdownLabel: targetMode
          ? (estimate == null
                ? 'Đạt $targetSoc% theo kế hoạch · khoảng'
                : 'Đạt $targetSoc% sau · khoảng')
          : 'Shelly tự ngắt sau · lúc',
      socCaption: targetMode ? null : 'ước tính · sạc hẹn giờ',
      sessionEnergyWh: session?.energyUsedWh ?? 0,
      powerW: status?.powerW ?? 0,
      voltageV: status?.voltageV ?? 0,
      currentA: status?.currentA ?? 0,
      temperatureC: status?.temperatureC,
      timerVerified:
          session?.timerVerified == true || status?.timerRemaining != null,
      estimatedSoc: estimatedSoc,
      isStopping: state.phase == SmartChargingViewPhase.stopping,
      isStarting: state.phase == SmartChargingViewPhase.starting,
      estimateNote: estimateNote,
      stopAwaitingReadback:
          state.phase == SmartChargingViewPhase.stopping &&
          session?.lastError == offPendingReadbackCode,
      onStop: () => _stopWithConfirmation(state, controller),
    );
    // QA 135: a target charge can move its target (Pro).
    final canEdit =
        targetMode &&
        session != null &&
        !session.state.isTerminal &&
        state.phase != SmartChargingViewPhase.stopping &&
        state.phase != SmartChargingViewPhase.starting;
    final withEdit = !canEdit
        ? card
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              card,
              const SizedBox(height: 10),
              PremiumLocked(
                feature: PremiumFeature.targetEdit,
                tagAlignment: AlignmentDirectional.centerEnd,
                tagPadding: const EdgeInsetsDirectional.only(end: 8),
                child: OutlinedButton.icon(
                  key: const ValueKey('edit-target-button'),
                  onPressed: () =>
                      _editTarget(estimatedSoc, targetSoc, controller),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text('Đổi mục tiêu ($targetSoc%)'),
                ),
              ),
            ],
          );
    final lost = state.linkLostSince;
    if (lost == null) return withEdit;
    final minutes = state.now.difference(lost).inMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeConnectionNotice(
          key: const ValueKey('charge-link-lost'),
          issue: ConnectionIssue.chargerWhileCharging,
          title:
              'Tạm mất liên lạc với ổ sạc${minutes >= 1 ? ' · $minutes phút' : ''}',
          detail:
              'Xe vẫn sạc theo hẹn giờ trên ổ, ổ tự tắt muộn nhất '
              '${formatClock(ceilingAt ?? session?.effectiveStopAt ?? state.now)}. '
              'Nếu kéo dài, kiểm tra Wi-Fi nhà và đèn trên ổ.',
          lastGoodAt: lost,
          onRetry: () => controller.refresh(force: true),
        ),
        const SizedBox(height: 12),
        withEdit,
      ],
    );
  }

  Future<void> _editTarget(
    double estimatedSoc,
    int targetSoc,
    SmartChargingController controller, {
    int? suggested,
  }) async {
    if (!PremiumGate.check(context, ref, PremiumFeature.targetEdit)) return;
    final changed = await EditTargetSheet.show(
      context,
      currentSoc: estimatedSoc,
      currentTarget: targetSoc.toDouble(),
      initialTarget: suggested,
      onSubmit: controller.updateTarget,
    );
    if (changed == true && mounted) {
      unawaited(controller.refresh(force: true));
    }
  }

  /// A charge this screen watched just ended: ask for the scooter's % while
  /// the user is still next to it (Task 126).
  void _maybeAskActualSoc(
    SmartChargingUiState? previous,
    SmartChargingUiState next,
  ) {
    final running = previous?.session;
    if (running == null || running.state.isTerminal) return;
    SmartChargingSession? ended;
    if (next.session?.sessionId == running.sessionId) {
      ended = next.session;
    } else {
      for (final item in next.history) {
        if (item.sessionId == running.sessionId) ended = item;
      }
    }
    if (ended == null || !ended.state.isTerminal) return;
    final controller = ref.read(smartChargingControllerProvider(args).notifier);
    if (!controller.shouldAskActualSoc(ended)) return;
    controller.markActualSocAsked(ended.sessionId);
    final session = ended;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_askActualSoc(session));
    });
  }

  Future<void> _askActualSoc(SmartChargingSession session) async {
    final controller = ref.read(smartChargingControllerProvider(args).notifier);
    controller.markActualSocAsked(session.sessionId);
    // The sheet saves and shows progress; a failure keeps it open with the
    // numbers (QA 135).
    final reading = await ConfirmActualSocSheet.show(
      context,
      estimatedSoc: session.estimatedSoc,
      startSoc: session.startSoc,
      onSave: (reading) async {
        try {
          await controller.confirmActualEndSoc(
            session,
            reading.soc,
            odoKm: reading.odoKm,
          );
          return null;
        } catch (error) {
          return AppErrorFormatter.format(error);
        }
      },
    );
    if (reading == null || !mounted) return;
    AppPopup.showSuccess(
      'Đã lưu ${reading.soc.round()}%',
      detail: 'Đã thêm vào dữ liệu học; app báo khi đủ để huấn luyện.',
    );
    unawaited(TrainingReadiness.refresh(session.vehicleId));
  }

  void _showStateNotices(
    SmartChargingUiState? previous,
    SmartChargingUiState next,
  ) {
    _maybeAskActualSoc(previous, next);
    _maybeFlashVerified(previous, next);
    // Background refresh/sync failures belong in the non-blocking connection
    // status strip. Only explicit action errors and urgent safety warnings
    // surface above content.
    if (next.actionError != null && previous?.actionError != next.actionError) {
      _showFloatingDetail('Thao tác chưa hoàn tất', next.actionError!);
    }
    if (next.safetyWarning != null &&
        previous?.safetyWarning != next.safetyWarning) {
      _showFloatingDetail(
        'Cảnh báo an toàn sạc',
        next.safetyWarning!,
        persistent: true,
      );
    }

    // Achievements: fold finished sessions into the ledger (no extra reads)
    // and note the first AI plan.
    if (previous == null || !identical(previous.history, next.history)) {
      ref.read(achievementsControllerProvider.notifier).ingest(next.history);
    }
    if (previous?.preview == null && next.preview != null) {
      AchievementSignals.instance.emit(AchievementEvents.aiPreview);
    }
  }

  void _showFloatingDetail(
    String title,
    String detail, {
    bool persistent = false,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppPopup.showWarning(
        title,
        detail: detail,
        actionLabel: 'CHI TIẾT',
        persistent: persistent,
        action: kDebugMode
            ? () => DebugErrorSheet.show(
                context,
                error: detail,
                source: 'SmartCharge',
              )
            : null,
      );
    });
  }

  Future<void> _startTimedCharge(
    SmartChargingUiState state,
    SmartChargingController controller,
    Duration duration,
  ) async {
    // state.now only ticks during a session; the sheet needs the wall
    // clock (QA 128: "Tự ngắt lúc 02:53" shown at 02:40 for 30 minutes).
    final stopAt = DateTime.now().add(duration);
    final endSoc = _timedEndSoc(state, duration);
    final confirmed = await StartChargeConfirmationSheet.show(
      context,
      currentSoc: state.draft.currentSoc.round(),
      // A timed charge has no target: show where the battery should be when
      // the timer ends (QA 130 showed "79% → 100%" for 30 minutes).
      targetSoc: endSoc,
      estimatedMinutes: duration.inMinutes,
      stopTime: _time(stopAt),
      isAiMode: false,
    );
    if (confirmed != true || !mounted) return;
    // The link may change while the confirmation sheet is open. Presentation
    // never grants authority; the repository still performs fresh backend checks.
    if (!_sharedConnectionReady(ShellyConnectionCoordinator.shared.current)) {
      AppPopup.showWarning(
        'Kết nối đã thay đổi. Hãy kiểm tra Shelly trước khi bật sạc.',
      );
      return;
    }

    final ok = await controller.manualOn(
      duration,
      targetSoc: endSoc.toDouble(),
    );
    if (!mounted) return;
    if (ok) {
      AppPopup.showSuccess(
        'Đã bắt đầu sạc',
        detail: 'Shelly sẽ tự ngắt sau ${_duration(duration.inMinutes)}.',
      );
    }
  }

  bool _sharedConnectionReady(ShellyConnectionSnapshot connection) =>
      connection.isLinked &&
      connection.state == ShellyConnectionFlowState.connected &&
      !connection.controlUncertain &&
      // Cached or grace-period readbacks are display-only, never control.
      !connection.syncDelayed &&
      !connection.fromCache &&
      connection.status?.online == true &&
      connection.status?.relay == false;

  /// "1 giờ 50 – 2 giờ 20" when the server sent an uncertainty band.
  String? _rangeLabel(SmartChargingPlanPreview preview) {
    final low = preview.estimateLowSeconds;
    final high = preview.estimateHighSeconds;
    if (low == null || high == null || high <= low) return null;
    return '${formatChargeDuration(Duration(seconds: low))} – '
        '${formatChargeDuration(Duration(seconds: high))}';
  }

  Future<void> _aiStart(
    SmartChargingUiState state,
    SmartChargingController controller,
  ) async {
    final preview = state.preview;
    if (preview == null) return;

    final ceiling = preview.isTargetMode ? preview.safetyCeilingAt : null;
    final confirmed = await StartChargeConfirmationSheet.show(
      context,
      currentSoc: state.draft.currentSoc.round(),
      targetSoc: state.draft.targetSoc.round(),
      estimatedMinutes: preview.predictedMinutes,
      stopTime: _time(preview.effectiveStopAt),
      isAiMode: true,
      personalizationLabel: preview.personalizationLabel,
      safetyCeiling: ceiling == null ? null : formatClock(ceiling),
    );

    if (confirmed != true) return;
    final ok = await controller.start(confirmed: true);
    if (ok) {
      AppPopup.showSuccess(
        'Đang sạc',
        detail: preview.isTargetMode
            ? 'Tự ngắt khi đạt khoảng ${state.draft.targetSoc.round()}% '
                  '(dự kiến ${_time(preview.effectiveStopAt)})'
            : 'Tự động tắt lúc ${_time(preview.effectiveStopAt)}',
      );
    } else {
      // The plan may have ended since the app last asked (QA 135): the
      // server refused with premiumRequired, so explain instead of failing.
      await ref.read(entitlementProvider.notifier).refresh();
      if (!mounted) return;
      if (preview.isTargetMode &&
          !ref
              .read(entitlementProvider)
              .allows(PremiumFeature.targetCharging)) {
        PremiumGate.showUpgrade(context, PremiumFeature.targetCharging);
        return;
      }
      AppPopup.showError('Không thể bật sạc', userInitiated: true);
    }
  }

  Future<void> _stopWithConfirmation(
    SmartChargingUiState state,
    SmartChargingController controller,
  ) async {
    final session = state.session;
    // The card's own countdown (QA 129: in target mode this showed the
    // Shelly ceiling, ~×1.5 + 20 min, instead of the time to the target).
    final remaining = state.displayRemaining ?? Duration.zero;
    final decision = await showStopChargingConfirmationSheet(
      context,
      currentSoc:
          session?.estimatedSoc ?? session?.startSoc ?? state.draft.currentSoc,
      targetSoc: session?.targetSoc ?? state.draft.targetSoc,
      remaining: remaining,
      targetMode: session?.isTargetMode == true,
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
        userInitiated: true,
      );
    }
  }
}

/// Status capsule: breathing dot, the shared Shelly connection label and
/// realtime metrics, setup shortcut while not ready, and the clock.
class _LuxeChargeHeader extends StatefulWidget {
  const _LuxeChargeHeader({
    required this.state,
    required this.onSetup,
    this.connection,
    this.settling = false,
  });
  final SmartChargingUiState state;

  /// A command just finished: readiness is being re-read, not a setup
  /// problem (QA 130: "Thiết lập" flashed right after a verified OFF).
  final bool settling;
  final VoidCallback onSetup;
  final ShellyConnectionSnapshot? connection;

  @override
  State<_LuxeChargeHeader> createState() => _LuxeChargeHeaderState();
}

class _LuxeChargeHeaderState extends State<_LuxeChargeHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  // The dot breathes only while the relay is verified ON (Task 125).
  void _syncPulse() {
    final charging = widget.state.chargerStatus?.relay == true;
    if (MediaQuery.disableAnimationsOf(context) || !charging) {
      _pulse
        ..stop()
        ..value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _LuxeChargeHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.chargerStatus?.relay !=
        widget.state.chargerStatus?.relay) {
      _syncPulse();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connection = widget.connection;
    // A transport response without a verified binding is not enrollment:
    // use exactly the same label as Settings and Setup.
    final connected =
        connection?.state == ShellyConnectionFlowState.connected &&
        connection?.controlUncertain != true;
    final dotColor = connected ? LuxeColors.emerald : LuxeColors.champagne;
    final statusText = connection?.connectionLabel ?? 'Chưa kết nối Shelly';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0x12FFFFFF), Color(0x05FFFFFF)],
        ),
        border: Border.all(color: LuxeColors.hairline),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 22,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => CustomPaint(
                painter: _PulseDotPainter(
                  color: dotColor,
                  t: _pulse.value,
                  animate: _pulse.isAnimating,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  statusText,
                  style: const TextStyle(
                    color: LuxeColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // Same realtime readout as Settings/BatteryBot (Task108).
                if (connection?.metricsLine != null)
                  Text(
                    connection!.metricsLine!,
                    key: const ValueKey('shelly-metrics-line'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: LuxeColors.muted,
                      fontSize: 12.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
          // While a session runs, "not ready for another ON" is expected,
          // not a setup problem (QA 128).
          // Not for a transient outage either: the connection notice below
          // offers "Thử lại", which is what helps then (QA 130).
          if (!widget.state.capabilities.readyForControl &&
              !widget.state.hasActiveSession &&
              widget.state.gatewayError == null &&
              !widget.settling) ...[
            const SizedBox(width: 6),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onSetup();
                },
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  // 48 dp touch target (Task 125); the pill stays visually
                  // compact through its padding.
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: LuxeColors.champagne.withValues(alpha: 0.5),
                    ),
                    color: LuxeColors.champagne.withValues(alpha: 0.08),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 14,
                        color: LuxeColors.champagne,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Thiết lập',
                        style: TextStyle(
                          color: LuxeColors.champagne,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          // The read time is in the metrics line; a second, unlabeled
          // clock here froze while idle (02:23 next to a 02:31 read, QA 128).
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _PulseDotPainter extends CustomPainter {
  _PulseDotPainter({
    required this.color,
    required this.t,
    required this.animate,
  });
  final Color color;
  final double t;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    if (animate) {
      canvas.drawCircle(
        c,
        4 + 7 * Curves.easeOut.transform(t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: 0.6 * (1 - t)),
      );
    }
    canvas.drawCircle(
      c,
      4.5,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(c, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PulseDotPainter old) =>
      old.t != t || old.color != color || old.animate != animate;
}

/// Quick targets: 80% (recommended), 90%, 100%.
class _TargetPresets extends StatelessWidget {
  const _TargetPresets({
    required this.target,
    required this.minimum,
    required this.enabled,
    required this.onSelected,
  });

  final double target;
  final double minimum;
  final bool enabled;
  final ValueChanged<double> onSelected;

  static const _presets = [
    (value: 80.0, title: 'Bảo vệ pin', recommended: true),
    (value: 90.0, title: 'Cân bằng', recommended: false),
    (value: 100.0, title: 'Đầy pin', recommended: false),
  ];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < _presets.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: _tile(_presets[i])),
      ],
    ],
  );

  Widget _tile(({double value, String title, bool recommended}) p) {
    final selected = target.round() == p.value.round();
    final available = enabled && p.value > minimum;
    return Semantics(
      button: true,
      selected: selected,
      enabled: available,
      child: Opacity(
        opacity: available ? 1 : 0.4,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            splashColor: const Color(0x1434D399),
            onTap: available
                ? () {
                    HapticFeedback.selectionClick();
                    onSelected(p.value);
                  }
                : null,
            child: LuxeGlass(
              selected: selected,
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${p.value.round()}%',
                      style: TextStyle(
                        color: selected ? LuxeColors.emerald : LuxeColors.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w300,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      p.title,
                      style: const TextStyle(
                        color: LuxeColors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  if (p.recommended) ...[
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Khuyên dùng',
                        style: TextStyle(
                          color: LuxeColors.platinum,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _time(DateTime value) => DateFormat('HH:mm').format(value.toLocal());
String _duration(int minutes) =>
    formatChargeDuration(Duration(minutes: math.max(0, minutes)));

/// Compact ETA for the dial pill: "khoảng 1g10" / "khoảng 45 phút" (QA 137
/// rule, QA 139: no "≈").
String _shortDuration(int minutes) {
  final m = math.max(0, minutes);
  if (m < 60) return 'khoảng $m phút';
  return 'khoảng ${formatChargeDurationShort(Duration(minutes: m))}';
}

/// "Lần sạc lúc 21:40 chưa có % thực tế" — one tap opens the sheet.
class _PendingActualSocCard extends StatelessWidget {
  const _PendingActualSocCard({required this.session, required this.onTap});

  final SmartChargingSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ended = session.stoppedAt ?? session.updatedAt;
    final estimate = session.estimatedSoc?.round();
    return Semantics(
      button: true,
      label: 'Nhập phần trăm pin thực tế của lần sạc lúc ${formatClock(ended)}',
      child: LuxeGlass(
        key: const ValueKey('pending-actual-soc'),
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.speed_rounded,
                    color: LuxeColors.champagne,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lần sạc lúc ${formatClock(ended)} chưa có % thực tế',
                          style: LuxeText.item,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          estimate == null
                              ? 'Nhập số trên đồng hồ xe để app học.'
                              : 'Ước tính $estimate%. Nhập số trên đồng hồ xe để app học.',
                          style: LuxeText.caption,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: LuxeColors.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
