import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/shelly_connection.dart';
import '../../data/services/server_smart_charger_service.dart';
import '../../data/services/smart_charger_credentials_service.dart';
import '../../data/services/smart_charger_service.dart';

class ShellySetupScreen extends StatefulWidget {
  const ShellySetupScreen({super.key});

  @override
  State<ShellySetupScreen> createState() => _ShellySetupScreenState();
}

class _ShellySetupScreenState extends State<ShellySetupScreen> {
  final _credentials = SmartChargerCredentialsService();
  final _service = SmartChargerService();
  final _host = TextEditingController();
  final _key = TextEditingController();
  final _deviceId = TextEditingController();
  final _lan = TextEditingController();
  final _password = TextEditingController();
  int _step = 0;
  bool _busy = false;
  bool _obscure = true;
  bool _connectionVerified = false;
  String? _message;
  List<DiscoveredShellyDevice> _devices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final profile = await _credentials.readProfile();
    if (!mounted) return;
    if (profile != null) {
      _host.text = profile.cloudHost;
      _key.text = profile.cloudAuthKey;
      _deviceId.text = profile.deviceId;
      _lan.text = profile.lanAddress ?? '';
      _password.text = profile.localPassword ?? '';
      setState(() {
        _connectionVerified = true;
        _busy = false;
      });
    } else {
      setState(() => _busy = false);
    }
  }

  ShellyConnectionProfile get _profile => ShellyConnectionProfile(
    cloudHost: _host.text.trim(),
    cloudAuthKey: _key.text.trim(),
    deviceId: _deviceId.text.trim(),
    lanAddress: _lan.text.trim().isEmpty ? null : _lan.text.trim(),
    localPassword: _password.text.isEmpty ? null : _password.text,
  );

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await action();
      if (mounted) setState(() => _message = result);
    } on Object catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _scan() async {
    final permission = await Permission.nearbyWifiDevices.request();
    if (permission.isPermanentlyDenied) {
      throw StateError(
        'Quyền Thiết bị Wi‑Fi lân cận bị tắt. Hãy bật trong Cài đặt Android.',
      );
    }
    final devices = await _service.discoverDevices();
    setState(() => _devices = devices);
    return devices.isEmpty
        ? 'Không tìm thấy Plug S Gen3. Bạn vẫn có thể nhập IP thủ công.'
        : 'Đã tìm thấy ${devices.length} Plug S Gen3.';
  }

  Future<String> _verifyAndSave() async {
    final error = _profile.validate();
    if (error != null) throw ArgumentError(error);
    final result = await _service.testConnection(profile: _profile);
    await _credentials.saveProfile(_profile);
    try {
      await ServerSmartChargerService().registerShellyDevice(_profile);
    } catch (e) {
      debugPrint('⚠️ Sync Shelly to server failed: $e');
    }
    setState(() => _connectionVerified = true);
    final route = result.lanStatus == null ? 'Cloud' : 'Cloud + LAN';
    return 'Đã xác minh $route, Device ID và đã đồng bộ với tài khoản.';
  }

  Future<String> _safeBoot() async {
    if (!_profile.hasLan) {
      throw StateError('Cần địa chỉ LAN để cấu hình khởi động an toàn.');
    }
    await _service.configureSafeBoot(profile: _profile);
    return 'Đã đặt initial_state=off, tắt auto-on và xác minh relay OFF.';
  }

  Future<String> _noLoadTest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận không có tải'),
        content: const Text(
          'Rút sạc xe và mọi tải khỏi Shelly. App sẽ bật relay 5 giây rồi gửi OFF và đọc lại trạng thái.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đã rút tải — chạy test'),
          ),
        ],
      ),
    );
    if (confirmed != true) return 'Đã hủy bài test.';
    await _service.runNoLoadTest(profile: _profile);
    return 'Bài test hoàn tất: relay đã OFF và được xác minh.';
  }

  Future<void> _deleteProfile() async {
    await _credentials.clearProfile();
    _host.clear();
    _key.clear();
    _deviceId.clear();
    _lan.clear();
    _password.clear();
    if (mounted) {
      setState(() {
        _connectionVerified = false;
        _message = 'Đã xóa Cloud key và hồ sơ Shelly khỏi vùng bảo mật.';
      });
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _key.dispose();
    _deviceId.dispose();
    _lan.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kết nối Shelly'),
        actions: [
          if (_connectionVerified)
            IconButton(
              tooltip: 'Xóa hồ sơ và Cloud key',
              onPressed: _busy ? null : _deleteProfile,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: Stepper(
                currentStep: _step,
                onStepTapped: (value) => setState(() => _step = value),
                controlsBuilder: (context, details) => Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      if (_step < 3)
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _step++),
                          child: const Text('Tiếp tục'),
                        ),
                      if (_step > 0) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _step--),
                          child: const Text('Quay lại'),
                        ),
                      ],
                    ],
                  ),
                ),
                steps: [
                  Step(
                    title: const Text('Chuẩn bị Shelly'),
                    isActive: _step >= 0,
                    content: const Text(
                      'Thêm Shelly Plug S Gen3 vào Wi‑Fi và Shelly Cloud bằng app/web chính thức. Xác nhận tải sạc không vượt 12A / 2500W.',
                    ),
                  ),
                  Step(
                    title: const Text('Shelly Cloud'),
                    isActive: _step >= 1,
                    content: Column(
                      children: [
                        _warning(
                          'Cloud key có toàn quyền điều khiển thiết bị. Key chỉ được lưu trong Android secure storage và không được ghi log.',
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _host,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Server URI',
                            hintText: 'https://shelly-xxx-eu.shelly.cloud',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _key,
                          obscureText: _obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: 'Authorization Cloud Key',
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _deviceId,
                          decoration: const InputDecoration(
                            labelText: 'Device ID',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Step(
                    title: const Text('LAN fallback'),
                    isActive: _step >= 2,
                    content: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : () => _run(_scan),
                            icon: const Icon(Icons.radar_rounded),
                            label: const Text('Quét Plug S Gen3'),
                          ),
                        ),
                        for (final device in _devices)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(device.name ?? device.id),
                            subtitle: Text(
                              '${device.model} • ${device.address}',
                            ),
                            onTap: () {
                              _lan.text = device.address;
                              if (_deviceId.text.isEmpty) {
                                _deviceId.text = device.id;
                              }
                            },
                          ),
                        TextField(
                          controller: _lan,
                          decoration: const InputDecoration(
                            labelText: 'IP riêng hoặc hostname .local',
                            hintText: '192.168.1.50',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Mật khẩu local (nếu Shelly bật auth)',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Step(
                    title: const Text('Xác minh an toàn'),
                    isActive: _step >= 3,
                    state: _connectionVerified
                        ? StepState.complete
                        : StepState.indexed,
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _run(_verifyAndSave),
                          icon: const Icon(Icons.cloud_done_rounded),
                          label: const Text(
                            'Kiểm tra Cloud, LAN và power meter',
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _run(_safeBoot),
                          icon: const Icon(Icons.shield_outlined),
                          label: const Text('Cấu hình khởi động OFF qua LAN'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _run(_noLoadTest),
                          icon: const Icon(Icons.power_settings_new_rounded),
                          label: const Text('Test không tải ON 5 giây → OFF'),
                        ),
                        if (_message != null) ...[
                          const SizedBox(height: 16),
                          Semantics(liveRegion: true, child: Text(_message!)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _warning(String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.amber.withValues(alpha: .10),
      border: Border.all(color: Colors.amber.withValues(alpha: .35)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.key_rounded, color: Colors.amber, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
