import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/pinova_api.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/charge_confirm_control.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../data/models/entitlement.dart';
import '../../data/services/charge_estimator.dart';
import '../ai/dashboard_scan_screen.dart';
import '../premium/premium_gate.dart';

/// A night plan as `/api/night-charging/<vehicle>` returns it (QA 135).
class NightPlan {
  const NightPlan({
    required this.state,
    required this.targetSoc,
    required this.wakeAt,
    this.startAt,
    this.finishBy,
    this.endsLate = false,
    this.error,
  });

  /// armed | started | cancelled | missed | failed.
  final String state;
  final int targetSoc;
  final String wakeAt;
  final DateTime? startAt;
  final DateTime? finishBy;
  final bool endsLate;
  final String? error;

  bool get armed => state == 'armed';

  static NightPlan? fromMap(Map<String, dynamic>? map) {
    if (map == null || map['state'] == null) return null;
    return NightPlan(
      state: map['state'].toString(),
      targetSoc: (map['targetSoc'] as num?)?.round() ?? 85,
      wakeAt: map['wakeAt']?.toString() ?? '06:30',
      startAt: DateTime.tryParse(map['startAt']?.toString() ?? '')?.toLocal(),
      finishBy: DateTime.tryParse(map['finishBy']?.toString() ?? '')?.toLocal(),
      endsLate: map['endsLate'] == true,
      error: map['error']?.toString(),
    );
  }
}

class NightChargingApi {
  NightChargingApi({PinovaApi? api})
    : _api = api ?? PinovaApi(timeout: const Duration(seconds: 45));
  final PinovaApi _api;

  String _path(String vehicleId) =>
      '/api/night-charging/${Uri.encodeComponent(vehicleId)}';

  /// Null when no plan was ever made (the server answers `data: null`).
  Future<NightPlan?> get(String vehicleId) async =>
      NightPlan.fromMap(await _api.get(_path(vehicleId)));

  Future<NightPlan?> arm(
    String vehicleId, {
    required double currentSoc,
    required int targetSoc,
    required TimeOfDay wake,
  }) async => NightPlan.fromMap(
    await _api.call(
      'PUT',
      _path(vehicleId),
      body: {
        'currentSoc': currentSoc,
        'targetSoc': targetSoc,
        'wakeAt':
            '${wake.hour.toString().padLeft(2, '0')}:${wake.minute.toString().padLeft(2, '0')}',
        'confirmed': true,
      },
    ),
  );

  Future<NightPlan?> cancel(String vehicleId) async =>
      NightPlan.fromMap(await _api.delete(_path(vehicleId)));
}

final nightChargingApiProvider = Provider<NightChargingApi>(
  (ref) => NightChargingApi(),
);

/// Sạc đêm an toàn (QA 135, Ultra): charged to 80–90 % just before the owner
/// wakes, started by the server through the normal ON checks, with stricter
/// night limits (60 °C, unusual power, overtime) and an alarm-style alert.
class NightChargingScreen extends ConsumerStatefulWidget {
  const NightChargingScreen({
    super.key,
    required this.vehicleId,
    this.currentSoc,
    this.currentOdoKm,
    this.initialTarget,
    this.initialWake,
  });

  final String vehicleId;
  final double? currentSoc;
  final double? currentOdoKm;

  /// Pre-filled by Pinova Bot (QA 135); the owner still confirms.
  final int? initialTarget;
  final TimeOfDay? initialWake;

  static Future<void> open(
    BuildContext context,
    WidgetRef ref, {
    required String vehicleId,
    double? currentSoc,
    double? currentOdoKm,
  }) async {
    if (vehicleId.isEmpty) {
      AppPopup.showWarning('Hãy chọn xe trước');
      return;
    }
    if (!PremiumGate.check(context, ref, PremiumFeature.nightCharging)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NightChargingScreen(
          vehicleId: vehicleId,
          currentSoc: currentSoc,
          currentOdoKm: currentOdoKm,
        ),
      ),
    );
  }

  @override
  ConsumerState<NightChargingScreen> createState() =>
      _NightChargingScreenState();
}

