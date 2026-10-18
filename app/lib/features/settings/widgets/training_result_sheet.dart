import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/widgets/luxe_kit.dart';
import '../../../data/models/vehicle_learning_status.dart';

/// "Mô hình có tốt hơn không?" (Task 127): the training verdict with numbers
/// the owner can check — error of the model in use, the new one and a simple
/// baseline on the same test data, plus actual vs predicted per case.
class TrainingResultSheet extends StatelessWidget {
  const TrainingResultSheet({
    super.key,
    required this.title,
    required this.report,
  });

  final String title;
  final TrainingReport report;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required TrainingReport report,
  }) => showLuxeSheet<void>(
    context,
    builder: (_) => TrainingResultSheet(title: title, report: report),
  );

  static String pct(double? value) =>
      value == null ? '—' : '±${value.toStringAsFixed(2)}%';

  /// One-sentence verdict that matches the numbers; says when the test set
  /// is too small to conclude (QA 128: one charge read as a firm verdict).
  static String verdict(TrainingReport report) {
    final e = report.evaluation;
    if (report.decision == 'no_data' || e == null) {
      return 'Chưa đủ dữ liệu để đánh giá.';
    }
    final n = e.next.n;
    final cases = e.unit == 'used' ? 'chuyến' : 'lần sạc';
    final weak = n > 0 && n < 3
        ? ' Mới kiểm tra trên $n $cases nên kết luận còn yếu.'
        : '';
    return _verdict(report, e) + weak;
  }

  static String _verdict(TrainingReport report, ModelEvaluation e) {
    final now = e.current.mae;
    final next = e.next.mae;
    if (report.promoted) {
      if (now == null) {
        return 'Đã dùng bản mới. Sai số khi kiểm tra trên dữ liệu nó chưa '
            'thấy: ${pct(next)}.';
      }
      if (next != null && next < now) {
        final better = ((now - next) / now * 100).round();
        return 'Bản mới tốt hơn: sai số giảm từ ${pct(now)} xuống ${pct(next)} '
            '(−$better%). Đã dùng bản mới.';
      }
      if (e.currentSawTest) {
        return 'Bản mới gần bằng bản đang dùng (${pct(next)} so với ${pct(now)}). '
            'Chênh lệch nằm trong mức cho phép vì bản đang dùng đã học chính '
            'dữ liệu kiểm tra, nên bản mới được dùng.';
      }
      return 'Bản mới tương đương bản đang dùng (${pct(next)} so với '
          '${pct(now)}) trên dữ liệu mới nên đã được dùng.';
    }
    return 'Bản mới chưa tốt hơn (${pct(next)} so với ${pct(now)}) nên vẫn '
        'giữ bản đang dùng. Dữ liệu vẫn được lưu cho lần sau.';
  }

  @override
  Widget build(BuildContext context) {
    final e = report.evaluation;
    final color = report.promoted ? LuxeColors.emerald : LuxeColors.champagne;
    final what = e?.unit == 'used'
        ? '% pin hao mỗi chuyến'
        : '% pin khi sạc xong';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LuxeSheetHeader(
            eyebrow: 'Kết quả huấn luyện',
            title: title,
            trailing: LuxeCircleButton(
              icon: Icons.close_rounded,
              tooltip: 'Đóng',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(height: 14),
          LuxeNotice(
            key: const ValueKey('training-verdict'),
            icon: report.promoted
                ? Icons.verified_rounded
                : Icons.history_toggle_off_rounded,
            color: color,
            message: verdict(report),
          ),
          if (e != null) ...[
            const SizedBox(height: 18),
            Text('SAI SỐ TRUNG BÌNH ($what)', style: LuxeText.eyebrow),
            const SizedBox(height: 10),
            _ErrorBars(evaluation: e),
            const SizedBox(height: 14),
            Text(
              _howTested(e),
              key: const ValueKey('training-method'),
              style: LuxeText.caption.copyWith(fontSize: 12.5),
            ),
            if (e.rows.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                e.unit == 'used'
                    ? 'THỰC TẾ SO VỚI DỰ ĐOÁN (% HAO)'
                    : 'THỰC TẾ SO VỚI DỰ ĐOÁN (% KHI XONG)',
                style: LuxeText.eyebrow,
              ),
              const SizedBox(height: 8),
              _CaseTable(evaluation: e),
            ],
          ],
        ],
      ),
    );
  }

  static String _howTested(ModelEvaluation e) {
    final cases = e.unit == 'used' ? 'chuyến' : 'lần sạc';
    final n = e.next.n;
    final base = e.onNewData
        ? 'Kiểm tra trên $n $cases mới (chưa dùng để huấn luyện bản cũ)'
        : 'Kiểm tra trên $n $cases đã lưu';
    final method = e.unit == 'used'
        ? 'Bản mới được chấm theo kiểm tra chéo 5 phần: mỗi chuyến được dự đoán bởi một bản chưa từng thấy chuyến đó.'
        : 'Bản mới được chấm kiểu bỏ-một-ra: mỗi lần sạc được dự đoán bởi một bản học từ các lần còn lại.';
    final optimistic = e.currentSawTest && e.current.scored
        ? ' Bản đang dùng đã học chính các $cases này nên điểm của nó lạc quan hơn thực tế.'
        : '';
    return '$base. $method$optimistic';
  }
}

