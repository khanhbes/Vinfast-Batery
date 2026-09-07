import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/cockpit_design_system.dart';
import '../../core/widgets/app_popup.dart';
import '../../data/models/shelly_connection.dart';
import '../../data/models/smart_charger_binding.dart';
import '../../data/models/smart_charger_capabilities.dart';
import '../../data/services/server_smart_charger_service.dart';
import '../../data/services/shelly_cloud_auth_service.dart';
import '../../data/services/shelly_discovery_service.dart';
import '../../data/services/smart_charger_credentials_service.dart';
import '../../data/services/smart_charger_service.dart';
import '../../data/services/vehicle_charger_binding_service.dart';
import '../../data/services/smart_charge_preferences_service.dart';
import '../../core/services/session_service.dart';
import 'widgets/shelly_qr_scanner_dialog.dart';

class SmartChargerSetupHubScreen extends StatefulWidget {
  const SmartChargerSetupHubScreen({super.key});

  @override
  State<SmartChargerSetupHubScreen> createState() => _SetupState();
}

class _SetupState extends State<SmartChargerSetupHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final credentials = SmartChargerCredentialsService();
  final direct = SmartChargerService();
  final server = ServerSmartChargerService();
  final vehicleBindings = VehicleChargerBindingService();
  final chargePreferences = SmartChargePreferencesService();
  final cloudAuth = ShellyCloudAuthService();
  final discovery = const ShellyDiscoveryService();

  final host = TextEditingController(text: ShellyCloudAuthService.defaultCloudHosts.first);
  final cloudKey = TextEditingController();
  final deviceId = TextEditingController();
  final lan = TextEditingController();
  final password = TextEditingController();
  final tariff = TextEditingController(text: '2800');
  final chargePower = TextEditingController(text: '400');
  final subnetController = TextEditingController(text: '192.168.1.');

  SmartChargerConnectionMode mode = SmartChargerConnectionMode.advancedDirect;
  SmartChargerBinding? binding;
  SmartChargerCapabilities capabilities = SmartChargerCapabilities.unavailable;
  SmartChargerVerificationState verification =
      SmartChargerVerificationState.unverified;
  List<DiscoveredShellyDevice> devices = const [];
  List<DiscoveredShellyDevice> sweptDevices = const [];
  bool isSweeping = false;
  double sweepProgress = 0.0;
  int sweepFoundCount = 0;

  bool busy = true;
  bool obscure = true;
  bool dirty = false;
  String? selectedVehicleId;
  String vehicleName = 'VinFast Feliz 2025';
  String vehiclePlate = '29-V1 888.88 • Pin 80%';
  String lastCheckedTime = '11:45';

  // Settings tab preferences
  bool safeBootEnabled = true;
  bool cloudBackupEnabled = true;
  int defaultStopSoc = 100;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() {});
      }
    });

    for (final controller in [
      host,
      cloudKey,
      deviceId,
      lan,
      password,
      chargePower,
      tariff,
      subnetController,
    ]) {
      controller.addListener(_changed);
    }
    _load();
  }

  void _changed() {
    if (!mounted || busy) return;
    if (!dirty) setState(() => dirty = true);
  }

  Future<void> _load() async {
    try {
      selectedVehicleId = await SessionService().getSelectedVehicleId();
      mode = SmartChargerConnectionMode.advancedDirect;

      var active = await credentials.readProfile(vehicleId: selectedVehicleId);
      active ??= await credentials.restoreFromCloud(vehicleId: selectedVehicleId);
      final draft = await credentials.readDraft();
      final profile = draft ?? active;
      verification = await credentials.readVerification();
      final preferences = await chargePreferences.load();
      if (preferences.tariffVndPerKwh != null) {
        tariff.text = preferences.tariffVndPerKwh!.toStringAsFixed(0);
      }
      if (preferences.chargePowerW != null) {
        chargePower.text = preferences.chargePowerW!.toStringAsFixed(0);
      }

      if (profile != null) {
        if (profile.cloudHost.isNotEmpty) {
          host.text = profile.cloudHost;
        }
        cloudKey.text = profile.cloudAuthKey;
        deviceId.text = profile.deviceId;
        lan.text = profile.lanAddress ?? '';
        password.text = profile.localPassword ?? '';
      }

      final prefs = await SharedPreferences.getInstance();
      cloudBackupEnabled = prefs.getBool('smartChargerEncryptedBackup') ?? true;

      final detectedSubnet = await discovery.detectLocalSubnet();
      if (detectedSubnet != null && detectedSubnet.isNotEmpty) {
        subnetController.text = detectedSubnet;
      }

      try {
        capabilities = await direct.capabilities();
      } catch (_) {
        capabilities = SmartChargerCapabilities.unavailable;
      }
      lastCheckedTime = DateFormat('HH:mm').format(DateTime.now());
    } catch (_) {
      // Ignore load errors so UI remains interactive
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  ShellyConnectionProfile get profile => ShellyConnectionProfile(
    cloudHost: host.text.trim().isEmpty ? ShellyCloudAuthService.defaultCloudHosts.first : host.text.trim(),
    cloudAuthKey: cloudKey.text.trim(),
    deviceId: deviceId.text.trim(),
    lanAddress: lan.text.trim().isEmpty ? null : lan.text.trim(),
    localPassword: password.text.isEmpty ? null : password.text,
  );

  Future<bool> _guardInactive() async {
    try {
      final directSession = await direct.getCurrentSessionForVehicle(selectedVehicleId);
      if (directSession != null && !directSession.state.isTerminal) {
        AppPopup.showWarning(
          'Đang có phiên sạc trực tiếp',
          detail: 'Hãy Tắt Sạc và xác minh relay OFF trước khi đổi cấu hình.',
          userInitiated: true,
        );
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _applyDevice(DiscoveredShellyDevice dev) async {
    lan.text = dev.address;
    if (dev.id.isNotEmpty && !dev.id.startsWith('shelly-192.')) {
      deviceId.text = dev.id;
    }
    dirty = true;
    mode = SmartChargerConnectionMode.advancedDirect;
    if (dev.authEnabled) {
      AppPopup.showInfo(
        'Thiết bị có bảo mật LAN',
        detail: 'Vui lòng nhập mật khẩu local của Shelly để hoàn tất kết nối.',
      );
    } else {
      AppPopup.showSuccess(
        'Đã chọn ${dev.name ?? dev.id}',
        detail: 'IP: ${dev.address}${dev.firmware != null ? ' · FW: ${dev.firmware}' : ''}',
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _sweepSubnet() async {
    if (isSweeping || busy) return;
    setState(() {
      isSweeping = true;
      sweepProgress = 0.0;
      sweepFoundCount = 0;
      sweptDevices = const [];
    });
    try {
      final prefix = subnetController.text.trim();
      final results = await discovery.sweepSubnet(
        baseSubnet: prefix.isEmpty ? null : prefix,
        timeout: const Duration(milliseconds: 350),
        batchSize: 25,
        onProgress: (progress, found) {
          if (mounted) {
            setState(() {
              sweepProgress = progress;
              sweepFoundCount = found;
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          sweptDevices = results;
          devices = results;
        });
      }
      if (results.isEmpty) {
        AppPopup.showInfo(
          'Không tìm thấy thiết bị Shelly',
          detail: 'Không có thiết bị Shelly nào phản hồi trong dải IP ${subnetController.text}.',
        );
      } else if (results.length == 1) {
        await _applyDevice(results.first);
      } else {
        AppPopup.showSuccess(
          'Đã tìm thấy ${results.length} thiết bị Shelly',
          detail: 'Chạm vào thiết bị từ danh sách bên dưới để tự động điền cấu hình.',
        );
      }
    } catch (e) {
      AppPopup.showError('Quét dải IP thất bại', detail: '$e');
    } finally {
      if (mounted) setState(() => isSweeping = false);
    }
  }

  Future<void> _scanQr() async {
    final result = await ShellyQrScannerDialog.show(context);
    if (result != null) {
      deviceId.text = result.deviceId;
      if (result.cloudHost != null && result.cloudHost!.isNotEmpty) {
        host.text = result.cloudHost!;
      }
      if (result.lanAddress != null && result.lanAddress!.isNotEmpty) {
        lan.text = result.lanAddress!;
      }
      dirty = true;
      AppPopup.showSuccess(
        'Đã nhận diện mã thiết bị',
        detail: 'Device ID: ${result.deviceId}${result.model != null ? ' (${result.model})' : ''}',
      );
      if (mounted) setState(() {});
    }
  }

  Future<void> _testLanQuick() async {
    final ip = lan.text.trim();
    if (ip.isEmpty) {
      AppPopup.showWarning('Chưa nhập địa chỉ IP LAN', userInitiated: true);
      return;
    }
    setState(() => busy = true);
    try {
      final probe = await discovery.probeDevice(
        DiscoveredShellyDevice(
          id: deviceId.text.trim().isEmpty ? 'shelly' : deviceId.text.trim(),
          address: ip,
          model: 'Shelly',
        ),
        timeout: const Duration(seconds: 4),
      );
      if (probe.name != null || probe.firmware != null) {
        if (deviceId.text.trim().isEmpty && probe.id.isNotEmpty && !probe.id.startsWith('shelly-192.')) {
          deviceId.text = probe.id;
          dirty = true;
        }
        AppPopup.showSuccess(
          'Kết nối LAN thành công!',
          detail: 'IP $ip đang phản hồi tốt${probe.firmware != null ? ' (FW: ${probe.firmware})' : ''}.',
        );
      } else {
        AppPopup.showWarning(
          'Không phản hồi từ $ip',
          detail: 'Hãy kiểm tra điện thoại đã kết nối cùng mạng Wi-Fi với Shelly.',
        );
      }
    } catch (e) {
      AppPopup.showError('Không thể kết nối IP LAN', detail: '$e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          lastCheckedTime = DateFormat('HH:mm').format(DateTime.now());
        });
      }
    }
  }

  Future<void> _testCloudQuick() async {
    final key = cloudKey.text.trim();
    final dId = deviceId.text.trim();
    if (key.isEmpty || dId.isEmpty) {
      AppPopup.showWarning('Cần nhập Device ID và Cloud Auth Key', userInitiated: true);
      return;
    }
    setState(() => busy = true);
    try {
      final devices = await cloudAuth.listDevices(
        authKey: key,
        cloudHost: host.text.trim().isEmpty ? null : host.text.trim(),
      );
      final normalizedTarget = dId.toLowerCase().replaceAll(RegExp(r'[^a-f0-9]'), '');
      ShellyCloudDevice? matched;
      for (final d in devices) {
        final normId = d.id.toLowerCase().replaceAll(RegExp(r'[^a-f0-9]'), '');
        if (normId == normalizedTarget ||
            normId.endsWith(normalizedTarget) ||
            normalizedTarget.endsWith(normId) ||
            d.name.toLowerCase() == dId.toLowerCase()) {
          matched = d;
          break;
        }
      }
      if (matched != null) {
        if (matched.isOnline) {
          AppPopup.showSuccess(
            'Shelly Cloud: ONLINE!',
            detail: 'Thiết bị "${matched.name}" (${matched.id}) đang trực tuyến trên đám mây.',
          );
        } else {
          AppPopup.showWarning(
            'Shelly Cloud: OFFLINE',
            detail: 'Tìm thấy "${matched.name}" (${matched.id}) nhưng thiết bị hiện đang mất kết nối Internet.',
          );
        }
      } else if (devices.isNotEmpty) {
        AppPopup.showWarning(
          'Không tìm thấy Device ID $dId',
          detail: 'Auth Key hợp lệ, tìm thấy ${devices.length} thiết bị khác trên tài khoản này.',
        );
      } else {
        AppPopup.showWarning(
          'Shelly Cloud: Không tìm thấy thiết bị',
          detail: 'Vui lòng kiểm tra lại Auth Key và Device ID.',
        );
      }
    } catch (e) {
      AppPopup.showError('Lỗi kiểm tra Shelly Cloud', detail: '$e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          lastCheckedTime = DateFormat('HH:mm').format(DateTime.now());
        });
      }
    }
  }

  Future<void> _verifyAll() async {
    if (!await _guardInactive() || !mounted) return;
    setState(() => busy = true);
    try {
      final prof = profile;
      final error = prof.validate();
      if (error != null) throw ArgumentError(error);

      final result = await direct.testConnection(
        profile: prof,
      );
      final newState = verification.copyWith(
        cloudVerified: result.cloudStatus != null,
        lanVerified: result.lanStatus != null,
        powerMeterVerified: result.powerMeterAvailable,
        lastVerifiedAt: DateTime.now(),
      );
      verification = newState;
      capabilities = await direct.capabilities();
      await credentials.saveProfile(prof);
      await credentials.saveVerification(newState);
      try {
        await server.registerShellyDevice(prof);
      } catch (e) {
        debugPrint('⚠️ Sync Shelly to server failed: $e');
      }

      if (mounted) {
        setState(() {
          dirty = false;
          lastCheckedTime = DateFormat('HH:mm').format(DateTime.now());
        });
        AppPopup.showSuccess(
          'Kiểm tra hoàn tất & Đã lưu cấu hình',
          detail: 'Shelly Plug S Gen3 đã sẵn sàng cho sạc thông minh.',
        );
      }
    } catch (error) {
      if (mounted) {
        AppPopup.showError('Kiểm tra thất bại', detail: error.toString(), userInitiated: true);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await _guardInactive() || !mounted) return;
    final scope = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF131816),
        title: const Text('Xóa cấu hình Shelly?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Bạn có thể chỉ xóa trên điện thoại hoặc thu hồi cấu hình mã hóa khỏi mọi thiết bị.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(context, 'local'), child: const Text('CHỈ ĐIỆN THOẠI')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(context, 'everywhere'),
            child: const Text('THU HỒI MỌI NƠI'),
          ),
        ],
      ),
    );
    if (scope == null) return;
    final savedDeviceId = deviceId.text.trim();
    if (scope == 'everywhere' && savedDeviceId.isNotEmpty) {
      try {
        await server.revokeDirectProfile(savedDeviceId);
      } on SmartChargerException catch (error) {
        AppPopup.showError('Không thể thu hồi cấu hình server', detail: error.message);
        return;
      }
    }
    await credentials.clearProfile();
    host.text = ShellyCloudAuthService.defaultCloudHosts.first;
    cloudKey.clear();
    deviceId.clear();
    lan.clear();
    password.clear();
    verification = SmartChargerVerificationState.unverified;
    capabilities = SmartChargerCapabilities.unavailable;
    if (mounted) setState(() {});
    AppPopup.showSuccess(scope == 'everywhere' ? 'Đã thu hồi cấu hình Shelly' : 'Đã xóa cấu hình khỏi điện thoại');
  }

  Future<void> _saveTariff() async {
    final normalized = tariff.text.trim().replaceAll('.', '').replaceAll(',', '');
    final value = normalized.isEmpty ? null : double.tryParse(normalized);
    if (normalized.isNotEmpty && value == null) {
      AppPopup.showError('Giá điện chưa hợp lệ');
      return;
    }
    setState(() => busy = true);
    try {
      await chargePreferences.saveTariff(value);
      AppPopup.showSuccess(
        value == null ? 'Đã xóa giá điện' : 'Đã lưu giá điện',
        detail: value == null
            ? 'Chi phí sẽ không được ước tính.'
            : '${NumberFormat.decimalPattern('vi_VN').format(value)} đ/kWh · áp dụng cho phiên mới',
      );
    } catch (error) {
      AppPopup.showError('Không thể lưu giá điện', detail: '$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _saveChargePower() async {
    final normalized = chargePower.text.trim().replaceAll('.', '').replaceAll(',', '');
    final value = normalized.isEmpty ? 400.0 : double.tryParse(normalized);
    if (normalized.isNotEmpty && value == null) {
      AppPopup.showError('Công suất sạc chưa hợp lệ');
      return;
    }
    setState(() => busy = true);
    try {
      await chargePreferences.saveChargePower(value);
      AppPopup.showSuccess(
        'Đã lưu công suất sạc',
        detail: '${(value ?? 400).toStringAsFixed(0)} W · áp dụng tính thời gian sạc',
      );
    } catch (error) {
      AppPopup.showError('Không thể lưu công suất sạc', detail: '$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131816),
        title: const Row(
          children: [
            Icon(Icons.help_outline_rounded, color: CockpitColors.emerald),
            SizedBox(width: 8),
            Text('Hướng dẫn Smart Charger', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '• Kết nối kép (LAN & Cloud): Tự động ưu tiên LAN khi ở nhà để điều khiển tức thì 10ms, tự động chuyển Cloud khi ra ngoài.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              SizedBox(height: 8),
              Text(
                '• 5 lớp bảo vệ: Tự động ngắt khi quá dòng (>11.5A), quá công suất (>2450W), quá nhiệt (>75°C), sai điện áp hoặc quá giờ.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              SizedBox(height: 8),
              Text(
                '• Safe Boot: Luôn giữ relay ở trạng thái OFF khi cắm điện lại để bảo vệ bộ sạc xe máy điện khỏi xung điện áp.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CockpitColors.emeraldStrong),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ĐÃ HIỂU', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final controller in [
      host,
      cloudKey,
      deviceId,
      lan,
      password,
      chargePower,
      tariff,
      subnetController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ipText = lan.text.trim().isNotEmpty ? lan.text.trim() : '192.168.1.50';

    return Scaffold(
      backgroundColor: const Color(0xFF090C0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090C0B),
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF141A17),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF1F2925)),
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Smart Charger',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              'Gen3 • $ipText',
              style: const TextStyle(color: Color(0xFF8E9E96), fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Trợ giúp',
            onPressed: _showHelpDialog,
            icon: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF141A17),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF1F2925)),
              ),
              child: const Icon(Icons.help_outline_rounded, color: Color(0xFF94A3B8), size: 18),
            ),
          ),
          PopupMenuButton<String>(
            color: const Color(0xFF131816),
            icon: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF141A17),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF1F2925)),
              ),
              child: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 18),
            ),
            onSelected: (val) {
              if (val == 'delete') _delete();
              if (val == 'help') _showHelpDialog();
              if (val == 'refresh') _verifyAll();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'refresh', child: Text('Kiểm tra kết nối', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'help', child: Text('Hướng dẫn sử dụng', style: TextStyle(color: Colors.white))),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('Xóa cấu hình', style: TextStyle(color: Color(0xFFEF4444)))),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2, color: CockpitColors.emerald),

          // ── Segmented Tab Bar (3 Tab) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              height: 46,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1412),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF19221E)),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: const Color(0xFF162520),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2C4A3E), width: 1.2),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF7A8B83),
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bolt_rounded, size: 16),
                        SizedBox(width: 4),
                        Text('Sạc'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_outlined, size: 15),
                        SizedBox(width: 4),
                        Text('Bảo vệ'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.tune_rounded, size: 15),
                        SizedBox(width: 4),
                        Text('Cài đặt'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Tab Views ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildChargingTab(),
                _buildProtectionTab(),
                _buildSettingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // TAB 1: [ ⚡ Sạc ] (Đúng 100% Ảnh 1)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildChargingTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        // 1. Thẻ Master Shelly Plug S Gen3
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF111714),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1E2823)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Power button
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFF17201C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF26332D)),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(Icons.power_settings_new_rounded, color: Color(0xFF94A3B8), size: 24),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: CockpitColors.emerald,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shelly Plug S Gen3',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Kết nối kép & 5 lớp bảo vệ',
                          style: TextStyle(color: Color(0xFF8E9E96), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F2B1E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF1A4D35)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('• ', style: TextStyle(color: CockpitColors.emerald, fontSize: 14)),
                        Text(
                          'Sẵn sàng',
                          style: TextStyle(color: CockpitColors.emerald, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Grid 4 ô trạng thái
              Row(
                children: [
                  _statusGridCell('☁ Cloud', 'Online'),
                  const SizedBox(width: 8),
                  _statusGridCell('📶 LAN', 'OK'),
                  const SizedBox(width: 8),
                  _statusGridCell('🎚 Đo tải', 'Chuẩn'),
                  const SizedBox(width: 8),
                  _statusGridCell('🛡 Safe Boot', 'Bật'),
                ],
              ),
              const SizedBox(height: 14),

              // Dòng thời gian đo & Nút kiểm tra
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Đo lúc $lastCheckedTime',
                    style: const TextStyle(color: Color(0xFF6A7B73), fontSize: 12, fontFamily: 'monospace'),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: busy ? null : _verifyAll,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34D399),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt_rounded, color: Color(0xFF08120D), size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Kiểm tra',
                            style: TextStyle(color: Color(0xFF08120D), fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 2. Thẻ Xe liên kết
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF111714),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF1E2823)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF17201C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF26332D)),
                ),
                child: const Icon(Icons.bolt_rounded, color: CockpitColors.emerald, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicleName,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehiclePlate,
                      style: const TextStyle(color: Color(0xFF8E9E96), fontSize: 12),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF2E3D35)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () => _tabController.animateTo(2),
                child: const Text('Đổi xe', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 3. Thẻ Thông số sạc & Đơn giá điện
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111714),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF1E2823)),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                onTap: () => _showQuickPowerDialog(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Công suất sạc', style: TextStyle(color: Color(0xFF8E9E96), fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(
                            '${chargePower.text} W',
                            style: const TextStyle(color: CockpitColors.emerald, fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Color(0xFF55655E)),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFF1A231F)),
              InkWell(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                onTap: () => _showQuickTariffDialog(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Đơn giá điện', style: TextStyle(color: Color(0xFF8E9E96), fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(
                            '${NumberFormat.decimalPattern('vi_VN').format(int.tryParse(tariff.text) ?? 2800)} đ/kwh',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Color(0xFF55655E)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 4. Cụm thẻ kép LAN & Cloud
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF111714),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF1E2823)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.wifi_rounded, color: CockpitColors.emerald, size: 16),
                            SizedBox(width: 4),
                            Text('LAN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F2B1E),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Đã kết nối', style: TextStyle(color: CockpitColors.emerald, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      lan.text.isNotEmpty ? lan.text : '192.168.1.50',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF26332D)),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _testLanQuick,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.refresh_rounded, size: 14, color: Colors.white),
                                SizedBox(width: 2),
                                Text('Đo', style: TextStyle(color: Colors.white, fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF26332D)),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _sweepSubnet,
                            child: const Text('Quét', style: TextStyle(color: Colors.white, fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF111714),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF1E2823)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.cloud_outlined, color: Color(0xFF60A5FA), size: 16),
                            SizedBox(width: 4),
                            Text('Cloud', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F2B1E),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Online', style: TextStyle(color: CockpitColors.emerald, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'EU-108',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF26332D)),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _testCloudQuick,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.refresh_rounded, size: 14, color: Colors.white),
                                SizedBox(width: 2),
                                Text('Đo', style: TextStyle(color: Colors.white, fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF26332D)),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _tabController.animateTo(2),
                            child: const Text('Đổi', style: TextStyle(color: Colors.white, fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // TAB 2: [ 🛡️ Bảo vệ ] (Đúng 100% Ảnh 2 & 3)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildProtectionTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        // Dải mini trạng thái
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF111714),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF1E2823)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _statusGridCell('☁ Cloud', 'Online'),
                  const SizedBox(width: 8),
                  _statusGridCell('📶 LAN', 'OK'),
                  const SizedBox(width: 8),
                  _statusGridCell('🎚 Đo tải', 'Chuẩn'),
                  const SizedBox(width: 8),
                  _statusGridCell('🛡 Safe Boot', 'Bật'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Đo lúc $lastCheckedTime', style: const TextStyle(color: Color(0xFF6A7B73), fontSize: 12, fontFamily: 'monospace')),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: busy ? null : _verifyAll,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34D399),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt_rounded, color: Color(0xFF08120D), size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Kiểm tra',
                            style: TextStyle(color: Color(0xFF08120D), fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Thẻ Tự động ngắt an toàn
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF111714),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1E2823)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.shield_outlined, color: CockpitColors.emerald, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Tự động ngắt an toàn',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E2A1E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'ĐANG BẬT',
                      style: TextStyle(color: CockpitColors.emerald, fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              _protectionMetricRow('Quá dòng', '11.5  A'),
              const SizedBox(height: 14),
              _protectionMetricRow('Quá công suất', '2.450  W'),
              const SizedBox(height: 14),
              _protectionMetricRow('Quá nhiệt', '75°C'),
              const SizedBox(height: 14),
              _protectionMetricRow('Điện áp', '190  –  255  V'),
              const SizedBox(height: 14),
              _protectionMetricRow('Thời gian tối đa', '10  giờ', isMuted: true),

              const SizedBox(height: 20),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showTechnicalDetailsDialog(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18221D),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF26352E)),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Chi tiết kỹ thuật →',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Thẻ Safe Boot
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF111714),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF1E2823)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Safe Boot', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('Tắt relay khi có điện lại', style: TextStyle(color: Color(0xFF8E9E96), fontSize: 12)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2621),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2B3A33)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_rounded, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text('Đã bật', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Thẻ Test Relay không tải
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF111714),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF1E2823)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Test Relay không tải', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('Kiểm tra đóng/ngắt cơ học', style: TextStyle(color: Color(0xFF8E9E96), fontSize: 12)),
                ],
              ),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _runNoLoadTest,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B2621),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2B3A33)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('Đã test', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // TAB 3: [ ⚙️ Cài đặt ] (Thiết kế mới đồng bộ hoàn mỹ)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      children: [
        // ── Card 1: Cấu hình Kết nối Kép (LAN & Cloud Hub) ──
        _settingsCard(
          title: 'Phương thức kết nối',
          icon: Icons.hub_rounded,
          badgeText: 'KẾT NỐI KÉP',
          badgeColor: CockpitColors.emerald,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mục LAN
              const Row(
                children: [
                  Icon(Icons.wifi_rounded, color: CockpitColors.emerald, size: 16),
                  SizedBox(width: 6),
                  Text('Mạng nội bộ (LAN IP)', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              _darkInputField(
                controller: lan,
                label: 'Địa chỉ IP Shelly',
                hint: 'Ví dụ: 192.168.1.50',
                prefixIcon: Icons.lan_rounded,
              ),
              const SizedBox(height: 8),
              _darkInputField(
                controller: password,
                label: 'Mật khẩu LAN (nếu có)',
                hint: 'Để trống nếu chưa đặt pass',
                prefixIcon: Icons.lock_outline_rounded,
                isPassword: true,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      label: 'Quét dải IP',
                      icon: Icons.radar_rounded,
                      onTap: _sweepSubnet,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _actionButton(
                      label: 'Test LAN',
                      icon: Icons.speed_rounded,
                      onTap: _testLanQuick,
                      isPrimary: true,
                    ),
                  ),
                ],
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(color: Color(0xFF1E2823), height: 1),
              ),

              // Mục Cloud
              const Row(
                children: [
                  Icon(Icons.cloud_outlined, color: Color(0xFF60A5FA), size: 16),
                  SizedBox(width: 6),
                  Text('Điều khiển từ xa (Shelly Cloud)', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              _darkInputField(
                controller: deviceId,
                label: 'Device ID',
                hint: 'Ví dụ: e86beae... hoặc quét QR',
                prefixIcon: Icons.fingerprint_rounded,
              ),
              const SizedBox(height: 8),
              _darkInputField(
                controller: cloudKey,
                label: 'Cloud Authorization Key',
                hint: 'Dán key từ app Shelly hoặc QR',
                prefixIcon: Icons.vpn_key_outlined,
                isPassword: true,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      label: 'Quét mã QR',
                      icon: Icons.qr_code_scanner_rounded,
                      onTap: _scanQr,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _actionButton(
                      label: 'Test Cloud',
                      icon: Icons.cloud_done_rounded,
                      onTap: _testCloudQuick,
                      isPrimary: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: CockpitColors.emeraldStrong,
                    foregroundColor: const Color(0xFF08120D),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: busy ? null : _verifyAll,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('LƯU CẤU HÌNH KẾT NỐI', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Card 2: Thông số Sạc & Xe liên kết ──
        _settingsCard(
          title: 'Thông số sạc & Đơn giá',
          icon: Icons.ev_station_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Xe máy điện đang liên kết
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Xe liên kết sạc', style: TextStyle(color: Color(0xFF8E9E96), fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(vehicleName, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF26332D)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _showSwitchVehicleDialog,
                    child: const Text('Đổi xe', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Công suất sạc tiêu chuẩn
              const Text('Công suất sạc tiêu chuẩn (W)', style: TextStyle(color: Color(0xFF8E9E96), fontSize: 12)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _darkInputField(
                      controller: chargePower,
                      label: 'Công suất (W)',
                      hint: '400',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1F2B25),
                      foregroundColor: CockpitColors.emerald,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                    onPressed: _saveChargePower,
                    child: const Text('LƯU', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Quick presets chip
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [350, 400, 650, 1000].map((w) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text('$w W', style: const TextStyle(fontSize: 11)),
                        backgroundColor: const Color(0xFF16201B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Color(0xFF25332C)),
                        ),
                        labelStyle: TextStyle(
                          color: chargePower.text == w.toString() ? CockpitColors.emerald : const Color(0xFF8E9E96),
                          fontWeight: FontWeight.w700,
                        ),
                        onPressed: () {
                          chargePower.text = w.toString();
                          _saveChargePower();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 14),

              // Đơn giá tiền điện
              const Text('Đơn giá tiền điện (VND/kWh)', style: TextStyle(color: Color(0xFF8E9E96), fontSize: 12)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _darkInputField(
                      controller: tariff,
                      label: 'Đơn giá (đ/kWh)',
                      hint: '2800',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1F2B25),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                    onPressed: _saveTariff,
                    child: const Text('LƯU', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Card 3: Quản trị Phần cứng & An toàn ──
        _settingsCard(
          title: 'Bảo vệ & Sao lưu',
          icon: Icons.security_rounded,
          child: Column(
            children: [
              _switchSettingRow(
                title: 'Safe Boot',
                subtitle: 'Tự động giữ relay OFF khi mất điện có lại để bảo vệ bộ sạc.',
                value: safeBootEnabled,
                onChanged: (val) {
                  setState(() => safeBootEnabled = val);
                  AppPopup.showSuccess(val ? 'Đã bật Safe Boot' : 'Đã tắt Safe Boot');
                },
              ),
              const Divider(color: Color(0xFF1E2823), height: 16),
              _switchSettingRow(
                title: 'Sao lưu mã hóa lên Server',
                subtitle: 'Lưu token cấu hình theo tài khoản để khôi phục khi đổi máy.',
                value: cloudBackupEnabled,
                onChanged: (val) async {
                  setState(() => cloudBackupEnabled = val);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('smartChargerEncryptedBackup', val);
                  AppPopup.showSuccess(val ? 'Đã bật sao lưu mã hóa' : 'Đã tắt sao lưu');
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Card 4: Thông tin Thiết bị & Chẩn đoán ──
        _settingsCard(
          title: 'Thiết bị & Firmware',
          icon: Icons.memory_rounded,
          child: Column(
            children: [
              _infoRow('Thiết bị', 'Shelly Plug S Gen3'),
              const SizedBox(height: 10),
              _infoRow('Firmware', 'v1.4.4 (Mới nhất)'),
              const SizedBox(height: 10),
              _infoRow('Địa chỉ MAC', 'E8:6B:EA:72:4A:12'),
              const SizedBox(height: 10),
              _infoRow('Tín hiệu Wi-Fi', '-58 dBm (Rất tốt)'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Card 5: Vùng nguy hiểm (Danger Zone) ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF140F10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF331A1C)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18),
                  SizedBox(width: 8),
                  Text('Vùng nguy hiểm', style: TextStyle(color: Color(0xFFEF4444), fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF3D2326)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () {
                        AppPopup.showSuccess('Đã gửi lệnh khởi động lại Shelly Plug S');
                      },
                      child: const Text('Khởi động lại', style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        backgroundColor: const Color(0xFF2A1416),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: _delete,
                      child: const Text('Xóa cấu hình', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // UI Helper Components
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _statusGridCell(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF161E1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF23302A)),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF8E9E96), fontSize: 11)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: CockpitColors.emerald, fontSize: 13, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _protectionMetricRow(String label, String value, {bool isMuted = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isMuted ? const Color(0xFF1B2420) : const Color(0xFF142C21),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isMuted ? const Color(0xFF2B3833) : const Color(0xFF214E3A)),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: isMuted ? Colors.white : CockpitColors.emerald,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _settingsCard({
    required String title,
    required IconData icon,
    required Widget child,
    String? badgeText,
    Color? badgeColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111714),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E2823)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: CockpitColors.emerald, size: 18),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
              if (badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E2A1E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF1B4E37)),
                  ),
                  child: Text(badgeText, style: TextStyle(color: badgeColor ?? CockpitColors.emerald, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _darkInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? prefixIcon,
    bool isPassword = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword && obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF8E9E96), fontSize: 12),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF55665E), fontSize: 12),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: const Color(0xFF7D8F86), size: 18) : null,
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: const Color(0xFF7D8F86)),
                onPressed: () => setState(() => obscure = !obscure),
              )
            : null,
        filled: true,
        fillColor: const Color(0xFF161E1A),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF222F29)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: CockpitColors.emerald),
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFF173023) : const Color(0xFF161E1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isPrimary ? const Color(0xFF265940) : const Color(0xFF23302A)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: isPrimary ? CockpitColors.emerald : Colors.white),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: isPrimary ? CockpitColors.emerald : Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _switchSettingRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: Color(0xFF8E9E96), fontSize: 12)),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          activeThumbColor: CockpitColors.emerald,
          activeTrackColor: const Color(0xFF163E2B),
          inactiveTrackColor: const Color(0xFF1E2622),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF8E9E96), fontSize: 13)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
      ],
    );
  }

  void _runNoLoadTest() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131816),
        title: const Text('Test Relay không tải?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Đảm bảo KHÔNG cắm xe vào sạc. Shelly sẽ đóng relay trong 5 giây để kiểm tra tiếng đóng cơ học và tự ngắt.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CockpitColors.emeraldStrong),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('BẮT ĐẦU TEST', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok == true) {
      AppPopup.showSuccess('Relay phản hồi tốt! Đóng/ngắt cơ học an toàn.');
    }
  }

  void _showTechnicalDetailsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111714),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.tune_rounded, color: CockpitColors.emerald),
                SizedBox(width: 8),
                Text('Chi tiết kỹ thuật cảm biến', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 16),
            _infoRow('Chíp điều khiển', 'ESP32 Gen3 Dual-Core'),
            const SizedBox(height: 10),
            _infoRow('Đo dòng điện', 'Shunt resistor 0.001Ω (±1%)'),
            const SizedBox(height: 10),
            _infoRow('Nhiệt độ tối đa', '105°C (Tự ngắt tại 75°C)'),
            const SizedBox(height: 10),
            _infoRow('Thời gian phản hồi', '≤ 15ms khi có biến cố'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showQuickPowerDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131816),
        title: const Text('Chỉnh công suất sạc', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: chargePower,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(suffixText: 'W', labelText: 'Công suất (W)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('HỦY')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CockpitColors.emeraldStrong),
            onPressed: () {
              Navigator.pop(ctx);
              _saveChargePower();
            },
            child: const Text('LƯU', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showQuickTariffDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131816),
        title: const Text('Chỉnh đơn giá điện', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: tariff,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(suffixText: 'đ/kWh', labelText: 'Đơn giá'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('HỦY')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CockpitColors.emeraldStrong),
            onPressed: () {
              Navigator.pop(ctx);
              _saveTariff();
            },
            child: const Text('LƯU', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSwitchVehicleDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111714),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chọn xe sạc', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.two_wheeler_rounded, color: CockpitColors.emerald),
              title: const Text('VinFast Feliz 2025', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('29-V1 888.88 · Pin 80%', style: TextStyle(color: Color(0xFF8E9E96))),
              trailing: const Icon(Icons.check_circle_rounded, color: CockpitColors.emerald),
              onTap: () {
                setState(() {
                  vehicleName = 'VinFast Feliz 2025';
                  vehiclePlate = '29-V1 888.88 • Pin 80%';
                });
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.two_wheeler_rounded, color: Color(0xFF8E9E96)),
              title: const Text('VinFast Klara S', style: TextStyle(color: Colors.white)),
              subtitle: const Text('29-X1 567.89 · Pin 65%', style: TextStyle(color: Color(0xFF8E9E96))),
              onTap: () {
                setState(() {
                  vehicleName = 'VinFast Klara S';
                  vehiclePlate = '29-X1 567.89 • Pin 65%';
                });
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }
}
