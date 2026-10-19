import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/learned_models_provider.dart';
import '../../core/widgets/luxe_connection_notice.dart';
import '../../core/providers/vehicle_providers.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/utils/app_error_formatter.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../data/models/personal_charging_profile.dart';
import '../../data/models/vehicle_learning_status.dart';
import '../../data/services/server_smart_charger_service.dart';
import '../../data/services/trip_csv_import.dart';
import '../ai/services/learning_flow.dart';
import 'widgets/training_result_sheet.dart';

/// AI cá nhân (Tasks 126–127): what each model learned, the data collected
/// since, and the owner's "Huấn luyện" buttons. Collection is silent;
/// training only happens here, and keeps the old model if the new one is
/// not better.
class PersonalAiSettingsScreen extends ConsumerStatefulWidget {
  const PersonalAiSettingsScreen({
    super.key,
    required this.vehicleId,
    this.service,
    this.pickCsv,
  });
  final String vehicleId;
  final ServerSmartChargerService? service;

  /// Test hook: returns the CSV bytes, or null when cancelled.
  final Future<List<int>?> Function()? pickCsv;

  @override
  ConsumerState<PersonalAiSettingsScreen> createState() =>
      _PersonalAiSettingsState();
}

class _PersonalAiSettingsState extends ConsumerState<PersonalAiSettingsScreen> {
  late final ServerSmartChargerService _service =
      widget.service ?? ServerSmartChargerService();
  PersonalChargingProfile? _profile;
  VehicleLearningStatus? _status;
  Object? _error;
  bool _busy = true;
  String? _training;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.getPersonalProfile(widget.vehicleId),
        _service.learningStatus(widget.vehicleId),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as PersonalChargingProfile;
        _status = results[1] as VehicleLearningStatus?;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(bool enabled) async {
    setState(() => _busy = true);
    try {
      final value = await _service.setPersonalAiConsent(
        widget.vehicleId,
        enabled,
      );
      if (!mounted) return;
      setState(() => _profile = value);
      AppPopup.showSuccess(enabled ? 'Đã bật AI cá nhân' : 'Đã tắt AI cá nhân');
      await _load();
    } catch (error) {
      AppPopup.showError(
        'Không thể cập nhật AI cá nhân',
        detail: AppErrorFormatter.format(error),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _train(String model, String mode) async {
    if (mode == 'retrain') {
      final confirmed = await showLuxeConfirm(
        context,
        title: 'Huấn luyện lại từ đầu?',
        message:
            'App học lại từ toàn bộ dữ liệu đã lưu, mọi lần đo có trọng số như '
            'nhau. Nếu bản mới không tốt hơn, app vẫn giữ bản đang dùng.',
        confirmLabel: 'Huấn luyện lại',
      );
      if (confirmed != true) return;
    }
    setState(() => _training = model);
    try {
      final result = await _service.trainModel(
        widget.vehicleId,
        model: model,
        mode: mode,
      );
      if (!mounted) return;
      setState(() => _status = result.status ?? _status);
      // Overview, Battery monitor and the trip planner read the new model.
      ref.invalidate(learnedModelsProvider(widget.vehicleId));
      final report = result.report;
      if (report == null) {
        AppPopup.showSuccess('Đã huấn luyện xong.');
      } else {
        // Objective numbers, not just "done" (Task 127).
        await TrainingResultSheet.show(
          context,
          title: model == 'charge'
              ? 'Dự đoán & tự ngắt sạc'
              : 'Hao pin theo lộ trình',
          report: report,
        );
        if (!mounted) return;
      }
      final profile = await _service.getPersonalProfile(widget.vehicleId);
      if (mounted) setState(() => _profile = profile);
    } catch (error) {
      AppPopup.showError(
        'Chưa huấn luyện được',
        detail: AppErrorFormatter.format(error),
      );
    } finally {
      if (mounted) setState(() => _training = null);
    }
  }

  Future<void> _importCsv() async {
    List<int>? bytes;
    try {
      if (widget.pickCsv != null) {
        bytes = await widget.pickCsv!();
      } else {
        final picked = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['csv'],
          withData: true,
        );
        bytes = picked?.files.single.bytes;
      }
    } catch (error) {
      AppPopup.showError(
        'Không mở được file',
        detail: AppErrorFormatter.format(error),
      );
      return;
    }
    if (bytes == null) return;
    final parsed = TripCsvImport.parse(bytes);
    if (parsed.error != null) {
      AppPopup.showError('File chưa đúng định dạng', detail: parsed.error);
      return;
    }
    setState(() => _training = 'import');
    var added = 0;
    var duplicates = 0;
    var rejected = 0;
    VehicleLearningStatus? status;
    try {
      final rows = parsed.rows;
      for (var i = 0; i < rows.length; i += TripCsvImport.batchSize) {
        final end = (i + TripCsvImport.batchSize).clamp(0, rows.length);
        final result = await _service.addTripSamples(
          widget.vehicleId,
          rows.sublist(i, end),
          source: 'csv',
        );
        added += result.added;
        duplicates += result.duplicates;
        rejected += result.rejected;
        status = result.status ?? status;
      }
      if (!mounted) return;
      setState(() => _status = status ?? _status);
      AppPopup.showSuccess(
        'Đã nhập $added chuyến'
        '${duplicates > 0 ? ' · $duplicates chuyến đã có' : ''}'
        '${rejected > 0 ? ' · bỏ $rejected dòng không hợp lệ' : ''}.',
      );
      await TrainingReadiness.check(status);
    } catch (error) {
      AppPopup.showError(
        'Chưa nhập được file',
        detail: AppErrorFormatter.format(error),
      );
    } finally {
      if (mounted) setState(() => _training = null);
    }
  }

  Future<void> _addReading() async {
    final vehicle = ref.read(vehicleProvider(widget.vehicleId)).valueOrNull;
    final result = await BatteryReadingFlow.run(
      context,
      vehicleId: widget.vehicleId,
      currentSoc: vehicle?.hasBatteryData == true
          ? vehicle!.currentBattery.toDouble()
          : null,
      currentOdoKm: vehicle?.currentOdo.toDouble(),
      service: _service,
    );
    if (result?.status != null && mounted) {
      setState(() => _status = result!.status);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showLuxeConfirm(
      context,
      title: 'Xóa dữ liệu AI cá nhân?',
      message:
          'Mô hình và toàn bộ mẫu học của xe này sẽ bị xóa vĩnh viễn. Dữ liệu sạc trong lịch sử không bị xóa.',
      confirmLabel: 'Xóa dữ liệu',
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _service.deletePersonalProfile(widget.vehicleId);
      if (!mounted) return;
      setState(() => _profile = null);
      AppPopup.showSuccess('Đã xóa dữ liệu AI cá nhân');
      await _load();
    } catch (error) {
      AppPopup.showError(
        'Không thể xóa dữ liệu',
        detail: AppErrorFormatter.format(error),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final status = _status;
    final consent = status?.consentEnabled ?? profile?.consentEnabled ?? true;
    return LuxeScaffold(
      appBar: const LuxeAppBar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            const LuxeReveal(
              child: LuxePageHeaderText(
                eyebrow: 'AI cá nhân',
                title: 'Mô hình riêng cho xe',
                caption:
                    'App tự thu thập dữ liệu sạc và chuyến đi của xe này. Khi đủ '
                    'dữ liệu mới, app báo để bạn bấm Huấn luyện. Dữ liệu chỉ '
                    'dùng cho xe này.',
              ),
            ),
            const SizedBox(height: 22),
            if (_busy && status == null)
              const Center(child: CircularProgressIndicator())
            // Same notice as the rest of the app, retrying by itself: a
            // read during a slow app start failed once and stayed (QA 130).
            else if (_error != null && status == null)
              LuxeConnectionNotice(
                key: const ValueKey('learning-connection-notice'),
                issue: ConnectionIssue.server,
                title: 'Chưa tải được dữ liệu học',
                detail:
                    'Dữ liệu đã thu thập vẫn được giữ trên máy chủ. '
                    'App sẽ tự tải lại.',
                onRetry: _load,
              )
            else if (status != null) ...[
              LuxeReveal(
                index: 1,
                child: _ModelCard(
                  key: const ValueKey('model-card-charge'),
                  icon: Icons.bolt_rounded,
                  title: 'Dự đoán & tự ngắt sạc',
                  status: status.charge,
                  unit: 'lần sạc',
                  dataRows: ChargeSampleRow.listFrom(
                    status.charge.raw['samples'],
                  ),
                  pendingRows: ChargeSampleRow.listFrom(
                    status.charge.raw['pendingSamples'],
                  ),
                  learned: _chargeLearned(status.charge),
                  sources:
                      'Học từ % bạn đọc trên đồng hồ sau sạc và lúc app tự nhận '
                      'biết pin đầy (công suất dưới 40 W suốt 5 phút).',
                  busy: _training == 'charge',
                  enabled: consent && _training == null,
                  onTrain: () => _train('charge', 'finetune'),
                  onRetrain: () => _train('charge', 'retrain'),
                ),
              ),
              const SizedBox(height: 14),
              LuxeReveal(
                index: 2,
                child: _ModelCard(
                  key: const ValueKey('model-card-trip'),
                  icon: Icons.route_rounded,
                  title: 'Hao pin theo lộ trình',
                  status: status.trip,
                  unit: 'chuyến',
                  learned: _tripLearned(status),
                  sources: _tripSources(status.trip),
                  busy: _training == 'trip',
                  enabled: consent && _training == null,
                  onTrain: () => _train('trip', 'finetune'),
                  onRetrain: () => _train('trip', 'retrain'),
                ),
              ),
              const LuxeSectionLabel('Thêm dữ liệu'),
              LuxeSettingsGroup(
                children: [
                  LuxeSettingsRow(
                    key: const ValueKey('learning-add-reading'),
                    icon: Icons.photo_camera_outlined,
                    title: 'Cập nhật % pin & ODO',
                    subtitle: 'Quét đồng hồ xe hoặc nhập tay',
                    onTap: _training == null ? _addReading : null,
                  ),
                  LuxeSettingsRow(
                    key: const ValueKey('learning-import-csv'),
                    icon: Icons.upload_file_rounded,
                    title: 'Nhập file chuyến đi (CSV)',
                    subtitle: _training == 'import'
                        ? 'Đang nhập…'
                        : 'Cột distance_km, soc_delta (hoặc start/end_soc), '
                              'avg_speed_kmh, payload_kg…',
                    onTap: _training == null && consent ? _importCsv : null,
                  ),
                ],
              ),
            ],
            const LuxeSectionLabel('Quyền học dữ liệu'),
            LuxeSettingsGroup(
              children: [
                LuxeSettingsRow(
                  icon: Icons.psychology_rounded,
                  accent: consent ? LuxeColors.emerald : null,
                  title: 'Cho phép AI học từ dữ liệu xe',
                  subtitle: 'Có thể tắt hoặc xóa dữ liệu bất cứ lúc nào.',
                  trailing: LuxeSwitch(
                    value: consent,
                    semanticLabel: 'Cho phép AI học từ dữ liệu xe',
                    onChanged: _busy || _training != null ? null : _toggle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const LuxeNotice(
              icon: Icons.info_outline_rounded,
              message:
                  'Mọi kết quả vẫn là ước tính. Huấn luyện không bao giờ làm kém '
                  'đi: app chỉ dùng bản mới khi sai số không tăng. Sạc vẫn có hẹn '
                  'giờ an toàn trên ổ và tự ngắt khi pin đầy.',
            ),
            const SizedBox(height: 24),
            LuxeDangerButton(
              label: 'Xóa model & dữ liệu cá nhân',
              icon: Icons.delete_outline_rounded,
              onPressed: _busy || _training != null ? null : _delete,
            ),
          ],
        ),
      ),
    );
  }

  static String _chargeLearned(ModelTrainingStatus status) {
    final wh = (status.raw['whPerPct'] as num?)?.toDouble();
    final power = (status.raw['powerW'] as num?)?.toDouble();
    if (wh == null) return 'Đang dùng thông số dòng xe (chưa huấn luyện).';
    final mae = status.mae;
    return '${wh.toStringAsFixed(1)} Wh cho 1 %'
        '${power == null ? '' : ' · sạc ~${power.round()} W'}'
        '${mae == null ? '' : ' · sai số ~±${mae.toStringAsFixed(1)}%'}';
  }

  static String _tripLearned(VehicleLearningStatus status) {
    final km = (status.trip.raw['kmPerPct'] as num?)?.toDouble();
    final model = status.trip.raw['model'];
    final source = model is Map ? model['source'] : null;
    if (km == null) return 'Chưa có định mức km/% cho xe này.';
    final value = '~${km.toStringAsFixed(2)} km cho 1 %';
    return switch (source) {
      'model' =>
        '$value · đã huấn luyện từ ${status.trip.trained} chuyến'
            '${status.trip.mae == null ? '' : ' · sai số ~±${status.trip.mae!.toStringAsFixed(1)}%/chuyến'}',
      'odo' => '$value · học từ ODO sau sạc',
      _ => '$value · theo định mức dòng xe',
    };
  }

  static String _tripSources(ModelTrainingStatus status) {
    final raw = status.raw['sources'];
    final counts = raw is Map ? raw : const {};
    String count(String key) => '${(counts[key] as num?)?.toInt() ?? 0}';
    return 'Dữ liệu: ${count('csv')} từ file · ${count('trip')} chuyến ghi '
        'trong app · ${count('odo_segment')} đoạn từ ODO + % pin.';
  }
}

Widget _sampleTile(ChargeSampleRow row, {bool pending = false}) {
  final tag = pending
      ? 'đang chờ huấn luyện'
      : row.fullDetected
      ? 'pin đầy tự nhận biết'
      : row.censored
      ? '100% (chỉ là cận trên)'
      : 'đã học';
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(
          pending ? Icons.hourglass_top_rounded : Icons.check_circle_outline,
          size: 16,
          color: pending ? LuxeColors.champagne : LuxeColors.platinumMid,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${row.date} · ${row.startPct.round()}% → ${row.endPct.round()}% · '
            '${row.energyWh.round()} Wh · $tag',
            style: LuxeText.caption.copyWith(fontSize: 12.5),
          ),
        ),
      ],
    ),
  );
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    super.key,
    required this.icon,
    required this.title,
    required this.status,
    required this.unit,
    required this.learned,
    required this.sources,
    required this.busy,
    required this.enabled,
    required this.onTrain,
    required this.onRetrain,
    this.dataRows = const [],
    this.pendingRows = const [],
  });

