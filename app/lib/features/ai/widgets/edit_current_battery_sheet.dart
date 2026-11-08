import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
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
  });

  final double initialPercent;
  final ValueChanged<double> onSave;

  /// QA 148: asking before a charge, because the saved number may be old.
  final String? savedNote;

  /// Reads the % from the dashboard; null when the caller has no scan.
  final Future<int?> Function()? scan;

  static Future<void> show(
    BuildContext context, {
    required double initialPercent,
    required ValueChanged<double> onSave,
    String? savedNote,
    Future<int?> Function()? scan,
  }) => showLuxeSheet<void>(
    context,
    builder: (_) => EditCurrentBatterySheet(
      initialPercent: initialPercent,
      onSave: onSave,
      savedNote: savedNote,
      scan: scan,
    ),
  );

  @override
  State<EditCurrentBatterySheet> createState() =>
      _EditCurrentBatterySheetState();
}

class _EditCurrentBatterySheetState extends State<EditCurrentBatterySheet> {
  late double _soc;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _soc = widget.initialPercent.clamp(0.0, 100.0);
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final read = await widget.scan!();
      if (mounted && read != null) _updateSoc(read.toDouble());
    } on Object {
      // The owner can still set it by hand.
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
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
    final accent = rounded < 20
        ? LuxeColors.danger
        : rounded < 40
        ? LuxeColors.champagne
        : context.planAccent;

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
          if (widget.scan != null) ...[
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
