import '../services/trip_energy_model.dart';

/// Server view of what the vehicle's models learned and what new data waits
/// for the owner to press "Huấn luyện" (Task 127, `/api/learning/...`).
class VehicleLearningStatus {
  const VehicleLearningStatus({
    required this.vehicleId,
    required this.consentEnabled,
    required this.charge,
    required this.trip,
  });

  final String vehicleId;
  final bool consentEnabled;
  final ModelTrainingStatus charge;
  final ModelTrainingStatus trip;

  /// The model the trip planner should use (trained, ODO or catalog prior).
  TripModelParams? get tripParams {
    final raw = trip.raw['model'];
    if (raw is! Map) return null;
    final source = raw['source'];
    final parsed = TripModelParams.fromJson(raw);
    if (parsed == null || source == 'model') return parsed;
    return TripModelParams(
      refPctPerKm: parsed.refPctPerKm,
      speed: parsed.speed,
      speed2: parsed.speed2,
      loadPer10Kg: parsed.loadPer10Kg,
      rain: parsed.rain,
      source: source == 'odo' ? TripKmSource.personal : TripKmSource.catalog,
      spread: parsed.spread,
    );
  }

  static VehicleLearningStatus? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final data = Map<String, dynamic>.from(raw);
    return VehicleLearningStatus(
      vehicleId: data['vehicleId']?.toString() ?? '',
      consentEnabled: data['consentEnabled'] != false,
      charge: ModelTrainingStatus.fromJson(data['charge']),
      trip: ModelTrainingStatus.fromJson(data['trip']),
    );
  }
}

class ModelTrainingStatus {
  const ModelTrainingStatus({
    required this.pending,
    required this.required,
    required this.ready,
    required this.trained,
    this.mae,
    this.trainedAt,
    this.report,
    this.raw = const {},
  });

  /// Labelled charges / rides collected since the last training.
  final int pending;
  final int required;
  final bool ready;

  /// Charges / rides the current model was trained on.
  final int trained;
  final double? mae;
  final DateTime? trainedAt;
  final TrainingReport? report;
  final Map<String, dynamic> raw;

  double get progress => required <= 0 ? 1 : (pending / required).clamp(0, 1);

  static ModelTrainingStatus fromJson(Object? raw) {
    final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final report = TrainingReport.fromJson(data['report']);
    final model = data['model'];
    return ModelTrainingStatus(
      pending: _int(data['pending']),
      required: _int(data['required'], fallback: 3),
      ready: data['ready'] == true,
      trained: _int(data['trained']),
      mae: _num(data['mae']) ?? (model is Map ? _num(model['mae']) : null),
      trainedAt: DateTime.tryParse(data['trainedAt']?.toString() ?? ''),
      report: report,
      raw: data,
    );
  }
}

class TrainingReport {
  const TrainingReport({
    required this.decision,
    required this.mode,
    required this.used,
    this.beforeMae,
    this.afterMae,
    this.at,
    this.evaluation,
  });

  /// promoted | rejected_worse | no_data
  final String decision;
  final String mode;
  final int used;
  final double? beforeMae;
  final double? afterMae;
  final DateTime? at;

  /// Objective comparison on data the new model did not see (Task 127).
  final ModelEvaluation? evaluation;

  bool get promoted => decision == 'promoted';

  String get summary {
    String error(double? value) =>
        value == null ? '—' : '±${value.toStringAsFixed(1)}%';
    return switch (decision) {
      'promoted' =>
        'Đã dùng bản mới · sai số ${error(beforeMae)} → ${error(afterMae)} ($used mẫu)',
      'rejected_worse' =>
        'Bản mới không tốt hơn nên vẫn giữ bản cũ (sai số ${error(beforeMae)}).',
      _ => 'Chưa đủ dữ liệu để huấn luyện.',
    };
  }

  static TrainingReport? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return TrainingReport(
      decision: raw['decision']?.toString() ?? 'no_data',
      mode: raw['mode']?.toString() ?? 'finetune',
      used: _int(raw['used']),
      beforeMae: _num(raw['beforeMae']),
      afterMae: _num(raw['afterMae']),
      at: DateTime.tryParse(raw['at']?.toString() ?? ''),
      evaluation: ModelEvaluation.fromJson(raw['evaluation']),
    );
  }
}

/// Error of one model on the test set (end % for charges, % used for rides).
class ErrorStats {
  const ErrorStats({required this.n, this.mae, this.bias, this.within1, this.within2});

  final int n;
  final double? mae;
  final double? bias;
  final double? within1;
  final double? within2;

  bool get scored => n > 0 && mae != null;

  static ErrorStats fromJson(Object? raw) {
    final data = raw is Map ? raw : const {};
    return ErrorStats(
      n: _int(data['n']),
      mae: _num(data['mae']),
      bias: _num(data['bias']),
      within1: _num(data['within1']),
      within2: _num(data['within2']),
    );
  }
}

