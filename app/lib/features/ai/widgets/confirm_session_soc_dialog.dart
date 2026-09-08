import 'package:flutter/material.dart';

class ConfirmSessionSocDialog extends StatefulWidget {
  const ConfirmSessionSocDialog({super.key});
  @override
  State<ConfirmSessionSocDialog> createState() =>
      _ConfirmSessionSocDialogState();
}

class _ConfirmSessionSocDialogState extends State<ConfirmSessionSocDialog> {
  final _input = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_input.text.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite || value < 0 || value > 100) {
      setState(() => _error = 'Nhập mức pin từ 0 đến 100%.');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('SOC thực tế cuối phiên'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Nhập mức pin bạn đọc trên xe sau khi kết thúc sạc.'),
        const SizedBox(height: 12),
        TextField(
          controller: _input,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Mức pin',
            suffixText: '%',
            hintText: 'Ví dụ: 80,5',
            errorText: _error,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Xác nhận')),
    ],
  );
}
