import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/theme/plan_style.dart';
import '../../../core/utils/number_text.dart';
import '../../../core/widgets/luxe_kit.dart';
import '../../../core/widgets/luxe_submit_button.dart';
import '../../../data/models/maintenance_task_model.dart';
import '../vinfast_service_catalog.dart';

/// The periodic visit the service book asks for next (QA 155).
class VisitProposal {
  const VisitProposal({
    required this.milestones,
    required this.currentOdo,
    this.open,
    this.suggestedDate,
  });

  /// One milestone, or two when the first is already behind the odometer
  /// (the owner says which one they are planning).
  final List<int> milestones;
  final int currentOdo;

  /// An open periodic visit already exists: nothing to create.
  final MaintenanceTaskModel? open;

  /// The date the book pairs with the first milestone, known only from a
  /// recorded earlier visit.
  final DateTime? suggestedDate;
}

/// QA 155: the book plans visits (1 000 km, then every 5 000 km or 6
/// months), not twenty separate items. This used to create one milestone
/// per item at intervals the book does not have.
VisitProposal proposeVisit(int currentOdo, List<MaintenanceTaskModel> existing) {
  MaintenanceTaskModel? open;
  MaintenanceTaskModel? last;
  for (final t in existing) {
    if (!VinFastSchedule.isVisit(t)) continue;
    if (!t.isCompleted) {
      if (open == null || t.targetOdo < open.targetOdo) open = t;
    } else if (last == null || _doneOdo(t) > _doneOdo(last)) {
      last = t;
    }
  }
  final first = VinFastSchedule.proposed(
    currentOdo: currentOdo,
    lastDoneOdo: last == null ? null : _doneOdo(last),
  );
  final lastDate = last?.completedDate?.toLocal();
  return VisitProposal(
    milestones: [
      first,
      if (first <= currentOdo) VinFastSchedule.after(first),
    ],
    currentOdo: currentOdo,
    open: open,
    suggestedDate: last == null || lastDate == null
        ? null
        : VinFastSchedule.addMonths(
            lastDate,
            VinFastSchedule.monthsToNext(
              VinFastSchedule.nearest(_doneOdo(last)),
            ),
          ),
  );
}

int _doneOdo(MaintenanceTaskModel t) => t.completedOdo ?? t.targetOdo;

/// What the sheet hands back to be saved.
typedef VisitDraft = ({int milestone, DateTime? date});

abstract final class VinFastScheduleSheet {
  /// Preview, then create one milestone. Nothing is written until the
  /// owner confirms. Returns the created milestone, or null.
  static Future<int?> show(
    BuildContext context, {
    required int currentOdo,
    required List<MaintenanceTaskModel> existing,
    required Future<String?> Function(VisitDraft draft) onCreate,
    DateTime Function()? now,
  }) => showLuxeSheet<int>(
    context,
    builder: (_) => VisitSheet(
      proposal: proposeVisit(currentOdo, existing),
      onCreate: onCreate,
      now: now,
    ),
  );

  /// The list of work of one visit, read only (at the garage).
  static Future<void> showChecklist(
    BuildContext context, {
    required int milestone,
  }) => showLuxeSheet<void>(
    context,
    builder: (_) => VisitSheet(
      proposal: VisitProposal(milestones: [milestone], currentOdo: 0),
      readOnly: true,
    ),
  );
}

class VisitSheet extends StatefulWidget {
  const VisitSheet({
    super.key,
    required this.proposal,
    this.onCreate,
    this.readOnly = false,
    this.now,
  });

  final VisitProposal proposal;
  final bool readOnly;
  final DateTime Function()? now;

  /// Saves; returns the reason when it failed (the sheet stays open).
  final Future<String?> Function(VisitDraft draft)? onCreate;

  @override
  State<VisitSheet> createState() => _VisitSheetState();
}

class _VisitSheetState extends State<VisitSheet> {
  late int _milestone = widget.proposal.milestones.first;
  late DateTime? _date = widget.proposal.suggestedDate;
  String? _error;

