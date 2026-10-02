import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_ui_colors.dart';
import '../../core/theme/cockpit_design_system.dart';
import '../../data/models/shelly_connection.dart';
import '../../data/models/shelly_connection_state.dart';
import '../../data/services/shelly_cloud_auth_service.dart';
import '../../data/services/shelly_connection_coordinator.dart';
import '../../data/services/smart_charger_service.dart';
import 'smart_charger_setup_hub_screen.dart';

/// Normal Mode Shelly setup.
/// Designed for everyday users: hides all technical secrets (Cloud keys,
/// raw tokens, device IDs, RPC URLs), provides a guided single-tap connect,
/// animated radar scan, safety test confirmation, and troubleshooting checklist.
class ShellyConnectScreen extends StatefulWidget {
  const ShellyConnectScreen({super.key});

  @override
  State<ShellyConnectScreen> createState() => _ShellyConnectScreenState();
}

class _ShellyConnectScreenState extends State<ShellyConnectScreen> {
  final _coordinator = ShellyConnectionCoordinator.shared;
  StreamSubscription<ShellyConnectionSnapshot>? _subscription;
  ShellyConnectionSnapshot _snapshot =
      ShellyConnectionCoordinator.shared.current;
  bool _restoring = true;
  bool _developerUnlocked = false;

  // 3-Flow navigation: 1 = LAN Wi-Fi, 2 = Shelly Cloud, 3 = Admin Code & Troubleshooting
  int _activeFlow = 1;

  // Flow 2 (Shelly Cloud) controllers & state
  final _cloudKeyController = TextEditingController();
  bool _cloudKeyObscure = true;
  bool _cloudLoading = false;
  List<ShellyCloudDevice> _cloudDevices = [];
  String? _cloudError;
  ShellyCloudAuthService? _cloudAuth;
  ShellyCloudAuthService get cloudAuth =>
      _cloudAuth ??= ShellyCloudAuthService();

  // Flow 3 (Admin Connection Code) controllers & state
  final _codeController = TextEditingController();
  bool _redeemingCode = false;
  String? _codeError;

  @override
  void initState() {
    super.initState();
    _subscription = _coordinator.states.listen((value) {
      if (mounted) setState(() => _snapshot = value);
    });
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _developerUnlocked = prefs.getBool('developerModeUnlocked') ?? false;
    } catch (_) {}

    final result = await _coordinator.restore();
    if (mounted) {
      setState(() {
        _snapshot = result;
        _restoring = false;
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _cloudKeyController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _searchCloudDevices() async {
    final key = _cloudKeyController.text.trim();
    if (key.isEmpty) {
      setState(() => _cloudError = 'Vui lòng nhập Cloud Auth Key');
      return;
    }
    setState(() {
      _cloudLoading = true;
      _cloudError = null;
      _cloudDevices = [];
    });
    try {
      final devices = await cloudAuth.listDevices(authKey: key);
      if (!mounted) return;
      if (devices.isEmpty) {
        setState(() {
          _cloudLoading = false;
          _cloudError =
              'Không tìm thấy thiết bị nào trong tài khoản Cloud này.';
        });
      } else {
        setState(() {
          _cloudLoading = false;
          _cloudDevices = devices;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cloudLoading = false;
        _cloudError = 'Chưa thể tìm thiết bị. Kiểm tra kết nối và thử lại.';
      });
    }
  }

  Future<void> _connectCloudDevice(ShellyCloudDevice device) async {
    final key = _cloudKeyController.text.trim();
    final result = await _coordinator.connectCloudKey(
      key,
      selectedDevice: device,
    );
    if (mounted) setState(() => _snapshot = result);
  }

  Future<void> _redeemAdminCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _codeError = 'Mã kết nối phải có đúng 6 ký tự.');
      return;
    }
    setState(() {
      _redeemingCode = true;
      _codeError = null;
    });
    try {
      final result = await _coordinator.redeemCode(code);
      if (!mounted) return;
      setState(() {
        _redeemingCode = false;
        _snapshot = result;
        if (result.state == ShellyConnectionFlowState.connectionFailed) {
          _codeError = result.errorMessage ?? 'Không thể kích hoạt mã kết nối';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _redeemingCode = false;
        _codeError = 'Chưa thể xác minh mã. Kiểm tra kết nối và thử lại.';
      });
    }
  }

  Future<void> _discover() async {
    final result = await _coordinator.autoConnect();
    if (mounted) setState(() => _snapshot = result);
  }

  Future<void> _connect(DiscoveredShellyDevice device) async {
    final result = await _coordinator.connectDevice(device);
    if (!mounted) return;
    setState(() => _snapshot = result);
    if (result.state == ShellyConnectionFlowState.passwordRequired) {
      await _askPassword(device);
    }
  }

  Future<void> _askPassword(DiscoveredShellyDevice device) async {
    final controller = TextEditingController();
    bool obscure = true;
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CockpitRadius.medium),
          ),
          backgroundColor: AppUiColors.of(context).surface,
          title: Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: AppUiColors.of(context).primary,
              ),
              const SizedBox(width: 10),
              Text(
                'Mật khẩu Shelly',
                style: TextStyle(
                  color: AppUiColors.of(context).text,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thiết bị "${_friendlyName(device)}" đã được bảo vệ bằng mật khẩu cục bộ.',
                style: TextStyle(
                  color: AppUiColors.of(context).muted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: obscure,
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                style: TextStyle(color: AppUiColors.of(context).text),
                decoration: InputDecoration(
                  labelText: 'Mật khẩu thiết bị',
                  hintText: 'Nhập mật khẩu Web UI của Shelly',
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppUiColors.of(context).muted,
                    ),
                    onPressed: () {
                      setModalState(() => obscure = !obscure);
                    },
                  ),
                  helperText:
                      'Lưu an toàn trên điện thoại, không gửi ra ngoài.',
                  helperMaxLines: 2,
                ),
                onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Hủy',
                style: TextStyle(color: AppUiColors.of(context).muted),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (password == null || password.isEmpty) return;
    final result = await _coordinator.connectDevice(
      device,
      localPassword: password,
    );
    if (mounted) setState(() => _snapshot = result);
  }

