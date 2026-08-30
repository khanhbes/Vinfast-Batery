import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/widgets/app_popup.dart';
import '../../data/models/shelly_connection.dart';
import '../../data/models/smart_charger_binding.dart';
import '../../data/models/smart_charger_capabilities.dart';
import '../../data/repositories/smart_charger_repository.dart';
import '../../data/services/server_smart_charger_service.dart';
import '../../data/services/smart_charger_credentials_service.dart';
import '../../data/services/smart_charger_service.dart';

class SmartChargerSetupHubScreen extends StatefulWidget {
  const SmartChargerSetupHubScreen({super.key});

  @override
  State<SmartChargerSetupHubScreen> createState() => _SetupState();
}

class _SetupState extends State<SmartChargerSetupHubScreen> {
  final credentials = SmartChargerCredentialsService();
  final direct = SmartChargerService();
  final server = ServerSmartChargerService();
  final host = TextEditingController();
  final cloudKey = TextEditingController();
  final deviceId = TextEditingController();
  final lan = TextEditingController();
  final password = TextEditingController();

  SmartChargerConnectionMode mode = SmartChargerConnectionMode.serverCloud;
  SmartChargerBinding? binding;
  SmartChargerCapabilities capabilities = SmartChargerCapabilities.unavailable;
  SmartChargerVerificationState verification =
      SmartChargerVerificationState.unverified;
  List<DiscoveredShellyDevice> devices = const [];
  bool busy = true;
  bool obscure = true;
  bool dirty = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [host, cloudKey, deviceId, lan, password]) {
      controller.addListener(_changed);
    }
    _load();
  }

  void _changed() {
    if (!mounted || busy) return;
    if (!dirty) setState(() => dirty = true);
  }

  Future<void> _load() async {
    mode = await SmartChargerRepositoryFactory.currentMode();
    final active = await credentials.readProfile();
    final draft = await credentials.readDraft();
    final profile = draft ?? active;
    verification = await credentials.readVerification();
    if (profile != null) {
      host.text = profile.cloudHost;
      cloudKey.text = profile.cloudAuthKey;
      deviceId.text = profile.deviceId;
      lan.text = profile.lanAddress ?? '';
      password.text = profile.localPassword ?? '';
    }
    if (mode == SmartChargerConnectionMode.serverCloud) {
      try {
        binding = await server.getBinding();
        capabilities = await server.getCapabilities();
      } on SmartChargerException {
        capabilities = SmartChargerCapabilities.unavailable;
      }
    } else {
      capabilities = await direct.capabilities();
    }
    if (mounted)
      setState(() {
        busy = false;
        dirty = draft != null;
      });
  }

  ShellyConnectionProfile get profile => ShellyConnectionProfile(
    cloudHost: host.text.trim(),
    cloudAuthKey: cloudKey.text.trim(),
    deviceId: deviceId.text.trim(),
    lanAddress: lan.text.trim().isEmpty ? null : lan.text.trim(),
    localPassword: password.text.isEmpty ? null : password.text,
  );

  Future<bool> _guardInactive() async {
    try {
      final repository = await SmartChargerRepositoryFactory.create();
      final session = await repository.current();
      if (session != null && !session.state.isTerminal) {
        AppPopup.showWarning(
          'Đang có phiên sạc',
          detail: 'Hãy Tắt Sạc và xác minh relay OFF trước khi đổi cấu hình.',
        );
        return false;
      }
      return true;
    } on SmartChargerException catch (error) {
      if (error.code == 'notConfigured') return true;
      AppPopup.showWarning(
        'Chưa thể xác minh trạng thái relay',
        detail:
            'Không đổi cấu hình để tránh bỏ sót một phiên đang chạy. ${error.message}',
      );
      return false;
    }
  }

  Future<void> _selectMode(SmartChargerConnectionMode next) async {
    if (next == mode || !await _guardInactive()) return;
    setState(() {
      busy = true;
    });
    mode = next;
    if (next == SmartChargerConnectionMode.serverCloud) {
      try {
        binding = await server.getBinding();
        capabilities = await server.getCapabilities();
      } on SmartChargerException {
        capabilities = SmartChargerCapabilities.unavailable;
      }
    } else {
      capabilities = await direct.capabilities();
    }
    if (mounted)
      setState(() {
        busy = false;
      });
  }

  Future<void> _testEasy() async {
    setState(() => busy = true);
    try {
      binding = await server.getBinding();
      capabilities = await server.getCapabilities();
      if (capabilities.readyForControl) {
        await SmartChargerRepositoryFactory.setMode(
          SmartChargerConnectionMode.serverCloud,
        );
        AppPopup.showSuccess(
          'Easy đã kết nối',
          detail: 'Timer, status và OFF đã được xác minh.',
        );
      } else {
        AppPopup.showWarning(
          'Easy chưa khả dụng để điều khiển',
          detail:
              'Tài khoản chưa có Shelly Integrator license/capability timer. Hãy dùng Direct Cloud + LAN.',
        );
      }
    } on SmartChargerException catch (error) {
      AppPopup.showWarning('Easy chưa sẵn sàng', detail: error.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _scan() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final permission = await Permission.nearbyWifiDevices.request();
      if (permission.isPermanentlyDenied) {
        AppPopup.showError('Quyền Wi-Fi lân cận bị tắt');
        return;
      }
      devices = await direct.discoverDevices();
      AppPopup.showInfo(
        devices.isEmpty
            ? 'Không tìm thấy Plug S Gen3'
            : 'Đã tìm thấy ${devices.length} thiết bị',
        detail: devices.isEmpty
            ? 'Bạn vẫn có thể nhập IP riêng hoặc hostname .local.'
            : null,
      );
    } catch (e) {
      devices = const [];
      AppPopup.showInfo(
        'Không tìm thấy Plug S Gen3',
        detail:
            'Bạn có thể nhập trực tiếp địa chỉ IP hoặc hostname .local của thiết bị.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _saveAndVerify() async {
    if (!await _guardInactive()) return;
    final validation = profile.validate();
    if (validation != null) {
      AppPopup.showError('Cấu hình chưa hợp lệ', detail: validation);
      return;
    }
    setState(() => busy = true);
    await credentials.saveDraft(profile);
    final activeVerification = await credentials.readVerification();
    try {
      final result = await direct.testConnection(profile: profile);
      var next = SmartChargerVerificationState(
        cloudVerified: result.cloudStatus != null,
        lanVerified: result.lanStatus != null,
        powerMeterVerified: result.powerMeterAvailable,
        safeBootVerified: false,
        noLoadTestVerified: false,
        lastVerifiedAt: DateTime.now(),
      );
      if (profile.hasLan) {
        await direct.configureSafeBoot(profile: profile);
        next = next.copyWith(safeBootVerified: true);
      }
      verification = next;
      if (!profile.hasLan) {
        verification = activeVerification;
        AppPopup.showWarning(
          'Kết nối Cloud thành công nhưng chưa an toàn',
          detail:
              'Cần LAN để xác minh safe boot và chạy test không tải trước lần ON đầu.',
        );
        return;
      }
      final confirmed = await _confirmNoLoad();
      if (!confirmed) {
        verification = activeVerification;
        AppPopup.showWarning(
          'Đã lưu draft',
          detail: 'Cần hoàn tất test không tải để kích hoạt cấu hình.',
        );
        return;
      }
      await direct.runNoLoadTest(profile: profile);
      final verified = next.copyWith(
        noLoadTestVerified: true,
        lastVerifiedAt: DateTime.now(),
      );
      await credentials.saveProfile(profile);
      await credentials.saveVerification(verified);
      verification = verified;
      await credentials.clearDraft();
      await SmartChargerRepositoryFactory.setMode(
        SmartChargerConnectionMode.advancedDirect,
      );
      mode = SmartChargerConnectionMode.advancedDirect;
      capabilities = await direct.capabilities();
      dirty = false;
      AppPopup.showSuccess(
        result.cloudStatus != null && result.lanStatus != null
            ? 'Đã kết nối Cloud + LAN'
            : 'Đã kết nối giới hạn',
        detail: 'Safe boot, power meter và ON 5 giây → OFF đã được xác minh.',
      );
    } on Object catch (error) {
      verification = await credentials.readVerification();
      AppPopup.showError(
        'Kiểm tra kết nối thất bại',
        detail: 'Cấu hình đang dùng được giữ nguyên. ${error.toString()}',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _confirmNoLoad() async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Xác nhận chưa cắm tải'),
          content: const Text(
            'Rút sạc xe và mọi tải khỏi Shelly. App sẽ bật relay 5 giây, gửi OFF rồi đọc lại trạng thái.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Để sau'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ĐÃ RÚT TẢI · CHẠY TEST'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _delete() async {
    if (!await _guardInactive() || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa cấu hình Shelly?'),
        content: const Text(
          'Cloud key và mật khẩu local sẽ bị xóa khỏi Secure Storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await credentials.clearProfile();
    host.clear();
    cloudKey.clear();
    deviceId.clear();
    lan.clear();
    password.clear();
    verification = SmartChargerVerificationState.unverified;
    capabilities = SmartChargerCapabilities.unavailable;
    if (mounted) setState(() {});
    AppPopup.showSuccess('Đã xóa cấu hình Shelly');
  }

  @override
  void dispose() {
    for (final controller in [host, cloudKey, deviceId, lan, password]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ready = capabilities.readyForControl || verification.readyForControl;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Charger'),
        actions: [
          IconButton(
            tooltip: 'Xóa cấu hình',
            onPressed: busy ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          _StatusCard(
            ready: ready,
            mode: mode,
            capabilities: capabilities,
            verification: verification,
          ),
          const SizedBox(height: 20),
          SegmentedButton<SmartChargerConnectionMode>(
            segments: const [
              ButtonSegment(
                value: SmartChargerConnectionMode.serverCloud,
                label: Text('Easy / Server'),
                icon: Icon(Icons.cloud_rounded),
              ),
              ButtonSegment(
                value: SmartChargerConnectionMode.advancedDirect,
                label: Text('Direct'),
                icon: Icon(Icons.router_rounded),
              ),
            ],
            selected: {mode},
            onSelectionChanged: busy
                ? null
                : (value) => _selectMode(value.first),
          ),
          const SizedBox(height: 20),
          if (mode == SmartChargerConnectionMode.serverCloud) ...[
            Text(
              'Easy / Server',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Easy cần Shelly Integrator license và chỉ mở điều khiển khi backend xác minh timer, status và OFF.',
            ),
            if (binding != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('${binding!.displayName} · ${binding!.deviceId}'),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: busy ? null : _testEasy,
              icon: const Icon(Icons.fact_check_rounded),
              label: const Text('KIỂM TRA EASY'),
            ),
          ] else ...[
            Text(
              'Direct Cloud + LAN',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Cloud key chỉ lưu trong Android Secure Storage và không đồng bộ lên server.',
              style: TextStyle(color: colors.tertiary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: host,
              decoration: const InputDecoration(
                labelText: 'Shelly Cloud Server URI',
                hintText: 'https://shelly-xxx-eu.shelly.cloud',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cloudKey,
              obscureText: obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Authorization Cloud Key',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => obscure = !obscure),
                  icon: Icon(
                    obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: deviceId,
              decoration: const InputDecoration(labelText: 'Device ID'),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'LAN fallback',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: busy ? null : _scan,
                  icon: const Icon(Icons.radar_rounded),
                  label: const Text('QUÉT'),
                ),
              ],
            ),
            for (final device in devices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(device.name ?? device.id),
                subtitle: Text('${device.model} · ${device.address}'),
                onTap: () {
                  lan.text = device.address;
                  if (deviceId.text.isEmpty) deviceId.text = device.id;
                },
              ),
            TextField(
              controller: lan,
              decoration: const InputDecoration(
                labelText: 'IP riêng hoặc hostname .local',
                hintText: '192.168.1.50',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Mật khẩu local (nếu có)',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                key: const ValueKey('save-test-smart-charger'),
                onPressed: busy ? null : _saveAndVerify,
                icon: const Icon(Icons.verified_user_rounded),
                label: Text(dirty ? 'LƯU & KIỂM TRA KẾT NỐI' : 'KIỂM TRA LẠI'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.ready,
    required this.mode,
    required this.capabilities,
    required this.verification,
  });
  final bool ready;
  final SmartChargerConnectionMode mode;
  final SmartChargerCapabilities capabilities;
  final SmartChargerVerificationState verification;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready ? Icons.verified_rounded : Icons.shield_outlined,
                color: ready ? const Color(0xFF22C55E) : colors.tertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ready ? 'Sẵn sàng điều khiển' : 'Chưa hoàn tất xác minh',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            mode == SmartChargerConnectionMode.serverCloud
                ? 'Easy / Server'
                : 'Direct Cloud + LAN',
          ),
          Text(
            'Cloud ${_yes(capabilities.cloudAvailable || verification.cloudVerified)} · LAN ${_yes(capabilities.lanAvailable || verification.lanVerified)} · Power ${_yes(capabilities.canReadPower || verification.powerMeterVerified)}',
          ),
          Text(
            'Safe boot ${_yes(capabilities.safeBootVerified || verification.safeBootVerified)} · No-load ${_yes(capabilities.noLoadTestVerified || verification.noLoadTestVerified)}',
          ),
          if (verification.lastVerifiedAt != null)
            Text(
              'Kiểm tra gần nhất: ${DateFormat('dd/MM/yyyy HH:mm').format(verification.lastVerifiedAt!.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

String _yes(bool value) => value ? '✓' : '—';
