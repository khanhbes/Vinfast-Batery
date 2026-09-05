import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/widgets/app_popup.dart';
import '../../data/models/shelly_connection.dart';
import '../../data/models/smart_charger_binding.dart';
import '../../data/models/smart_charger_capabilities.dart';
import '../../data/models/vehicle_charger_binding.dart';
import '../../data/repositories/smart_charger_repository.dart';
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

class _SetupState extends State<SmartChargerSetupHubScreen> {
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
  final tariff = TextEditingController();
  final chargePower = TextEditingController(text: '400');
  final subnetController = TextEditingController(text: '192.168.1.');

  SmartChargerConnectionMode mode = SmartChargerConnectionMode.advancedDirect;
  int _activeTabIndex = 0; // 0: Mạng nội bộ (IP LAN), 1: Điều khiển từ xa (Shelly Cloud)
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

  @override
  void initState() {
    super.initState();
    for (final controller in [
      host,
      cloudKey,
      deviceId,
      lan,
      password,
      chargePower,
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
    selectedVehicleId = await SessionService().getSelectedVehicleId();
    // Default to advancedDirect (Nhập thủ công) as requested
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
    } else {
      chargePower.text = '400';
    }
    if (profile != null) {
      if (profile.cloudHost.isNotEmpty) {
        host.text = profile.cloudHost;
      }
      cloudKey.text = profile.cloudAuthKey;
      deviceId.text = profile.deviceId;
      lan.text = profile.lanAddress ?? '';
      password.text = profile.localPassword ?? '';
      // If LAN address is set, default to LAN tab; otherwise if cloud is set, cloud tab
      if (profile.lanAddress?.isNotEmpty == true) {
        _activeTabIndex = 0;
      } else if (profile.cloudAuthKey.isNotEmpty) {
        _activeTabIndex = 1;
      }
    }

    // Auto-detect local subnet for HTTP Subnet Sweep
    final detectedSubnet = await discovery.detectLocalSubnet();
    if (detectedSubnet != null && detectedSubnet.isNotEmpty) {
      subnetController.text = detectedSubnet;
    }

    try {
      capabilities = await direct.capabilities();
    } catch (_) {
      capabilities = SmartChargerCapabilities.unavailable;
    }

    if (mounted) {
      setState(() {
        busy = false;
        dirty = draft != null;
      });
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
      final repository = await SmartChargerRepositoryFactory.create();
      final session = await repository.current(vehicleId: selectedVehicleId);
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
        detail: 'IP: ${dev.address}${dev.firmware != null ? ' · FW: ${dev.firmware}' : ''}${dev.currentPowerW != null ? ' · Đang tiêu thụ ${dev.currentPowerW!.toStringAsFixed(1)}W' : ''}',
      );
    }
    if (mounted) setState(() {});
  }

  /// Quét dải IP mạng nội bộ qua TCP Unicast (vượt qua mọi lớp chặn multicast/mDNS của router)
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
          detail: 'Không có thiết bị Shelly nào phản hồi trong dải IP ${subnetController.text}. Bạn hãy kiểm tra lại dải mạng hoặc nhập trực tiếp IP.',
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

  /// Quét mã QR / Serial trên tem thân ổ cắm hoặc vỏ hộp
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