class _ErrorBars extends StatelessWidget {
  const _ErrorBars({required this.evaluation});
  final ModelEvaluation evaluation;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Bản đang dùng', evaluation.current, LuxeColors.platinum),
      ('Bản mới', evaluation.next, LuxeColors.emerald),
      (evaluation.baselineLabel, evaluation.baseline, LuxeColors.dim),
    ].where((row) => row.$2.scored).toList();
    final worst = rows.fold<double>(
      0.01,
      (max, row) => row.$2.mae! > max ? row.$2.mae! : max,
    );
    return Column(
      children: [
        for (final (label, stats, color) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              label:
                  '$label: sai số ${TrainingResultSheet.pct(stats.mae)}, trúng trong 2% ${((stats.within2 ?? 0) * 100).round()}%',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: LuxeText.item.copyWith(fontSize: 14),
                          ),
                        ),
                        Text(
                          TrainingResultSheet.pct(stats.mae),
                          style: TextStyle(
                            color: color == LuxeColors.dim
                                ? LuxeColors.muted
                                : color,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (stats.mae! / worst).clamp(0.02, 1.0),
                        minHeight: 6,
                        color: color,
                        backgroundColor: LuxeColors.hairline,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Trúng trong ±1%: ${((stats.within1 ?? 0) * 100).round()}% · '
                      '±2%: ${((stats.within2 ?? 0) * 100).round()}% · '
                      'lệch TB ${(stats.bias ?? 0) >= 0 ? '+' : ''}${(stats.bias ?? 0).toStringAsFixed(2)}%',
                      style: LuxeText.caption.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CaseTable extends StatelessWidget {
  const _CaseTable({required this.evaluation});
  final ModelEvaluation evaluation;

  static String _v(double? value) =>
      value == null ? '—' : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    const header = TextStyle(
      color: LuxeColors.muted,
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
    );
    const cell = TextStyle(
      color: LuxeColors.text,
      fontSize: 12.5,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return LuxeGlass(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          const Row(
            children: [
              Expanded(flex: 5, child: Text('Lần', style: header)),
              Expanded(flex: 3, child: Text('Thực tế', style: header)),
              Expanded(flex: 3, child: Text('Đang dùng', style: header)),
              Expanded(flex: 3, child: Text('Mới', style: header)),
            ],
          ),
          const Divider(height: 12),
          for (final row in evaluation.rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      row.note == null
                          ? row.label
                          : '${row.label}\n${row.note}',
                      style: cell.copyWith(
                        color: row.tested ? LuxeColors.text : LuxeColors.dim,
                        fontSize: row.note == null ? 12.5 : 11.5,
                      ),
                    ),
                  ),
                  Expanded(flex: 3, child: Text(_v(row.actual), style: cell)),
                  Expanded(
                    flex: 3,
                    child: Text(
                      _v(row.current),
                      style: cell.copyWith(color: LuxeColors.platinum),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      _v(row.next),
                      style: cell.copyWith(color: LuxeColors.emerald),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
