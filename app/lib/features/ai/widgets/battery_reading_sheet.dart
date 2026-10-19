import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/widgets/luxe_kit.dart';
import '../../../data/services/dashboard_reader.dart';
import '../dashboard_scan_screen.dart';

/// What the owner confirmed: battery % and/or ODO, and where it came from.
typedef BatteryReadingInput = ({double? soc, double? odoKm, String source});

/// Reads the dashboard (live scan or photo); injectable for tests.
typedef DashboardReadFn =
    Future<DashboardReading?> Function({required bool camera});

/// "% pin và ODO trên đồng hồ" (Task 127). The scooter has no BMS/Bluetooth,
/// so the dashboard is the only ground truth: take a photo (read on the
/// phone), pick one, or type. Nothing is saved until the owner checks it.
class BatteryReadingSheet extends StatefulWidget {
  const BatteryReadingSheet({
    super.key,
    this.initialSoc,
    this.currentOdoKm,
    this.eyebrow = 'Đồng hồ xe',
    this.title = '% pin và ODO hiện tại',
    this.requireSoc = false,
    this.reader,
  });

  final double? initialSoc;
  final double? currentOdoKm;
  final String eyebrow;
  final String title;
  final bool requireSoc;
  final DashboardReadFn? reader;

  static Future<BatteryReadingInput?> show(
    BuildContext context, {
    double? initialSoc,
    double? currentOdoKm,
    String eyebrow = 'Đồng hồ xe',
    String title = '% pin và ODO hiện tại',
    bool requireSoc = false,
    DashboardReadFn? reader,
  }) => showLuxeSheet<BatteryReadingInput>(
    context,
    builder: (_) => BatteryReadingSheet(
      initialSoc: initialSoc,
      currentOdoKm: currentOdoKm,
      eyebrow: eyebrow,
      title: title,
      requireSoc: requireSoc,
      reader: reader,
    ),
  );

  @override
  State<BatteryReadingSheet> createState() => _BatteryReadingSheetState();
}

class _BatteryReadingSheetState extends State<BatteryReadingSheet> {
  final _soc = TextEditingController();
  final _odo = TextEditingController();
  DashboardReading? _read;
  bool _reading = false;
  String? _readError;
  String? _socError;
  String? _odoError;

  @override
  void initState() {
    super.initState();
    final soc = widget.initialSoc;
    if (soc != null) _soc.text = soc.round().toString();
  }

  @override
  void dispose() {
    _soc.dispose();
    _odo.dispose();
    super.dispose();
  }

