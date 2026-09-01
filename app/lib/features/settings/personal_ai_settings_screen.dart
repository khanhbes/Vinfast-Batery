import 'package:flutter/material.dart';

import '../../core/widgets/app_popup.dart';
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa dữ liệu AI cá nhân?'),
        content: const Text(
          'Adapter và toàn bộ mẫu học của xe này sẽ bị xóa vĩnh viễn. Dữ liệu sạc trong lịch sử không bị xóa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa dữ liệu'),
          ),
        ],
      ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('AI cá nhân')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Dự đoán riêng cho xe',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Khi bật, dữ liệu sạc của xe này được dùng để hiệu chỉnh ETA. Dữ liệu không dùng chung với tài khoản hoặc xe khác.',
          ),
          const SizedBox(height: 24),
          if (_busy && profile == null)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_off_rounded),
              title: const Text('Chưa thể tải trạng thái học'),
              subtitle: Text('$_error'),
              trailing: TextButton(
                onPressed: _load,
                child: const Text('Thử lại'),
              ),
            )
          else ...[
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: profile?.consentEnabled ?? false,
              onChanged: _busy ? null : _toggle,
              title: const Text('Cho phép AI học từ phiên sạc'),
              subtitle: const Text(
                'Có thể tắt hoặc xóa dữ liệu bất cứ lúc nào.',
              ),
            ),
            const Divider(),
            _row(
              'Trạng thái',
              profile?.friendlyStageLabel ?? 'AI đang làm quen với xe của bạn',
            ),
            _row(
              'Phiên đủ điều kiện',
              '${profile?.validSessions ?? 0} phiên đã được dùng để học',
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Sau khi đủ ít nhất 5 phiên, backend sẽ fine-tune và gửi kết quả '
                'vào Trung tâm thông báo. Model cũ vẫn được giữ nếu bản mới kém hơn.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
            if (profile?.lastTrainedAt != null)
              _row(
                'Cập nhật gần nhất',
                profile!.lastTrainedAt!.toLocal().toString().substring(0, 16),
              ),
            if (profile?.lastTrainingError != null) ...[
              const SizedBox(height: 12),
              Text(
                'Lần học gần nhất chưa thành công; app vẫn giữ adapter tốt trước đó.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('XÓA MODEL & DỮ LIỆU CÁ NHÂN'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