/// One test case: what really happened and what each model predicted.
class EvaluationRow {
  const EvaluationRow({
    required this.label,
    required this.actual,
    this.current,
    this.next,
    this.baseline,
    this.tested = true,
    this.note,
  });

  final String label;
  final double actual;
  final double? current;
  final double? next;
  final double? baseline;
  final bool tested;
  final String? note;
}

class ModelEvaluation {
  const ModelEvaluation({
    required this.method,
    required this.onNewData,
    required this.currentSawTest,
    required this.current,
    required this.next,
    required this.baseline,
    required this.baselineLabel,
    required this.rows,
    required this.unit,
  });

  final String method;

  /// Tested on data collected since the last training (fairest case).
  final bool onNewData;

  /// The model in use was trained on the test data: its score is optimistic.
  final bool currentSawTest;
  final ErrorStats current;
  final ErrorStats next;
  final ErrorStats baseline;
  final String baselineLabel;
  final List<EvaluationRow> rows;

  /// What the numbers measure: `end` (% at the end of a charge) or `used`.
  final String unit;

  static ModelEvaluation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final trip = raw.containsKey('flat');
    final rows = <EvaluationRow>[];
    for (final item in (raw['examples'] as List?) ?? const []) {
      if (item is! Map) continue;
      final actual = _num(item['actual']);
      if (actual == null) continue;
      final at = item['at']?.toString() ?? '';
      final date = at.length >= 10 ? '${at.substring(8, 10)}/${at.substring(5, 7)}' : at;
      rows.add(EvaluationRow(
        label: trip
            ? '$date · ${_num(item['km'])?.toStringAsFixed(1) ?? '?'} km'
            : '$date · ${_num(item['startPct'])?.round() ?? '?'}%→',
        actual: actual,
        current: _num(item['current']),
        next: _num(item['new']),
        baseline: _num(item[trip ? 'flat' : 'base']),
        tested: item['tested'] != false,
        note: item['censored'] == true
            ? 'kết thúc 100% (chỉ là cận trên)'
            : item['labelSource'] == 'taper_full'
            ? 'pin đầy tự nhận biết'
            : null,
      ));
    }
    return ModelEvaluation(
      method: raw['method']?.toString() ?? '',
      onNewData: raw['testSet'] == 'new',
      currentSawTest: raw['currentSawTest'] == true,
      current: ErrorStats.fromJson(raw['current']),
      next: ErrorStats.fromJson(raw['new']),
      baseline: ErrorStats.fromJson(raw[trip ? 'flat' : 'base']),
      baselineLabel: trip ? 'km/1% cố định' : 'Thông số dòng xe',
      rows: rows,
      unit: trip ? 'used' : 'end',
    );
  }
}

/// A labelled charge the charge model learned from (or that waits).
class ChargeSampleRow {
  const ChargeSampleRow({
    required this.date,
    required this.startPct,
    required this.endPct,
    required this.energyWh,
    required this.fullDetected,
    required this.censored,
  });

  final String date;
  final double startPct;
  final double endPct;
  final double energyWh;
  final bool fullDetected;
  final bool censored;

  static List<ChargeSampleRow> listFrom(Object? raw) => [
    for (final item in (raw is List ? raw : const []))
      if (item is Map)
        ChargeSampleRow(
          date: () {
            final at = item['at']?.toString() ?? '';
            return at.length >= 10
                ? '${at.substring(8, 10)}/${at.substring(5, 7)}/${at.substring(0, 4)}'
                : at;
          }(),
          startPct: _num(item['startPct']) ?? 0,
          endPct: _num(item['actualEndPct']) ?? 0,
          energyWh: _num(item['energyWh']) ?? 0,
          fullDetected: item['labelSource'] == 'taper_full',
          censored: item['censored'] == true,
        ),
  ];
}

/// Result of saving one battery/ODO reading.
class BatteryReadingResult {
  const BatteryReadingResult({
    required this.readingId,
    this.rideKm,
    this.rideUsedPct,
    this.status,
  });

  final String readingId;

  /// Set when this reading closed a ride since the previous one.
  final double? rideKm;
  final double? rideUsedPct;
  final VehicleLearningStatus? status;

  static BatteryReadingResult fromJson(Map<String, dynamic> data) {
    final reading = data['reading'];
    final segment = data['segment'];
    return BatteryReadingResult(
      readingId: reading is Map ? reading['id']?.toString() ?? '' : '',
      rideKm: segment is Map ? _num(segment['distanceKm']) : null,
      rideUsedPct: segment is Map ? _num(segment['socUsed']) : null,
      status: VehicleLearningStatus.fromJson(data['training']),
    );
  }
}

int _int(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

double? _num(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed.isFinite ? parsed : null;
}