  Future<void> _readPhoto(bool camera) async {
    setState(() {
      _reading = true;
      _readError = null;
    });
    try {
      final result = await _readDashboard(camera);
      if (!mounted || result == null) return;
      setState(() {
        _read = result;
        if (result.soc != null) _soc.text = '${result.soc}';
        if (result.odoKm != null) _odo.text = _plain(result.odoKm!);
        _socError = null;
        _odoError = null;
      });
      HapticFeedback.selectionClick();
    } on Object {
      if (mounted) {
        setState(
          () => _readError = 'Không đọc được ảnh. Hãy thử lại hoặc nhập tay.',
        );
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  /// The camera opens the live scanner (QA 131); it can hand over to the
  /// gallery. Tests inject [BatteryReadingSheet.reader].
  Future<DashboardReading?> _readDashboard(bool camera) async {
    final injected = widget.reader;
    if (injected != null) return injected(camera: camera);
    if (camera) {
      return scanDashboard(context, lastOdoKm: widget.currentOdoKm);
    }
    final lastOdo = widget.currentOdoKm;
    return DashboardReader().read(
      camera: false,
      lastOdoKm: lastOdo != null && lastOdo > 0 ? lastOdo : null,
    );
  }

  static String _plain(double km) =>
      km == km.roundToDouble() ? '${km.round()}' : km.toStringAsFixed(1);

  double? _number(String text) =>
      double.tryParse(text.trim().replaceAll(' ', '').replaceAll(',', '.'));

  void _save() {
    final socText = _soc.text.trim();
    final odoText = _odo.text.trim();
    double? soc;
    double? odo;
    String? socError;
    String? odoError;
    if (socText.isNotEmpty) {
      soc = _number(socText);
      if (soc == null || soc < 0 || soc > 100) {
        socError = 'Nhập % từ 0 đến 100.';
      }
    } else if (widget.requireSoc) {
      socError = 'Nhập % pin trên đồng hồ.';
    }
    if (odoText.isNotEmpty) {
      odo = _number(odoText);
      final previous = widget.currentOdoKm;
      if (odo == null || odo < 0 || odo > 500000) {
        odoError = 'Nhập số km từ 0 đến 500.000.';
      } else if (previous != null && previous > 0 && odo < previous - 0.5) {
        odoError = 'ODO không thể nhỏ hơn lần trước (${previous.round()} km).';
      }
    }
    if (socError == null && odoError == null && soc == null && odo == null) {
      socError = 'Nhập % pin hoặc ODO.';
    }
    if (socError != null || odoError != null) {
      setState(() {
        _socError = socError;
        _odoError = odoError;
      });
      return;
    }
    final read = _read;
    final fromPhoto =
        read != null &&
        ((soc != null && read.soc == soc.round()) ||
            (odo != null && read.odoKm == odo));
    HapticFeedback.lightImpact();
    Navigator.of(
      context,
    ).pop((soc: soc, odoKm: odo, source: fromPhoto ? 'photo' : 'manual'));
  }

  @override
  Widget build(BuildContext context) {
    final read = _read;
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
            eyebrow: widget.eyebrow,
            title: widget.title,
            caption:
                'Quét đồng hồ: đưa camera vào, app tự nhận % pin và ODO ngay '
                'trên máy. Bạn kiểm tra lại trước khi lưu.',
            trailing: LuxeCircleButton(
              icon: Icons.close_rounded,
              tooltip: 'Đóng',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('reading-camera'),
                onPressed: _reading ? null : () => _readPhoto(true),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Quét đồng hồ'),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              ),
              OutlinedButton.icon(
                key: const ValueKey('reading-gallery'),
                onPressed: _reading ? null : () => _readPhoto(false),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Chọn ảnh'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
              ),
            ],
          ),
          if (_reading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_readError != null) ...[
            const SizedBox(height: 12),
            LuxeNotice(
              icon: Icons.error_outline_rounded,
              color: LuxeColors.danger,
              message: _readError!,
            ),
          ] else if (read != null) ...[
            const SizedBox(height: 12),
            LuxeNotice(
              key: const ValueKey('reading-ocr-result'),
              icon: read.isEmpty
                  ? Icons.help_outline_rounded
                  : Icons.document_scanner_outlined,
              color: LuxeColors.champagne,
              message: read.isEmpty
                  ? 'Chưa đọc được số nào. Chụp gần, thẳng, đủ sáng và không '
                        'lóa, hoặc nhập tay.'
                  : '${read.frames > 0 ? 'Đã khớp qua ${read.frames} khung hình' : 'Đọc được'}: '
                        '${[if (read.soc != null) '${read.soc}%', if (read.odoKm != null) 'ODO ${_plain(read.odoKm!)} km'].join(' · ')}. '
                        'So lại với đồng hồ xe rồi bấm Lưu.',
            ),
            if (read.odoCandidates.length > 1 || read.socCandidates.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final value in read.socCandidates.take(4))
                      ActionChip(
                        label: Text('$value%'),
                        onPressed: () => setState(() => _soc.text = '$value'),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                    for (final value in read.odoCandidates)
                      ActionChip(
                        label: Text('${_plain(value)} km'),
                        onPressed: () =>
                            setState(() => _odo.text = _plain(value)),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('reading-soc'),
            controller: _soc,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_socError != null) setState(() => _socError = null);
            },
            decoration: InputDecoration(
              labelText: widget.requireSoc
                  ? '% pin trên đồng hồ'
                  : '% pin trên đồng hồ (không bắt buộc)',
              suffixText: '%',
              errorText: _socError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('reading-odo'),
            controller: _odo,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            onChanged: (_) {
              if (_odoError != null) setState(() => _odoError = null);
            },
            decoration: InputDecoration(
              labelText: 'Số ODO (không bắt buộc)',
              hintText: widget.currentOdoKm == null || widget.currentOdoKm == 0
                  ? 'Ví dụ: 1250'
                  : 'Lần trước: ${widget.currentOdoKm!.round()} km',
              suffixText: 'km',
              errorText: _odoError,
            ),
          ),
          const SizedBox(height: 14),
          const LuxeNotice(
            icon: Icons.lock_outline_rounded,
            message:
                'Ảnh được đọc ngay trên điện thoại, không gửi đi. Hai lần nhập '
                'có cả % và ODO (không sạc ở giữa) thành một chuyến đi để AI '
                'học hao pin của xe bạn.',
          ),
          const SizedBox(height: 18),
          FilledButton(
            key: const ValueKey('reading-save'),
            onPressed: _reading ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}
