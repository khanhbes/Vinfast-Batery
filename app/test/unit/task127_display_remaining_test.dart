import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charger_status.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/features/ai/controllers/smart_charging_controller.dart';

/// The owner's real 17/10 target charge: 58 % → 80 %, ON at 04:19 UTC,
/// plan 05:37, Shelly ceiling 06:37, server hard deadline 14:19.
SmartChargingSession _target({double averagePowerW = 0}) =>
    SmartChargingSession.fromJson({
      'session_id': 's-target',
      'vehicle_id': 'car',
      'state': 'active',
      'strategy': 'target_soc',
      'stop_mode': 'target',
      'start_soc': 58,
      'target_soc': 80,
      'estimated_soc': 58,
      'model_wh_per_pct': 26.151,
      'target_energy_wh': 575.32,
      'average_power_w': averagePowerW,
      'predicted_minutes': 79,
      'prediction_source': 'personal_physics',
      'created_at': '2026-10-17T04:19:15Z',
      'updated_at': '2026-10-17T04:19:15Z',
      'started_at': '2026-10-17T04:19:15Z',
      'ai_stop_at': '2026-10-17T05:37:45Z',
      'hard_deadline_at': '2026-10-17T14:19:15Z',
      'effective_stop_at': '2026-10-17T06:37:11Z',
      'absolute_safety_stop_at': '2026-10-17T14:19:15Z',
      'relay_verified': true,
      'energy_used_wh': 0,
      'energy_quality': 'good',
      'shadow_mode': false,
      'version': 2,
    });

void main() {
  final now = DateTime.utc(2026, 10, 17, 4, 19, 30);
  late SmartChargingController controller;
  setUp(() {
    controller = SmartChargingController(
      vehicleId: 'car',
      currentSoc: 58,
      autoInitialize: false,
    );
  });
  tearDown(() => controller.dispose());

  test('no power reading yet: the plan, not the 600-minute cap', () {
    // Task 127: the card showed "09:59:57 · lúc 21:19" for a ~1 h charge.
    final state = controller.state.copyWith(session: _target(), now: now);
    expect(state.remainingEstimate, isNull);
    expect(state.displayRemaining, const Duration(minutes: 78, seconds: 15));
  });

  test('measured power counts down to the target, never past the ceiling', () {
    final state = controller.state.copyWith(
      session: _target(),
      livePowerSamples: const [450, 452, 449],
      now: now,
    );
    final left = state.displayRemaining!;
    // 22 % x 26.15 Wh / ~450 W ≈ 77 min.
    expect(left.inMinutes, inInclusiveRange(70, 80));
    final slow = controller.state.copyWith(
      session: _target(),
      livePowerSamples: const [70, 70, 70],
      now: now,
    );
    expect(
      slow.displayRemaining,
      DateTime.utc(2026, 10, 17, 6, 37, 11).difference(now),
      reason: 'capped by the Shelly ceiling',
    );
  });

  test('a timed charge follows the device timer', () {
    final timed = SmartChargingSession.fromJson({
      ..._target().toJson(),
      'stop_mode': 'timer',
      'strategy': 'manual_timed',
    });
    final state = controller.state.copyWith(
      session: timed,
      chargerStatus: SmartChargerStatus(
        online: true,
        relay: true,
        powerW: 440,
        voltageV: 229,
        currentA: 2.9,
        frequencyHz: 50,
        temperatureC: 40,
        energyWh: 0,
        timerRemaining: const Duration(hours: 1),
        readAt: now,
      ),
      now: now,
    );
    expect(state.displayRemaining, const Duration(hours: 1));
  });
}