  DateTime get _today {
    final now = (widget.now ?? DateTime.now)();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDate() async {
    final first = _today.subtract(const Duration(days: 30));
    final last = _today.add(const Duration(days: 365 * 2));
    final initial = _date ?? _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first)
          ? first
          : initial.isAfter(last)
          ? last
          : initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Ngày hẹn',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<bool> _create() async {
    setState(() => _error = null);
    final error = await widget.onCreate!((milestone: _milestone, date: _date));
    if (!mounted) return error == null;
    if (error != null) {
      setState(() => _error = error);
      return false;
    }
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) Navigator.of(context).pop(_milestone);
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.proposal;
    final open = widget.readOnly ? null : p.open;
    final canCreate = !widget.readOnly && open == null;
    final work = VinFastSchedule.workAt(_milestone);
    final groups = <String, List<VisitWork>>{};
    for (final w in work) {
      groups.putIfAbsent(w.preset.group, () => []).add(w);
    }
    final behind = p.currentOdo - _milestone;
    final first = _milestone < VinFastSchedule.intervalKm;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LuxeSheetHeader(
              eyebrow: 'Sổ tay VinFast',
              title: VinFastSchedule.visitTitle(_milestone),
              caption:
                  'Mốc ${groupThousands(_milestone)} km hoặc tháng thứ '
                  '${VinFastSchedule.monthOf(_milestone)} kể từ khi mua xe, '
                  'điều kiện nào đến trước.',
            ),
            if (canCreate && p.milestones.length > 1) ...[
              const SizedBox(height: 14),
              Text(
                'Xe đang ở ${groupThousands(p.currentOdo)} km, đã qua mốc '
                '${groupThousands(p.milestones.first)} km. Bạn lên lịch cho '
                'lần nào?',
                style: LuxeText.body,
              ),
              const SizedBox(height: 10),
              for (final m in p.milestones)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _MilestoneChoice(
                    key: ValueKey('visit-choice-$m'),
                    selected: m == _milestone,
                    title: 'Mốc ${groupThousands(m)} km',
                    caption: m <= p.currentOdo
                        ? 'Chưa làm, đã qua ${groupThousands(p.currentOdo - m)} km'
                        : 'Đã làm mốc trước, còn ${groupThousands(m - p.currentOdo)} km',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _milestone = m);
                    },
                  ),
                ),
            ] else if (canCreate && p.currentOdo > 0 && behind < 0) ...[
              const SizedBox(height: 10),
              Text(
                'Xe đang ở ${groupThousands(p.currentOdo)} km, còn '
                '${groupThousands(-behind)} km.',
                style: LuxeText.body,
              ),
            ],
            if (!widget.readOnly && p.currentOdo == 0) ...[
              const SizedBox(height: 10),
              const LuxeNotice(
                icon: Icons.speed_rounded,
                color: LuxeColors.champagne,
                message:
                    'Chưa có số ODO của xe. Nếu xe đã chạy, hãy cập nhật ODO '
                    'trước để chọn đúng mốc.',
              ),
            ],
            if (open != null) ...[
              const SizedBox(height: 12),
              LuxeNotice(
                key: const ValueKey('visit-open'),
                message:
                    'Đã có "${open.title}" đang mở. Đánh dấu đã làm xong thì '
                    'app đề xuất mốc kế tiếp.',
              ),
            ],
            if (canCreate) ...[
              const SizedBox(height: 14),
              Semantics(
                button: true,
                label: _date == null
                    ? 'Ngày hẹn, chưa chọn'
                    : 'Ngày hẹn ${DateFormat('dd/MM/yyyy').format(_date!)}',
                excludeSemantics: true,
                child: InkWell(
                  key: const ValueKey('visit-date'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Ngày hẹn (không bắt buộc)',
                      prefixIcon: const Icon(Icons.event_rounded, size: 20),
                      helperText: p.suggestedDate != null
                          ? '${VinFastSchedule.intervalMonths} tháng sau lần '
                                'bảo dưỡng trước. Bạn đổi được.'
                          : 'Chọn ngày nếu bạn muốn được nhắc cả theo ngày.',
                      helperMaxLines: 3,
                    ),
                    child: Text(
                      _date == null
                          ? 'Chưa chọn'
                          : DateFormat('dd/MM/yyyy').format(_date!),
                      style: TextStyle(
                        color: _date == null
                            ? LuxeColors.muted
                            : LuxeColors.text,
                        fontSize: 15.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              first
                  ? 'LẦN ĐẦU · ${work.length} HẠNG MỤC'
                  : '${work.length} HẠNG MỤC Ở LẦN NÀY',
              style: LuxeText.label.copyWith(letterSpacing: 1.4),
            ),
            for (final entry in groups.entries) ...[
              const SizedBox(height: 14),
              Text(entry.key, style: LuxeText.caption),
              const SizedBox(height: 2),
              for (final w in entry.value) _WorkRow(work: w, first: first),
            ],
            const SizedBox(height: 14),
            const Text(
              'Theo ${VinFastSchedule.source}. Dòng xe khác có thể khác đôi '
              'chút, hãy đối chiếu sổ của xe bạn. Sổ tay khuyên làm sớm hơn '
              'khi thường đi đường ẩm ướt, bụi, ngập nước, dốc hoặc đường xấu.',
              style: LuxeText.caption,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              LuxeNotice(
                icon: Icons.error_outline_rounded,
                color: LuxeColors.danger,
                message: _error!,
              ),
            ],
            if (canCreate) ...[
              const SizedBox(height: 14),
              LuxeSubmitButton(
                key: const ValueKey('visit-create'),
                label: 'Tạo mốc ${groupThousands(_milestone)} km',
                busyLabel: 'Đang tạo',
                icon: Icons.add_rounded,
                onPressed: _create,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MilestoneChoice extends StatelessWidget {
  const _MilestoneChoice({
    super.key,
    required this.selected,
    required this.title,
    required this.caption,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$title. $caption',
    excludeSemantics: true,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: LuxeGlass(
          selected: selected,
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: LuxeColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(caption, style: LuxeText.caption),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? context.planAccent : LuxeColors.dim,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _WorkRow extends StatelessWidget {
  const _WorkRow({required this.work, required this.first});
  final VisitWork work;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final note = work.preset.from5kNote;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: LuxeColors.glass)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  work.preset.title,
                  style: const TextStyle(
                    color: LuxeColors.text,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
                if (note != null && !first)
                  Text('Gồm cả $note', style: LuxeText.caption),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              work.action,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: LuxeColors.muted,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
