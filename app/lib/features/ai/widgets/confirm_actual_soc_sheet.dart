import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/widgets/luxe_kit.dart';
import '../dashboard_scan_screen.dart';
import 'battery_reading_sheet.dart';

/// What the user read on the scooter after a charge (Task 126).
typedef ActualSocReading = ({double soc, double? odoKm});

/// "Đồng hồ xe đang báo bao nhiêu %?" — the scooter has no BMS link, so the
/// number on its display is the only ground truth the charge model can learn
/// from. Pre-filled with the estimate; ODO is optional (it teaches km per %).
class ConfirmActualSocSheet extends StatefulWidget {
  const ConfirmActualSocSheet({
    super.key,
    required this.estimatedSoc,
    required this.startSoc,
    this.currentOdoKm,
    this.reader,
  });

  final double? estimatedSoc;
  final double startSoc;
  final double? currentOdoKm;

  /// Dashboard photo reader (Task 127); injectable for tests.
  final DashboardReadFn? reader;

  static Future<ActualSocReading?> show(
    BuildContext context, {
    required double? estimatedSoc,
    required double startSoc,
    double? currentOdoKm,
    DashboardReadFn? reader,
  }) => showLuxeSheet<ActualSocReading>(
    context,
    builder: (_) => ConfirmActualSocSheet(
      estimatedSoc: estimatedSoc,
      startSoc: startSoc,
      currentOdoKm: currentOdoKm,
      reader: reader,
    ),
  );

  @override
  State<ConfirmActualSocSheet> createState() => _ConfirmActualSocSheetState();
}

class _ConfirmActualSocSheetState extends State<ConfirmActualSocSheet> {
  late double _soc;
  final _odo = TextEditingController();
  String? _odoError;
  bool _reading = false;
  String? _readNote;

  double get _minimum => (widget.startSoc - 5).clamp(0, 100).toDouble();

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
    setState(() => _soc = next);
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

  void _save() {
    final raw = _odo.text.trim().replaceAll(',', '.').replaceAll(' ', '');
    double? odo;
    if (raw.isNotEmpty) {
      odo = double.tryParse(raw);
      final previous = widget.currentOdoKm;
      if (odo == null || !odo.isFinite || odo < 0 || odo > 500000) {
        setState(() => _odoError = 'Nhập số km từ 0 đến 500.000.');
        return;
      }
      if (previous != null && odo < previous) {
        setState(
          () => _odoError =
              'ODO không thể nhỏ hơn lần trước (${previous.round()} km).',
        );
        return;
      }
    }
    HapticFeedback.lightImpact();
    Navigator.of(context).pop((soc: _soc, odoKm: odo));
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
              icon: const Icon(Icons.document_scanner_outlined),
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
              value: _soc / 100,
              size: 160,
              stroke: 9,
              color: LuxeColors.platinum,
              duration: const Duration(milliseconds: 220),
              semanticLabel: 'Pin trên xe $rounded phần trăm',
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
                          '$rounded',
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
                            fontSize: 20,
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
                  selected: rounded == value,
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
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            onChanged: (_) {
              if (_odoError != null) setState(() => _odoError = null);
            },
            decoration: InputDecoration(
              labelText: 'Số ODO trên xe (không bắt buộc)',
              hintText: widget.currentOdoKm == null
                  ? 'Ví dụ: 1250'
                  : 'Lần trước: ${widget.currentOdoKm!.round()} km',
              suffixText: 'km',
              errorText: _odoError,
            ),
          ),
          const SizedBox(height: 14),
          const LuxeNotice(
            icon: Icons.school_outlined,
            color: LuxeColors.steel,
            message:
                'Xe không có kết nối pin, nên app học từ số bạn đọc trên đồng '
                'hồ: lần sạc sau sẽ tự ngắt sát mục tiêu hơn. ODO giúp dự '
                'đoán quãng đường cho từng % pin.',
          ),
          const SizedBox(height: 18),
          FilledButton(
            key: const ValueKey('actual-soc-save'),
            onPressed: _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            child: Text('Lưu $rounded%'),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text('Để sau'),
          ),
        ],
      ),
    );
  }
}
