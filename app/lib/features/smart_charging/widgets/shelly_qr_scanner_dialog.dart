import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/services/shelly_qr_parser.dart';

class ShellyQrScannerDialog extends StatefulWidget {
  const ShellyQrScannerDialog({super.key});

  static Future<ShellyQrParseResult?> show(BuildContext context) {
    return showDialog<ShellyQrParseResult>(
      context: context,
      builder: (context) => const ShellyQrScannerDialog(),
    );
  }

  @override
  State<ShellyQrScannerDialog> createState() => _ShellyQrScannerDialogState();
}

class _ShellyQrScannerDialogState extends State<ShellyQrScannerDialog> {
  final _inputController = TextEditingController();
  ShellyQrParseResult? _parsedResult;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onTextChanged);
    _checkClipboard();
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && data!.text!.trim().isNotEmpty) {
        final parsed = ShellyQrParser.parse(data.text!);
        if (parsed != null && mounted) {
          setState(() {
            _inputController.text = data.text!.trim();
            _parsedResult = parsed;
          });
        }
      }
    } catch (_) {}
  }

  void _onTextChanged() {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _parsedResult = null;
        _errorText = null;
      });
      return;
    }

    final result = ShellyQrParser.parse(text);
    setState(() {
      _parsedResult = result;
      _errorText = result == null
          ? 'Chưa nhận diện được mã Shelly. Hãy kiểm tra lại chuỗi hoặc mã QR.'
          : null;
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.qr_code_scanner_rounded, color: colors.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Quét mã QR / Serial Shelly')),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mã QR hoặc Barcode được in trên tem thân ổ cắm Shelly hoặc trên vỏ hộp.',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bạn có thể dùng ứng dụng quét mã của điện thoại hoặc dán trực tiếp mã vào đây.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _inputController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Dán mã QR, URL hoặc Device ID',
                  hintText: 'Ví dụ: shellyplugs3-c049ef87b64c hoặc https://...',
                  errorText: _errorText,
                  suffixIcon: IconButton(
                    tooltip: 'Dán từ bộ nhớ tạm',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null) {
                        _inputController.text = data!.text!.trim();
                      }
                    },
                  ),
                ),
              ),
              if (_parsedResult != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF22C55E),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Đã nhận diện thành công',
                            style: TextStyle(
                              color: colors.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Device ID: ${_parsedResult!.deviceId}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_parsedResult!.model != null)
                        Text(
                          'Model: ${_parsedResult!.model}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      if (_parsedResult!.cloudHost != null)
                        Text(
                          'Server: ${_parsedResult!.cloudHost}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ĐÓNG'),
        ),
        FilledButton.icon(
          onPressed: _parsedResult != null
              ? () => Navigator.pop(context, _parsedResult)
              : null,
          icon: const Icon(Icons.check_rounded),
          label: const Text('ÁP DỤNG'),
        ),
      ],
    );
  }
}
