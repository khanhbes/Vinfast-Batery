import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/cockpit_design_system.dart';
import '../../core/widgets/app_popup.dart';
import '../../data/services/server_smart_charger_service.dart';

/// Read-only developer inspector for owner/vehicle-scoped training samples.
/// Raw measurements remain immutable in the client; corrections are performed
/// with Firebase Admin by excluding a sample instead of rewriting provenance.
class PersonalAiTrainingDataScreen extends StatefulWidget {
  const PersonalAiTrainingDataScreen({super.key, required this.vehicleId});

  final String vehicleId;

  @override
  State<PersonalAiTrainingDataScreen> createState() =>
      _PersonalAiTrainingDataScreenState();
}

class _PersonalAiTrainingDataScreenState
    extends State<PersonalAiTrainingDataScreen> {
  bool _loading = true;
  String? _error;
  String? _uid;
  bool _canEdit = false;
  List<_TrainingSample> _samples = const [];

  String get _collectionPath => _uid == null
      ? 'users/{uid}/chargingTrainingSamples'
      : 'users/$_uid/chargingTrainingSamples';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Bạn chưa đăng nhập.');
      final snapshots = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chargingTrainingSamples')
          .get();
      final samples =
          snapshots.docs
              .where(
                (doc) => '${doc.data()['vehicleId'] ?? ''}' == widget.vehicleId,
              )
              .map((doc) => _TrainingSample(id: doc.id, data: doc.data()))
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      var canEdit = false;
      try {
        canEdit = await ServerSmartChargerService().developerTrainingAccess();
      } on Object {
        // The API is the authority. Keep the screen read-only on failure.
      }
      if (!mounted) return;
      setState(() {
        _uid = user.uid;
        _samples = samples;
        _canEdit = canEdit;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Dữ liệu fine-tune')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            CockpitSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.science_outlined,
                        color: CockpitColors.emerald,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Kho mẫu học cá nhân',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Xe ${widget.vehicleId} · ${_samples.length} mẫu',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _collectionPath),
                      );
                      AppPopup.showSuccess('Đã sao chép đường dẫn Firestore');
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _collectionPath,
                              style: const TextStyle(
                                color: CockpitColors.muted,
                                fontFamily: 'JetBrainsMono',
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.copy_rounded,
                            size: 18,
                            color: CockpitColors.emerald,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _canEdit
                        ? 'Quyền developer đã được xác minh. Bạn có thể chỉnh '
                              'dữ liệu dùng để train; số đo gốc vẫn được giữ để audit.'
                        : 'Chế độ này chỉ xem. Đăng nhập tài khoản có quyền '
                              'developer để chỉnh dữ liệu fine-tune.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 72),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _MessageCard(
                icon: Icons.cloud_off_rounded,
                title: 'Không đọc được dữ liệu fine-tune',
                detail: _error!,
                action: _load,
              )
            else if (_samples.isEmpty)
              const _MessageCard(
                icon: Icons.data_array_rounded,
                title: 'Chưa có mẫu học cho xe này',
                detail:
                    'Mẫu sẽ xuất hiện sau phiên sạc đủ điều kiện và đã đồng bộ.',
              )
            else
              ..._samples.map(_buildSampleCard),
          ],
        ),
      ),
    );
  }

  Widget _buildSampleCard(_TrainingSample sample) {
    final excluded = sample.data['trainingExcluded'] == true;
    final eligible = sample.data['eligibleForTargetTraining'] == true;
    final durationSeconds = _asDouble(sample.data['durationSeconds']);
    final energyWh = _asDouble(
      sample.data['gridEnergyWh'] ?? sample.data['energyUsedWh'],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CockpitSurface(
        padding: EdgeInsets.zero,
        child: ListTile(
          minTileHeight: 72,
          contentPadding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (excluded ? CockpitColors.amber : CockpitColors.emerald)
                  .withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              excluded ? Icons.block_rounded : Icons.analytics_outlined,
              color: excluded ? CockpitColors.amber : CockpitColors.emerald,
            ),
          ),
          title: Text(
            sample.id,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            '${eligible ? 'Đủ điều kiện' : 'Chỉ hiệu chỉnh'}'
            '${excluded ? ' · Đã loại khỏi train' : ''}'
            '${durationSeconds > 0 ? ' · ${(durationSeconds / 60).round()} phút' : ''}'
            '${energyWh > 0 ? ' · ${energyWh.round()} Wh' : ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _showSample(sample),
        ),
      ),
    );
  }

  Future<void> _showSample(_TrainingSample sample) async {
    final normalized = _normalizeJson(<String, dynamic>{
      'documentId': sample.id,
      ...sample.data,
    });
    final text = const JsonEncoder.withIndent('  ').convert(normalized);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .78,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 10, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Dữ liệu mẫu gốc',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (_canEdit)
                      IconButton(
                        tooltip: 'Chỉnh dữ liệu dùng để train',
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _editSample(sample);
                        },
                        icon: const Icon(Icons.edit_note_rounded),
                      ),
                    IconButton(
                      tooltip: 'Sao chép JSON',
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: text));
                        AppPopup.showSuccess('Đã sao chép JSON');
                      },
                      icon: const Icon(Icons.copy_all_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    text,
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editSample(_TrainingSample sample) async {
    final note = TextEditingController(
      text: '${sample.data['developerNote'] ?? ''}',
    );
    final duration = TextEditingController(
      text: _overrideText(sample.data['trainingDurationSecondsOverride']),
    );
    final predicted = TextEditingController(
      text: _overrideText(sample.data['trainingPredictedMinutesOverride']),
    );
    var excluded = sample.data['trainingExcluded'] == true;
    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppColors.card,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Chỉnh dữ liệu dùng để fine-tune',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Override chỉ ảnh hưởng dữ liệu đưa vào lần train tiếp theo. '
                    'Số đo gốc của phiên sạc không bị thay đổi.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: excluded,
                    onChanged: (value) => setSheetState(() => excluded = value),
                    title: const Text('Loại mẫu khỏi fine-tune'),
                    subtitle: const Text(
                      'Dùng khi dữ liệu phiên không đáng tin cậy',
                    ),
                  ),
                  TextField(
                    controller: duration,
                    enabled: !excluded,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Thời lượng thực dùng để train (giây)',
                      hintText: 'Để trống để dùng số đo gốc',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: predicted,
                    enabled: !excluded,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'ETA dự đoán dùng để train (phút)',
                      hintText: 'Để trống để dùng số đo gốc',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: note,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Ghi chú developer',
                      hintText: 'Lý do chỉnh hoặc loại mẫu',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final durationValue = _parseOptional(duration.text);
                        final predictedValue = _parseOptional(predicted.text);
                        final durationInvalid =
                            durationValue == null &&
                            duration.text.trim().isNotEmpty;
                        final predictedInvalid =
                            predictedValue == null &&
                            predicted.text.trim().isNotEmpty;
                        if (durationInvalid || predictedInvalid) {
                          AppPopup.showWarning(
                            'Giá trị override phải là số hợp lệ',
                          );
                          return;
                        }
                        try {
                          await ServerSmartChargerService()
                              .reviewTrainingSample(
                                sessionId: sample.id,
                                vehicleId: widget.vehicleId,
                                trainingExcluded: excluded,
                                developerNote: note.text.trim(),
                                durationSecondsOverride: excluded
                                    ? null
                                    : durationValue,
                                predictedMinutesOverride: excluded
                                    ? null
                                    : predictedValue,
                              );
                          if (context.mounted) Navigator.pop(context, true);
                        } on Object catch (error) {
                          AppPopup.showError(
                            'Không thể lưu dữ liệu fine-tune',
                            detail: '$error',
                          );
                        }
                      },
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('LƯU OVERRIDE TRAIN'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (saved == true) {
        AppPopup.showSuccess('Đã lưu override fine-tune');
        await _load();
      }
    } finally {
      note.dispose();
      duration.dispose();
      predicted.dispose();
    }
  }
}

class _TrainingSample {
  const _TrainingSample({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;

  DateTime get updatedAt {
    final value = data['updatedAt'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Future<void> Function()? action;

  @override
  Widget build(BuildContext context) => CockpitSurface(
    child: Column(
      children: [
        Icon(icon, size: 34, color: CockpitColors.muted),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        if (action != null) ...[
          const SizedBox(height: 10),
          TextButton(onPressed: action, child: const Text('Thử lại')),
        ],
      ],
    ),
  );
}

double _asDouble(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

String _overrideText(Object? value) => value == null ? '' : '$value';

double? _parseOptional(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : double.tryParse(trimmed);
}

Object? _normalizeJson(Object? value) {
  if (value is Timestamp) return value.toDate().toIso8601String();
  if (value is DateTime) return value.toIso8601String();
  if (value is GeoPoint) {
    return {'latitude': value.latitude, 'longitude': value.longitude};
  }
  if (value is DocumentReference) return value.path;
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', _normalizeJson(item)));
  }
  if (value is Iterable) return value.map(_normalizeJson).toList();
  return value;
}
