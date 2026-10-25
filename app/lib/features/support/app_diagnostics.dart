import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/entitlement.dart';
import '../../data/models/shelly_connection_state.dart';
import '../../data/services/shelly_connection_coordinator.dart';

enum CheckStatus { ok, warn, fail, unknown }

/// What a check's button does (the screen maps it to a real action).
enum CheckFix {
  retry,
  signIn,
  chooseVehicle,
  openShellySetup,
  allowNotifications,
  allowCamera,
  allowBackground,
  openAppSettings,
}

class DiagnosticCheck {
  const DiagnosticCheck({
    required this.id,
    required this.title,
    required this.status,
    required this.detail,
    this.fix,
    this.fixLabel,
  });

  final String id;
  final String title;
  final CheckStatus status;
  final String detail;
  final CheckFix? fix;
  final String? fixLabel;
}

/// Everything a check needs, behind seams so tests need no plugins.
class DiagnosticsProbe {
  const DiagnosticsProbe();

  Future<String> appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } on Object {
      return AppConstants.appVersion;
    }
  }

  bool isAndroid() {
    try {
      return Platform.isAndroid;
    } on Object {
      return false;
    }
  }

  String platform() {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } on Object {
      return 'unknown';
    }
  }

  Future<bool> online() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result != ConnectivityResult.none;
    } on Object {
      return true;
    }
  }

  /// `GET /api/ready`: 200 = server and Firebase ready.
  Future<int?> serverReady() async {
    final uri = AppConstants.tryBuildApiUri('/api/ready');
    if (uri == null || !AppConstants.isApiConfigured) return null;
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      return response.statusCode;
    } on Object {
      return 0;
    }
  }

  bool signedIn() {
    try {
      return Firebase.apps.isNotEmpty &&
          FirebaseAuth.instance.currentUser != null;
    } on Object {
      return false;
    }
  }

  Future<PermissionStatus?> permission(Permission permission) async {
    try {
      return await permission.status;
    } on Object {
      return null;
    }
  }

  ShellyConnectionSnapshot shelly() =>
      ShellyConnectionCoordinator.shared.current;
}

class DiagnosticsReport {
  const DiagnosticsReport(this.checks, this.snapshot);
  final List<DiagnosticCheck> checks;

  /// Short, non-secret facts attached to a support ticket.
  final Map<String, Object?> snapshot;

  int get problems => checks.where((c) => c.status == CheckStatus.fail).length;
  int get warnings => checks.where((c) => c.status == CheckStatus.warn).length;
}

/// The app-wide self-check behind "Trợ giúp & khắc phục sự cố" (QA 135).
class AppDiagnostics {
  const AppDiagnostics({this.probe = const DiagnosticsProbe()});
  final DiagnosticsProbe probe;

  Future<DiagnosticsReport> run({
    required String vehicleId,
    required String? vehicleName,
    required Entitlement plan,
  }) async {
    final android = probe.isAndroid();
    final results = await Future.wait<Object?>([
      probe.appVersion(),
      probe.online(),
      probe.serverReady(),
      probe.permission(Permission.notification),
      probe.permission(Permission.camera),
      android
          ? probe.permission(Permission.ignoreBatteryOptimizations)
          : Future<PermissionStatus?>.value(),
    ]);
    final version = results[0]! as String;
    final online = results[1]! as bool;
    final ready = results[2] as int?;
    final notifications = results[3] as PermissionStatus?;
    final camera = results[4] as PermissionStatus?;
    final background = results[5] as PermissionStatus?;
    final signedIn = probe.signedIn();
    final shelly = probe.shelly();
    final checks = <DiagnosticCheck>[];

    checks.add(
      !online
          ? const DiagnosticCheck(
              id: 'network',
              title: 'Kết nối mạng',
              status: CheckStatus.fail,
              detail:
                  'Điện thoại đang không có mạng. Bật Wi-Fi hoặc dữ liệu di động.',
              fix: CheckFix.retry,
              fixLabel: 'Kiểm tra lại',
            )
          : ready == 200
          ? const DiagnosticCheck(
              id: 'network',
              title: 'Mạng & máy chủ Pinova',
              status: CheckStatus.ok,
              detail: 'Máy chủ đang hoạt động.',
            )
          : DiagnosticCheck(
              id: 'network',
              title: 'Máy chủ Pinova',
              status: ready == null ? CheckStatus.warn : CheckStatus.fail,
              detail: ready == null
                  ? 'Bản cài này chưa cấu hình địa chỉ máy chủ.'
                  : 'Chưa liên lạc được máy chủ (mã ${ready == 0 ? 'mạng' : ready}). '
                        'Thử lại sau ít phút; nếu vẫn lỗi hãy gửi cho hỗ trợ.',
              fix: CheckFix.retry,
              fixLabel: 'Thử lại',
            ),
    );
    checks.add(
      signedIn
          ? const DiagnosticCheck(
              id: 'account',
              title: 'Tài khoản',
              status: CheckStatus.ok,
              detail: 'Đã đăng nhập.',
            )
          : const DiagnosticCheck(
              id: 'account',
              title: 'Tài khoản',
              status: CheckStatus.fail,
              detail:
                  'Phiên đăng nhập đã hết. Đăng nhập lại để đồng bộ dữ liệu.',
              fix: CheckFix.signIn,
              fixLabel: 'Đăng nhập lại',
            ),
    );
    checks.add(
      vehicleId.isNotEmpty
          ? DiagnosticCheck(
              id: 'vehicle',
              title: 'Xe đang chọn',
              status: CheckStatus.ok,
              detail: vehicleName ?? 'Đã chọn xe.',
            )
          : const DiagnosticCheck(
              id: 'vehicle',
              title: 'Xe đang chọn',
              status: CheckStatus.warn,
              detail: 'Chưa chọn xe: % pin, sạc và lịch sử cần một xe.',
              fix: CheckFix.chooseVehicle,
              fixLabel: 'Chọn xe',
            ),
    );
    checks.add(_shellyCheck(shelly));
    checks.add(
      _permissionCheck(
        id: 'notifications',
        title: 'Thông báo',
        status: notifications,
        okText: 'Được phép: app báo khi sạc xong hoặc khi ngắt an toàn.',
        badText:
            'Đang tắt: bạn sẽ không nhận được báo sạc xong, ngắt an toàn hay trả lời hỗ trợ.',
        fix: CheckFix.allowNotifications,
      ),
    );
    checks.add(
      _permissionCheck(
        id: 'camera',
        title: 'Camera (quét đồng hồ)',
        status: camera,
        okText: 'Được phép.',
        badText: 'Chưa cho phép: không quét được % pin và ODO trên đồng hồ xe.',
        fix: CheckFix.allowCamera,
        warnOnly: true,
      ),
    );
    if (android) {
      checks.add(
        _permissionCheck(
          id: 'background',
          title: 'Chạy nền khi đang sạc',
          status: background,
          okText: 'Không bị tối ưu pin: theo dõi phiên sạc ổn định.',
          badText:
              'Android có thể dừng app khi tắt màn hình; theo dõi sạc và thông báo có thể trễ.',
          fix: CheckFix.allowBackground,
          warnOnly: true,
        ),
      );
    }
    checks.add(
      DiagnosticCheck(
        id: 'version',
        title: 'Phiên bản',
        status: CheckStatus.ok,
        detail: 'Pinova $version · gói ${plan.tier.label}',
      ),
    );

    return DiagnosticsReport(checks, {
      'appVersion': version,
      'platform': probe.platform(),
      'online': online,
      'serverReady': ready,
      'signedIn': signedIn,
      'vehicleSelected': vehicleId.isNotEmpty,
      'vehicleName': vehicleName,
      'plan': plan.tier.id,
      'planStatus': plan.status,
      'shellyLinked': shelly.isLinked,
      'shellyState': shelly.state.name,
      'shellyOnline': shelly.status?.online,
      'shellyRelay': shelly.status?.relay,
      'shellyFromCache': shelly.fromCache,
      'notifications': notifications?.name,
      'camera': camera?.name,
      'background': background?.name,
      'checksFailed': [
        for (final c in checks)
          if (c.status == CheckStatus.fail) c.id,
      ],
    });
  }

