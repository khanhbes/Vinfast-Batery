import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/theme/plan_style.dart';
import '../../../core/widgets/charge_confirm_control.dart';
import '../../../core/widgets/luxe_kit.dart';
import '../../../core/widgets/luxe_submit_button.dart';
import '../../../data/services/charge_estimator.dart';
import 'timed_charging_section_v2.dart';

/// Move the end of a running timed charge (QA 140). Later: the owner
/// confirms the way they switch charging ON (the outlet stays on longer).
/// Sooner: a plain button. The server re-arms the outlet's timer and reads
/// it back; the old end stays if it cannot. Stop is never behind this sheet.
class EditStopAtSheet extends StatefulWidget {
  const EditStopAtSheet({
    super.key,
    required this.currentStopAt,
    required this.latestStopAt,
    required this.onSubmit,
    this.clock = DateTime.now,
  });

  final DateTime currentStopAt;

  /// The session's 10-hour limit.
  final DateTime latestStopAt;

  /// The server's refusal message, or null when the new end is set.
  final Future<String?> Function(DateTime stopAt) onSubmit;
  final DateTime Function() clock;

  static Future<bool?> show(
    BuildContext context, {
    required DateTime currentStopAt,
    required DateTime latestStopAt,
    required Future<String?> Function(DateTime stopAt) onSubmit,
  }) => showLuxeSheet<bool>(
    context,
    builder: (_) => EditStopAtSheet(
      currentStopAt: currentStopAt,
      latestStopAt: latestStopAt,
      onSubmit: onSubmit,
    ),
  );

  @override
  State<EditStopAtSheet> createState() => _EditStopAtSheetState();
}

class _EditStopAtSheetState extends State<EditStopAtSheet> {
  late DateTime _stopAt = _minute(widget.currentStopAt);
  bool _busy = false;
  bool _done = false;
  String? _error;
  Timer? _tick;

  static DateTime _minute(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour, t.minute);

  DateTime get _old => _minute(widget.currentStopAt);
  bool get _later => _stopAt.isAfter(_old);
  bool get _changed => _stopAt != _old;

  DateTime get _earliest =>
      widget.clock().add(const Duration(minutes: 2));
  DateTime get _latest => widget.latestStopAt;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _set(DateTime at) {
    var value = _minute(at);
    if (value.isBefore(_earliest)) value = _minute(_earliest);
    if (value.isAfter(_latest)) value = _minute(_latest);
    HapticFeedback.selectionClick();
    setState(() {
      _stopAt = value;
      _error = null;
    });
  }

  Future<void> _pick() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_stopAt),
      helpText: 'NGẮT LÚC',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    _set(TimedChargingSectionV2.stopAtFor(picked, widget.clock()));
  }

  Future<bool> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final message = await widget.onSubmit(_stopAt);
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
    final plan = PlanStyle.of(context);
    final now = widget.clock();
    final left = _stopAt.difference(now);
    final locked = _busy || _done;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LuxeSheetHeader(
              eyebrow: 'Đang sạc theo giờ',
              title: 'Đổi giờ ngắt',
              caption: 'Đang hẹn ngắt lúc ${formatClock(_old)}',
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _RoundButton(
                  key: const ValueKey('edit-stop-minus'),
                  icon: Icons.remove_rounded,
                  label: 'Sớm hơn 15 phút',
                  onTap: locked
                      ? null
                      : () => _set(_stopAt.subtract(const Duration(minutes: 15))),
                ),
                Expanded(
                  child: InkWell(
                    key: const ValueKey('edit-stop-picker'),
                    onTap: locked ? null : _pick,
                    borderRadius: BorderRadius.circular(18),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 72),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              formatClock(_stopAt),
                              key: const ValueKey('edit-stop-value'),
                              style: TextStyle(
                                color: _later
                                    ? LuxeColors.champagne
                                    : _changed
                                    ? LuxeColors.steel
                                    : plan.accent,
                                fontSize: 46,
                                fontWeight: FontWeight.w300,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          Text(
                            'còn ${formatChargeDuration(left)}',
                            style: LuxeText.caption,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _RoundButton(
                  key: const ValueKey('edit-stop-plus'),
                  icon: Icons.add_rounded,
                  label: 'Muộn hơn 15 phút',
                  onTap: locked
                      ? null
                      : () => _set(_stopAt.add(const Duration(minutes: 15))),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Muộn nhất ${formatClock(_latest)} (một phiên tối đa 10 giờ).',
              textAlign: TextAlign.center,
              style: LuxeText.caption,
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              LuxeNotice(
                key: const ValueKey('edit-stop-error'),
                icon: Icons.error_outline_rounded,
                color: LuxeColors.danger,
                message: _error!,
              ),
              const SizedBox(height: 12),
            ],
            if (!_changed)
              const LuxeNotice(message: 'Chọn giờ khác để đổi giờ ngắt.')
            else if (_later) ...[
              const LuxeNotice(
                icon: Icons.shield_rounded,
                color: LuxeColors.champagne,
                message:
                    'Sạc lâu hơn: máy chủ đặt lại hẹn giờ của ổ (vẫn kiểm tra '
                    'điện áp, dòng, nhiệt độ) rồi mới nhận giờ mới. Dừng sạc '
                    'luôn bấm được.',
              ),
              const SizedBox(height: 14),
              if (locked)
                _Progress(done: _done)
              else
                ChargeConfirmControl(
                  key: ValueKey('edit-stop-later-${formatClock(_stopAt)}'),
                  label: 'Vuốt để sạc đến ${formatClock(_stopAt)}',
                  onConfirmed: _submit,
                ),
            ] else
              LuxeSubmitButton(
                key: const ValueKey('edit-stop-sooner'),
                label: 'Ngắt sớm hơn, lúc ${formatClock(_stopAt)}',
                busyLabel: 'Đang đặt lại hẹn giờ…',
                doneLabel: 'Đã đổi giờ ngắt',
                icon: Icons.schedule_rounded,
                onPressed: _submit,
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final plan = PlanStyle.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Ink(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: plan.glassColors),
              border: Border.all(color: plan.glassBorder),
            ),
            child: Icon(
              icon,
              size: 22,
              color: onTap == null ? LuxeColors.dim : LuxeColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey(done ? 'edit-stop-done' : 'edit-stop-busy'),
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
            done ? 'Đã đổi giờ ngắt' : 'Đang đặt lại hẹn giờ của ổ…',
            style: const TextStyle(color: LuxeColors.text, fontSize: 15),
          ),
        ),
      ],
    ),
  );
}
