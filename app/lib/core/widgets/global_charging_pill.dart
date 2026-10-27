import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/active_charging_session_coordinator.dart';
import '../../features/ai/controllers/smart_charging_controller.dart';
import '../theme/luxe_theme.dart';
import 'luxe_kit.dart';
import 'luxe_settings.dart';

/// One rebuild per second while a synced session is shown, so its timer
/// counts down between snapshots (Task 125). Disposed with the pill.
final _pillTickProvider = StreamProvider.autoDispose<int>(
  (ref) => Stream.periodic(const Duration(seconds: 1), (tick) => tick),
);

/// Persistent account-scoped indicator for an active charging session.
class GlobalChargingPill extends ConsumerWidget {
  const GlobalChargingPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    final coordinator = ref.watch(activeChargingSessionProvider);
    if (coordinator.sessions.isNotEmpty) ref.watch(_pillTickProvider);
    if (vehicleId.isEmpty) {
      // A fresh device can receive the account-scoped session before its
      // vehicle picker has restored a selection. Keep the session visible
      // instead of silently hiding cross-device charging.
      if (coordinator.sessions.length == 1) {
        final remote = coordinator.sessions.single;
        return _pill(
          context,
          ref,
          remote.vehicleId,
          remote.targetSoc,
          remote.remaining,
          remote.vehicleId,
          synced: true,
          stale: remote.isStale,
        );
      }
      if (coordinator.sessions.length > 1) {
        return _multiPill(context, ref, coordinator.sessions);
      }
      return const SizedBox.shrink();
    }
    final vehicle = ref.watch(vehicleProvider(vehicleId));
    return vehicle.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (value) {
        if (value == null) return const SizedBox.shrink();
        final args = SmartChargingControllerArgs(
          vehicleId: vehicleId,
          currentSoc: value.currentBattery.toDouble(),
        );
        final state = ref.watch(smartChargingControllerProvider(args));
        if (state.hasActiveSession) {
          // The Charge tab already shows this session in full; the pill on
          // top of it hid the Shelly card (Task 127).
          if (ref.watch(currentTabProvider) == 1) {
            return const SizedBox.shrink();
          }
          return _pill(
            context,
            ref,
            vehicleId,
            state.session?.targetSoc,
            state.displayRemaining,
            value.vehicleName,
            synced: false,
          );
        }
        final remote = coordinator.forVehicle(vehicleId);
        if (remote != null) {
          return _pill(
            context,
            ref,
            vehicleId,
            remote.targetSoc,
            remote.remaining,
            value.vehicleName,
            synced: true,
            stale: remote.isStale,
          );
        }
        final others = coordinator.sessions
            .where((item) => item.vehicleId != vehicleId)
            .toList(growable: false);
        if (others.isEmpty) return const SizedBox.shrink();
        if (others.length == 1) {
          final other = others.first;
          final name =
              ref
                  .watch(vehicleProvider(other.vehicleId))
                  .valueOrNull
                  ?.vehicleName ??
              other.vehicleId;
          return _pill(
            context,
            ref,
            other.vehicleId,
            other.targetSoc,
            other.remaining,
            name,
            synced: true,
            stale: other.isStale,
          );
        }
        return _multiPill(context, ref, others);
      },
    );
  }

  Widget _pill(
    BuildContext context,
    WidgetRef ref,
    String vehicleId,
    double? targetSoc,
    Duration? remaining,
    String vehicleName, {
    required bool synced,
    bool stale = false,
  }) {
    final prefix = !synced
        ? 'ĐANG SẠC'
        : stale
        ? 'ĐANG SẠC · DỮ LIỆU CŨ'
        : 'ĐANG SẠC · ĐỒNG BỘ';
    final label = remaining == null
        ? prefix
        : '$prefix · ${remaining.inHours.toString().padLeft(2, '0')}:${(remaining.inMinutes % 60).toString().padLeft(2, '0')}';
    return _LuxeChargingPill(
      semanticLabel: 'Phiên sạc xe $vehicleName đang diễn ra. $label.',
      label: label,
      detail: targetSoc != null && targetSoc > 0
          ? '→ ${targetSoc.round()}%'
          : null,
      stale: stale,
      onTap: () {
        ref.read(selectedVehicleIdProvider.notifier).state = vehicleId;
        ref.read(currentTabProvider.notifier).state = 1;
      },
    );
  }

  Widget _multiPill(
    BuildContext context,
    WidgetRef ref,
    List<ActiveChargingSessionSnapshot> sessions,
  ) {
    return _LuxeChargingPill(
      semanticLabel: '${sessions.length} phiên sạc đang diễn ra.',
      label: '${sessions.length} XE ĐANG SẠC',
      trailing: const Icon(
        Icons.expand_more_rounded,
        size: 18,
        color: LuxeColors.platinumMid,
      ),
      onTap: () => _showSessionChooser(context, ref, sessions),
    );
  }

  Future<void> _showSessionChooser(
    BuildContext context,
    WidgetRef ref,
    List<ActiveChargingSessionSnapshot> sessions,
  ) async {
    final selected = await showLuxeSheet<String>(
      context,
      isScrollControlled: false,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            const LuxeSheetHeader(
              eyebrow: 'Đang sạc',
              title: 'Phiên sạc đang diễn ra',
            ),
            const SizedBox(height: 14),
            LuxeSettingsGroup(
              children: [
                for (final session in sessions)
                  LuxeSettingsRow(
                    icon: Icons.ev_station_rounded,
                    accent: session.isStale
                        ? LuxeColors.champagne
                        : LuxeColors.emerald,
                    title: session.vehicleId,
                    subtitle: session.isStale
                        ? 'Dữ liệu cũ — cần xác minh'
                        : 'Đang đồng bộ',
                    onTap: () =>
                        Navigator.of(sheetContext).pop(session.vehicleId),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    ref.read(selectedVehicleIdProvider.notifier).state = selected;
    ref.read(currentTabProvider.notifier).state = 1;
  }
}

/// Dark glass capsule with an emerald rim. It drops in once; the status dot
/// breathes only while a real session is shown (paused off-screen by
/// [TickerMode], static under reduced motion).
class _LuxeChargingPill extends StatefulWidget {
  const _LuxeChargingPill({
    required this.semanticLabel,
    required this.label,
    required this.onTap,
    this.detail,
    this.trailing,
    this.stale = false,
  });

  final String semanticLabel;
  final String label;
  final String? detail;
  final Widget? trailing;
  final bool stale;
  final VoidCallback onTap;

  @override
  State<_LuxeChargingPill> createState() => _LuxeChargingPillState();
}

class _LuxeChargingPillState extends State<_LuxeChargingPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (luxeReduceMotion(context)) {
      _breath.stop();
      _breath.value = 1;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.stale ? LuxeColors.champagne : LuxeColors.emerald;
    // Bottom-left above the navigation bar, clear of the BatteryBot button:
    // at the top it covered page headers and cards (Task 127).
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14, left: 16, right: 104),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: luxeDuration(context, 520),
          curve: LuxeMotion.enter,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 12 * (1 - t)),
              child: child,
            ),
          ),
          child: Semantics(
            button: true,
            label: widget.semanticLabel,
            excludeSemantics: true,
            onTap: widget.onTap,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: widget.onTap,
                child: Ink(
                  decoration: BoxDecoration(
                    color: const Color(0xF0121315),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: accent.withValues(alpha: 0.45)),
                    boxShadow: [
                      const BoxShadow(
                        color: Color(0x99000000),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                      BoxShadow(
                        color: accent.withValues(alpha: 0.12),
                        blurRadius: 20,
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _breath,
                            builder: (context, _) {
                              final b = Curves.easeInOut.transform(
                                _breath.value,
                              );
                              return Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: accent,
                                  boxShadow: [
                                    BoxShadow(
                                      color: accent.withValues(
                                        alpha: 0.25 + 0.45 * b,
                                      ),
                                      blurRadius: 4 + 8 * b,
                                      spreadRadius: 1 * b,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 10),
                          Text(
                            widget.label,
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(
                              color: LuxeColors.text,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.1,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (widget.detail != null) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                widget.detail!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: LuxeColors.muted,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                          if (widget.trailing != null) ...[
                            const SizedBox(width: 4),
                            widget.trailing!,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
