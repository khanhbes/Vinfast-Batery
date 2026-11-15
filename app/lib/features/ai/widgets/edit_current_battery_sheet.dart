import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/utils/number_text.dart';
import '../../../core/widgets/luxe_kit.dart';
import '../../../core/theme/plan_style.dart';

/// Modal bottom sheet to let the user adjust the current battery percentage
/// when the vehicle or BMS is not automatically synchronizing telemetry.
class EditCurrentBatterySheet extends StatefulWidget {
  const EditCurrentBatterySheet({
    super.key,
    required this.initialPercent,
    required this.onSave,
    this.savedNote,
    this.scan,
    this.scanReading,
    this.onOdo,
    this.lastOdoKm,
  });

  final double initialPercent;
  final ValueChanged<double> onSave;

  /// QA 148: asking before a charge, because the saved number may be old.
  final String? savedNote;

  /// Reads the % from the dashboard; null when the caller has no scan.
  final Future<int?> Function()? scan;

  /// QA 158: reads both numbers; preferred over [scan] when given.
  final Future<({int? soc, double? odoKm})?> Function()? scanReading;

  /// QA 158: the odometer before a charge, optional. The field shows only
  /// when this is given.
  final ValueChanged<double?>? onOdo;
  final double? lastOdoKm;

  static Future<void> show(
    BuildContext context, {
    required double initialPercent,
    required ValueChanged<double> onSave,
    String? savedNote,
    Future<int?> Function()? scan,
    Future<({int? soc, double? odoKm})?> Function()? scanReading,
    ValueChanged<double?>? onOdo,
    double? lastOdoKm,
  }) => showLuxeSheet<void>(
    context,
    builder: (_) => EditCurrentBatterySheet(
      initialPercent: initialPercent,
      onSave: onSave,
      savedNote: savedNote,
      scan: scan,
      scanReading: scanReading,
      onOdo: onOdo,
      lastOdoKm: lastOdoKm,
    ),
  );

  @override
  State<EditCurrentBatterySheet> createState() =>
      _EditCurrentBatterySheetState();
}

class _EditCurrentBatterySheetState extends State<EditCurrentBatterySheet> {
  late double _soc;
  bool _scanning = false;
  final _odo = TextEditingController();
  String? _odoError;

  @override
  void dispose() {
    _odo.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _soc = widget.initialPercent.clamp(0.0, 100.0);
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      if (widget.scanReading != null) {
        final both = await widget.scanReading!();
        if (!mounted || both == null) return;
        if (both.soc != null) _updateSoc(both.soc!.toDouble());
        if (both.odoKm != null && widget.onOdo != null) {
          setState(() => _odo.text = '${both.odoKm!.round()}');
        }
        return;
      }
      final read = await widget.scan!();
      if (mounted && read != null) _updateSoc(read.toDouble());
    } on Object {
      // The owner can still set it by hand.
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// The typed or scanned ODO, checked; false keeps the sheet open.
  bool _saveOdo() {
    final digits = _odo.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      widget.onOdo!(null);
      return true;
    }
    final odo = double.tryParse(digits);
    final last = widget.lastOdoKm;
    String? error;
    if (odo == null || odo > 999999) {
      error = 'Nhập số km trên đồng hồ (0 đến 999 999), hoặc để trống.';
    } else if (last != null && odo < last - 1) {
      error =
          'Nhỏ hơn ODO đã lưu (${groupThousands(last.round())} km). Kiểm tra '
          'lại, hoặc để trống.';
    }
    setState(() => _odoError = error);
    if (error != null) return false;
    widget.onOdo!(odo);
    return true;
  }

  void _updateSoc(double val) {
    final next = val.clamp(0.0, 100.0);
    if ((next.round() - _soc.round()).abs() >= 1) {
      HapticFeedback.selectionClick();
    }
    setState(() => _soc = next);
  }

