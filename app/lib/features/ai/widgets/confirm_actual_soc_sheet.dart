import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/widgets/luxe_kit.dart';
import '../../../core/widgets/luxe_submit_button.dart';
import '../dashboard_scan_screen.dart';
import 'battery_reading_sheet.dart';
import '../../../core/utils/number_text.dart';

/// What the user read on the scooter after a charge (Task 126).
typedef ActualSocReading = ({double soc, double? odoKm, bool ridden});

/// "Đồng hồ xe đang báo bao nhiêu %?" — the scooter has no BMS link, so the
/// number on its display is the only ground truth the charge model can learn
/// from. Nothing is pre-filled (QA 148): one tap on the estimate used to save it as
/// a reading, teaching the model that it was right. ODO is optional (it teaches km
/// per %). The whole sheet is optional too.
class ConfirmActualSocSheet extends StatefulWidget {
  const ConfirmActualSocSheet({
    super.key,
    required this.estimatedSoc,
    required this.startSoc,
    this.currentOdoKm,
    this.endedAt,
    this.reader,
    this.onSave,
  });

  /// Longer ago than this, the scooter may have been ridden since the charge.
  static const askRiddenAfter = Duration(hours: 6);

  final double? estimatedSoc;
  final double startSoc;
  final double? currentOdoKm;

  /// When the charge ended, to ask about riding on a late reading.
  final DateTime? endedAt;

  /// Saves on the server while the sheet shows progress (QA 135); returns
  /// the reason when it failed (the sheet stays open with the numbers).
  final Future<String?> Function(ActualSocReading reading)? onSave;

  /// Dashboard photo reader (Task 127); injectable for tests.
  final DashboardReadFn? reader;

  static Future<ActualSocReading?> show(
    BuildContext context, {
    required double? estimatedSoc,
    required double startSoc,
    double? currentOdoKm,
    DateTime? endedAt,
    DashboardReadFn? reader,
    Future<String?> Function(ActualSocReading reading)? onSave,
  }) => showLuxeSheet<ActualSocReading>(
    context,
    builder: (_) => ConfirmActualSocSheet(
      estimatedSoc: estimatedSoc,
      startSoc: startSoc,
      currentOdoKm: currentOdoKm,
      endedAt: endedAt,
      reader: reader,
      onSave: onSave,
    ),
  );

  @override
  State<ConfirmActualSocSheet> createState() => _ConfirmActualSocSheetState();
}

class _ConfirmActualSocSheetState extends State<ConfirmActualSocSheet> {
  late double _soc;

  /// The owner chose or scanned a number; until then nothing can be saved.
  bool _chosen = false;
  bool? _ridden;
  final _odo = TextEditingController();
  String? _odoError;
  bool _reading = false;
  String? _readNote;
  String? _saveError;
  bool _saving = false;

  double get _minimum => (widget.startSoc - 5).clamp(0, 100).toDouble();

  bool get _askRidden {
    final ended = widget.endedAt;
    return ended != null &&
        DateTime.now().difference(ended) > ConfirmActualSocSheet.askRiddenAfter;
  }

  bool get _canSave => _chosen && (!_askRidden || _ridden != null);

  @override
  void initState() {
    super.initState();
    _soc = (widget.estimatedSoc ?? widget.startSoc).roundToDouble().clamp(
      _minimum,
      100.0,
    );
  }

  @override
  void dispose() {
    _odo.dispose();
    super.dispose();
  }

  void _set(double value) {
    final next = value.clamp(_minimum, 100.0).roundToDouble();
    if (next != _soc) HapticFeedback.selectionClick();
    setState(() {
      _soc = next;
      _chosen = true;
    });
  }

