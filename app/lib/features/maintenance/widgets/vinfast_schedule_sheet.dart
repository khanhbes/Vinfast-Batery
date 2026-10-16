import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../data/models/maintenance_task_model.dart';
import '../vinfast_service_catalog.dart';

/// One proposed milestone from the VinFast service book.
class ScheduleProposal {
  const ScheduleProposal(this.preset, this.targetOdo, this.alreadyOpen);
  final VinFastServicePreset preset;
  final int targetOdo;

  /// An open task of this type exists: proposed but unticked by default.
  final bool alreadyOpen;
}

/// Next multiple of each preset's interval above [currentOdo].
List<ScheduleProposal> proposeSchedule(
  int currentOdo,
  List<MaintenanceTaskModel> existing,
) {
  final openTypes = {
    for (final t in existing)
      if (!t.isCompleted) t.serviceType,
  };
  return [
    for (final p in VinFastServiceCatalog.presets)
      ScheduleProposal(
        p,
        ((currentOdo ~/ p.suggestedOdoInterval) + 1) * p.suggestedOdoInterval,
        openTypes.contains(p.type),
      ),
  ];
}

/// Preview → tick → create. Nothing is written until the user confirms.
abstract final class VinFastScheduleSheet {
  static Future<int?> show(
    BuildContext context, {
    required int currentOdo,
    required List<MaintenanceTaskModel> existing,
    required Future<void> Function(List<ScheduleProposal> picked) onCreate,
  }) => showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (context) => Theme(
      data: LuxeTheme.of(context),
      child: _Sheet(
        proposals: proposeSchedule(currentOdo, existing),
        currentOdo: currentOdo,
        onCreate: onCreate,
      ),
    ),
  );
}

class _Sheet extends StatefulWidget {
  const _Sheet({
    required this.proposals,
    required this.currentOdo,
    required this.onCreate,
  });
  final List<ScheduleProposal> proposals;
  final int currentOdo;
  final Future<void> Function(List<ScheduleProposal>) onCreate;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  late final Set<int> _picked = {
    for (var i = 0; i < widget.proposals.length; i++)
      if (!widget.proposals[i].alreadyOpen) i,
  };
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    if (_picked.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    try {
      final picked = [
        for (final i in _picked.toList()..sort()) widget.proposals[i],
      ];
      await widget.onCreate(picked);
      if (mounted) Navigator.of(context).pop(picked.length);
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Chưa tạo được lịch. Kiểm tra kết nối rồi thử lại.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<int>>{};
    for (var i = 0; i < widget.proposals.length; i++) {
      groups.putIfAbsent(widget.proposals[i].preset.group, () => []).add(i);
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0C0D0F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: LuxeColors.hairline)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: LuxeColors.hairlineStrong,
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                children: [
                  const Text('SỔ TAY VINFAST', style: LuxeText.eyebrow),
                  const SizedBox(height: 6),
                  const Text('Tạo lịch chuẩn', style: LuxeText.title),
                  const SizedBox(height: 6),
                  Text(
                    'Mốc kế tiếp của từng hạng mục, tính từ ODO hiện tại ${widget.currentOdo} km. Bỏ chọn mục bạn không muốn tạo.',
                    style: LuxeText.body,
                  ),
                  if (widget.currentOdo == 0) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'ODO đang là 0 km. Nếu xe đã chạy, hãy cập nhật ODO trước để mốc không bị sớm.',
                      style: TextStyle(
                        color: LuxeColors.champagne,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                  for (final entry in groups.entries) ...[
                    const SizedBox(height: 18),
                    Text(
                      entry.key.toUpperCase(),
                      style: LuxeText.label.copyWith(letterSpacing: 1.4),
                    ),
                    const SizedBox(height: 8),
                    for (final i in entry.value) _row(i),
                  ],
                ],
              ),
            ),
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0x0FFFFFFF))),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: LuxeColors.danger,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _picked.isEmpty || _busy ? null : _create,
                          child: _busy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF2A2C30),
                                  ),
                                )
                              : Text(
                                  _picked.isEmpty
                                      ? 'Chọn ít nhất một hạng mục'
                                      : 'Tạo ${_picked.length} mốc bảo dưỡng',
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(int i) {
    final p = widget.proposals[i];
    final on = _picked.contains(i);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        checked: on,
        label: '${p.preset.title}, mốc ${p.targetOdo} km',
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _busy
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    setState(() => on ? _picked.remove(i) : _picked.add(i));
                  },
            child: LuxeGlass(
              selected: on,
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.preset.title,
                          style: const TextStyle(
                            color: LuxeColors.text,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (p.preset.subtitle != null) p.preset.subtitle!,
                            'mỗi ${p.preset.suggestedOdoInterval} km',
                            if (p.alreadyOpen) 'đã có mốc đang mở',
                          ].join(' · '),
                          style: LuxeText.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${p.targetOdo} km',
                    style: TextStyle(
                      color: on ? LuxeColors.emerald : LuxeColors.muted,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    on
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    color: on ? LuxeColors.emerald : LuxeColors.dim,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