  static DiagnosticCheck _shellyCheck(ShellyConnectionSnapshot shelly) {
    if (!shelly.isLinked) {
      return const DiagnosticCheck(
        id: 'shelly',
        title: 'Ổ sạc Shelly',
        status: CheckStatus.warn,
        detail: 'Chưa liên kết ổ sạc. Sạc thông minh cần Shelly Plug S Gen3.',
        fix: CheckFix.openShellySetup,
        fixLabel: 'Kết nối',
      );
    }
    if (shelly.codeRefreshRequired) {
      return const DiagnosticCheck(
        id: 'shelly',
        title: 'Ổ sạc Shelly',
        status: CheckStatus.fail,
        detail: 'Cần nhập lại mã kết nối của quản trị viên.',
        fix: CheckFix.openShellySetup,
        fixLabel: 'Nhập mã',
      );
    }
    final online = shelly.status?.online;
    if (online == false) {
      return const DiagnosticCheck(
        id: 'shelly',
        title: 'Ổ sạc Shelly',
        status: CheckStatus.fail,
        detail:
            'Ổ đang mất kết nối Shelly Cloud. Kiểm tra ổ có điện và Wi-Fi nhà, '
            'rồi đợi 1–2 phút.',
        fix: CheckFix.openShellySetup,
        fixLabel: 'Mở thiết lập',
      );
    }
    if (online == null ||
        shelly.fromCache ||
        shelly.state != ShellyConnectionFlowState.connected) {
      return const DiagnosticCheck(
        id: 'shelly',
        title: 'Ổ sạc Shelly',
        status: CheckStatus.unknown,
        detail:
            'Đã liên kết; chưa đọc được trạng thái mới. Mở tab Sạc pin để kiểm tra.',
      );
    }
    return DiagnosticCheck(
      id: 'shelly',
      title: 'Ổ sạc Shelly',
      status: CheckStatus.ok,
      detail: shelly.status?.relay == true
          ? 'Trực tuyến · đang bật.'
          : 'Trực tuyến · đang tắt.',
    );
  }

  static DiagnosticCheck _permissionCheck({
    required String id,
    required String title,
    required PermissionStatus? status,
    required String okText,
    required String badText,
    required CheckFix fix,
    bool warnOnly = false,
  }) {
    if (status == null) {
      return DiagnosticCheck(
        id: id,
        title: title,
        status: CheckStatus.unknown,
        detail: 'Không đọc được quyền này trên máy.',
      );
    }
    if (status.isGranted || status.isLimited) {
      return DiagnosticCheck(
        id: id,
        title: title,
        status: CheckStatus.ok,
        detail: okText,
      );
    }
    final blocked = status.isPermanentlyDenied || status.isRestricted;
    return DiagnosticCheck(
      id: id,
      title: title,
      status: warnOnly ? CheckStatus.warn : CheckStatus.fail,
      detail: badText,
      fix: blocked ? CheckFix.openAppSettings : fix,
      fixLabel: blocked ? 'Mở cài đặt' : 'Cho phép',
    );
  }
}
