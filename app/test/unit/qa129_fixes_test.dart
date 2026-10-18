import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/providers/learned_models_provider.dart';
import 'package:vinfast_battery/core/utils/number_text.dart';
import 'package:vinfast_battery/data/models/smart_charge_cost.dart';
import 'package:vinfast_battery/data/models/smart_charge_history.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/data/models/vehicle_learning_status.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/services/charge_progress_notification.dart';
import 'package:vinfast_battery/data/services/range_estimator.dart';
import 'package:vinfast_battery/data/services/trip_energy_model.dart';
import 'package:vinfast_battery/features/achievements/controllers/achievements_controller.dart';
import 'package:vinfast_battery/features/achievements/services/achievement_engine.dart';
import 'package:vinfast_battery/features/achievements/services/achievement_signals.dart';
import 'package:vinfast_battery/features/ai/widgets/history_luxe_widgets.dart';
import 'package:vinfast_battery/features/battery_monitor/battery_monitor_screen.dart';

/// The owner's trained trip model: 1.21 km/% mixed riding, 77 rides.
const learned = TripModelParams(
  refPctPerKm: TripEnergyModel.refToMean / 1.21,
  source: TripKmSource.model,
  samples: 77,
  spread: 0.18,
);

VehicleModel feliz({int battery = 79, double soh = 100}) => VehicleModel(
  vehicleId: 'car',
  currentOdo: 4804,
  currentBattery: battery,
  stateOfHealth: soh,
  defaultEfficiency: 1.2,
);

SmartChargingSession session(
  String id, {
  String vehicle = 'car',
  double wh = 576,
  String state = 'completed',
  String? energyQuality,
}) => SmartChargingSession.fromJson({
  'session_id': id,
  'vehicle_id': vehicle,
  'state': state,
  'strategy': 'target_soc',
  'stop_mode': 'target',
  'start_soc': 58,
  'target_soc': 80,
  'predicted_minutes': 79,
  'prediction_source': 'personal_physics',
  'created_at': '2026-10-17T04:19:15Z',
  'updated_at': '2026-10-17T05:36:00Z',
  'started_at': '2026-10-17T04:19:15Z',
  'stopped_at': '2026-10-17T05:36:00Z',
  'ai_stop_at': '2026-10-17T05:37:45Z',
  'hard_deadline_at': '2026-10-17T14:19:15Z',
  'effective_stop_at': '2026-10-17T06:37:11Z',
  'absolute_safety_stop_at': '2026-10-17T14:19:15Z',
  'relay_verified': true,
  'energy_used_wh': wh,
  'energy_quality': ?energyQuality,
  'version': 2,
});