  Future<void> _confirmSafetyTest() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CockpitRadius.medium),
        ),
        backgroundColor: AppUiColors.of(context).surface,
        title: Row(
          children: [
            Icon(
              Icons.shield_outlined,
              color: AppUiColors.of(context).primary,
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              'Kiểm tra an toàn phần cứng',
              style: TextStyle(
                color: AppUiColors.of(context).text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Để đảm bảo an toàn điện áp cho xe và gia đình, hệ thống sẽ thực hiện:',
              style: TextStyle(
                color: AppUiColors.of(context).text,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            _safetyBullet(
              'Cấu hình Safe Boot về OFF (tự ngắt khi cắm lại điện)',
              AppUiColors.of(context),
            ),
            _safetyBullet(
              'Tắt chế độ Auto-ON trên ổ cắm Shelly',
              AppUiColors.of(context),
            ),
            _safetyBullet(
              'Kích hoạt đóng relay 5 giây không tải để xác thực cảm biến',
              AppUiColors.of(context),
            ),
            _safetyBullet(
              'Yêu cầu ngắt relay OFF và đọc lại trạng thái an toàn',
              AppUiColors.of(context),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppUiColors.of(context).amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppUiColors.of(context).amber.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppUiColors.of(context).amber,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Vui lòng rút phích cắm sạc xe khỏi ổ cắm trước khi chạy kiểm tra.',
                      style: TextStyle(
                        color: AppUiColors.of(context).text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Để sau',
              style: TextStyle(color: AppUiColors.of(context).muted),
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Bắt đầu kiểm tra'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    final result = await _coordinator.runConfirmedSafetyTest();
    if (mounted) setState(() => _snapshot = result);
  }

  Widget _safetyBullet(String text, AppUiColors ui) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_rounded, size: 16, color: ui.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: ui.muted, fontSize: 13)),
        ),
      ],
    ),
  );

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CockpitRadius.medium),
        ),
        backgroundColor: AppUiColors.of(context).surface,
        title: const Text('Ngắt kết nối Shelly?'),
        content: const Text(
          'Thiết bị sẽ không còn được dùng để điều khiển sạc thông minh cho xe này. '
          'Bạn có thể kết nối lại bất cứ lúc nào.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppUiColors.of(context).danger,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ngắt kết nối'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _coordinator.disconnect();
    } on SmartChargerException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppUiColors.of(context).danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openDeveloperSetup() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SmartChargerSetupHubScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ui = AppUiColors.of(context);
    final state = _snapshot.state;
    final busy =
        _restoring ||
        {
          ShellyConnectionFlowState.discovering,
          ShellyConnectionFlowState.connecting,
          ShellyConnectionFlowState.verifying,
        }.contains(state);

    return Scaffold(
      backgroundColor: ui.background,
      appBar: AppBar(
        backgroundColor: ui.background,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Quay lại',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded, color: ui.text),
        ),
        title: Text(
          'Smart Charger',
          style: CockpitTypography.heading(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: ui.text,
          ),
        ),
        actions: [
          if (_developerUnlocked)
            IconButton(
              tooltip: 'Cấu hình kỹ thuật (Developer)',
              onPressed: _openDeveloperSetup,
              icon: Icon(Icons.tune_rounded, color: ui.muted),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                if (_snapshot.codeRefreshRequired)
                  ListTile(
                    title: const Text('Thiết bị có mã kết nối mới'),
                    subtitle: const Text(
                      'Liên kết hiện tại vẫn được giữ. Nhập mã mới do quản trị viên cấp khi thuận tiện.',
                    ),
                    trailing: TextButton(
                      onPressed: () => setState(() => _activeFlow = 3),
                      child: const Text('Nhập mã'),
                    ),
                  ),
                if (state == ShellyConnectionFlowState.discovering) ...[
                  const SizedBox(height: 16),
                  Center(child: _PulsingRadar(color: ui.primary)),
                  const SizedBox(height: 16),
                ] else ...[
                  Center(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _badgeColorFor(
                          state,
                          ui,
                        ).withValues(alpha: 0.14),
                        border: Border.all(
                          color: _badgeColorFor(
                            state,
                            ui,
                          ).withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        _iconFor(state),
                        size: 28,
                        color: _badgeColorFor(state, ui),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  _titleFor(state),
                  textAlign: TextAlign.center,
                  style: CockpitTypography.heading(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: ui.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitleFor(state),
                  textAlign: TextAlign.center,
                  style: CockpitTypography.body(fontSize: 13, color: ui.muted),
                ),
                const SizedBox(height: 14),
                if (busy && state != ShellyConnectionFlowState.discovering) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 14),
                  Text(
                    'Đang kiểm tra và xác thực thiết bị…',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ui.muted, fontSize: 13),
                  ),
                ] else ...[
                  ..._buildStateContent(ui),
                ],
                if (_developerUnlocked &&
                    state != ShellyConnectionFlowState.discovering) ...[
                  const SizedBox(height: 32),
                  _buildDeveloperBanner(ui),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStateContent(AppUiColors ui) {
    final state = _snapshot.state;

    switch (state) {
      case ShellyConnectionFlowState.connected:
        return _buildConnectedView(ui);
      case ShellyConnectionFlowState.verificationRequired:
        return _buildVerificationRequiredView(ui);
      case ShellyConnectionFlowState.deviceFound:
        return _buildDeviceFoundView(ui);
      case ShellyConnectionFlowState.multipleDevices:
        return _buildMultipleDevicesView(ui);
      case ShellyConnectionFlowState.passwordRequired:
        return _buildPasswordRequiredView(ui);
      case ShellyConnectionFlowState.connectionFailed:
      case ShellyConnectionFlowState.offline:
        return _buildErrorView(ui);
      case ShellyConnectionFlowState.incompatible:
        return _buildIncompatibleView(ui);
      case ShellyConnectionFlowState.discovering:
        return [
          Center(
            child: Text(
              'Đang quét các thiết bị Shelly trong cùng mạng Wi-Fi…',
              style: TextStyle(color: ui.muted, fontSize: 13),
            ),
          ),
        ];
      case ShellyConnectionFlowState.connecting:
      case ShellyConnectionFlowState.verifying:
        return const [];
      case ShellyConnectionFlowState.disconnected:
        return [
          _buildStepIndicator(ui),
          if (_activeFlow == 1) ..._buildDisconnectedView(ui),
          if (_activeFlow == 2) ..._buildCloudConnectView(ui),
          if (_activeFlow == 3) ..._buildAdminCodeView(ui),
        ];
    }
  }

  Widget _buildStepIndicator(AppUiColors ui) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: ui.surface,
        borderRadius: BorderRadius.circular(CockpitRadius.medium),
        border: Border.all(color: ui.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _stepTab(
              title: '1. Wi-Fi gần',
              icon: Icons.wifi_rounded,
              isActive: _activeFlow == 1,
              ui: ui,
              onTap: () => setState(() => _activeFlow = 1),
            ),
          ),
          Container(width: 1, height: 16, color: ui.border),
          Expanded(
            child: _stepTab(
              title: '2. Cloud',
              icon: Icons.cloud_outlined,
              isActive: _activeFlow == 2,
              ui: ui,
              onTap: () => setState(() => _activeFlow = 2),
            ),
          ),
          Container(width: 1, height: 16, color: ui.border),
          Expanded(
            child: _stepTab(
              title: '3. Mã Admin',
              icon: Icons.vpn_key_outlined,
              isActive: _activeFlow == 3,
              ui: ui,
              onTap: () => setState(() => _activeFlow = 3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepTab({
    required String title,
    required IconData icon,
    required bool isActive,
    required AppUiColors ui,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isActive ? ui.primary.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isActive ? ui.primary : ui.muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive ? ui.primary : ui.muted,
                    fontSize: 11.5,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCloudConnectView(AppUiColors ui) {
    return [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: ui.surface,
          borderRadius: BorderRadius.circular(CockpitRadius.medium),
          border: Border.all(color: ui.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_outlined, color: ui.primary, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Kết nối từ xa qua Shelly Cloud',
                    style: TextStyle(
                      color: ui.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Nếu điện thoại và Shelly không ở cùng mạng Wi-Fi, bạn có thể kết nối từ xa bằng tài khoản Shelly Cloud.',
              style: TextStyle(color: ui.muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ui.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ui.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cách lấy mã xác thực Cloud:',
                    style: TextStyle(
                      color: ui.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _checkItem(
                    '1. Mở ứng dụng Shelly Smart Control trên điện thoại',
                    ui,
                  ),
                  _checkItem(
                    '2. Vào User Profile -> Authorization Cloud Key',
                    ui,
                  ),
                  _checkItem('3. Sao chép key và dán vào ô bên dưới', ui),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cloudKeyController,
              obscureText: _cloudKeyObscure,
              style: TextStyle(color: ui.text),
              decoration: InputDecoration(
                labelText: 'Mã xác thực Shelly Cloud',
                hintText: 'Dán mã tại đây…',
                prefixIcon: Icon(Icons.key_rounded, color: ui.muted),
                suffixIcon: IconButton(
                  icon: Icon(
                    _cloudKeyObscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: ui.muted,
                  ),
                  onPressed: () =>
                      setState(() => _cloudKeyObscure = !_cloudKeyObscure),
                ),
              ),
            ),
            if (_cloudError != null) ...[
              const SizedBox(height: 10),
              Text(
                _cloudError!,
                style: TextStyle(color: ui.danger, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _cloudLoading ? null : _searchCloudDevices,
                icon: _cloudLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search_rounded),
                label: Text(
                  _cloudLoading
                      ? 'Đang tìm thiết bị…'
                      : 'Tìm thiết bị trên Cloud',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CockpitRadius.medium),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: () => cloudAuth.launchShellyCloudPortal(),
                icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                label: const Text('Mở trang quản trị Shelly Cloud (Web)'),
              ),
            ),
          ],
        ),
      ),
      if (_cloudDevices.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(
          'Thiết bị tìm thấy trong tài khoản Cloud:',
          style: TextStyle(
            color: ui.text,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 10),
        ..._cloudDevices.map(
          (dev) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: ui.surface,
              borderRadius: BorderRadius.circular(CockpitRadius.medium),
              child: InkWell(
                onTap: () => _connectCloudDevice(dev),
                borderRadius: BorderRadius.circular(CockpitRadius.medium),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(CockpitRadius.medium),
                    border: Border.all(color: ui.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_done_rounded, color: ui.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dev.name.isNotEmpty ? dev.name : 'Shelly',
                              style: TextStyle(
                                color: ui.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              dev.type,
                              style: TextStyle(color: ui.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        onPressed: () => _connectCloudDevice(dev),
                        child: const Text('Kết nối'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ui.surface,
          borderRadius: BorderRadius.circular(CockpitRadius.medium),
          border: Border.all(color: ui.border),
        ),
        child: Row(
          children: [
            Icon(Icons.help_outline_rounded, color: ui.muted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Không có tài khoản Cloud hoặc gặp sự cố?',
                style: TextStyle(color: ui.muted, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _activeFlow = 3),
              child: const Text('Nhập mã Admin ➔'),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildAdminCodeView(AppUiColors ui) {
    return [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: ui.surface,
          borderRadius: BorderRadius.circular(CockpitRadius.medium),
          border: Border.all(color: ui.primary.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: ui.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.vpn_key_rounded,
                    color: ui.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nhập mã kết nối từ Admin',
                        style: TextStyle(
                          color: ui.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Cung cấp bởi Quản trị viên hệ thống',
                        style: TextStyle(color: ui.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Nếu bạn không thể kết nối qua Wi-Fi hay Cloud, Quản trị viên có thể tạo một mã kết nối gồm 6 ký tự trên Admin Portal để cấp cho bạn.',
              style: TextStyle(color: ui.muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 18),
            Center(
              child: SizedBox(
                width: 260,
                child: TextField(
                  controller: _codeController,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(6),
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                  ],
                  style: TextStyle(
                    color: ui.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 8,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: 'A8X9K2',
                    hintStyle: TextStyle(
                      color: ui.muted.withValues(alpha: 0.4),
                      letterSpacing: 8,
                    ),
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                  ),
                ),
              ),
            ),
            if (_codeError != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: ui.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _codeError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ui.danger, fontSize: 12.5),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _redeemingCode ? null : _redeemAdminCode,
                icon: _redeemingCode
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline_rounded),
                label: Text(
                  _redeemingCode ? 'Đang kích hoạt mã…' : 'Xác nhận mã kết nối',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CockpitRadius.medium),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ui.surface,
          borderRadius: BorderRadius.circular(CockpitRadius.medium),
          border: Border.all(color: ui.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.checklist_rounded, color: ui.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Kiểm tra lại thiết bị phần cứng',
                  style: TextStyle(
                    color: ui.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _checkItem(
              'Shelly đã được cắm nguồn điện và đèn LED hoạt động',
              ui,
            ),
            _checkItem(
              'Điện thoại và Shelly đang ở cùng mạng Wi-Fi (2.4GHz)',
              ui,
            ),
            _checkItem(
              'Quyền Mạng cục bộ (Local Network) đã được cấp cho ứng dụng',
              ui,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Center(
        child: OutlinedButton.icon(
          onPressed: () {
            setState(() => _activeFlow = 1);
            _discover();
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Quét lại từ Bước 1 (Wi-Fi)'),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CockpitRadius.medium),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildDisconnectedView(AppUiColors ui) {
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ui.surface,
          borderRadius: BorderRadius.circular(CockpitRadius.medium),
          border: Border.all(color: ui.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt_rounded, color: ui.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Kiểm tra bộ sạc và điện năng',
                    style: TextStyle(
                      color: ui.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Kết nối ổ cắm Shelly để xem công suất, điện áp và dòng điện khi sạc.',
              style: TextStyle(color: ui.muted, fontSize: 12.5, height: 1.3),
            ),
            const SizedBox(height: 10),
            _featurePill(
              Icons.shield_outlined,
              'Kiểm tra cấu hình an toàn',
              ui,
            ),
            const SizedBox(height: 4),
            _featurePill(
              Icons.speed_rounded,
              'Xem trạng thái thiết bị theo thời gian thực',
              ui,
            ),
            const SizedBox(height: 4),
            _featurePill(
              Icons.wifi_rounded,
              'Chỉ bật điều khiển sau khi xác minh',
              ui,
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      SizedBox(
        height: 46,
        child: FilledButton.icon(
          onPressed: _discover,
          icon: const Icon(Icons.search_rounded),
          label: const Text(
            'Tìm và kết nối Shelly',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CockpitRadius.medium),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _featurePill(IconData icon, String text, AppUiColors ui) => Row(
    children: [
      Icon(icon, size: 16, color: ui.primary),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: TextStyle(color: ui.text, fontSize: 12)),
      ),
    ],
  );

  List<Widget> _buildConnectedView(AppUiColors ui) {
    final status = _snapshot.status;
    return [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: ui.surface,
          borderRadius: BorderRadius.circular(CockpitRadius.medium),
          border: Border.all(color: ui.primary.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ui.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ui.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'ĐÃ KẾT NỐI',
                        style: TextStyle(
                          color: ui.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  'Gen 3 • LAN Direct',
                  style: TextStyle(color: ui.muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _snapshot.deviceName ?? 'Shelly Plug S',
              style: TextStyle(
                color: ui.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Đã vượt qua kiểm tra an toàn phần cứng và đang sẵn sàng giám sát.',
              style: TextStyle(color: ui.muted, fontSize: 13),
            ),
            if (status != null) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _telemetryTile(
                    'Công suất',
                    '${status.powerW.toStringAsFixed(0)} W',
                    Icons.bolt_rounded,
                    ui,
                  ),
                  _telemetryTile(
                    'Điện áp',
                    '${status.voltageV.toStringAsFixed(0)} V',
                    Icons.speed_rounded,
                    ui,
                  ),
                  _telemetryTile(
                    'Dòng điện',
                    '${status.currentA.toStringAsFixed(2)} A',
                    Icons.electrical_services_rounded,
                    ui,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),
      ElevatedButton.icon(
        onPressed: () => Navigator.of(context).maybePop(true),
        icon: const Icon(Icons.bolt_rounded),
        label: const Text('Đến trang điều khiển Smart Charger'),
        style: ElevatedButton.styleFrom(
          backgroundColor: ui.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CockpitRadius.medium),
          ),
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _disconnect,
        icon: const Icon(Icons.power_settings_new_rounded),
        label: const Text('Ngắt kết nối thiết bị'),
        style: OutlinedButton.styleFrom(
          foregroundColor: ui.danger,
          side: BorderSide(color: ui.danger.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CockpitRadius.medium),
          ),
        ),
      ),
    ];
  }

  Widget _telemetryTile(
    String label,
    String value,
    IconData icon,
    AppUiColors ui,
  ) => Column(
    children: [
      Icon(icon, size: 20, color: ui.primary),
      const SizedBox(height: 4),
      Text(
        value,
        style: CockpitTypography.numbers(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: ui.text,
        ),
      ),
      Text(label, style: TextStyle(color: ui.muted, fontSize: 11)),
    ],
  );

  List<Widget> _buildVerificationRequiredView(AppUiColors ui) {
    final dev = _snapshot.devices.isNotEmpty ? _snapshot.devices.first : null;
    return [
      if (dev != null) ...[
        _deviceCard(dev, ui, isSelected: true),
        const SizedBox(height: 16),
      ],
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ui.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(CockpitRadius.medium),
          border: Border.all(color: ui.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user_outlined, color: ui.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Cần xác thực an toàn phần cứng',
                  style: TextStyle(
                    color: ui.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Để tránh tai nạn chập cháy và đảm bảo an toàn pin xe, ứng dụng sẽ chạy một bài kiểm tra relay 5 giây không tải trước khi kích hoạt điều khiển.',
              style: TextStyle(color: ui.muted, fontSize: 13, height: 1.35),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      SizedBox(
        height: 50,
        child: FilledButton.icon(
          onPressed: _confirmSafetyTest,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text(
            'Chạy kiểm tra an toàn',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CockpitRadius.medium),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextButton.icon(
        onPressed: _discover,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Quét lại thiết bị khác'),
      ),
    ];
  }

  List<Widget> _buildDeviceFoundView(AppUiColors ui) {
    final dev = _snapshot.devices.first;
    return [
      _deviceCard(dev, ui, isSelected: true),
      const SizedBox(height: 20),
      SizedBox(
        height: 50,
        child: FilledButton.icon(
          onPressed: () => _connect(dev),
          icon: const Icon(Icons.link_rounded),
          label: const Text(
            'Kết nối thiết bị này',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CockpitRadius.medium),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextButton.icon(
        onPressed: _discover,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Tìm lại thiết bị khác'),
      ),
    ];
  }

  List<Widget> _buildMultipleDevicesView(AppUiColors ui) {
    return [
      Text(
        'Chọn thiết bị bạn đang dùng để sạc:',
        style: TextStyle(
          color: ui.text,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      const SizedBox(height: 12),
      ..._snapshot.devices.map(
        (dev) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _deviceCard(dev, ui, onTap: () => _connect(dev)),
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton.icon(
          onPressed: _discover,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Quét lại mạng Wi-Fi'),
        ),
      ),
    ];
  }

  Widget _deviceCard(
    DiscoveredShellyDevice dev,
    AppUiColors ui, {
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: isSelected ? ui.primary.withValues(alpha: 0.1) : ui.surface,
      borderRadius: BorderRadius.circular(CockpitRadius.medium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CockpitRadius.medium),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CockpitRadius.medium),
            border: Border.all(
              color: isSelected ? ui.primary : ui.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ui.primary.withValues(alpha: 0.12),
                ),
                child: Icon(Icons.power_rounded, color: ui.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _friendlyName(dev),
                            style: TextStyle(
                              color: ui.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: ui.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Online',
                            style: TextStyle(
                              color: ui.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'IP: ${dev.address} • ${dev.model.isNotEmpty ? dev.model : 'Gen 3'}',
                      style: TextStyle(color: ui.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: ui.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPasswordRequiredView(AppUiColors ui) {
    final dev = _snapshot.devices.isNotEmpty ? _snapshot.devices.first : null;
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ui.surface,
          borderRadius: BorderRadius.circular(CockpitRadius.medium),
          border: Border.all(color: ui.amber.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Icon(Icons.lock_rounded, size: 36, color: ui.amber),
            const SizedBox(height: 8),
            Text(
              'Yêu cầu mật khẩu thiết bị',
              style: TextStyle(
                color: ui.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _snapshot.errorMessage ??
                  'Thiết bị Shelly có bật mật khẩu bảo vệ Web UI.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ui.muted, fontSize: 13),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (dev != null)
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: () => _askPassword(dev),
            icon: const Icon(Icons.key_rounded),
            label: const Text('Nhập mật khẩu Shelly'),
          ),
        ),
      const SizedBox(height: 12),
      TextButton(onPressed: _discover, child: const Text('Quét lại mạng')),
    ];
  }

  List<Widget> _buildErrorView(AppUiColors ui) {
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ui.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(CockpitRadius.medium),
          border: Border.all(color: ui.danger.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline_rounded, color: ui.danger, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _snapshot.errorMessage ?? 'Không tìm thấy thiết bị Shelly',
                    style: TextStyle(
                      color: ui.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Hãy kiểm tra các bước sau:',
              style: TextStyle(
                color: ui.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _checkItem(
              'Shelly đã được cắm nguồn điện và đèn LED hoạt động',
              ui,
            ),
            _checkItem(
              'Điện thoại và Shelly đang ở cùng mạng Wi-Fi (2.4GHz)',
              ui,
            ),
            _checkItem(
              'Quyền Mạng cục bộ (Local Network) đã được cấp cho ứng dụng',
              ui,
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: _discover,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Thử lại'),
        ),
      ),
      if (_snapshot.isPermissionDenied) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => openAppSettings(),
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Mở Cài đặt hệ thống để cấp quyền'),
        ),
      ],
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ui.surface,
          borderRadius: BorderRadius.circular(CockpitRadius.medium),
          border: Border.all(color: ui.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.alt_route_rounded, color: ui.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Không tìm thấy thiết bị trên Wi-Fi?',
                    softWrap: true,
                    style: TextStyle(
                      color: ui.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Bạn có thể kết nối từ xa qua Shelly Cloud hoặc yêu cầu mã kết nối từ Admin.',
              style: TextStyle(color: ui.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _activeFlow = 2;
                        _snapshot = const ShellyConnectionSnapshot(
                          state: ShellyConnectionFlowState.disconnected,
                        );
                      });
                    },
                    icon: const Icon(Icons.cloud_outlined, size: 16),
                    label: const Text('Qua Bước 2: Cloud'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _activeFlow = 3;
                        _snapshot = const ShellyConnectionSnapshot(
                          state: ShellyConnectionFlowState.disconnected,
                        );
                      });
                    },
                    icon: const Icon(Icons.vpn_key_outlined, size: 16),
                    label: const Text('Qua Bước 3: Mã Admin'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  Widget _checkItem(String text, AppUiColors ui) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '• ',
          style: TextStyle(color: ui.primary, fontWeight: FontWeight.bold),
        ),
        Expanded(
          child: Text(text, style: TextStyle(color: ui.muted, fontSize: 12.5)),
        ),
      ],
    ),
  );

  List<Widget> _buildIncompatibleView(AppUiColors ui) {
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ui.amber.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(CockpitRadius.medium),
          border: Border.all(color: ui.amber.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(Icons.warning_amber_rounded, size: 36, color: ui.amber),
            const SizedBox(height: 10),
            Text(
              'Thiết bị không tương thích',
              style: TextStyle(
                color: ui.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _snapshot.errorMessage ??
                  'Thiết bị tìm thấy không hỗ trợ đo điện năng (Power Metering). '
                      'Hệ thống yêu cầu các trường công suất, điện áp và điện năng để theo dõi sạc.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ui.muted, fontSize: 13, height: 1.35),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _discover,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Quét lại thiết bị khác'),
      ),
    ];
  }

  Widget _buildDeveloperBanner(AppUiColors ui) {
    return InkWell(
      onTap: _openDeveloperSetup,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: ui.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ui.border),
        ),
        child: Row(
          children: [
            Icon(Icons.developer_mode_rounded, size: 18, color: ui.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Mở cấu hình kỹ thuật nâng cao (Developer)',
                style: TextStyle(
                  color: ui.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: ui.muted),
          ],
        ),
      ),
    );
  }

  String _titleFor(ShellyConnectionFlowState state) {
    if (state == ShellyConnectionFlowState.disconnected) {
      if (_activeFlow == 2) return 'Kết nối qua Shelly Cloud';
      if (_activeFlow == 3) return 'Hỗ trợ & Nhập mã từ Admin';
      return 'Theo dõi điện năng sạc bằng Shelly';
    }
    return switch (state) {
      ShellyConnectionFlowState.connected => 'Shelly đã được kết nối',
      ShellyConnectionFlowState.verificationRequired => 'Xác nhận an toàn',
      ShellyConnectionFlowState.deviceFound => 'Đã tìm thấy Shelly',
      ShellyConnectionFlowState.multipleDevices => 'Chọn thiết bị Shelly',
      ShellyConnectionFlowState.discovering => 'Đang tìm kiếm Shelly…',
      ShellyConnectionFlowState.connecting => 'Đang kết nối…',
      ShellyConnectionFlowState.verifying => 'Đang kiểm tra an toàn…',
      ShellyConnectionFlowState.offline => 'Shelly đang ngoại tuyến',
      ShellyConnectionFlowState.connectionFailed => 'Chưa kết nối được Shelly',
      ShellyConnectionFlowState.incompatible => 'Thiết bị không tương thích',
      ShellyConnectionFlowState.passwordRequired => 'Cần mật khẩu thiết bị',
      _ => 'Theo dõi điện năng sạc bằng Shelly',
    };
  }

  String _subtitleFor(ShellyConnectionFlowState state) {
    if (state == ShellyConnectionFlowState.disconnected) {
      if (_activeFlow == 2) {
        return 'Kết nối thiết bị từ xa bằng tài khoản Shelly Cloud của bạn.';
      }
      if (_activeFlow == 3) {
        return 'Nhập mã kết nối do Quản trị viên cấp hoặc kiểm tra lại thiết bị.';
      }
      return 'Kết nối ổ cắm Shelly để tự động ghi nhận điện năng sạc và bảo vệ pin.';
    }
    return switch (state) {
      ShellyConnectionFlowState.connected =>
        'Thiết bị đã sẵn sàng tự động theo dõi sạc cho xe của bạn.',
      ShellyConnectionFlowState.verificationRequired =>
        'Xác nhận kiểm tra an toàn phần cứng để kích hoạt điều khiển.',
      ShellyConnectionFlowState.deviceFound =>
        'Đã phát hiện thiết bị trên mạng Wi-Fi nội bộ.',
      ShellyConnectionFlowState.multipleDevices =>
        'Tìm thấy nhiều thiết bị. Vui lòng chọn thiết bị đang sạc xe.',
      ShellyConnectionFlowState.discovering =>
        'Đang quét mạng Wi-Fi để tự động tìm thiết bị Shelly.',
      ShellyConnectionFlowState.connecting =>
        'Đang thiết lập kênh giao tiếp an toàn với thiết bị.',
      ShellyConnectionFlowState.verifying =>
        'Đang xác thực thông số đo điện năng và cấu hình an toàn.',
      ShellyConnectionFlowState.offline =>
        'Kiểm tra nguồn điện và đảm bảo thiết bị đang bật Wi-Fi.',
      ShellyConnectionFlowState.connectionFailed =>
        'Hãy đảm bảo điện thoại và Shelly cùng mạng Wi-Fi và thử lại.',
      ShellyConnectionFlowState.incompatible =>
        'Thiết bị cần có tính năng đo điện năng (apower/voltage/current).',
      ShellyConnectionFlowState.passwordRequired =>
        'Vui lòng nhập mật khẩu Web UI để hoàn tất kết nối.',
      _ =>
        'Kết nối ổ cắm Shelly để tự động ghi nhận điện năng sạc và bảo vệ pin.',
    };
  }

  Color _badgeColorFor(ShellyConnectionFlowState state, AppUiColors ui) =>
      switch (state) {
        ShellyConnectionFlowState.connected => ui.primary,
        ShellyConnectionFlowState.verificationRequired => ui.primary,
        ShellyConnectionFlowState.deviceFound => ui.primary,
        ShellyConnectionFlowState.multipleDevices => ui.primary,
        ShellyConnectionFlowState.connectionFailed => ui.danger,
        ShellyConnectionFlowState.offline => ui.danger,
        ShellyConnectionFlowState.incompatible => ui.amber,
        ShellyConnectionFlowState.passwordRequired => ui.amber,
        _ => ui.primary,
      };

  IconData _iconFor(ShellyConnectionFlowState state) {
    if (state == ShellyConnectionFlowState.disconnected) {
      if (_activeFlow == 2) return Icons.cloud_outlined;
      if (_activeFlow == 3) return Icons.vpn_key_rounded;
      return Icons.bolt_rounded;
    }
    return switch (state) {
      ShellyConnectionFlowState.connected => Icons.check_circle_outline_rounded,
      ShellyConnectionFlowState.verificationRequired => Icons.shield_outlined,
      ShellyConnectionFlowState.deviceFound => Icons.power_rounded,
      ShellyConnectionFlowState.multipleDevices => Icons.devices_other_rounded,
      ShellyConnectionFlowState.connectionFailed => Icons.error_outline_rounded,
      ShellyConnectionFlowState.offline => Icons.wifi_off_rounded,
      ShellyConnectionFlowState.incompatible => Icons.warning_amber_rounded,
      ShellyConnectionFlowState.passwordRequired => Icons.lock_rounded,
      _ => Icons.bolt_rounded,
    };
  }

  String _friendlyName(DiscoveredShellyDevice device) {
    final name = device.name?.trim() ?? '';
    if (name.isEmpty ||
        RegExp(r'^[a-f0-9:-]{8,}$', caseSensitive: false).hasMatch(name)) {
      return device.model.toUpperCase().contains('S3PL')
          ? 'Shelly Plug S'
          : 'Shelly';
    }
    return name;
  }
}

/// Pulsating radar wave animation for the discovering state.
class _PulsingRadar extends StatefulWidget {
  const _PulsingRadar({required this.color});
  final Color color;

  @override
  State<_PulsingRadar> createState() => _PulsingRadarState();
}

class _PulsingRadarState extends State<_PulsingRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      width: 140,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = _controller.value;
          final p2 = (progress + 0.5) % 1.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 60 + progress * 76,
                height: 60 + progress * 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(
                    alpha: (1.0 - progress) * 0.18,
                  ),
                  border: Border.all(
                    color: widget.color.withValues(
                      alpha: (1.0 - progress) * 0.35,
                    ),
                    width: 1.5,
                  ),
                ),
              ),
              Container(
                width: 60 + p2 * 76,
                height: 60 + p2 * 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: (1.0 - p2) * 0.14),
                  border: Border.all(
                    color: widget.color.withValues(alpha: (1.0 - p2) * 0.25),
                    width: 1.2,
                  ),
                ),
              ),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.16),
                  border: Border.all(color: widget.color, width: 2),
                ),
                child: Icon(
                  Icons.wifi_tethering_rounded,
                  size: 34,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
