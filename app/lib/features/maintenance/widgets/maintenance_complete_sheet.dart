import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/utils/number_text.dart';
import '../../../core/widgets/luxe_kit.dart';
import '../../../core/widgets/luxe_submit_button.dart';
import '../../../data/models/maintenance_task_model.dart';

/// What the owner recorded when a service was done (QA 154).
typedef MaintenanceCompletion = ({
  int odo,
  DateTime date,
  int? costVnd,
  String? note,
});

/// "Đã làm xong": the ODO and the day the work was done, and optionally what
/// it cost and a note. Marking a task done used to keep only today's date,
/// so the next milestone was counted from the wrong place and the app had no
/// service history to show.
class MaintenanceCompleteSheet extends StatefulWidget {
  const MaintenanceCompleteSheet({
    super.key,
    required this.task,
    required this.currentOdo,
    required this.onSave,
    this.now,
  });

  final MaintenanceTaskModel task;
  final int currentOdo;
  final DateTime Function()? now;

  /// Saves; returns the reason when it failed (the sheet stays open).
  final Future<String?> Function(MaintenanceCompletion record) onSave;

  static Future<MaintenanceCompletion?> show(
    BuildContext context, {
    required MaintenanceTaskModel task,
    required int currentOdo,
    required Future<String?> Function(MaintenanceCompletion record) onSave,
  }) => showLuxeSheet<MaintenanceCompletion>(
    context,
    builder: (_) => MaintenanceCompleteSheet(
      task: task,
      currentOdo: currentOdo,
      onSave: onSave,
    ),
  );

  /// Digits only: "150.000", "150 000" and "150000" are the same amount.
  static int? parseAmount(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  @override
  State<MaintenanceCompleteSheet> createState() =>
      _MaintenanceCompleteSheetState();
}

class _MaintenanceCompleteSheetState extends State<MaintenanceCompleteSheet> {
  late final _odo = TextEditingController(
    text: widget.currentOdo > 0 ? '${widget.currentOdo}' : '',
  );
  final _cost = TextEditingController();
  final _note = TextEditingController();
  late DateTime _date = _today;
  String? _odoError;
  String? _costError;
  String? _saveError;

  DateTime get _today {
    final now = (widget.now ?? DateTime.now)();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _odo.dispose();
    _cost.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _today.subtract(const Duration(days: 365 * 3)),
      lastDate: _today,
      helpText: 'Ngày làm',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<bool> _save() async {
    final odo = MaintenanceCompleteSheet.parseAmount(_odo.text);
    final costText = _cost.text.trim();
    final cost = costText.isEmpty
        ? null
        : MaintenanceCompleteSheet.parseAmount(costText);
    String? odoError;
    String? costError;
    if (odo == null || odo <= 0 || odo > 999999) {
      odoError = 'Nhập số km trên đồng hồ lúc làm (1 đến 999 999).';
    } else if (widget.currentOdo > 0 && odo > widget.currentOdo + 50) {
      odoError =
          'Lớn hơn ODO hiện tại của xe '
          '(${groupThousands(widget.currentOdo)} km). Hãy cập nhật ODO trước.';
    }
    if (costText.isNotEmpty && (cost == null || cost > 999999999)) {
      costError = 'Nhập số tiền bằng chữ số, hoặc để trống.';
    }
    setState(() {
      _odoError = odoError;
      _costError = costError;
      _saveError = null;
    });
    if (odoError != null || costError != null) return false;
    final note = _note.text.trim();
    final MaintenanceCompletion record = (
      odo: odo!,
      date: _date,
      costVnd: cost,
      note: note.isEmpty ? null : note,
    );
    final error = await widget.onSave(record);
    if (!mounted) return error == null;
    if (error != null) {
      setState(() => _saveError = error);
      return false;
    }
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) Navigator.of(context).pop(record);
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
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
              eyebrow: 'Đã làm xong',
              title: widget.task.title,
              caption:
                  'Ghi lại để xe có sổ bảo dưỡng và mốc kế tiếp được đề xuất '
                  'đúng.',
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('maintenance-done-odo'),
              controller: _odo,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 .]')),
                LengthLimitingTextInputFormatter(9),
              ],
              style: const TextStyle(color: LuxeColors.text, fontSize: 15.5),
              decoration: InputDecoration(
                labelText: 'ODO lúc làm (km)',
                prefixIcon: const Icon(Icons.speed_rounded, size: 20),
                errorText: _odoError,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              button: true,
              label: 'Ngày làm ${DateFormat('dd/MM/yyyy').format(_date)}',
              excludeSemantics: true,
              child: InkWell(
                key: const ValueKey('maintenance-done-date'),
                borderRadius: BorderRadius.circular(14),
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Ngày làm',
                    prefixIcon: Icon(Icons.event_rounded, size: 20),
                  ),
                  child: Text(
                    DateFormat('dd/MM/yyyy').format(_date),
                    style: const TextStyle(
                      color: LuxeColors.text,
                      fontSize: 15.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('maintenance-done-cost'),
              controller: _cost,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 .]')),
                LengthLimitingTextInputFormatter(13),
              ],
              style: const TextStyle(color: LuxeColors.text, fontSize: 15.5),
              decoration: InputDecoration(
                labelText: 'Chi phí (đồng, không bắt buộc)',
                prefixIcon: const Icon(Icons.payments_rounded, size: 20),
                errorText: _costError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('maintenance-done-note'),
              controller: _note,
              maxLines: 2,
              maxLength: 200,
              style: const TextStyle(color: LuxeColors.text, fontSize: 14),
              decoration: const InputDecoration(
                // QA 155: the long label was cut off at 360 dp.
                labelText: 'Ghi chú (không bắt buộc)',
                hintText: 'Nơi làm, phụ tùng đã thay',
                prefixIcon: Icon(Icons.notes_rounded, size: 20),
              ),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 8),
              LuxeNotice(
                icon: Icons.error_outline_rounded,
                color: LuxeColors.danger,
                message: _saveError!,
              ),
            ],
            const SizedBox(height: 12),
            LuxeSubmitButton(
              key: const ValueKey('maintenance-done-save'),
              label: 'Lưu là đã làm',
              busyLabel: 'Đang lưu',
              icon: Icons.check_rounded,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