void main() {
  group('one km/% on every screen', () {
    test('learned model wins and SoH is not applied twice', () {
      final range = estimateRange(feliz(soh: 90), learned: learned)!;
      expect(range.source, RangeSource.learned);
      expect(range.kmPerPct, closeTo(1.21, 1e-9));
      expect(range.km, closeTo((79 - 5) * 1.21, 1e-9));
      expect(range.samples, 77);
      expect(kmPerPctFor(feliz(), learned), closeTo(1.21, 1e-9));
    });

    test('without a model: catalog x SoH, labelled catalog', () {
      final range = estimateRange(feliz(soh: 90))!;
      expect(range.source, RangeSource.catalog);
      expect(range.km, closeTo(74 * 1.2 * 0.9, 1e-9));
      expect(kmPerPctFor(feliz(soh: 90), null), closeTo(1.08, 1e-9));
    });

    test('learned models are read from the server status', () {
      final models = LearnedModels.fromStatus(
        VehicleLearningStatus.fromJson({
          'vehicleId': 'car',
          'charge': {'whPerPct': 26.2, 'powerW': 440},
          'trip': {
            'model': {'refPctPerKm': 0.73, 'source': 'model', 'samples': 77},
          },
        }),
      );
      expect(models.whPerPct, 26.2);
      expect(models.powerW, 440);
      expect(models.trip?.source, TripKmSource.model);
      expect(models.trip?.kmPerPct, closeTo(0.882 / 0.73, 1e-9));
      // A catalog prior is not a learned model.
      final prior = LearnedModels.fromStatus(
        VehicleLearningStatus.fromJson({
          'vehicleId': 'car',
          'trip': {
            'model': {'refPctPerKm': 0.73, 'source': 'catalog'},
          },
        }),
      );
      expect(prior.trip, isNull);
    });
  });

  test('thousands never use the decimal dot', () {
    expect(groupThousands(4804), '4 804');
    expect(groupThousands(999), '999');
    expect(groupThousands(1234567), '1 234 567');
    expect(formatVnd(12500), '12 500 đ');
  });

  test('a target charge that reached its target is "Hoàn thành"', () {
    final (label, _) = historyStatus(session('a', energyQuality: 'partial'));
    expect(label, 'Hoàn thành');
    const filter = SmartChargeHistoryQuery(
      status: SmartChargeHistorySessionFilter.completed,
    );
    expect(filter.matches(session('a', energyQuality: 'partial')), isTrue);
  });

  test('no price set means "—", not 0 đ', () {
    final summary = SmartChargeHistorySummary.calculate([session('a')]);
    expect(summary.pricedSessions, 0);
    expect(summary.totalGridEnergyWh, 576);
  });

  test('battery source is said in words', () {
    expect(batterySourceLabel('user_confirmed'), 'Bạn xác nhận sau khi sạc');
    expect(batterySourceLabel('reading_chat'), 'Nhập qua BatteryBot');
    expect(batterySourceLabel('reading_photo'), 'Quét từ đồng hồ xe');
    expect(batterySourceLabel('smart_charge_estimated'), 'Ước tính sau phiên sạc');
    expect(batterySourceLabel(null), 'Bạn nhập');
  });

  test('charging notification marks the estimate', () {
    final content = ChargeProgressContent.from({
      'event': 'smart_charge_progress',
      'soc': '63',
      'targetSoc': '80',
      'stopMode': 'target',
      'powerW': '412',
    }, DateTime.utc(2026, 10, 18, 4));
    expect(content!.title, 'Đang sạc ~63% → 80%');
  });

  group('ledger matches History (QA 129)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AchievementSignals.instance.drain();
      AchievementSignals.instance.drainHidden();
    });

    test('30 Wh floor, vehicle kept through storage', () {
      final entry = LedgerSession.fromSession(session('a', vehicle: 'evo'))!;
      expect(entry.vehicleId, 'evo');
      expect(LedgerSession.fromJson(entry.toJson())!.vehicleId, 'evo');
      expect(LedgerSession.fromSession(session('b', wh: 25))!.valid, isFalse);
      expect(LedgerSession.fromSession(session('c', wh: 30))!.valid, isTrue);
    });

    test('a full sync drops sessions History no longer lists', () async {
      var listed = [session('a'), session('b')];
      Future<SmartChargeHistoryPage> page({String? cursor}) async =>
          SmartChargeHistoryPage(items: listed);
      final c = AchievementsController(uid: 'u1', historyPage: page);
      await c.sync(force: true);
      expect(c.state.sessions.map((s) => s.id), unorderedEquals(['a', 'b']));
      listed = [session('a')];
      await c.sync(force: true);
      expect(c.state.sessions.map((s) => s.id), ['a']);
      c.dispose();
    });

    test('hiding a session removes it from the ledger', () async {
      final c = AchievementsController(uid: 'u2');
      await c.ingest([session('a'), session('b')]);
      AchievementSignals.instance.sessionHidden('b');
      await Future<void>.delayed(Duration.zero);
      await c.load();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(c.state.sessions.map((s) => s.id), ['a']);
      c.dispose();
    });
  });
}