  @override
  Widget build(BuildContext context) {
    final rounded = _soc.round();
    final accent = LuxeColors.level(rounded, context.planAccent);

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
            eyebrow: widget.savedNote == null
                ? 'Pin hiện tại'
                : 'Trước khi sạc',
            title: widget.savedNote == null
                ? 'Chỉnh mức pin hiện tại'
                : 'Đồng hồ xe đang báo bao nhiêu %?',
            caption:
                'Điều chỉnh mức pin thực tế nếu xe chưa đồng bộ với ứng dụng',
            trailing: LuxeCircleButton(
              icon: Icons.close_rounded,
              tooltip: 'Đóng',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: LuxeRing(
              value: _soc / 100,
              size: 172,
              stroke: 9,
              color: accent,
              duration: const Duration(milliseconds: 260),
              semanticLabel: 'Mức pin $rounded phần trăm',
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
          if (widget.savedNote != null) ...[
            const SizedBox(height: 12),
            Text(
              widget.savedNote!,
              key: const ValueKey('start-soc-saved-note'),
              style: LuxeText.caption.copyWith(color: LuxeColors.champagne),
            ),
          ],
          if (widget.onOdo != null) ...[
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('start-odo'),
              controller: _odo,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 .]')),
                LengthLimitingTextInputFormatter(9),
              ],
              style: const TextStyle(color: LuxeColors.text, fontSize: 15.5),
              decoration: InputDecoration(
                labelText: 'ODO trên đồng hồ (km, không bắt buộc)',
                prefixIcon: const Icon(Icons.speed_rounded, size: 20),
                helperText: widget.lastOdoKm == null
                    ? 'Giúp app đối chiếu đồng hồ pin theo số km đã chạy.'
                    : 'Lần gần nhất ${groupThousands(widget.lastOdoKm!.round())} km.',
                helperMaxLines: 2,
                errorText: _odoError,
                errorMaxLines: 2,
              ),
            ),
          ],
          if (widget.scan != null || widget.scanReading != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: const ValueKey('start-soc-scan'),
                onPressed: _scanning ? null : _scan,
                icon: const Icon(Icons.document_scanner_rounded),
                label: const Text('Quét đồng hồ để tự đọc'),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              LuxeCircleButton(
                icon: Icons.remove_rounded,
                tooltip: 'Giảm 1%',
                onPressed: rounded > 0 ? () => _updateSoc(_soc - 1) : null,
              ),
              Expanded(
                child: Slider(
                  value: _soc,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '$rounded%',
                  onChanged: _updateSoc,
                ),
              ),
              LuxeCircleButton(
                icon: Icons.add_rounded,
                tooltip: 'Tăng 1%',
                onPressed: rounded < 100 ? () => _updateSoc(_soc + 1) : null,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in const [20, 35, 50, 75, 80])
                _PresetPill(
                  label: '$preset%',
                  selected: rounded == preset,
                  onTap: () => _updateSoc(preset.toDouble()),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const LuxeNotice(
            icon: Icons.edit_note_rounded,
            color: LuxeColors.champagne,
            message:
                'Mức pin bạn nhập là ước tính, dùng cho dự đoán sạc cho tới khi có dữ liệu đo thật.',
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('start-soc-confirm'),
            onPressed: () {
              if (widget.onOdo != null && !_saveOdo()) return;
              HapticFeedback.lightImpact();
              widget.onSave(_soc.roundToDouble());
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            child: Text(
              widget.savedNote != null &&
                      rounded == widget.initialPercent.round()
                  ? 'Đúng số trên xe'
                  : 'Xác nhận mức pin',
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetPill extends StatelessWidget {
  const _PresetPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: luxeDuration(context, 220),
          curve: LuxeMotion.enter,
          constraints: const BoxConstraints(minHeight: 48, minWidth: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: selected
                ? context.planAccent.withValues(alpha: 0.14)
                : LuxeColors.glass,
            border: Border.all(
              color: selected
                  ? context.planAccent.withValues(alpha: 0.7)
                  : LuxeColors.hairline,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? LuxeColors.text : LuxeColors.muted,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    ),
  );
}