  /// Đồng bộ danh sách ổ cắm từ tài khoản Shelly Cloud
  Future<void> _syncFromCloud() async {
    final keyInputController = TextEditingController(text: cloudKey.text.trim());
    final serverInputController = TextEditingController(
      text: host.text.trim().isEmpty ? ShellyCloudAuthService.defaultCloudHosts.first : host.text.trim(),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_sync_rounded),
            SizedBox(width: 8),
            Text('Đồng bộ từ Shelly Cloud'),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nhập Authorization Cloud Key của tài khoản Shelly để tự động lấy toàn bộ danh sách ổ cắm trong nhà.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyInputController,
                decoration: InputDecoration(
                  labelText: 'Authorization Cloud Key',
                  hintText: 'Nhập hoặc dán Auth Key',
                  suffixIcon: IconButton(
                    tooltip: 'Mở web lấy Key',
                    icon: const Icon(Icons.open_in_new_rounded),
                    onPressed: () => cloudAuth.launchShellyCloudPortal(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: serverInputController,
                decoration: const InputDecoration(
                  labelText: 'Máy chủ Cloud (Server URI)',
                  hintText: 'https://shelly-108-eu.shelly.cloud',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('LẤY DANH SÁCH'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final key = keyInputController.text.trim();
    if (key.isEmpty) {
      AppPopup.showWarning('Vui lòng nhập Cloud Auth Key');
      return;
    }

    setState(() => busy = true);
    try {
      final cloudDevices = await cloudAuth.listDevices(
        authKey: key,
        cloudHost: serverInputController.text.trim(),
      );

      if (cloudDevices.isEmpty) {
        AppPopup.showInfo(
          'Không tìm thấy thiết bị',
          detail: 'Không tìm thấy ổ cắm Shelly nào trên tài khoản với Auth Key này. Vui lòng kiểm tra lại Key.',
        );
        return;
      }

      if (!mounted) return;
      final selected = await showModalBottomSheet<ShellyCloudDevice>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Chọn ổ cắm Shelly Cloud của bạn',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: cloudDevices.length,
                  itemBuilder: (ctx, idx) {
                    final d = cloudDevices[idx];
                    return ListTile(
                      leading: const Icon(Icons.cloud_done_rounded),
                      title: Text(d.name.isNotEmpty ? d.name : d.id),
                      subtitle: Text('${d.id} · ${d.type}'),
                      trailing: d.isOnline
                          ? const Chip(
                              label: Text('ONLINE', style: TextStyle(fontSize: 11, color: Colors.green)),
                              backgroundColor: Color(0x2222C55E),
                            )
                          : const Chip(
                              label: Text('OFFLINE', style: TextStyle(fontSize: 11)),
                            ),
                      onTap: () => Navigator.pop(ctx, d),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

      if (selected != null) {
        cloudKey.text = selected.cloudAuthKey.isNotEmpty ? selected.cloudAuthKey : key;
        deviceId.text = selected.id;
        if (selected.serverUri != null && selected.serverUri!.isNotEmpty) {
          host.text = selected.serverUri!;
        }
        dirty = true;
        AppPopup.showSuccess(
          'Đã chọn ${selected.name.isNotEmpty ? selected.name : selected.id}',
          detail: 'Đã tự động điền Device ID, Cloud Key và Server URL.',
        );
        if (mounted) setState(() {});
      }
    } catch (e) {
      AppPopup.showError('Lỗi kết nối Shelly Cloud', detail: '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Thử kết nối nhanh riêng cho cổng LAN
  Future<void> _testLanQuick() async {
    final ip = lan.text.trim();
    if (ip.isEmpty) {
      AppPopup.showWarning('Chưa nhập địa chỉ IP LAN');
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
          detail: 'Thiết bị: ${probe.name ?? probe.id} (${probe.model})'
              '${probe.firmware != null ? ' · FW: ${probe.firmware}' : ''}'
              '${probe.relayState != null ? ' · Relay: ${probe.relayState! ? "BẬT" : "TẮT"}' : ''}'
              '${probe.currentPowerW != null ? ' · Công suất: ${probe.currentPowerW!.toStringAsFixed(1)}W' : ''}',
        );
      } else {
        AppPopup.showWarning(
          'Không phản hồi từ IP $ip',
          detail: 'Vui lòng kiểm tra lại địa chỉ IP hoặc đảm bảo điện thoại đang kết nối cùng Wi-Fi.',
        );
      }
    } catch (e) {
      AppPopup.showError('Kiểm tra LAN thất bại', detail: '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Thử kết nối nhanh riêng cho Cloud
  Future<void> _testCloudQuick() async {
    final key = cloudKey.text.trim();
    if (key.isEmpty) {
      AppPopup.showWarning('Chưa nhập Authorization Cloud Key');
      return;
    }
    setState(() => busy = true);
    try {
      final cloudDevices = await cloudAuth.listDevices(
        authKey: key,
        cloudHost: host.text.trim().isEmpty ? ShellyCloudAuthService.defaultCloudHosts.first : host.text.trim(),
      );
      if (cloudDevices.isNotEmpty) {
        AppPopup.showSuccess(
          'Kết nối Shelly Cloud thành công!',
          detail: 'Tài khoản có ${cloudDevices.length} thiết bị Shelly đang hoạt động.',
        );
      } else {
        AppPopup.showWarning(
          'Chưa tìm thấy thiết bị trên Cloud',
          detail: 'Cloud Key có thể chưa chính xác hoặc chưa có thiết bị nào được gán vào phòng.',
        );
      }
    } catch (e) {
      AppPopup.showError('Kiểm tra Cloud thất bại', detail: '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _saveAndVerify() async {
    if (!await _guardInactive()) return;
    if (host.text.trim().isEmpty) {
      host.text = ShellyCloudAuthService.defaultCloudHosts.first;
    }
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
      if (selectedVehicleId != null && selectedVehicleId!.isNotEmpty) {
        await vehicleBindings.save(
          VehicleChargerBinding(
            vehicleId: selectedVehicleId!,
            deviceId: profile.deviceId,
          ),
        );
      }
      await credentials.saveVerification(verified);
      await _offerServerBackup(profile, verified);
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

  Future<void> _offerServerBackup(
    ShellyConnectionProfile value,
    SmartChargerVerificationState state,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final optedIn = prefs.getBool('smartChargerEncryptedBackup') ?? false;
    var shouldUpload = optedIn;
    if (!optedIn && mounted) {
      shouldUpload = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Lưu cấu hình theo tài khoản?'),
              content: const Text(
                'Cloud key và mật khẩu LAN sẽ được mã hóa trên server để tự khôi phục khi đổi điện thoại. Firestore chỉ nhận metadata.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('KHÔNG LƯU')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('LƯU MÃ HÓA')),
              ],
            ),
          ) ??
          false;
      await prefs.setBool('smartChargerEncryptedBackup', shouldUpload);
    }
    if (!shouldUpload) return;
    try {
      await server.registerShellyDevice(
        value,
        vehicleId: selectedVehicleId,
        verification: state.toJson(),
      );
    } on SmartChargerException catch (error) {
      AppPopup.showWarning('Đã lưu trên điện thoại, chưa đồng bộ server', detail: error.message);
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
    final scope = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa cấu hình Shelly?'),
        content: const Text(
          'Bạn có thể chỉ xóa trên điện thoại hoặc thu hồi cấu hình mã hóa khỏi mọi thiết bị.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(context, 'local'), child: const Text('CHỈ ĐIỆN THOẠI')),
          FilledButton(
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
    final normalized = tariff.text
        .trim()
        .replaceAll('.', '')
        .replaceAll(',', '');
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
            ? 'Chi phí sẽ không được ước tính cho phiên mới.'
            : '${NumberFormat.decimalPattern('vi_VN').format(value)} VND/kWh · áp dụng cho phiên mới',
      );
    } on Object catch (error) {
      AppPopup.showError('Không thể lưu giá điện', detail: '$error', userInitiated: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _saveChargePower() async {
    final normalized = chargePower.text
        .trim()
        .replaceAll('.', '')
        .replaceAll(',', '');
    final value = normalized.isEmpty ? 400.0 : double.tryParse(normalized);
    if (normalized.isNotEmpty && value == null) {
      AppPopup.showError('Công suất sạc chưa hợp lệ', userInitiated: true);
      return;
    }
    setState(() => busy = true);
    try {
      await chargePreferences.saveChargePower(value);
      AppPopup.showSuccess(
        'Đã lưu công suất sạc',
        detail: '${(value ?? 400).toStringAsFixed(0)} W · áp dụng cho phiên sạc và dự đoán thời gian',
      );
    } on Object catch (error) {
      AppPopup.showError('Không thể lưu công suất sạc', detail: '$error', userInitiated: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      host,
      cloudKey,
      deviceId,
      lan,
      password,
      chargePower,
      subnetController,
    ]) {
      controller.dispose();
    }
    tariff.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ready = capabilities.readyForControl || verification.readyForControl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt Smart Charger'),
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
          Text('Chi phí & Cấu hình sạc', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Giá điện và công suất bộ sạc được lưu theo tài khoản, áp dụng cho tính toán chi phí và dự đoán thời gian sạc.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: tariff,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: false,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Giá điện',
                    hintText: 'Ví dụ: 2800',
                    suffixText: 'VND/kWh',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: busy ? null : _saveTariff,
                  child: const Text('LƯU GIÁ'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: chargePower,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: false,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Công suất sạc tiêu chuẩn',
                    hintText: 'Mặc định: 400',
                    suffixText: 'W',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: busy ? null : _saveChargePower,
                  child: const Text('LƯU CÔNG SUẤT'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 2 Tab chuyên biệt: Mạng nội bộ (IP LAN) vs Điều khiển từ xa (Shelly Cloud)
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('Mạng nội bộ (IP LAN)'),
                icon: Icon(Icons.lan_rounded),
              ),
              ButtonSegment(
                value: 1,
                label: Text('Điều khiển từ xa (Cloud)'),
                icon: Icon(Icons.cloud_rounded),
              ),
            ],
            selected: {_activeTabIndex},
            onSelectionChanged: busy
                ? null
                : (val) => setState(() => _activeTabIndex = val.first),
          ),
          const SizedBox(height: 16),

          // TAB 0: MẠNG NỘI BỘ (IP LAN)
          if (_activeTabIndex == 0) ...[
            Card(
              elevation: 0,
              color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.radar_rounded, color: colors.primary, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Quét dải IP mạng nội bộ (HTTP Subnet Sweep)',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Quét nhanh các thiết bị trong mạng Wi-Fi nhà bạn bằng kết nối trực tiếp (TCP cổng 80). Không bị chặn bởi router như mDNS.',
                      style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: subnetController,
                            decoration: const InputDecoration(
                              labelText: 'Dải mạng quét (/24)',
                              hintText: '192.168.1.',
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: (busy || isSweeping) ? null : _sweepSubnet,
                            icon: isSweeping
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.search_rounded),
                            label: Text(isSweeping ? 'ĐANG QUÉT...' : 'QUÉT DẢI IP'),
                          ),
                        ),
                      ],
                    ),
                    if (isSweeping) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: sweepProgress > 0 ? sweepProgress : null),
                      const SizedBox(height: 6),
                      Text(
                        'Tiến độ: ${(sweepProgress * 100).toStringAsFixed(0)}% · Đã phát hiện $sweepFoundCount thiết bị',
                        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (sweptDevices.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Thiết bị Shelly phát hiện (${sweptDevices.length}):',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              for (final dev in sweptDevices)
                Card(
                  elevation: 0,
                  color: (lan.text.trim() == dev.address)
                      ? colors.primaryContainer.withValues(alpha: 0.3)
                      : colors.surfaceContainerHighest.withValues(alpha: 0.25),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: (lan.text.trim() == dev.address)
                          ? colors.primary
                          : colors.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.power_rounded),
                    title: Text(dev.name ?? dev.id, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${dev.address} · ${dev.model}${dev.firmware != null ? ' (v${dev.firmware})' : ''}'),
                    trailing: (lan.text.trim() == dev.address)
                        ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                        : const Text('CHỌN', style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () => _applyDevice(dev),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Text(
              'Địa chỉ IP nội mạng của Shelly',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            TextField(
              controller: lan,
              decoration: const InputDecoration(
                labelText: 'Địa chỉ IP hoặc hostname .local',
                hintText: '192.168.1.50',
                prefixIcon: Icon(Icons.router_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Mật khẩu local của thiết bị (nếu có)',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: busy ? null : _testLanQuick,
                icon: const Icon(Icons.cable_rounded),
                label: const Text('KIỂM TRA KẾT NỐI LAN'),
              ),
            ),
          ]

          // TAB 1: ĐIỀU KHIỂN TỪ XA (SHELLY CLOUD)
          else ...[
            Text(
              'Công cụ hỗ trợ nhanh',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _scanQr,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('QUÉT MÃ QR'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _syncFromCloud,
                    icon: const Icon(Icons.cloud_sync_rounded),
                    label: const Text('ĐỒNG BỘ CLOUD'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: host,
              decoration: const InputDecoration(
                labelText: 'Shelly Cloud Server URI',
                hintText: 'https://shelly-108-eu.shelly.cloud',
                prefixIcon: Icon(Icons.dns_rounded),
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
                hintText: 'Nhập mã Cloud Key của tài khoản',
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => obscure = !obscure),
                  icon: Icon(
                    obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: deviceId,
              decoration: const InputDecoration(
                labelText: 'Device ID',
                hintText: 'Ví dụ: shellyplugs3-c049ef87b64c',
                prefixIcon: Icon(Icons.memory_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: busy ? null : _testCloudQuick,
                icon: const Icon(Icons.cloud_done_rounded),
                label: const Text('KIỂM TRA KẾT NỐI CLOUD'),
              ),
            ),
          ],

          const SizedBox(height: 28),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              key: const ValueKey('save-test-smart-charger'),
              onPressed: busy ? null : _saveAndVerify,
              icon: const Icon(Icons.verified_user_rounded),
              label: Text(dirty ? 'LƯU & KIỂM TRA TOÀN DIỆN' : 'KIỂM TRA LẠI CẤU HÌNH'),
            ),
          ),
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
