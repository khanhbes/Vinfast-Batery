import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/widgets/charge_confirm_control.dart';
import '../../../core/widgets/luxe_kit.dart';
import '../../../core/widgets/luxe_submit_button.dart';

/// Change the target while charging (QA 135, Pro). Lower: a plain button,
/// the server cuts at the new target. Higher: the owner confirms the way
/// they switch charging ON (it charges longer and the outlet's safety
/// ceiling is extended), and the server keeps the old target if it cannot
/// verify the new ceiling. Stop is never behind this sheet.
class EditTargetSheet extends StatefulWidget {
  const EditTargetSheet({
    super.key,
    required this.currentSoc,
    required this.currentTarget,
    required this.onSubmit,
    this.initialTarget,
  });

  final double currentSoc;
  final double currentTarget;

  /// Suggested by Pinova Bot; the owner still confirms.
  final int? initialTarget;

  /// The server's refusal message, or null when the new target is set.
  final Future<String?> Function(double target) onSubmit;

  static Future<bool?> show(
    BuildContext context, {
    required double currentSoc,
    required double currentTarget,
    required Future<String?> Function(double target) onSubmit,
    int? initialTarget,
  }) => showLuxeSheet<bool>(
    context,
    builder: (_) => EditTargetSheet(
      currentSoc: currentSoc,
      currentTarget: currentTarget,
      onSubmit: onSubmit,
      initialTarget: initialTarget,
    ),
  );

  @override
  State<EditTargetSheet> createState() => _EditTargetSheetState();
}

class _EditTargetSheetState extends State<EditTargetSheet> {
  late final int _min = (widget.currentSoc.floor() + 2).clamp(1, 100);
  late int _target = (widget.initialTarget ?? widget.currentTarget.round())
      .clamp(_min, 100);
  bool _busy = false;
  bool _done = false;
  String? _error;

  int get _old => widget.currentTarget.round();
  bool get _raising => _target > _old;

  Future<bool> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final message = await widget.onSubmit(_target.toDouble());
    if (!mounted) return message == null;
    if (message != null) {
      setState(() {
        _busy = false;
        _error = message;
      });
      return false;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _busy = false;
      _done = true;
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) Navigator.of(context).pop(true);
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final presets = [
      for (final p in const [80, 85, 90, 95, 100])
        if (p >= _min) p,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LuxeSheetHeader(
              eyebrow: 'Đang sạc · ước tính ${widget.currentSoc.round()}%',
              title: 'Đổi mục tiêu sạc',
              caption: 'Mục tiêu hiện tại $_old%',
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                '$_target%',
                key: const ValueKey('edit-target-value'),
                style: TextStyle(
                  color: _raising
                      ? LuxeColors.champagne
                      : _target < _old
                      ? LuxeColors.steel
                      : LuxeColors.text,
                  fontSize: 46,
                  fontWeight: FontWeight.w300,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Slider(
              key: const ValueKey('edit-target-slider'),
              value: _target.toDouble(),
              min: _min.toDouble(),
              max: 100,
              divisions: (100 - _min).clamp(1, 100),
              label: '$_target%',
              onChanged: _busy || _done
                  ? null
                  : (v) => setState(() {
                      _target = v.round();
                      _error = null;
                    }),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final p in presets)
                  ChoiceChip(
                    label: Text('$p%'),
                    selected: _target == p,
                    onSelected: _busy || _done
                        ? null
                        : (_) => setState(() {
                            _target = p;
                            _error = null;
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              LuxeNotice(
                key: const ValueKey('edit-target-error'),
                icon: Icons.error_outline_rounded,
                color: LuxeColors.danger,
                message: _error!,
              ),
              const SizedBox(height: 12),
            ],
            if (_target == _old)
              const LuxeNotice(message: 'Chọn mức khác để đổi mục tiêu.')
            else if (_raising) ...[
              const LuxeNotice(
                icon: Icons.shield_outlined,
                color: LuxeColors.champagne,
                message:
                    'Sạc lâu hơn: máy chủ gia hạn giới hạn an toàn của ổ (vẫn '
                    'kiểm tra điện áp, dòng, nhiệt độ) rồi mới nhận mục tiêu '
                    'mới. Dừng sạc luôn bấm được.',
              ),
              const SizedBox(height: 14),
              if (_busy || _done)
                _Progress(done: _done, label: 'Đang gia hạn giới hạn an toàn…')
              else
                ChargeConfirmControl(
                  key: ValueKey('edit-target-raise-$_target'),
                  label: 'Vuốt để sạc đến $_target%',
                  onConfirmed: _submit,
                ),
            ] else
              LuxeSubmitButton(
                key: const ValueKey('edit-target-lower'),
                label: 'Đổi mục tiêu còn $_target%',
                busyLabel: 'Đang cập nhật…',
                doneLabel: 'Đã đổi mục tiêu',
                icon: Icons.south_rounded,
                onPressed: _submit,
              ),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.label});
  final bool done;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey(done ? 'edit-target-done' : 'edit-target-busy'),
    height: 60,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(99),
      color: done
          ? LuxeColors.emerald.withValues(alpha: 0.15)
          : LuxeColors.glass,
      border: Border.all(
        color: done
            ? LuxeColors.emerald.withValues(alpha: 0.6)
            : LuxeColors.hairline,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (done)
          const Icon(Icons.check_circle_rounded, color: LuxeColors.emerald)
        else
          SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: LuxeColors.champagne,
              value: luxeReduceMotion(context) ? 0.7 : null,
            ),
          ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            done ? 'Đã đổi mục tiêu' : label,
            style: const TextStyle(color: LuxeColors.text, fontSize: 15),
          ),
        ),
      ],
    ),
  );
}
