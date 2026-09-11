import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

import '../models/smart_charge_cost.dart';
import '../models/smart_charging_session.dart';

class SmartChargeReportService {
  Future<ChargeReportResult> export({
    required ChargeReportRequest request,
    required List<SmartChargingSession> sessions,
  }) async {
    if (!request.to.isAfter(request.from)) {
      throw ArgumentError('Khoảng ngày báo cáo chưa hợp lệ.');
    }
    if (request.to.difference(request.from) > const Duration(days: 366)) {
      throw ArgumentError('Mỗi báo cáo chỉ hỗ trợ tối đa 12 tháng.');
    }
    final selected = sessions.where((session) {
      final started = session.startedAt ?? session.createdAt;
      if (!session.state.isTerminal ||
          started.isBefore(request.from) ||
          !started.isBefore(request.to)) {
        return false;
      }
      return request.allVehicles || session.vehicleId == request.vehicleId;
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final summary = SmartChargeHistorySummary.calculate(
      selected,
      from: request.from,
      to: request.to,
    );
    final directory = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final extension = request.format == ChargeReportFormat.csv ? 'csv' : 'pdf';
    final file = File('${directory.path}/SmartCharge_$stamp.$extension');
    if (request.format == ChargeReportFormat.csv) {
      await file.writeAsBytes(_csv(selected), flush: true);
    } else {
      await file.writeAsBytes(
        await _pdf(request, selected, summary),
        flush: true,
      );
    }
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Báo cáo Smart Charge',
      text:
          'Báo cáo ${DateFormat('dd/MM/yyyy').format(request.from)} – ${DateFormat('dd/MM/yyyy').format(request.to.subtract(const Duration(days: 1)))}',
    );
    return ChargeReportResult(
      path: file.path,
      sessionCount: selected.length,
      format: request.format,
    );
  }

  Uint8List _csv(List<SmartChargingSession> sessions) {
    final rows = <List<Object?>>[
      const [
        'Mã phiên',
        'Xe',
        'Bắt đầu',
        'Kết thúc',
        'Loại',
        'Trạng thái',
        'SOC đầu (%)',
        'SOC cuối/mục tiêu (%)',
        'Điện lưới (Wh)',
        'Giá điện (VND/kWh)',
        'Chi phí (VND)',
        'Thiết bị',
        'Kết nối',
        'Chất lượng dữ liệu',
      ],
      for (final session in sessions)
        [
          session.sessionId,
          session.vehicleId,
          _iso(session.startedAt ?? session.createdAt),
          session.stoppedAt == null ? '' : _iso(session.stoppedAt!),
          session.strategy == ChargingStrategy.manualTimed ? 'Thủ công' : 'AI',
          session.state.wireValue,
          session.startSoc.toStringAsFixed(1),
          (session.actualEndSoc ?? session.estimatedSoc ?? session.targetSoc)
              .toStringAsFixed(1),
          session.energyUsedWh.toStringAsFixed(1),
          session.tariffVndPerKwhSnapshot?.toStringAsFixed(0) ?? '',
          session.estimatedCostVnd?.toStringAsFixed(0) ?? '',
          session.deviceId ?? '',
          session.transport ?? '',
          session.energyQuality,
        ],
    ];
    final content = rows
        .map(
          (row) =>
              row.map((value) => _escapeCsv(value?.toString() ?? '')).join(','),
        )
        .join('\r\n');
    return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(content)]);
  }

  Future<Uint8List> _pdf(
    ChargeReportRequest request,
    List<SmartChargingSession> sessions,
    SmartChargeHistorySummary summary,
  ) async {
    final document = pw.Document();
    final regular = await _bundledFont('assets/fonts/VinFastUnicode-Regular.ttf');
    final bold = await _bundledFont('assets/fonts/VinFastUnicode-Bold.ttf');
    final theme = regular == null
        ? null
        : pw.ThemeData.withFont(base: regular, bold: bold ?? regular);
    final currency = NumberFormat.decimalPattern('vi_VN');
    document.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'SMART CHARGE',
              style: pw.TextStyle(font: bold, fontSize: 10),
            ),
            pw.Text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())),
          ],
        ),
        build: (_) => [
          pw.SizedBox(height: 16),
          pw.Text(
            'Báo cáo lịch sử sạc',
            style: pw.TextStyle(font: bold, fontSize: 24),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${DateFormat('dd/MM/yyyy').format(request.from)} – ${DateFormat('dd/MM/yyyy').format(request.to.subtract(const Duration(days: 1)))}',
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _pdfKpi('Điện từ lưới', _energy(summary.totalGridEnergyWh), bold),
              _pdfKpi(
                'Tổng chi phí',
                summary.totalCostVnd <= 0
                    ? 'Chưa có dữ liệu'
                    : '${currency.format(summary.totalCostVnd)} đ',
                bold,
              ),
              _pdfKpi('Phiên hoàn tất', '${summary.completedSessions}', bold),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Thời gian',
              'Xe',
              'Loại',
              'SOC',
              'Điện',
              'Chi phí',
              'Trạng thái',
            ],
            data: [
              for (final session in sessions)
                [
                  DateFormat(
                    'dd/MM HH:mm',
                  ).format((session.startedAt ?? session.createdAt).toLocal()),
                  session.vehicleId,
                  session.strategy == ChargingStrategy.manualTimed
                      ? 'Thủ công'
                      : 'AI',
                  '~${session.startSoc.round()} → ~${(session.actualEndSoc ?? session.estimatedSoc ?? session.targetSoc).round()}%',
                  _energy(session.energyUsedWh),
                  session.estimatedCostVnd == null
                      ? '—'
                      : '${currency.format(session.estimatedCostVnd)} đ',
                  session.state.wireValue,
                ],
            ],
            headerStyle: pw.TextStyle(font: bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF101216),
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.all(5),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'SOC và dung lượng pin có dấu ~ là giá trị ước tính, không phải dữ liệu BMS. Chi phí dùng điện năng Shelly đo và giá được chụp tại thời điểm bắt đầu phiên.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return document.save();
  }

  Future<pw.Font?> _bundledFont(String asset) async {
    try {
      return pw.Font.ttf(await rootBundle.load(asset));
    } on Object {
      return null;
    }
  }

  pw.Widget _pdfKpi(String label, String value, pw.Font? bold) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label,
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 3),
      pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 13)),
    ],
  );

  String _escapeCsv(String value) =>
      '"${value.replaceAll('"', '""').replaceAll('\r', ' ').replaceAll('\n', ' ')}"';
  String _iso(DateTime value) => value.toLocal().toIso8601String();
  String _energy(double wh) => wh >= 1000
      ? '${(wh / 1000).toStringAsFixed(2)} kWh'
      : '${wh.toStringAsFixed(0)} Wh';
}