class _NightChargingScreenState extends ConsumerState<NightChargingScreen> {
  NightPlan? _plan;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  late double _current = (widget.currentSoc ?? 40).clamp(0, 75).toDouble();
  late int _target = (widget.initialTarget ?? 85).clamp(80, 90);
  late TimeOfDay _wake =
      widget.initialWake ?? const TimeOfDay(hour: 6, minute: 30);

  NightChargingApi get _api => ref.read(nightChargingApiProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final plan = await _api.get(widget.vehicleId);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _loading = false;
        if (plan != null && widget.initialTarget == null) {
          _target = plan.targetSoc.clamp(80, 90);
          final parts = plan.wakeAt.split(':');
          if (parts.length == 2 && widget.initialWake == null) {
            _wake = TimeOfDay(
              hour: int.tryParse(parts[0]) ?? 6,
              minute: int.tryParse(parts[1]) ?? 30,
            );
          }
        }
      });
    } on PinovaApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.notDeployed
            ? 'Máy chủ chưa cập nhật tính năng sạc đêm.'
            : error.offline
            ? 'Cần kết nối mạng để hẹn sạc đêm.'
            : error.message;
      });
    }
  }

  Future<void> _arm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plan = await _api.arm(
        widget.vehicleId,
        currentSoc: _current,
        targetSoc: _target,
        wake: _wake,
      );
      if (!mounted) return;
      setState(() => _plan = plan);
      AppPopup.showSuccess(
        plan?.state == 'started'
            ? 'Đã bắt đầu sạc đêm'
            : 'Đã hẹn sạc đêm lúc ${_clock(plan?.startAt)}',
      );
    } on PinovaApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.offline
              ? 'Cần kết nối mạng để hẹn sạc đêm.'
              : (error.message ?? 'Chưa hẹn được sạc đêm.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      final plan = await _api.cancel(widget.vehicleId);
      if (mounted) setState(() => _plan = plan);
    } on PinovaApiException catch (error) {
      AppPopup.showWarning(error.message ?? 'Chưa huỷ được.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final read = await scanDashboard(context, lastOdoKm: widget.currentOdoKm);
    final soc = read?.soc;
    if (soc != null && mounted) {
      setState(() => _current = soc.toDouble().clamp(0, _target - 5));
    }
  }

  static String _clock(DateTime? at) => at == null
      ? '--:--'
      : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  @override
  // QA 136: however this screen is reached (a tile, Pinova Bot, a
  // notification), outside the plan it shows Pinova Premium instead.
  Widget build(BuildContext context) => PremiumRequired(
    feature: PremiumFeature.nightCharging,
    child: Builder(builder: _screen),
  );

  Widget _screen(BuildContext context) {
    final plan = _plan;
    return LuxeScaffold(
      title: 'Sạc đêm an toàn',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          const Text(
            'Sạc đầy đến mức vừa đủ ngay trước khi bạn thức dậy: ít giờ pin '
            'nằm ở mức cao, đúng khung giá điện đêm, và giám sát chặt hơn '
            'ban ngày.',
            style: LuxeText.body,
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: LuxeColors.emerald),
              ),
            )
          else ...[
            if (plan != null && (plan.armed || plan.state == 'started'))
              _PlanCard(plan: plan, busy: _busy, onCancel: _cancel)
            else ...[
              if (plan != null && plan.state != 'cancelled')
                LuxeNotice(
                  key: const ValueKey('night-last-state'),
                  icon: Icons.history_rounded,
                  color: LuxeColors.champagne,
                  message: plan.state == 'missed'
                      ? 'Lần hẹn trước chưa bật kịp (máy chủ bận). Hãy hẹn lại.'
                      : plan.state == 'failed'
                      ? 'Lần hẹn trước không bật được sạc. Kiểm tra ổ Shelly.'
                      : 'Lần hẹn trước: ${plan.state}.',
                ),
              const LuxeSectionLabel('Pin hiện tại'),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      key: const ValueKey('night-current'),
                      value: _current,
                      min: 0,
                      max: (_target - 5).toDouble(),
                      divisions: _target - 5,
                      label: '${_current.round()}%',
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _current = v.roundToDouble()),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '${_current.round()}%',
                      textAlign: TextAlign.end,
                      style: LuxeText.item,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _scan,
                  icon: const Icon(Icons.document_scanner_rounded, size: 18),
                  label: const Text('Quét đồng hồ xe'),
                ),
              ),
              const LuxeSectionLabel('Sạc đến'),
              LuxeSegmented<int>(
                key: const ValueKey('night-target'),
                segments: const [(80, '80%'), (85, '85%'), (90, '90%')],
                selected: _target,
                onChanged: (v) => setState(() {
                  _target = v;
                  _current = _current.clamp(0, v - 5).toDouble();
                }),
              ),
              const LuxeSectionLabel('Giờ thức dậy'),
              LuxeSettingsGroup(
                children: [
                  LuxeSettingsRow(
                    key: const ValueKey('night-wake'),
                    icon: Icons.alarm_rounded,
                    title: _clock(
                      DateTime(2000, 1, 1, _wake.hour, _wake.minute),
                    ),
                    subtitle: 'Pin đạt mục tiêu khoảng 20 phút trước giờ này',
                    onTap: _busy
                        ? null
                        : () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: _wake,
                            );
                            if (picked != null) setState(() => _wake = picked);
                          },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const LuxeNotice(
                key: ValueKey('night-safety'),
                icon: Icons.shield_moon_rounded,
                color: LuxeColors.emerald,
                message:
                    'Ban đêm ngắt ngay khi ổ trên 60 °C (ban ngày 75 °C), khi '
                    'công suất cao bất thường, hoặc khi sạc kéo dài quá dự '
                    'đoán; mọi điện thoại của tài khoản nhận cảnh báo kêu như '
                    'báo thức. Ổ Shelly vẫn có hẹn giờ tự tắt.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                LuxeNotice(
                  key: const ValueKey('night-error'),
                  icon: Icons.error_outline_rounded,
                  color: LuxeColors.danger,
                  message: _error!,
                ),
              ],
              const SizedBox(height: 16),
              if (_busy)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(color: LuxeColors.emerald),
                  ),
                )
              else
                ChargeConfirmControl(
                  key: const ValueKey('night-confirm'),
                  label: 'Vuốt để hẹn sạc đêm đến $_target%',
                  onConfirmed: _arm,
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.busy,
    required this.onCancel,
  });
  final NightPlan plan;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final start = plan.startAt, finish = plan.finishBy;
    final running = plan.state == 'started';
    return Container(
      key: const ValueKey('night-plan-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: LuxeColors.raised,
        border: Border.all(color: LuxeColors.emerald.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            running ? 'ĐANG SẠC ĐÊM' : 'ĐÃ HẸN SẠC ĐÊM',
            style: LuxeText.eyebrow,
          ),
          const SizedBox(height: 8),
          Text(
            'Đến ${plan.targetSoc}% trước ${plan.wakeAt}',
            style: LuxeText.title.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 6),
          if (!running && start != null)
            Text(
              'Bắt đầu khoảng ${_NightChargingScreenState._clock(start)}'
              '${finish == null ? '' : ' · xong khoảng ${_NightChargingScreenState._clock(finish)}'}'
              '${start.difference(DateTime.now()).isNegative ? '' : ' (sau ${formatChargeDuration(start.difference(DateTime.now()))})'}',
              style: LuxeText.caption,
            ),
          if (running)
            const Text(
              'Theo dõi ở tab Sạc pin. Dừng sạc luôn bấm được ở đó.',
              style: LuxeText.caption,
            ),
          if (plan.endsLate) ...[
            const SizedBox(height: 10),
            const LuxeNotice(
              color: LuxeColors.champagne,
              icon: Icons.schedule_rounded,
              message:
                  'Đêm nay không đủ giờ: sạc bắt đầu ngay và xong sau giờ thức.',
            ),
          ],
          if (plan.armed) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              key: const ValueKey('night-cancel'),
              onPressed: busy ? null : onCancel,
              child: const Text('Huỷ hẹn sạc đêm'),
            ),
          ],
        ],
      ),
    );
  }
}
