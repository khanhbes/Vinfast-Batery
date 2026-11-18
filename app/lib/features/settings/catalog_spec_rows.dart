import '../../core/utils/number_text.dart';
import '../../data/models/vinfast_model_spec.dart';
import '../../data/services/charge_estimator.dart' show formatChargeDuration;

/// The "Catalog xe điện" rows of Thông số chi tiết (QA 143, QA 166).
///
/// QA 166 (owner's choice, 18/11/2026): only what the maker publishes.
/// VinFast publishes no voltage or Ah for the Feliz 2025: the row says so
/// instead of a number nobody published. The wall power the app's estimates
/// fall back to is the app's own figure (measured on the owner's charger), not
/// a published one, and is not listed; the charger the model comes with and
/// its published time from 0 to 100 % are.
List<(String, String)> catalogSpecRows(VinFastModelSpec spec) {
  String n(num value) => groupThousands(value.round());
  String published(double value) =>
      value > 0 ? n(value) : VinFastModelSpec.unpublished;
  return [
    ('Tên model', spec.modelName),
    ('Dung lượng (Wh)', n(spec.nominalCapacityWh)),
    ('Dung lượng (Ah)', published(spec.nominalCapacityAh)),
    ('Điện áp (V)', published(spec.nominalVoltageV)),
    if (spec.batteryChemistry case final chemistry?) ('Loại pin', chemistry),
    if (spec.rangeKm case final range?)
      ('Quãng đường công bố', '${n(range)} km'),
    if (spec.topSpeedKmh case final speed?)
      ('Tốc độ tối đa', '${n(speed)} km/h'),
    if (spec.maxDcChargePowerW case final charger? when charger > 0)
      ('Bộ sạc theo xe', '${n(charger)} W'),
    if (spec.chargeTimeMinutes case final minutes? when minutes > 0)
      (
        'Sạc đầy (0–100%)',
        'khoảng ${formatChargeDuration(Duration(minutes: minutes.round()))}',
      ),
    ('Công suất định mức (W)', n(spec.ratedMotorPowerW)),
    ('Công suất tối đa (W)', n(spec.peakMotorPowerW)),
    ('Nguồn dữ liệu', 'Số liệu VinFast công bố'),
  ];
}