  /// Fill % and ODO from a dashboard photo read on the phone.
  Future<void> _readPhoto() async {
    setState(() {
      _reading = true;
      _readNote = null;
    });
    try {
      final injected = widget.reader;
      final scan = injected != null
          ? injected(camera: true)
          : scanDashboard(context, lastOdoKm: widget.currentOdoKm);
      final result = await scan;
      if (!mounted || result == null) return;
      setState(() {
        if (result.soc != null) {
          _soc = result.soc!.toDouble().clamp(_minimum, 100.0);
          _chosen = true;
        }
        if (result.odoKm != null) {
          final km = result.odoKm!;
          _odo.text = km == km.roundToDouble()
              ? '${km.round()}'
              : km.toStringAsFixed(1);
        }
        _readNote = result.isEmpty
            ? 'Chưa đọc được số nào. Quét gần, thẳng, tránh lóa hoặc chỉnh tay.'
            : 'Đã điền số đọc từ đồng hồ. So lại với đồng hồ xe.';
      });
    } on Object {
      if (mounted) {
        setState(() => _readNote = 'Không đọc được ảnh. Hãy chỉnh tay.');
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<bool> _save() async {
    final raw = _odo.text.trim().replaceAll(',', '.').replaceAll(' ', '');
    double? odo;
    if (raw.isNotEmpty) {
      odo = double.tryParse(raw);
      final previous = widget.currentOdoKm;
      if (odo == null || !odo.isFinite || odo < 0 || odo > 999999) {
        setState(() => _odoError = 'Nhập số km từ 0 đến 999 999.');
        return false;
      }
      if (previous != null && odo < previous) {
        setState(
          () => _odoError =
              'ODO không thể nhỏ hơn lần trước (${groupThousands(previous.round())} km). '
              'Nếu lần trước nhập nhầm, sửa ở Cài đặt → Xe của tôi → Thông số chi tiết.',
        );
        return false;
      }
    }
    final reading = (soc: _soc, odoKm: odo, ridden: _ridden == true);
    final save = widget.onSave;
    if (save == null) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(reading);
      return true;
    }
    setState(() => _saveError = null);
    final error = await save(reading);
    if (!mounted) return error == null;
    if (error != null) {
      setState(() => _saveError = error);
      return false;
    }
    // The tick shows, then the sheet closes (QA 135).
    Future.delayed(const Duration(milliseconds: 950), () {
      if (mounted) Navigator.of(context).pop(reading);
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final rounded = _soc.round();
    final estimate = widget.estimatedSoc?.round();
    final chips = <int>{
      if (estimate != null)
        for (final delta in const [-4, -2, 0, 2, 4])
          (estimate + delta).clamp(_minimum.round(), 100),
      100,
    }.toList()..sort();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LuxeSheetHeader(
            eyebrow: 'Sau khi sạc',
            title: 'Đồng hồ xe đang báo bao nhiêu %?',
            caption: estimate == null
                ? 'Nhập đúng số trên xe để app học cách sạc của xe bạn.'
                : 'App ước tính khoảng $estimate%. Nhập đúng số trên xe để '
                      'lần sau chính xác hơn.',
            trailing: LuxeCircleButton(
              icon: Icons.close_rounded,
              tooltip: 'Để sau',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const ValueKey('actual-soc-photo'),
              onPressed: _reading ? null : _readPhoto,
              icon: const Icon(Icons.document_scanner_rounded),
              label: const Text('Quét đồng hồ để tự đọc'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ),
          if (_reading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_readNote != null) ...[
            const SizedBox(height: 8),
            Text(
              _readNote!,
              key: const ValueKey('actual-soc-photo-note'),
              style: LuxeText.caption.copyWith(color: LuxeColors.champagne),
            ),
          ],
          const SizedBox(height: 16),
          Center(
            child: LuxeRing(
              value: _chosen ? _soc / 100 : 0,
              size: 160,
              stroke: 9,
              color: LuxeColors.platinum,
              duration: const Duration(milliseconds: 220),
              semanticLabel: _chosen
                  ? 'Pin trên xe $rounded phần trăm'
                  : 'Chưa chọn số trên xe',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: FittedBox(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        LuxeMetalText(
                          _chosen ? '$rounded' : '—',
                          key: const ValueKey('actual-soc-value'),
                          style: const TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w200,
                            letterSpacing: -2,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const Text(
                          '%',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w300,
                            color: LuxeColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              LuxeCircleButton(
                key: const ValueKey('actual-soc-minus'),
                icon: Icons.remove_rounded,
                tooltip: 'Giảm 1%',
                onPressed: _soc > _minimum ? () => _set(_soc - 1) : null,
              ),
              Expanded(
                child: Slider(
                  value: _soc,
                  min: _minimum,
                  max: 100,
                  divisions: (100 - _minimum).round().clamp(1, 100),
                  label: '$rounded%',
                  onChanged: _set,
                ),
              ),
              LuxeCircleButton(
                key: const ValueKey('actual-soc-plus'),
                icon: Icons.add_rounded,
                tooltip: 'Tăng 1%',
                onPressed: _soc < 100 ? () => _set(_soc + 1) : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in chips)
                ChoiceChip(
                  label: Text('$value%'),
                  selected: _chosen && rounded == value,
                  onSelected: (_) => _set(value.toDouble()),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            key: const ValueKey('actual-soc-odo'),
            controller: _odo,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [LengthLimitingTextInputFormatter(8)],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            onChanged: (_) {
              if (_odoError != null) setState(() => _odoError = null);
            },
            decoration: InputDecoration(
              labelText: 'Số ODO trên xe (không bắt buộc)',
              hintText: widget.currentOdoKm == null
                  ? 'Ví dụ: 1250'
                  : 'Lần trước: ${groupThousands(widget.currentOdoKm!.round())} km',
              suffixText: 'km',
              errorText: _odoError,
              // QA 143: the hint where to fix a wrong ODO is two lines.
              errorMaxLines: 3,
            ),
          ),
          if (_askRidden) ...[
            const SizedBox(height: 16),
            const Text(
              'Từ lúc rút sạc, xe đã chạy chưa?',
              style: TextStyle(color: LuxeColors.text, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const ValueKey('actual-soc-not-ridden'),
                  label: const Text('Chưa chạy'),
                  selected: _ridden == false,
                  onSelected: (_) => setState(() => _ridden = false),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
                ChoiceChip(
                  key: const ValueKey('actual-soc-ridden'),
                  label: const Text('Đã chạy'),
                  selected: _ridden == true,
                  onSelected: (_) => setState(() => _ridden = true),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
              ],
            ),
            if (_ridden == true) ...[
              const SizedBox(height: 8),
              const Text(
                'Số này vẫn được lưu nhưng không dùng để học, vì pin đã giảm '
                'sau khi chạy.',
                key: ValueKey('actual-soc-ridden-note'),
                style: LuxeText.caption,
              ),
            ],
          ],
          const SizedBox(height: 14),
          const LuxeNotice(
            icon: Icons.school_rounded,
            color: LuxeColors.steel,
            message:
                'Không nhập cũng được, xe vẫn tự ngắt. Xe không có kết nối pin, '
                'nên số bạn đọc trên đồng hồ giúp lần sau ngắt sát mục tiêu '
                'hơn. ODO giúp dự đoán quãng đường cho từng % pin.',
          ),
          const SizedBox(height: 18),
          if (_saveError != null) ...[
            LuxeNotice(
              key: const ValueKey('actual-soc-error'),
              icon: Icons.error_outline_rounded,
              color: LuxeColors.danger,
              message: _saveError!,
            ),
            const SizedBox(height: 12),
          ],
          LuxeSubmitButton(
            key: const ValueKey('actual-soc-save'),
            label: _chosen ? 'Lưu $rounded%' : 'Chọn số trên xe',
            busyLabel: 'Đang lưu…',
            doneLabel: 'Đã lưu $rounded%',
            onPressed: _reading || !_canSave ? null : _save,
            onBusyChanged: (busy) => setState(() => _saving = busy),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text('Để sau'),
          ),
        ],
      ),
    );
  }
}
