import 'package:flutter/material.dart';
import '../../core/utils/app_error_formatter.dart';

import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../data/models/personal_charging_profile.dart';
import '../../data/services/server_smart_charger_service.dart';

class PersonalAiSettingsScreen extends StatefulWidget {
  const PersonalAiSettingsScreen({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  State<PersonalAiSettingsScreen> createState() => _PersonalAiSettingsState();
}

class _PersonalAiSettingsState extends State<PersonalAiSettingsScreen> {
  final _service = ServerSmartChargerService();
  PersonalChargingProfile? _profile;
  Object? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await _service.getPersonalProfile(widget.vehicleId);
      if (mounted) setState(() => _profile = value);
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
    } catch (error) {
      AppPopup.showError('Không thể cập nhật AI cá nhân', detail: '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showLuxeConfirm(
      context,
      title: 'Xóa dữ liệu AI cá nhân?',
      message:
          'Adapter và toàn bộ mẫu học của xe này sẽ bị xóa vĩnh viễn. Dữ liệu sạc trong lịch sử không bị xóa.',
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
      AppPopup.showError('Không thể xóa dữ liệu', detail: '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final sessions = profile?.validSessions ?? 0;
    return LuxeScaffold(
      appBar: const LuxeAppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          const LuxeReveal(
            child: LuxePageHeaderText(
              eyebrow: 'AI cá nhân',
              title: 'Dự đoán riêng cho xe',
              caption:
                  'Khi bật, dữ liệu sạc của xe này được dùng để điều chỉnh thời gian sạc dự kiến. Dữ liệu không dùng chung với tài khoản hoặc xe khác.',
            ),
          ),
          const SizedBox(height: 22),
          if (_busy && profile == null)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            LuxeNotice(
              icon: Icons.cloud_off_rounded,
              color: LuxeColors.champagne,
              message:
                  'Chưa thể tải trạng thái học. ${AppErrorFormatter.format(_error)}',
              action: TextButton(
                onPressed: _load,
                style: TextButton.styleFrom(
                  foregroundColor: LuxeColors.emerald,
                ),
                child: const Text('Thử lại'),
              ),
            )
          else ...[
            LuxeReveal(
              index: 1,
              child: LuxeGlass(
                radius: 24,
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    LuxeRing(
                      value: sessions / 5,
                      size: 92,
                      stroke: 7,
                      semanticLabel: '$sessions trên 5 phiên cần để học',
                      child: ExcludeSemantics(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$sessions',
                              style: const TextStyle(
                                color: LuxeColors.text,
                                fontSize: 24,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            Text(
                              '/ 5 phiên',
                              style: LuxeText.label.copyWith(fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('TRẠNG THÁI', style: LuxeText.eyebrow),
                          const SizedBox(height: 6),
                          Text(
                            profile?.friendlyStageLabel ??
                                'AI đang làm quen với xe của bạn',
                            style: LuxeText.item.copyWith(fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$sessions phiên đã được dùng để học',
                            style: LuxeText.caption.copyWith(fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const LuxeSectionLabel('Quyền học dữ liệu'),
            LuxeReveal(
              index: 2,
              child: LuxeSettingsGroup(
                children: [
                  LuxeSettingsRow(
                    icon: Icons.psychology_rounded,
                    accent: (profile?.consentEnabled ?? false)
                        ? LuxeColors.emerald
                        : null,
                    title: 'Cho phép AI học từ phiên sạc',
                    subtitle: 'Có thể tắt hoặc xóa dữ liệu bất cứ lúc nào.',
                    trailing: LuxeSwitch(
                      value: profile?.consentEnabled ?? false,
                      semanticLabel: 'Cho phép AI học từ phiên sạc',
                      onChanged: _busy ? null : _toggle,
                    ),
                  ),
                  if (profile?.lastTrainedAt != null)
                    LuxeSettingsRow(
                      icon: Icons.update_rounded,
                      title: 'Cập nhật gần nhất',
                      subtitle: profile!.lastTrainedAt!
                          .toLocal()
                          .toString()
                          .substring(0, 16),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const LuxeNotice(
              icon: Icons.info_outline_rounded,
              message:
                  'Sau khi đủ ít nhất 5 phiên, backend sẽ fine-tune và gửi kết quả vào Trung tâm thông báo. Model cũ vẫn được giữ nếu bản mới kém hơn.',
            ),
            if (profile?.lastTrainingError != null) ...[
              const SizedBox(height: 10),
              const LuxeNotice(
                icon: Icons.error_outline_rounded,
                color: LuxeColors.danger,
                message:
                    'Lần học gần nhất chưa thành công; app vẫn giữ adapter tốt trước đó.',
              ),
            ],
            const SizedBox(height: 24),
            LuxeDangerButton(
              label: 'Xóa model & dữ liệu cá nhân',
              icon: Icons.delete_outline_rounded,
              onPressed: _busy ? null : _delete,
            ),
          ],
        ],
      ),
    );
  }
}
