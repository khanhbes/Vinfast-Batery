import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/luxe_theme.dart';
import '../theme/plan_style.dart';
import 'luxe_kit.dart';

/// A 24-hour time picker in the LUXE language (QA 150, owner's choice): the
/// Material dialog was the one screen that did not look like the app. Two
/// wheels in a sheet; returns null when dismissed.
Future<TimeOfDay?> showLuxeTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
  String title = 'Chọn giờ',
}) => showLuxeSheet<TimeOfDay>(
  context,
  builder: (_) => _LuxeTimeSheet(initial: initialTime, title: title),
);

class _LuxeTimeSheet extends StatefulWidget {
  const _LuxeTimeSheet({required this.initial, required this.title});

  final TimeOfDay initial;
  final String title;

  @override
  State<_LuxeTimeSheet> createState() => _LuxeTimeSheetState();
}

class _LuxeTimeSheetState extends State<_LuxeTimeSheet> {
  late int _hour = widget.initial.hour;
  late int _minute = widget.initial.minute;
  late final _hours = FixedExtentScrollController(initialItem: _hour);
  late final _minutes = FixedExtentScrollController(initialItem: _minute);

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final accent = context.planAccent;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title.toUpperCase(), style: LuxeText.eyebrow),
            const SizedBox(height: 6),
            Semantics(
              liveRegion: true,
              child: Text(
                '${_two(_hour)}:${_two(_minute)}',
                key: const ValueKey('luxe-time-value'),
                style: LuxeText.title.copyWith(
                  fontSize: 28,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 168,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  IgnorePointer(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: LuxeColors.glass,
                        border: Border.all(
                          color: accent.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _Wheel(
                          key: const ValueKey('luxe-time-hour'),
                          controller: _hours,
                          count: 24,
                          selected: _hour,
                          semanticsLabel: 'Giờ',
                          onChanged: (v) => setState(() => _hour = v),
                        ),
                      ),
                      const ExcludeSemantics(
                        child: Text(':', style: LuxeText.title),
                      ),
                      Expanded(
                        child: _Wheel(
                          key: const ValueKey('luxe-time-minute'),
                          controller: _minutes,
                          count: 60,
                          selected: _minute,
                          semanticsLabel: 'Phút',
                          onChanged: (v) => setState(() => _minute = v),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text('Hủy'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('luxe-time-confirm'),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(TimeOfDay(hour: _hour, minute: _minute)),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text('Chọn'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Wheel extends StatelessWidget {
  const _Wheel({
    super.key,
    required this.controller,
    required this.count,
    required this.selected,
    required this.semanticsLabel,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final int count;
  final int selected;
  final String semanticsLabel;
  final ValueChanged<int> onChanged;

  void _step(int by) {
    final next = (selected + by) % count;
    controller.jumpToItem(next < 0 ? next + count : next);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    value: selected.toString().padLeft(2, '0'),
    increasedValue: ((selected + 1) % count).toString().padLeft(2, '0'),
    decreasedValue: ((selected - 1 + count) % count).toString().padLeft(2, '0'),
    onIncrease: () => _step(1),
    onDecrease: () => _step(-1),
    child: ExcludeSemantics(
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 48,
        physics: const FixedExtentScrollPhysics(),
        perspective: 0.003,
        diameterRatio: 1.6,
        onSelectedItemChanged: (index) {
          HapticFeedback.selectionClick();
          onChanged(index % count);
        },
        childDelegate: ListWheelChildLoopingListDelegate(
          children: [
            for (var i = 0; i < count; i++)
              Center(
                child: Text(
                  i.toString().padLeft(2, '0'),
                  style: LuxeText.title.copyWith(
                    fontSize: 22,
                    color: i == selected ? LuxeColors.text : LuxeColors.dim,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
