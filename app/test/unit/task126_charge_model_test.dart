import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/data/services/charge_estimator.dart';
import 'package:vinfast_battery/data/services/charge_history_quality.dart';

/// Task 126: the app and the server must give the same answers. Both suites
/// read the same fixture files from web/tests/fixtures.
Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('../web/tests/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('charge history quality (shared vectors)', () {
    final vectors = _fixture('charge_history_quality_vectors.json');
    for (final raw in vectors['vectors'] as List) {
      final vector = Map<String, dynamic>.from(raw as Map);
      test(vector['name'], () {
        final log = Map<String, dynamic>.from(vector['log'] as Map);
        expect(ChargeHistoryQuality.classify(log), (
          vector['expect'] as String,
          vector['reason'] as String,
        ));
      });
    }
    test('hidden flags', () {
      for (final raw in vectors['hidden'] as List) {
        final vector = Map<String, dynamic>.from(raw as Map);
        expect(
          ChargeHistoryQuality.isHidden(
            Map<String, dynamic>.from(vector['log'] as Map),
          ),
          vector['hidden'],
        );
      }
    });
  });

  group('charge model (shared vectors)', () {
    for (final raw
        in _fixture('charge_model_vectors.json')['estimates'] as List) {
      final vector = Map<String, dynamic>.from(raw as Map);
      test(vector['name'], () {
        final params = Map<String, dynamic>.from(vector['params'] as Map);
        final seconds = ChargeEstimator.wallSeconds(
          whPerPct: (params['wh_per_pct'] as num).toDouble(),
          powerW: (params['power_w'] as num).toDouble(),
          from: (vector['start'] as num).toDouble(),
          to: (vector['target'] as num).toDouble(),
          taperStart:
              (params['taper_start_pct'] as num?)?.toDouble() ??
              ChargeEstimator.cvStartSoc,
          taperRatio:
              (params['taper_power_ratio'] as num?)?.toDouble() ??
              ChargeEstimator.cvPowerFactor,
        );
        expect(seconds, vector['seconds']);
      });
    }

    test('SoC from wall energy uses the learned Wh per %', () {
      expect(
        ChargeEstimator.socAfter(whPerPct: 26.15, startSoc: 22, energyWh: 1556),
        closeTo(81.5, 0.1),
      );
      expect(
        ChargeEstimator.socAfter(whPerPct: 26, startSoc: 90, energyWh: 9999),
        100,
      );
    });

    test('the capacity estimate and the wall model agree', () {
      final estimate = ChargeEstimator.estimate(
        currentSoc: 20,
        targetSoc: 80,
        capacityWh: 2340,
        powerW: 440,
        powerSource: ChargePowerSource.measuredHistory,
      )!;
      // 2340 Wh / 100 / 0.9 = 26 Wh per % at the wall: 12764 s on the server.
      expect(estimate.minutes, (12764 / 60).ceil());
    });
  });

  group('server contract', () {
    test('unknown stop reasons never make a session unreadable', () {
      expect(
        ChargingStopReason.fromJson('target_reached'),
        ChargingStopReason.targetReached,
      );
      expect(
        ChargingStopReason.fromJson('charger_idle'),
        ChargingStopReason.chargerIdle,
      );
      expect(
        ChargingStopReason.fromJson('deadline_cutoff'),
        ChargingStopReason.deadlineCutoff,
      );
      expect(ChargingStopReason.fromJson('something_new'), isNull);
    });

    test('target session fields round-trip', () {
      final now = DateTime.utc(2026, 10, 16, 8);
      final json = {
        'session_id': 's1',
        'vehicle_id': 'car',
        'state': 'active',
        'strategy': 'target_soc',
        'start_soc': 20,
        'target_soc': 80,
        'predicted_minutes': 213,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'ai_stop_at': now.add(const Duration(minutes: 213)).toIso8601String(),
        'hard_deadline_at': now
            .add(const Duration(hours: 10))
            .toIso8601String(),
        'effective_stop_at': now
            .add(const Duration(minutes: 276))
            .toIso8601String(),
        'absolute_safety_stop_at': now
            .add(const Duration(hours: 10))
            .toIso8601String(),
        'version': 2,
        'energy_used_wh': 500,
        'stop_mode': 'target',
        'target_energy_wh': 1560,
        'model_wh_per_pct': 26,
      };
      final session = SmartChargingSession.fromJson(json);
      expect(session.isTargetMode, isTrue);
      expect(session.remainingTargetWh, 1060);
      final copy = session.copyWith(energyUsedWh: 600);
      expect(copy.modelWhPerPct, 26);
      expect(copy.targetEnergyWh, 1560);
      expect(SmartChargingSession.fromJson(copy.toJson()).stopMode, 'target');
    });
  });
}