  final IconData icon;
  final String title;
  final ModelTrainingStatus status;

  /// Charges the model learned from / that wait for training (charge card).
  final List<ChargeSampleRow> dataRows;
  final List<ChargeSampleRow> pendingRows;
  final String unit;
  final String learned;
  final String sources;
  final bool busy;
  final bool enabled;
  final VoidCallback onTrain;
  final VoidCallback onRetrain;

  @override
  Widget build(BuildContext context) {
    final report = status.report;
    final canTrain = enabled && status.pending > 0;
    final canRetrain = enabled && status.trained + status.pending >= 2;
    return LuxeGlass(
      radius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LuxeRing(
                value: status.progress,
                size: 76,
                stroke: 6,
                color: status.ready
                    ? LuxeColors.champagne
                    : LuxeColors.platinum,
                semanticLabel:
                    '${status.pending} trên ${status.required} $unit mới cần để huấn luyện',
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    // Large text scales shrink inside the ring, not overflow.
                    child: FittedBox(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${status.pending}',
                            style: const TextStyle(
                              color: LuxeColors.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                          Text(
                            '/ ${status.required} mới',
                            style: LuxeText.label.copyWith(fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 16, color: LuxeColors.muted),
                        const SizedBox(width: 6),
                        // One line ("TỰ NGẮT / SẠC" wrapped, QA 129).
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              title.toUpperCase(),
                              maxLines: 1,
                              style: LuxeText.eyebrow,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      // The ring counts NEW data for the next training; with
                      // a trained model "0 / 3 · Đang thu thập" read as "no
                      // data at all" (QA 129).
                      status.ready
                          ? 'Đủ dữ liệu mới — nên huấn luyện'
                          : status.pending == 0 && status.trained > 0
                          ? 'Đã học ${status.trained} $unit · chờ ${status.required} $unit mới'
                          : status.pending == 0
                          ? 'Đang thu thập dữ liệu'
                          : '${status.pending} $unit mới đang chờ',
                      style: LuxeText.item.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      learned,
                      style: LuxeText.caption.copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(sources, style: LuxeText.caption.copyWith(fontSize: 12)),
          if (report != null) ...[
            const SizedBox(height: 8),
            Text(
              'Lần gần nhất: ${TrainingResultSheet.verdict(report)}',
              style: LuxeText.caption.copyWith(fontSize: 12),
            ),
            if (report.evaluation != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey('evaluation-$unit'),
                  onPressed: () => TrainingResultSheet.show(
                    context,
                    title: title,
                    report: report,
                  ),
                  icon: const Icon(Icons.analytics_outlined, size: 18),
                  label: const Text('Xem đánh giá chi tiết'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
              ),
          ],
          if (dataRows.isNotEmpty || pendingRows.isNotEmpty) ...[
            const SizedBox(height: 4),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: ValueKey('learned-data-$unit'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 6),
                title: Text(
                  'Dữ liệu sạc: ${dataRows.length} đã học · ${pendingRows.length} đang chờ',
                  style: LuxeText.item.copyWith(fontSize: 13.5),
                ),
                children: [
                  for (final row in pendingRows)
                    _sampleTile(row, pending: true),
                  for (final row in dataRows.reversed) _sampleTile(row),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (busy)
            const LinearProgressIndicator(minHeight: 2)
          else
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: ValueKey('train-$unit'),
                  onPressed: canTrain ? onTrain : null,
                  icon: const Icon(Icons.model_training_rounded),
                  label: const Text('Huấn luyện'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                ),
                TextButton(
                  key: ValueKey('retrain-$unit'),
                  onPressed: canRetrain ? onRetrain : null,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text('Huấn luyện lại từ đầu'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
