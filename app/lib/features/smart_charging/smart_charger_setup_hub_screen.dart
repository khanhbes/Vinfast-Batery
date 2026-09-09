import 'package:flutter/material.dart';
import '../../core/theme/app_ui_colors.dart';
import '../../core/theme/cockpit_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../data/repositories/charge_log_repository.dart';
import '../../core/widgets/settings_reveal.dart';
import '../../core/widgets/responsive_card_grid.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class SmartChargerSetupHubScreen extends ConsumerStatefulWidget {
  const SmartChargerSetupHubScreen({super.key});

  @override
  ConsumerState<SmartChargerSetupHubScreen> createState() => _SetupState();
}

class _SetupState extends ConsumerState<SmartChargerSetupHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  AppUiColors get _ui => AppUiColors.of(context);

  final credentials = SmartChargerCredentialsService();
  final direct = SmartChargerService();
  final server = ServerSmartChargerService();
  final vehicleBindings = VehicleChargerBindingService();
  final chargePreferences = SmartChargePreferencesService();
  final cloudAuth = ShellyCloudAuthService();
  final discovery = ShellyDiscoveryService();

  final host = TextEditingController(
    text: ShellyCloudAuthService.defaultCloudHosts.first,
  );
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
  List<DiscoveredShellyDevice> devices = [];
  List<DiscoveredShellyDevice> sweptDevices = [];
  bool isSweeping = false;
  double sweepProgress = 0.0;
  int sweepFoundCount = 0;

  bool busy = true;
  bool obscure = true;
  bool dirty = false;
  String? selectedVehicleId;
  String vehicleName = 'Chưa chọn xe';
  String vehiclePlate = 'Chưa có dữ liệu xe';
  String lastCheckedTime = 'Chưa kiểm tra';

  // Settings tab preferences
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
    setState(() {
      dirty = true;
      verification = SmartChargerVerificationState.unverified;
      lastCheckedTime = 'Cấu hình đã thay đổi';
    });
  }

  Future<void> _load() async {
    try {
      selectedVehicleId = await SessionService().getSelectedVehicleId();
      final currentId = ref.read(selectedVehicleIdProvider);
      if (currentId.isNotEmpty) selectedVehicleId = currentId;
      final vehicle = selectedVehicleId == null
          ? null
          : await ref
                .read(chargeLogRepositoryProvider)
                .getVehicle(selectedVehicleId!);
      if (!mounted) return;
      vehicleName = vehicle?.vehicleName ?? 'Chưa chọn xe';
      vehiclePlate = vehicle == null
          ? 'Chưa có dữ liệu xe'
          : '${vehicle.vehicleId} • ${vehicle.hasBatteryData ? 'Pin ${vehicle.currentBattery}%' : 'Chưa có SOC'}';
      mode = SmartChargerConnectionMode.advancedDirect;

      var active = await credentials.readProfile(vehicleId: selectedVehicleId);
      active ??= await credentials.restoreFromCloud(
        vehicleId: selectedVehicleId,
      );
      final draft = await credentials.readDraft();
      final profile = draft ?? active;
      verification = await credentials.readVerification();
      if (draft != null) {
        verification = SmartChargerVerificationState.unverified;
      }
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
      lastCheckedTime = verification.lastVerifiedAt == null
          ? 'Chưa kiểm tra'
          : DateFormat('HH:mm').format(verification.lastVerifiedAt!);
    } catch (_) {
      // Ignore load errors so UI remains interactive
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  ShellyConnectionProfile get profile => ShellyConnectionProfile(
    cloudHost: host.text.trim().isEmpty
        ? ShellyCloudAuthService.defaultCloudHosts.first
        : host.text.trim(),
    cloudAuthKey: cloudKey.text.trim(),
    deviceId: deviceId.text.trim(),
    lanAddress: lan.text.trim().isEmpty ? null : lan.text.trim(),
    localPassword: password.text.isEmpty ? null : password.text,
  );

  Future<bool> _guardInactive() async {
    try {
      final directSession = await direct.getCurrentSessionForVehicle(
        selectedVehicleId,
      );
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
        detail:
            'IP: ${dev.address}${dev.firmware != null ? ' · FW: ${dev.firmware}' : ''}',
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
      sweptDevices = [];
    });
    try {
      final prefix = subnetController.text.trim();
      final results = await discovery.sweepSubnet(
        baseSubnet: prefix.isEmpty ? null : prefix,
        timeout: Duration(milliseconds: 350),
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
          detail:
              'Không có thiết bị Shelly nào phản hồi trong dải IP ${subnetController.text}.',
        );
      } else if (results.length == 1) {
        await _applyDevice(results.first);
      } else {
        AppPopup.showSuccess(
          'Đã tìm thấy ${results.length} thiết bị Shelly',
          detail:
              'Chạm vào thiết bị từ danh sách bên dưới để tự động điền cấu hình.',
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
        detail:
            'Device ID: ${result.deviceId}${result.model != null ? ' (${result.model})' : ''}',
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
        timeout: Duration(seconds: 4),
      );
      if (probe.name != null || probe.firmware != null) {
        if (deviceId.text.trim().isEmpty &&
            probe.id.isNotEmpty &&
            !probe.id.startsWith('shelly-192.')) {
          deviceId.text = probe.id;
          dirty = true;
        }
        AppPopup.showSuccess(
          'Kết nối LAN thành công!',
          detail:
              'IP $ip đang phản hồi tốt${probe.firmware != null ? ' (FW: ${probe.firmware})' : ''}.',
        );
      } else {
        AppPopup.showWarning(
          'Không phản hồi từ $ip',
          detail:
              'Hãy kiểm tra điện thoại đã kết nối cùng mạng Wi-Fi với Shelly.',
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
      AppPopup.showWarning(
        'Cần nhập Device ID và Cloud Auth Key',
        userInitiated: true,
      );
      return;
    }
    setState(() => busy = true);
    try {
      final devices = await cloudAuth.listDevices(
        authKey: key,
        cloudHost: host.text.trim().isEmpty ? null : host.text.trim(),
      );
      final normalizedTarget = dId.toLowerCase().replaceAll(
        RegExp(r'[^a-f0-9]'),
        '',
      );
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
            detail:
                'Thiết bị "${matched.name}" (${matched.id}) đang trực tuyến trên đám mây.',
          );
        } else {
          AppPopup.showWarning(
            'Shelly Cloud: OFFLINE',
            detail:
                'Tìm thấy "${matched.name}" (${matched.id}) nhưng thiết bị hiện đang mất kết nối Internet.',
          );
        }
      } else if (devices.isNotEmpty) {
        AppPopup.showWarning(
          'Không tìm thấy Device ID $dId',
          detail:
              'Auth Key hợp lệ, tìm thấy ${devices.length} thiết bị khác trên tài khoản này.',
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

      final result = await direct.testConnection(profile: prof);
      final newState = SmartChargerVerificationState.unverified.copyWith(
        cloudVerified: result.cloudStatus != null,
        lanVerified: result.lanStatus != null,
        powerMeterVerified: result.powerMeterAvailable,
        lastVerifiedAt: DateTime.now(),
      );
      verification = newState;
      await credentials.saveProfile(prof);
      await credentials.saveVerification(newState);
      await credentials.clearDraft();
      capabilities = await direct.capabilities();
      bool backupFailed = false;
      try {
        if (cloudBackupEnabled) await server.registerShellyDevice(prof);
      } catch (_) {
        backupFailed = true;
      }

      if (mounted) {
        setState(() {
          dirty = false;
          lastCheckedTime = DateFormat('HH:mm').format(DateTime.now());
        });
        AppPopup.showSuccess(
          'Kiểm tra hoàn tất & Đã lưu cấu hình',
          detail: backupFailed
              ? 'Đã lưu trên máy; sao lưu server thất bại. Chưa xác minh Safe Boot/test relay.'
              : 'Đã kiểm tra kết nối và lưu trên máy. Chưa xác minh Safe Boot/test relay.',
        );
      }
    } catch (error) {
      if (mounted) {
        AppPopup.showError(
          'Kiểm tra thất bại',
          detail: error.toString(),
          userInitiated: true,
        );
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
        backgroundColor: _ui.surface,
        title: Text('Xóa cấu hình Shelly?', style: TextStyle(color: _ui.text)),
        content: Text(
          'Bạn có thể chỉ xóa trên điện thoại hoặc thu hồi cấu hình mã hóa khỏi mọi thiết bị.',
          style: TextStyle(color: _ui.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'local'),
            child: Text('CHỈ ĐIỆN THOẠI'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _ui.danger),
            onPressed: () => Navigator.pop(context, 'everywhere'),
            child: Text('THU HỒI MỌI NƠI'),
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
        AppPopup.showError(
          'Không thể thu hồi cấu hình server',
          detail: error.message,
        );
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
    AppPopup.showSuccess(
      scope == 'everywhere'
          ? 'Đã thu hồi cấu hình Shelly'
          : 'Đã xóa cấu hình khỏi điện thoại',
    );
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
    final normalized = chargePower.text
        .trim()
        .replaceAll('.', '')
        .replaceAll(',', '');
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
        detail:
            '${(value ?? 400).toStringAsFixed(0)} W · áp dụng tính thời gian sạc',
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
        backgroundColor: _ui.surface,
        title: Row(
          children: [
            Icon(Icons.help_outline_rounded, color: _ui.primary),
            SizedBox(width: 8),
            Text(
              'Hướng dẫn Smart Charger',
              style: TextStyle(color: _ui.text, fontSize: 16),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '• Kết nối kép (LAN & Cloud): Tự động ưu tiên LAN khi ở nhà để điều khiển tức thì 10ms, tự động chuyển Cloud khi ra ngoài.',
                style: TextStyle(color: _ui.muted, fontSize: 13),
              ),
              SizedBox(height: 8),
              Text(
                '• 5 lớp bảo vệ: Tự động ngắt khi quá dòng (>11.5A), quá công suất (>2450W), quá nhiệt (>75°C), sai điện áp hoặc quá giờ.',
                style: TextStyle(color: _ui.muted, fontSize: 13),
              ),
              SizedBox(height: 8),
              Text(
                '• Safe Boot: Luôn giữ relay ở trạng thái OFF khi cắm điện lại để bảo vệ bộ sạc xe máy điện khỏi xung điện áp.',
                style: TextStyle(color: _ui.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _ui.primary),
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'ĐÃ HIỂU',
              style: TextStyle(
                color: _ui.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
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
    final ipText = lan.text.trim().isNotEmpty
        ? lan.text.trim()
        : 'Chưa cấu hình LAN';

    return Scaffold(
      backgroundColor: _ui.background,
      appBar: AppBar(
        toolbarHeight: 24 + MediaQuery.textScalerOf(context).scale(36),
        backgroundColor: _ui.background,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Quay lại',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded, color: _ui.text, size: 24),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Smart Charger',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CockpitTypography.heading(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: CockpitColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Gen3 • $ipText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CockpitTypography.label(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: CockpitColors.muted,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Trợ giúp',
            onPressed: _showHelpDialog,
            icon: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: CockpitColors.elevated,
                borderRadius: BorderRadius.circular(CockpitRadius.small),
                border: Border.all(color: CockpitColors.border),
              ),
              child: const Icon(
                Icons.help_outline_rounded,
                color: CockpitColors.muted,
                size: 18,
              ),
            ),
          ),
          PopupMenuButton<String>(
            color: CockpitColors.surface,
            icon: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: CockpitColors.elevated,
                borderRadius: BorderRadius.circular(CockpitRadius.small),
                border: Border.all(color: CockpitColors.border),
              ),
              child: const Icon(Icons.more_vert_rounded, color: CockpitColors.muted, size: 18),
            ),
            onSelected: (val) {
              if (val == 'delete') _delete();
              if (val == 'help') _showHelpDialog();
              if (val == 'refresh') _verifyAll();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'refresh',
                child: Text(
                  'Kiểm tra kết nối',
                  style: CockpitTypography.body(fontSize: 13, color: CockpitColors.text),
                ),
              ),
              PopupMenuItem(
                value: 'help',
                child: Text(
                  'Hướng dẫn sử dụng',
                  style: CockpitTypography.body(fontSize: 13, color: CockpitColors.text),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Xóa cấu hình',
                  style: CockpitTypography.body(
                    fontSize: 13,
                    color: CockpitColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (busy) LinearProgressIndicator(minHeight: 2, color: _ui.primary),

          // ── Segmented Tab Bar (3 Tab) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              height: 46,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: CockpitColors.surface,
                borderRadius: BorderRadius.circular(CockpitRadius.medium),
                border: Border.all(color: CockpitColors.border),
              ),
              child: TabBar(
                isScrollable: false,
                controller: _tabController,
                indicator: BoxDecoration(
                  color: CockpitColors.emerald.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(CockpitRadius.small),
                  border: Border.all(
                    color: CockpitColors.emerald.withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: CockpitColors.emeraldStrong,
                unselectedLabelColor: CockpitColors.muted,
                labelStyle: CockpitTypography.label(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: CockpitTypography.label(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bolt_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Sạc'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_outlined, size: 15),
                        SizedBox(width: 6),
                        Text('Bảo vệ'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.tune_rounded, size: 15),
                        SizedBox(width: 6),
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
                SettingsReveal(child: _buildChargingTab()),
                SettingsReveal(child: _buildProtectionTab()),
                SettingsReveal(child: _buildSettingsTab()),
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
      padding: EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        // 1. Thẻ Master Shelly Plug S Gen3
        CockpitSurface(
          highlight: true,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Power button
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: CockpitColors.elevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: CockpitColors.border),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.power_settings_new_rounded,
                          color: CockpitColors.muted,
                          size: 22,
                        ),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shelly Plug S Gen3',
                          style: CockpitTypography.heading(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: CockpitColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Kết nối kép & 5 lớp bảo vệ',
                          style: CockpitTypography.label(
                            fontSize: 12,
                            color: CockpitColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: CockpitColors.emeraldSubtle,
                      borderRadius: BorderRadius.circular(CockpitRadius.full),
                      border: Border.all(color: CockpitColors.emeraldGlow),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: CockpitColors.emerald,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Sẵn sàng',
                          style: CockpitTypography.label(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: CockpitColors.emerald,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Dải pill trạng thái gọn gàng
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusPillBadge(
                    icon: Icons.cloud_done_rounded,
                    label: 'Cloud',
                    verified: verification.cloudVerified,
                  ),
                  _statusPillBadge(
                    icon: Icons.wifi_rounded,
                    label: 'LAN',
                    verified: verification.lanVerified,
                  ),
                  _statusPillBadge(
                    icon: Icons.speed_rounded,
                    label: 'Đo tải',
                    verified: verification.powerMeterVerified,
                  ),
                  _statusPillBadge(
                    icon: Icons.shield_rounded,
                    label: 'Safe Boot',
                    verified: verification.safeBootVerified,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Dòng thời gian đo & Nút kiểm tra
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Đo lúc $lastCheckedTime',
                    style: CockpitTypography.numbers(
                      fontSize: 11,
                      color: CockpitColors.dim,
                    ),
                  ),
                  SizedBox(
                    height: 36,
                    child: FilledButton.icon(
                      onPressed: busy ? null : _verifyAll,
                      style: FilledButton.styleFrom(
                        backgroundColor: CockpitColors.emerald,
                        foregroundColor: CockpitColors.shell,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(CockpitRadius.small),
                        ),
                      ),
                      icon: const Icon(Icons.bolt_rounded, size: 16),
                      label: Text(
                        'Kiểm tra',
                        style: CockpitTypography.label(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: CockpitColors.shell,
                        ),
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
        CockpitSurface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: CockpitColors.elevated,
                  borderRadius: BorderRadius.circular(CockpitRadius.small),
                  border: Border.all(color: CockpitColors.border),
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
                      style: CockpitTypography.heading(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: CockpitColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehiclePlate,
                      style: CockpitTypography.numbers(
                        fontSize: 12,
                        color: CockpitColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 36,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CockpitColors.text,
                    side: const BorderSide(color: CockpitColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CockpitRadius.small),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () => _tabController.animateTo(2),
                  child: Text(
                    'Đổi xe',
                    style: CockpitTypography.label(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: CockpitColors.text,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 3. Thẻ Thông số sạc & Đơn giá điện
        CockpitSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              InkWell(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(CockpitRadius.large)),
                onTap: () => _showQuickPowerDialog(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Công suất sạc',
                            style: CockpitTypography.label(fontSize: 12, color: CockpitColors.muted),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${chargePower.text} W',
                            style: CockpitTypography.numbers(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: CockpitColors.emerald,
                            ),
                          ),
                        ],
                      ),
                      const Icon(Icons.chevron_right_rounded, color: CockpitColors.muted),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: CockpitColors.border),
              InkWell(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(CockpitRadius.large),
                ),
                onTap: () => _showQuickTariffDialog(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Đơn giá điện',
                            style: CockpitTypography.label(fontSize: 12, color: CockpitColors.muted),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${NumberFormat.decimalPattern('vi_VN').format(int.tryParse(tariff.text) ?? 2800)} đ/kWh',
                            style: CockpitTypography.numbers(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: CockpitColors.text,
                            ),
                          ),
                        ],
                      ),
                      const Icon(Icons.chevron_right_rounded, color: CockpitColors.muted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 4. Cụm thẻ kép LAN & Cloud
        ResponsiveCardGrid(
          minCardWidth: 220,
          children: [
            CockpitSurface(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.wifi_rounded,
                            color: CockpitColors.emerald,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'LAN',
                            style: CockpitTypography.heading(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: CockpitColors.text,
                            ),
                          ),
                        ],
                      ),
                      _statusPillBadge(
                        icon: Icons.wifi_rounded,
                        label: verification.lanVerified ? 'Đã xác minh' : 'Chưa xác minh',
                        verified: verification.lanVerified,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    lan.text.isNotEmpty ? lan.text : 'Chưa cấu hình',
                    style: CockpitTypography.numbers(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CockpitColors.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: CockpitColors.border),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(CockpitRadius.small),
                              ),
                            ),
                            onPressed: busy ? null : _testLanQuick,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.refresh_rounded,
                                  size: 14,
                                  color: CockpitColors.text,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Đo',
                                  style: CockpitTypography.label(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: CockpitColors.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: CockpitColors.border),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(CockpitRadius.small),
                              ),
                            ),
                            onPressed: busy || isSweeping ? null : _sweepSubnet,
                            child: Text(
                              'Quét',
                              style: CockpitTypography.label(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: CockpitColors.text,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            CockpitSurface(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_outlined, color: CockpitColors.info, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Cloud',
                            style: CockpitTypography.heading(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: CockpitColors.text,
                            ),
                          ),
                        ],
                      ),
                      _statusPillBadge(
                        icon: Icons.cloud_rounded,
                        label: verification.cloudVerified ? 'Đã xác minh' : 'Chưa xác minh',
                        verified: verification.cloudVerified,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    host.text.trim().isEmpty
                        ? 'Chưa cấu hình máy chủ'
                        : host.text.trim(),
                    style: CockpitTypography.numbers(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CockpitColors.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: CockpitColors.border),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(CockpitRadius.small),
                              ),
                            ),
                            onPressed: busy ? null : _testCloudQuick,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.refresh_rounded,
                                  size: 14,
                                  color: CockpitColors.text,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Đo',
                                  style: CockpitTypography.label(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: CockpitColors.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: CockpitColors.border),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(CockpitRadius.small),
                              ),
                            ),
                            onPressed: () => _tabController.animateTo(2),
                            child: Text(
                              'Đổi',
                              style: CockpitTypography.label(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: CockpitColors.text,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
      padding: EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        // Dải mini trạng thái
        CockpitSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusPillBadge(
                    icon: Icons.cloud_done_rounded,
                    label: 'Cloud',
                    verified: verification.cloudVerified,
                  ),
                  _statusPillBadge(
                    icon: Icons.wifi_rounded,
                    label: 'LAN',
                    verified: verification.lanVerified,
                  ),
                  _statusPillBadge(
                    icon: Icons.speed_rounded,
                    label: 'Đo tải',
                    verified: verification.powerMeterVerified,
                  ),
                  _statusPillBadge(
                    icon: Icons.shield_rounded,
                    label: 'Safe Boot',
                    verified: verification.safeBootVerified,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Đo lúc $lastCheckedTime',
                    style: CockpitTypography.numbers(
                      fontSize: 11,
                      color: CockpitColors.dim,
                    ),
                  ),
                  SizedBox(
                    height: 36,
                    child: FilledButton.icon(
                      onPressed: busy ? null : _verifyAll,
                      style: FilledButton.styleFrom(
                        backgroundColor: CockpitColors.emerald,
                        foregroundColor: CockpitColors.shell,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(CockpitRadius.small),
                        ),
                      ),
                      icon: const Icon(Icons.bolt_rounded, size: 16),
                      label: Text(
                        'Kiểm tra',
                        style: CockpitTypography.label(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: CockpitColors.shell,
                        ),
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
        CockpitSurface(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: CockpitColors.emerald.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.shield_outlined, color: CockpitColors.emerald, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Tự động ngắt an toàn',
                        style: CockpitTypography.heading(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: CockpitColors.text,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: CockpitColors.emeraldSubtle,
                      borderRadius: BorderRadius.circular(CockpitRadius.full),
                      border: Border.all(color: CockpitColors.emeraldGlow),
                    ),
                    child: Text(
                      'ĐANG BẬT',
                      style: CockpitTypography.label(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: CockpitColors.emerald,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _protectionMetricRow(
                'Quá dòng',
                '11.5 A',
                icon: Icons.electric_bolt_rounded,
              ),
              const SizedBox(height: 8),
              _protectionMetricRow(
                'Quá công suất',
                '2.450 W',
                icon: Icons.flash_on_rounded,
              ),
              const SizedBox(height: 8),
              _protectionMetricRow(
                'Quá nhiệt',
                '75°C',
                icon: Icons.thermostat_rounded,
              ),
              const SizedBox(height: 8),
              _protectionMetricRow(
                'Điện áp',
                '190 – 255 V',
                icon: Icons.power_rounded,
              ),
              const SizedBox(height: 8),
              _protectionMetricRow(
                'Thời gian tối đa',
                '10 giờ',
                icon: Icons.timer_outlined,
                isMuted: true,
              ),

              const SizedBox(height: 16),
              SizedBox(
                height: CockpitButtonTokens.height,
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _showTechnicalDetailsDialog,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: CockpitColors.border),
                    backgroundColor: CockpitColors.elevated,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CockpitButtonTokens.radius),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Chi tiết kỹ thuật',
                        style: CockpitTypography.label(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: CockpitColors.text,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_rounded, size: 16, color: CockpitColors.muted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Thẻ Gộp: An toàn phần cứng (Safe Boot + Test Relay)
        CockpitSurface(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: CockpitColors.emerald.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.verified_user_outlined, color: CockpitColors.emerald, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'An toàn phần cứng',
                    style: CockpitTypography.heading(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: CockpitColors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Row 1: Safe Boot
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Safe Boot',
                          style: CockpitTypography.heading(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: CockpitColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Khởi động an toàn & bảo vệ role',
                          style: CockpitTypography.label(
                            fontSize: 12,
                            color: CockpitColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _statusPillBadge(
                    icon: Icons.shield_rounded,
                    label: verification.safeBootVerified ? 'Đã xác minh' : 'Chưa xác minh',
                    verified: verification.safeBootVerified,
                  ),
                ],
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(color: CockpitColors.border, height: 1),
              ),

              // Row 2: Test Relay không tải
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Test Relay không tải',
                          style: CockpitTypography.heading(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: CockpitColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Kiểm tra đóng/ngắt cơ học relay',
                          style: CockpitTypography.label(
                            fontSize: 12,
                            color: CockpitColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 36,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: CockpitColors.border),
                        backgroundColor: CockpitColors.elevated,
                        foregroundColor: CockpitColors.text,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(CockpitRadius.small),
                        ),
                      ),
                      onPressed: busy ? null : _runNoLoadTest,
                      icon: const Icon(Icons.toggle_on_outlined, size: 16, color: CockpitColors.emerald),
                      label: Text(
                        'Kiểm tra',
                        style: CockpitTypography.label(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: CockpitColors.text,
                        ),
                      ),
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
  // TAB 3: [ ⚙️ Cài đặt ] (Thiết kế mới đồng bộ hoàn mỹ)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      children: [
        // ── Section 1: KẾT NỐI MẠNG NỘI BỘ (LAN) ──
        const CockpitSectionLabel('Mạng nội bộ (LAN)'),
        CockpitSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _darkInputField(
                controller: lan,
                label: 'Địa chỉ IP Shelly',
                hint: 'Ví dụ: 192.168.1.50',
                prefixIcon: Icons.lan_rounded,
              ),
              const SizedBox(height: 10),
              _darkInputField(
                controller: password,
                label: 'Mật khẩu LAN (nếu có)',
                hint: 'Để trống nếu chưa đặt mật khẩu',
                prefixIcon: Icons.lock_outline_rounded,
                isPassword: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      label: 'Quét dải IP',
                      icon: Icons.radar_rounded,
                      onTap: _sweepSubnet,
                    ),
                  ),
                  const SizedBox(width: 10),
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
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Section 2: ĐIỀU KHIỂN TỪ XA (SHELLY CLOUD) ──
        const CockpitSectionLabel('Điều khiển từ xa (Shelly Cloud)'),
        CockpitSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _darkInputField(
                controller: deviceId,
                label: 'Device ID',
                hint: 'Ví dụ: e86beae... hoặc quét QR',
                prefixIcon: Icons.fingerprint_rounded,
              ),
              const SizedBox(height: 10),
              _darkInputField(
                controller: cloudKey,
                label: 'Cloud Authorization Key',
                hint: 'Dán key từ app Shelly hoặc quét QR',
                prefixIcon: Icons.vpn_key_outlined,
                isPassword: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      label: 'Quét mã QR',
                      icon: Icons.qr_code_scanner_rounded,
                      onTap: _scanQr,
                    ),
                  ),
                  const SizedBox(width: 10),
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
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Nút Lưu Cấu Hình Kết Nối
        SizedBox(
          width: double.infinity,
          height: CockpitButtonTokens.height,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: CockpitColors.emerald,
              foregroundColor: CockpitColors.shell,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(CockpitButtonTokens.radius),
              ),
            ),
            onPressed: busy ? null : _verifyAll,
            icon: const Icon(Icons.save_rounded, size: 18),
            label: Text(
              'LƯU CẤU HÌNH KẾT NỐI',
              style: CockpitTypography.label(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: CockpitColors.shell,
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // ── Section 3: THÔNG SỐ SẠC & ĐƠN GIÁ ──
        const CockpitSectionLabel('Thông số sạc & Đơn giá'),
        CockpitSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Xe máy điện đang liên kết
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: CockpitColors.emerald.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.bolt_rounded, color: CockpitColors.emerald, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Xe liên kết',
                            style: CockpitTypography.label(fontSize: 11, color: CockpitColors.muted),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            vehicleName,
                            style: CockpitTypography.heading(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: CockpitColors.text,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 34,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: CockpitColors.border),
                        foregroundColor: CockpitColors.text,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(CockpitRadius.small),
                        ),
                      ),
                      onPressed: _showSwitchVehicleDialog,
                      child: Text(
                        'Đổi xe',
                        style: CockpitTypography.label(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: CockpitColors.text,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(color: CockpitColors.border, height: 1),
              ),

              // Công suất sạc tiêu chuẩn
              Text(
                'Công suất sạc tiêu chuẩn (W)',
                style: CockpitTypography.label(fontSize: 12, color: CockpitColors.muted),
              ),
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
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: CockpitColors.emeraldSubtle,
                        foregroundColor: CockpitColors.emerald,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(CockpitRadius.small),
                          side: BorderSide(color: CockpitColors.emerald.withValues(alpha: 0.3)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onPressed: _saveChargePower,
                      child: Text(
                        'LƯU',
                        style: CockpitTypography.label(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: CockpitColors.emerald,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Quick presets chip
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [350, 400, 650, 1000].map((w) {
                    final isSelected = chargePower.text == w.toString();
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text('$w W'),
                        backgroundColor: isSelected
                            ? CockpitColors.emeraldSubtle
                            : CockpitColors.elevated,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected
                                ? CockpitColors.emerald.withValues(alpha: 0.5)
                                : CockpitColors.border,
                          ),
                        ),
                        labelStyle: CockpitTypography.numbers(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? CockpitColors.emerald
                              : CockpitColors.muted,
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

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(color: CockpitColors.border, height: 1),
              ),

              // Đơn giá tiền điện
              Text(
                'Đơn giá tiền điện (VND/kWh)',
                style: CockpitTypography.label(fontSize: 12, color: CockpitColors.muted),
              ),
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
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: CockpitColors.elevated,
                        foregroundColor: CockpitColors.text,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(CockpitRadius.small),
                          side: const BorderSide(color: CockpitColors.border),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onPressed: _saveTariff,
                      child: Text(
                        'LƯU',
                        style: CockpitTypography.label(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: CockpitColors.text,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Section 4: BẢO VỆ & SAO LƯU ──
        const CockpitSectionLabel('Bảo vệ & Sao lưu'),
        CockpitSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _switchSettingRow(
                title: 'Safe Boot',
                subtitle:
                    'Chỉ hiển thị trạng thái đã xác minh; ứng dụng chưa hỗ trợ bật/tắt Safe Boot tại đây.',
                value: verification.safeBootVerified,
                onChanged: null,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: CockpitColors.border, height: 1),
              ),
              _switchSettingRow(
                title: 'Sao lưu mã hóa lên Server',
                subtitle:
                    'Lưu token cấu hình theo tài khoản để khôi phục khi đổi máy.',
                value: cloudBackupEnabled,
                onChanged: (val) async {
                  setState(() => cloudBackupEnabled = val);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('smartChargerEncryptedBackup', val);
                  AppPopup.showSuccess(
                    val ? 'Đã bật sao lưu mã hóa' : 'Đã tắt sao lưu',
                  );
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Section 5: THIẾT BỊ & FIRMWARE ──
        const CockpitSectionLabel('Thiết bị & Firmware'),
        CockpitSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _infoRow('Thiết bị', 'Shelly Plug S Gen3'),
              const SizedBox(height: 10),
              _infoRow('Firmware', 'Chưa đọc từ thiết bị'),
              const SizedBox(height: 10),
              _infoRow('Địa chỉ MAC', 'Chưa đọc từ thiết bị'),
              const SizedBox(height: 10),
              _infoRow('Tín hiệu Wi-Fi', 'Chưa có số đo'),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── Section 6: VÙNG NGUY HIỂM ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CockpitColors.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(CockpitRadius.large),
            border: Border.all(color: CockpitColors.danger.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: CockpitColors.danger,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Vùng nguy hiểm',
                    style: CockpitTypography.heading(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: CockpitColors.danger,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: CockpitButtonTokens.height,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: CockpitColors.danger.withValues(alpha: 0.2)),
                          backgroundColor: CockpitColors.elevated,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(CockpitButtonTokens.radius),
                          ),
                        ),
                        onPressed: () {
                          AppPopup.showWarning(
                            'Chưa hỗ trợ khởi động lại từ màn hình này. Không có lệnh nào được gửi đến Shelly.',
                          );
                        },
                        child: Text(
                          'Khởi động lại',
                          style: CockpitTypography.label(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: CockpitColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: CockpitButtonTokens.height,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: CockpitColors.danger),
                          backgroundColor: CockpitColors.danger.withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(CockpitButtonTokens.radius),
                          ),
                        ),
                        onPressed: _delete,
                        child: Text(
                          'Xóa cấu hình',
                          style: CockpitTypography.label(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: CockpitColors.danger,
                          ),
                        ),
                      ),
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
  Widget _statusPillBadge({
    required IconData icon,
    required String label,
    required bool verified,
  }) {
    final color = verified ? CockpitColors.emerald : CockpitColors.amber;
    final bg = verified ? CockpitColors.emeraldSubtle : const Color(0x1AFBBF24);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CockpitRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: CockpitTypography.label(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _protectionMetricRow(
    String label,
    String value, {
    IconData? icon,
    bool isMuted = false,
  }) {
    final accent = isMuted ? CockpitColors.dim : CockpitColors.emerald;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CockpitColors.elevated,
        borderRadius: BorderRadius.circular(CockpitRadius.small),
        border: Border.all(color: CockpitColors.border),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isMuted ? 0.08 : 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: accent),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              label,
              style: CockpitTypography.body(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isMuted ? CockpitColors.muted : CockpitColors.text,
              ),
            ),
          ),
          Text(
            value,
            style: CockpitTypography.numbers(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
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
      enabled: !busy,
      controller: controller,
      obscureText: isPassword && obscure,
      keyboardType: keyboardType,
      style: CockpitTypography.body(fontSize: 13, color: CockpitColors.text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: CockpitTypography.label(fontSize: 12, color: CockpitColors.muted),
        hintText: hint,
        hintStyle: CockpitTypography.body(fontSize: 12, color: CockpitColors.dim),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: CockpitColors.muted, size: 18)
            : null,
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                  color: CockpitColors.muted,
                ),
                onPressed: () => setState(() => obscure = !obscure),
              )
            : null,
        filled: true,
        fillColor: CockpitColors.elevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CockpitRadius.small),
          borderSide: const BorderSide(color: CockpitColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CockpitRadius.small),
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
    return SizedBox(
      height: CockpitButtonTokens.height,
      child: OutlinedButton.icon(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: isPrimary ? CockpitColors.emerald : CockpitColors.text,
          backgroundColor: isPrimary
              ? CockpitColors.emeraldSubtle
              : CockpitColors.elevated,
          side: BorderSide(
            color: isPrimary
                ? CockpitColors.emerald.withValues(alpha: 0.3)
                : CockpitColors.border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CockpitButtonTokens.radius),
          ),
        ),
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          textAlign: TextAlign.center,
          style: CockpitTypography.label(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isPrimary ? CockpitColors.emerald : CockpitColors.text,
          ),
        ),
      ),
    );
  }

  Widget _switchSettingRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: CockpitTypography.body(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: CockpitColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: CockpitTypography.label(
                  fontSize: 12,
                  color: CockpitColors.muted,
                ),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          activeThumbColor: CockpitColors.emerald,
          activeTrackColor: CockpitColors.emeraldSubtle,
          inactiveTrackColor: CockpitColors.elevated,
          onChanged: busy ? null : onChanged,
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: CockpitTypography.label(
              fontSize: 13,
              color: CockpitColors.muted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: CockpitTypography.numbers(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: CockpitColors.text,
            ),
          ),
        ),
      ],
    );
  }

  void _runNoLoadTest() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _ui.surface,
        title: Text(
          'Kiểm tra relay chưa khả dụng',
          style: TextStyle(color: _ui.text),
        ),
        content: Text(
          'Chức năng này chưa gửi lệnh kiểm tra đến Shelly. Không thể xác nhận relay hoạt động hoặc an toàn từ màn hình này.',
          style: TextStyle(color: _ui.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('HỦY'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _ui.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'ĐÃ HIỂU',
              style: TextStyle(
                color: _ui.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      AppPopup.showWarning(
        'Chưa hỗ trợ kiểm tra relay thực tế. Không có lệnh đóng/ngắt nào được gửi; chưa thể xác nhận an toàn.',
      );
    }
  }

  void _showTechnicalDetailsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: CockpitColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CockpitRadius.sheet)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: CockpitColors.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: CockpitColors.emerald.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.tune_rounded, color: CockpitColors.emerald, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Chi tiết kỹ thuật cảm biến',
                    style: CockpitTypography.heading(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: CockpitColors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
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
      ),
    );
  }

  void _showQuickPowerDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CockpitColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CockpitRadius.large),
          side: const BorderSide(color: CockpitColors.border),
        ),
        title: Text(
          'Chỉnh công suất sạc',
          style: CockpitTypography.heading(fontSize: 16, fontWeight: FontWeight.w700, color: CockpitColors.text),
        ),
        content: TextField(
          controller: chargePower,
          keyboardType: TextInputType.number,
          style: CockpitTypography.numbers(fontSize: 15, color: CockpitColors.text),
          decoration: InputDecoration(
            suffixText: 'W',
            suffixStyle: CockpitTypography.label(fontSize: 13, color: CockpitColors.muted),
            labelText: 'Công suất (W)',
            labelStyle: CockpitTypography.label(fontSize: 12, color: CockpitColors.muted),
            filled: true,
            fillColor: CockpitColors.elevated,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CockpitRadius.small),
              borderSide: const BorderSide(color: CockpitColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CockpitRadius.small),
              borderSide: const BorderSide(color: CockpitColors.emerald),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'HỦY',
              style: CockpitTypography.label(fontSize: 12, color: CockpitColors.muted),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: CockpitColors.emerald,
              foregroundColor: CockpitColors.shell,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CockpitRadius.small)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _saveChargePower();
            },
            child: Text(
              'LƯU',
              style: CockpitTypography.label(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: CockpitColors.shell,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showQuickTariffDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CockpitColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CockpitRadius.large),
          side: const BorderSide(color: CockpitColors.border),
        ),
        title: Text(
          'Chỉnh đơn giá điện',
          style: CockpitTypography.heading(fontSize: 16, fontWeight: FontWeight.w700, color: CockpitColors.text),
        ),
        content: TextField(
          controller: tariff,
          keyboardType: TextInputType.number,
          style: CockpitTypography.numbers(fontSize: 15, color: CockpitColors.text),
          decoration: InputDecoration(
            suffixText: 'đ/kWh',
            suffixStyle: CockpitTypography.label(fontSize: 13, color: CockpitColors.muted),
            labelText: 'Đơn giá',
            labelStyle: CockpitTypography.label(fontSize: 12, color: CockpitColors.muted),
            filled: true,
            fillColor: CockpitColors.elevated,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CockpitRadius.small),
              borderSide: const BorderSide(color: CockpitColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CockpitRadius.small),
              borderSide: const BorderSide(color: CockpitColors.emerald),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'HỦY',
              style: CockpitTypography.label(fontSize: 12, color: CockpitColors.muted),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: CockpitColors.emerald,
              foregroundColor: CockpitColors.shell,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CockpitRadius.small)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _saveTariff();
            },
            child: Text(
              'LƯU',
              style: CockpitTypography.label(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: CockpitColors.shell,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSwitchVehicleDialog() async {
    if (busy || !await _guardInactive() || !mounted) return;
    if (dirty) {
      AppPopup.showWarning('Hãy lưu cấu hình đang sửa trước khi đổi xe.');
      return;
    }
    try {
      final vehicles = await ref
          .read(chargeLogRepositoryProvider)
          .getAllVehicles();
      if (!mounted) return;
      final id = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: _ui.surface,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text('Chọn xe sạc')),
              if (vehicles.where((v) => !v.isArchived).isEmpty)
                ListTile(
                  title: Text('Chưa có xe. Hãy thêm xe ở màn hình quản lý xe.'),
                ),
              for (final vehicle in vehicles.where((v) => !v.isArchived))
                ListTile(
                  title: Text(vehicle.vehicleName),
                  subtitle: Text(vehicle.vehicleId),
                  selected: vehicle.vehicleId == selectedVehicleId,
                  onTap: () => Navigator.pop(context, vehicle.vehicleId),
                ),
            ],
          ),
        ),
      );
      if (id == null || !mounted || !await _guardInactive() || !mounted) return;
      await SessionService().setSelectedVehicleId(id);
      if (!mounted) return;
      ref.read(selectedVehicleIdProvider.notifier).state = id;
      setState(() => busy = true);
      await _load();
    } catch (_) {
      if (mounted) {
        AppPopup.showError('Không tải được danh sách xe. Vui lòng thử lại.');
      }
    }
  }
}
