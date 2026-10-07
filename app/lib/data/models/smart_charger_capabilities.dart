class SmartChargerCapabilities {
  const SmartChargerCapabilities({
    required this.canReadStatus,
    required this.canManualOn,
    required this.canManualOff,
    required this.supportsDeviceTimer,
    required this.canReadPower,
    required this.canConfigureSafeBoot,
    required this.cloudAvailable,
    required this.lanAvailable,
    required this.readyForControl,
    this.safeBootVerified = false,
    this.noLoadTestVerified = false,
    this.provider,
    this.controlBlockedCode,
  });

  final bool canReadStatus;
  final bool canManualOn;
  final bool canManualOff;
  final bool supportsDeviceTimer;
  final bool canReadPower;
  final bool canConfigureSafeBoot;
  final bool cloudAvailable;
  final bool lanAvailable;
  final bool safeBootVerified;
  final bool noLoadTestVerified;
  final bool readyForControl;
  final String? provider;
  final String? controlBlockedCode;

  String? get controlBlockedMessage {
    if (controlBlockedCode == 'relayUnverified') {
      return 'Chưa xác minh được trạng thái Shelly. Hãy đọc lại hoặc dừng sạc trước khi bật phiên mới.';
    }
    if (controlBlockedCode == 'activeSessionConflict') {
      return 'Shelly đang có phiên sạc. Hãy xem trạng thái hoặc dừng phiên hiện tại.';
    }
    if (controlBlockedCode == 'deviceCoordinationUnavailable') {
      return 'Chưa kiểm tra được quyền điều khiển. Hãy thử lại; chưa thể bật sạc.';
    }
    if (controlBlockedCode == 'STAGING_HARDWARE_DISABLED') {
      return 'Máy chủ thử nghiệm chưa cho phép bật sạc. Bạn vẫn có thể xem trạng thái và dừng sạc.';
    }
    if (readyForControl) return null;
    if (!canReadStatus) {
      return 'Chưa đọc được trạng thái Shelly. Hãy kiểm tra kết nối và thử lại.';
    }
    if (!canReadPower) {
      return 'Cần xác minh thiết bị và số đo điện trước khi bật sạc.';
    }
    if (!safeBootVerified) return 'Cần xác minh cấu hình an toàn của Shelly.';
    if (!noLoadTestVerified) {
      return 'Cần hoàn tất kiểm tra không tải trong thiết lập Shelly.';
    }
    if (!supportsDeviceTimer) {
      return 'Chưa xác minh được bộ hẹn giờ an toàn của Shelly.';
    }
    return 'Chưa đủ điều kiện bật sạc. Hãy mở thiết lập Shelly để kiểm tra.';
  }

  bool get limited => readyForControl && !(cloudAvailable && lanAvailable);

  factory SmartChargerCapabilities.fromJson(Map<String, dynamic> json) =>
      SmartChargerCapabilities(
        canReadStatus: json['canReadStatus'] == true,
        canManualOn: json['canManualOn'] == true,
        canManualOff: json['canManualOff'] == true,
        supportsDeviceTimer: json['supportsDeviceTimer'] == true,
        canReadPower: json['canReadPower'] == true,
        canConfigureSafeBoot: json['canConfigureSafeBoot'] == true,
        cloudAvailable: json['cloudAvailable'] == true,
        lanAvailable: json['lanAvailable'] == true,
        safeBootVerified: json['safeBootVerified'] == true,
        noLoadTestVerified: json['noLoadTestVerified'] == true,
        readyForControl: json['readyForControl'] == true,
        provider: json['provider']?.toString(),
        controlBlockedCode: json['controlBlockedCode']?.toString(),
      );

  static const unavailable = SmartChargerCapabilities(
    canReadStatus: false,
    canManualOn: false,
    canManualOff: false,
    supportsDeviceTimer: false,
    canReadPower: false,
    canConfigureSafeBoot: false,
    cloudAvailable: false,
    lanAvailable: false,
    readyForControl: false,
  );
}
