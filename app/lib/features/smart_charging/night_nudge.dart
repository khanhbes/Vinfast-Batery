import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers/app_state_providers.dart';
import '../../core/providers/entitlement_provider.dart';
import '../../core/providers/vehicle_providers.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/theme/plan_style.dart';
import '../home/widgets/luxe_dashboard_cards.dart';
import '../../data/models/entitlement.dart';
import '../../data/services/shelly_connection_coordinator.dart';
import 'night_charging_screen.dart';

/// When the app offers a night charge by itself (QA 152, owner's request):
/// in the evening, on a vehicle that can use one. All of it is decided on the
/// phone from real state; nothing is switched on, the owner still sets the
/// numbers and swipes on the night screen.
abstract final class NightNudge {
  static const enabledKey = 'night_nudge_enabled';
  static const dismissedKey = 'night_nudge_dismissed';

  /// The evening window: 21:00 until 02:00.
  static bool isNight(DateTime now) => now.hour >= 21 || now.hour < 2;

  /// One key per night: 00:30 still belongs to the evening before it.
  static String nightOf(DateTime now) {
    final day = now.hour < 2 ? now.subtract(const Duration(days: 1)) : now;
    return '${day.year}-${day.month}-${day.day}';
  }

  /// The server takes a night plan up to 5% under its lowest target (80%).
  static const maxSoc = 75;

  static bool shouldOffer({
    required DateTime now,
    required bool enabled,
    required bool allowed,
    required bool shellyLinked,
    required bool hasBatteryData,
    required num soc,
    required bool charging,
    required String? dismissedNight,
  }) =>
      enabled &&
      allowed &&
      shellyLinked &&
      hasBatteryData &&
      !charging &&
      soc <= maxSoc &&
      isNight(now) &&
      dismissedNight != nightOf(now);

  static Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(enabledKey) ?? true;

  static Future<void> setEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(enabledKey, value);
}

/// The card on Tổng quan. Takes no space unless there is an offer to make.
class NightNudgeCard extends ConsumerStatefulWidget {
  const NightNudgeCard({super.key, required this.vehicleId, this.clock});

  final String vehicleId;
  final DateTime Function()? clock;

  @override
  ConsumerState<NightNudgeCard> createState() => _NightNudgeCardState();
}

class _NightNudgeCardState extends ConsumerState<NightNudgeCard> {
  bool _enabled = false;
  String? _dismissed;
  bool _prefsLoaded = false;

  /// Null until the server said whether a plan is already armed or running.
  bool? _planFree;
  bool _checking = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void didUpdateWidget(covariant NightNudgeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vehicleId != widget.vehicleId) _planFree = null;
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _enabled = prefs.getBool(NightNudge.enabledKey) ?? true;
        _dismissed = prefs.getString(NightNudge.dismissedKey);
        _prefsLoaded = true;
      });
    } on Object {
      // No offer without the owner's saved choice.
    }
  }

  Future<void> _checkPlan() async {
    if (_checking || _planFree != null) return;
    _checking = true;
    try {
      final plan = await ref
          .read(nightChargingApiProvider)
          .get(widget.vehicleId);
      if (mounted) {
        setState(
          () => _planFree = !(plan?.armed == true || plan?.state == 'started'),
        );
      }
    } on Object {
      // Offline or an older server: say nothing rather than guess.
      if (mounted) setState(() => _planFree = false);
    } finally {
      _checking = false;
    }
  }

  Future<void> _dismiss() async {
    final night = NightNudge.nightOf(_now);
    setState(() => _dismissed = night);
    try {
      (await SharedPreferences.getInstance()).setString(
        NightNudge.dismissedKey,
        night,
      );
    } on Object {
      // Hidden for this run all the same.
    }
  }

  Future<void> _open(num soc, num? odo) async {
    await NightChargingScreen.open(
      context,
      ref,
      vehicleId: widget.vehicleId,
      currentSoc: soc.toDouble(),
      currentOdoKm: odo?.toDouble(),
    );
    // Armed or not, the question was answered for tonight.
    if (mounted) await _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefsLoaded || widget.vehicleId.isEmpty || Firebase.apps.isEmpty) {
      return const SizedBox.shrink();
    }
    final vehicle = ref.watch(vehicleProvider(widget.vehicleId)).valueOrNull;
    if (vehicle == null) return const SizedBox.shrink();
    final link = ShellyConnectionCoordinator.shared.current;
    final offer = NightNudge.shouldOffer(
      now: _now,
      enabled: _enabled,
      allowed: ref
          .watch(entitlementProvider)
          .allows(PremiumFeature.nightCharging),
      shellyLinked: link.isLinked || link.serverBinding != null,
      hasBatteryData: vehicle.hasBatteryData,
      soc: vehicle.currentBattery,
      charging: ref.watch(chargingEstimateProvider(widget.vehicleId)) != null,
      dismissedNight: _dismissed,
    );
    if (!offer) return const SizedBox.shrink();
    if (_planFree == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkPlan());
      return const SizedBox.shrink();
    }
    if (_planFree != true) return const SizedBox.shrink();

    final soc = vehicle.currentBattery;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: LuxeGlass(
        key: const ValueKey('night-nudge'),
        selected: true,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LuxeOrb(
                  icon: Icons.nightlight_round,
                  color: context.planAccent,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hẹn sạc đêm nay?',
                        style: TextStyle(
                          color: LuxeColors.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Pin đang $soc%. Ổ Shelly sẽ tự bật trong đêm để pin '
                        'đạt 80–90% ngay trước giờ bạn thức dậy.',
                        style: LuxeText.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const ValueKey('night-nudge-later'),
                    onPressed: _dismiss,
                    child: const Text('Để sau'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const ValueKey('night-nudge-open'),
                    onPressed: () => _open(soc, vehicle.currentOdo),
                    child: const Text('Hẹn sạc đêm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
