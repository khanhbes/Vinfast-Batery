import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/models/smart_charger_binding.dart';
import '../../../data/repositories/smart_charger_repository.dart';
import '../../../data/services/server_smart_charger_service.dart';
import '../../../data/services/charging_tflite_runner.dart';
import '../../../data/services/account_reminder_service.dart';
import '../../../core/utils/battery_bot_faq.dart';
import 'local_chat_engine.dart';

class AppChatToolGateway implements ChatToolGateway {
  AppChatToolGateway({
    required this.selectedVehicle,
    required this.reminders,
    String? Function()? uidResolver,
  }) : _uidResolver = uidResolver ?? _firebaseUid;
  final VehicleModel? Function() selectedVehicle;
  final AccountReminderService reminders;
  final String? Function() _uidResolver;
  static String? _firebaseUid() =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
  @override
  String? get uid => _uidResolver();
  VehicleModel? get _vehicle {
    final vehicle = selectedVehicle();
    return vehicle?.ownerUid == uid && uid != null ? vehicle : null;
  }

  @override
  String? get vehicleId => _vehicle?.vehicleId;
  ServerSmartChargerService? _ownedService;
  ServerSmartChargerRepository? _repository;
  String? _repositoryUid, _repositoryVehicle;
  ServerSmartChargerRepository get _server {
    final generation = _generation, owner = uid, vehicle = vehicleId;
    if (_repository != null &&
        owner == _repositoryUid &&
        vehicle == _repositoryVehicle) {
      return _repository!;
    }
    _ownedService?.close();
    _repositoryUid = owner;
    _repositoryVehicle = vehicle;
    _ownedService = ServerSmartChargerService(
      requestValid: () =>
          generation == _generation && owner == uid && vehicle == vehicleId,
    );
    return _repository = ServerSmartChargerRepository(_ownedService!);
  }

  int _generation = 0;
  @override
  void invalidate() {
    _generation++;
    _ownedService?.close();
    _ownedService = null;
    _repository = null;
    _repositoryUid = null;
    _repositoryVehicle = null;
  }

  void _guard(String owner, String vehicle, int generation) {
    if (uid != owner || vehicleId != vehicle || generation != _generation) {
      throw StateError('accountChanged');
    }
  }

  /// Reject decimals, negative values and multi-part durations instead of guessing.
  static int? parseDuration(String question) {
    if (RegExp(r'[-+]|\d[.,]\d').hasMatch(question)) return null;
    final matches = RegExp(
      r'\b(\d{1,3})\s*(phut|gio)\b',
    ).allMatches(BatteryBotFaq.normalize(question)).toList();
    if (matches.length != 1) return null;
    final match = matches.single;
    final seconds = int.parse(match[1]!) * (match[2] == 'gio' ? 3600 : 60);
    return seconds >= 60 && seconds <= 36000 ? seconds : null;
  }

  static Map<String, dynamic> _result(
    bool ok,
    String message, [
    String status = 'verified',
  ]) => {
    'success': ok,
    'status': status,
    'data': {'success': ok, 'message': message},
    'message': message,
  };

  @override
  Future<LocalChatReply> read(String tool, String question) async {
    final generation = _generation;
    final owner = uid!;
    final vehicle = _vehicle!;
    switch (tool) {
      case 'battery_status':
        return LocalChatReply(
          vehicle.hasBatteryData
              ? 'Pin ${vehicle.displayName}: ${vehicle.currentBattery}%. Dữ liệu hồ sơ; chưa xác minh đo trực tiếp hoặc lần cập nhật.'
              : 'Chưa có dữ liệu pin cho xe này. Hãy cập nhật mức pin trong app.',
        );
      case 'predict_range':
        return const LocalChatReply(
          'Chưa có dự đoán quãng đường đã được kiểm chứng trên điện thoại. Mình chưa thể đưa ra số km đáng tin cậy.',
        );
      case 'predict_charging':
        final matches = RegExp(r'(\d{1,3})\s*%').allMatches(question).toList();
        if (!vehicle.hasBatteryData || matches.isEmpty) {
          return const LocalChatReply(
            'Bạn muốn sạc từ mức pin nào đến bao nhiêu phần trăm? Ví dụ: sạc từ 20% đến 80%.',
          );
        }
        final start = matches.length >= 2
            ? double.parse(matches.first[1]!)
            : vehicle.currentBattery.toDouble();
        final target = double.parse(matches.last[1]!);
        if (start < 0 || target > 100 || target <= start) {
          return const LocalChatReply(
            'Mức pin đích phải lớn hơn mức pin đầu và không quá 100%.',
          );
        }
        final runner = ChargingTfliteRunner();
        final seconds = await runner.predictDurationSeconds(
          startSoc: start,
          targetSoc: target,
        );
        _guard(owner, vehicle.vehicleId, generation);
        if (seconds == null || seconds <= 0) {
          return const LocalChatReply(
            'Chưa có dự đoán thời gian sạc đã được kiểm chứng. Bạn có thể chọn thời lượng ở Sạc hẹn giờ; điện năng và chi phí còn thiếu dữ liệu.',
          );
        }
        return LocalChatReply(
          'Ước tính khoảng ${(seconds / 60).ceil()} phút từ ${start.round()}% đến ${target.round()}%. Không phải số đo BMS; điện năng và chi phí chưa đủ dữ liệu.',
          card: {
            'cardType': 'local_prediction',
            'title': 'Thời gian sạc ước tính',
            'data': {
              'durationSeconds': seconds,
              'source': 'model local',
              'modelVersion': runner.getLocalVersion(),
              'updatedAt': DateTime.now().toIso8601String(),
            },
          },
        );
      case 'charger_status':
        final live = await _server.live(vehicleId: vehicle.vehicleId);
        _guard(owner, vehicle.vehicleId, generation);
        if (!live.status.online) {
          return const LocalChatReply(
            'Shelly tạm mất kết nối. Không thể xác nhận trạng thái relay.',
          );
        }
        return LocalChatReply(
          'Shelly ${live.status.relay ? 'đang bật' : 'đã tắt'} theo readback máy chủ vừa đọc. Công suất ${live.status.powerW.toStringAsFixed(1)} W.',
        );
      case 'charging_history':
        final page = await _server.getHistoryPage(
          vehicleId: vehicle.vehicleId,
          limit: 5,
        );
        _guard(owner, vehicle.vehicleId, generation);
        return LocalChatReply(
          'Đã đọc ${page.items.length} phiên gần nhất. Mở Lịch sử để xem điện năng và chi phí từng phiên.',
        );
      case 'reminders':
        final all = await reminders.list(
          vehicle.vehicleId,
          includeCancelled: true,
        );
        final items = all
            .where((e) => !e.cancelled || e.pendingSync || e.syncConflict)
            .toList();
        _guard(owner, vehicle.vehicleId, generation);
        final summary = items
            .map(
              (e) =>
                  '${e.title}: ${e.dueDate.day}/${e.dueDate.month}/${e.dueDate.year}${e.cancelled ? ' · Yêu cầu hủy' : ''}${e.syncConflict
                      ? ' · Cần kiểm tra xung đột đồng bộ'
                      : e.pendingSync
                      ? ' · Đang chờ đồng bộ'
                      : ''}',
            )
            .join('\n');
        return LocalChatReply(
          items.isEmpty
              ? (reminders.remoteVerified
                    ? 'Chưa có lịch nhắc cho xe này.'
                    : 'Chưa có lịch lưu trên điện thoại. Chưa xác minh được lịch đồng bộ; hãy kiểm tra kết nối.')
              : '$summary\nĐể đổi ngày hoặc hủy, ghi rõ loại lịch và ngày hiện tại. Mình sẽ hỏi xác nhận trước.',
        );
      default:
        return const LocalChatReply(AppKnowledgeRepository.outsideScope);
    }
  }

  @override
  Future<Map<String, dynamic>> prepare(String tool, String question) async {
    final generation = _generation;
    final owner = uid!;
    final vehicle = _vehicle!;
    if (tool == 'edit_reminder' || tool == 'cancel_reminder') {
      final items = await reminders.list(vehicle.vehicleId);
      _guard(owner, vehicle.vehicleId, generation);
      final cancel = tool == 'cancel_reminder';
      final selection = ReminderChatSelection.parse(
        question,
        items,
        cancel: cancel,
      );
      if (selection == null) {
        return {
          'allowed': false,
          'userMessage': cancel
              ? 'Hãy ghi loại lịch và ngày dd/mm/yyyy cần hủy. Nếu có nhiều lịch cùng ngày, mình chưa thể tự chọn.'
              : 'Hãy ghi ngày cũ và ngày mới. Ví dụ: đổi lịch bảo dưỡng ngày 20/11/2026 sang 25/11/2026. Mình chỉ đổi khi xác định đúng một lịch.',
        };
      }
      final item = selection.item;
      if (item.pendingSync || item.syncConflict) {
        return {
          'allowed': false,
          'userMessage':
              'Lịch này chưa đồng bộ xong hoặc có xung đột. Hãy chờ đồng bộ trước khi thay đổi tiếp.',
        };
      }
      String date(DateTime value) =>
          '${value.day}/${value.month}/${value.year}';
      return {
        'allowed': true,
        'title': cancel ? 'Xác nhận hủy lịch nhắc' : 'Xác nhận đổi ngày nhắc',
        'description':
            '${vehicle.displayName}\n${item.title}\nNgày hiện tại: ${date(item.dueDate)}${cancel ? '\nHủy các thông báo của lịch này.' : '\nNgày mới: ${date(selection.newDate!)}\nNhắc trước 7 ngày và 1 ngày lúc 09:00 (giờ Việt Nam).'}',
        'reminderId': item.id,
        'revision': item.revision,
        'newDate': selection.newDate?.toIso8601String(),
      };
    }
    if (tool == 'create_reminder') {
      final parsed = AccountReminder.parse(question, owner, vehicle.vehicleId);
      if (parsed == null) {
        return {
          'allowed': false,
          'userMessage':
              'Bạn hãy ghi nội dung và ngày cụ thể theo dd/mm/yyyy. Ví dụ: nhắc bảo dưỡng phanh ngày 20/11/2026.',
        };
      }
      return {
        'allowed': true,
        'title': 'Xác nhận lịch nhắc',
        'description':
            '${vehicle.displayName}\n${parsed.title}\nNgày ${parsed.dueDate.day}/${parsed.dueDate.month}/${parsed.dueDate.year}\nNhắc trước 7 ngày và 1 ngày lúc 09:00 (giờ Việt Nam).',
        if (parsed.kind == 'warranty')
          'safetyNote':
              'Thông tin bảo hành do bạn cung cấp, không phải xác nhận quyền lợi của hãng.',
        'reminder': parsed.toJson(),
      };
    }
    final repo = _server;
    final binding = await repo.binding(vehicleId: vehicle.vehicleId);
    _guard(owner, vehicle.vehicleId, generation);
    if (binding == null ||
        binding.mode != SmartChargerConnectionMode.serverCloud) {
      return {
        'allowed': false,
        'userMessage':
            'Hãy kết nối Shelly qua máy chủ trước khi điều khiển trong chat.',
      };
    }
    final live = await repo.live(vehicleId: vehicle.vehicleId);
    _guard(owner, vehicle.vehicleId, generation);
    if (!live.status.online || live.status.deviceId != binding.deviceId) {
      return {
        'allowed': false,
        'userMessage':
            'Chưa xác minh được đúng Shelly. Hãy mở Sạc pin để kiểm tra.',
      };
    }
    if (tool == 'stop_charging') {
      final session = live.session;
      if (session == null || session.deviceId != binding.deviceId) {
        return {
          'allowed': false,
          'userMessage':
              'Chưa có phiên sạc đã xác minh để dừng trong chat. Hãy mở Sạc pin để tắt khẩn cấp hoặc đọc lại trạng thái.',
        };
      }
      return {
        'allowed': true,
        'title': 'Xác nhận dừng sạc',
        'description': '${vehicle.displayName} · ${binding.displayName}',
        'deviceId': binding.deviceId,
        'sessionId': session.sessionId,
        'version': session.version,
      };
    }
    final duration = parseDuration(question);
    if (duration == null) {
      return {
        'allowed': false,
        'userMessage':
            'Bạn muốn bật sạc trong bao nhiêu phút? Ví dụ: bật sạc 30 phút.',
      };
    }
    final seconds = duration;
    if (seconds < 60 || seconds > 36000 || !vehicle.hasBatteryData) {
      return {
        'allowed': false,
        'userMessage':
            'Chọn thời lượng từ 1 phút đến 10 giờ và cập nhật mức pin trước khi bật sạc.',
      };
    }
    final caps = await repo.capabilities(vehicleId: vehicle.vehicleId);
    _guard(owner, vehicle.vehicleId, generation);
    if (!caps.readyForControl ||
        !caps.canManualOn ||
        !caps.supportsDeviceTimer ||
        live.status.relay ||
        live.session != null) {
      return {
        'allowed': false,
        'userMessage':
            caps.controlBlockedMessage ??
            'Shelly đang có phiên hoặc chưa đủ điều kiện bật sạc.',
      };
    }
    return {
      'allowed': true,
      'title': 'Xác nhận bật sạc theo thời gian',
      'description': '${vehicle.displayName} · ${binding.displayName}',
      'estimatedTime': '${seconds ~/ 60} phút',
      'safetyNote':
          'Chỉ báo bật thành công sau readback ON và timer. Không tự gửi lại ON khi mất phản hồi.',
      'deviceId': binding.deviceId,
      'durationSeconds': seconds,
      'currentSoc': vehicle.currentBattery,
    };
  }

  @override
  Future<Map<String, dynamic>> execute(
    String tool,
    Map<String, dynamic> evidence,
    String operationId,
  ) async {
    final generation = _generation;
    final owner = uid!;
    final vehicle = _vehicle!;
    if (tool == 'edit_reminder' || tool == 'cancel_reminder') {
      try {
        final saved = await reminders.revise(
          vehicleId: vehicle.vehicleId,
          reminderId: evidence['reminderId'] as String,
          expectedRevision: evidence['revision'] as int,
          operationId: operationId,
          cancel: tool == 'cancel_reminder',
          dueDate: evidence['newDate'] == null
              ? null
              : DateTime.parse(evidence['newDate'] as String),
        );
        _guard(owner, vehicle.vehicleId, generation);
        if (saved.syncConflict) {
          return _result(
            false,
            'Lịch đã thay đổi trên thiết bị khác. Thay đổi của bạn được giữ trên máy để kiểm tra, chưa xác nhận đồng bộ.',
            'conflict',
          );
        }
        return _result(
          true,
          '${saved.cancelled ? 'Đã hủy lịch trên điện thoại' : 'Đã đổi ngày nhắc'}${saved.pendingSync ? ' · Đang chờ đồng bộ sang thiết bị khác' : ''}.${!saved.cancelled && !saved.notificationsEnabled ? ' Chưa bật nhắc trên điện thoại.' : ''}',
        );
      } on ReminderConflictException {
        return _result(
          false,
          'Lịch đã thay đổi hoặc đang chờ đồng bộ. Hãy xem lịch và tạo yêu cầu mới.',
          'expired',
        );
      }
    }
    if (tool == 'create_reminder') {
      final reminder = AccountReminder.fromJson(
        Map<String, dynamic>.from(evidence['reminder'] as Map),
      );
      if (reminder.uid != owner || reminder.vehicleId != vehicle.vehicleId) {
        throw StateError('accountChanged');
      }
      final saved = await reminders.save(reminder.copyWithId(operationId));
      _guard(owner, vehicle.vehicleId, generation);
      if (saved.syncConflict) {
        return _result(
          false,
          'Lịch bị xung đột đồng bộ. Thông tin được giữ trên điện thoại để kiểm tra.',
          'conflict',
        );
      }
      return _result(
        true,
        'Đã lưu lịch nhắc${saved.pendingSync ? ' · Đang chờ đồng bộ' : ''}. ${saved.notificationsEnabled ? '' : 'Chưa bật nhắc trên điện thoại; bật quyền thông báo trong Cài đặt.'}',
      );
    }
    final repo = _server;
    final binding = await repo.binding(vehicleId: vehicle.vehicleId);
    _guard(owner, vehicle.vehicleId, generation);
    if (binding?.deviceId != evidence['deviceId'] ||
        binding?.mode != SmartChargerConnectionMode.serverCloud) {
      return _result(
        false,
        'Liên kết đã thay đổi. Hãy tạo yêu cầu mới.',
        'expired',
      );
    }
    final live = await repo.live(vehicleId: vehicle.vehicleId);
    _guard(owner, vehicle.vehicleId, generation);
    if (!live.status.online || live.status.deviceId != evidence['deviceId']) {
      return _result(
        false,
        'Chưa xác minh được thiết bị. Hãy đọc lại trong Sạc pin.',
        'unknown',
      );
    }
    if (tool == 'start_timed_charging') {
      final caps = await repo.capabilities(vehicleId: vehicle.vehicleId);
      _guard(owner, vehicle.vehicleId, generation);
      if (!caps.readyForControl ||
          !caps.canManualOn ||
          !caps.supportsDeviceTimer ||
          live.status.relay ||
          live.session != null) {
        return _result(
          false,
          caps.controlBlockedMessage ?? 'Thiết bị đang được sử dụng.',
          'blocked',
        );
      }
      final session = await repo.manualOn(
        Duration(seconds: evidence['durationSeconds'] as int),
        operationId,
        vehicleId: vehicle.vehicleId,
        currentSoc: (evidence['currentSoc'] as num).toDouble(),
      );
      _guard(owner, vehicle.vehicleId, generation);
      final readback = await repo.live(vehicleId: vehicle.vehicleId);
      _guard(owner, vehicle.vehicleId, generation);
      final ok =
          readback.status.deviceId == evidence['deviceId'] &&
          readback.status.online &&
          readback.status.relay &&
          (readback.status.timerRemaining?.inSeconds ?? 0) > 0 &&
          readback.session?.sessionId == session.sessionId &&
          session.relayVerified;
      return _result(
        ok,
        ok
            ? 'Đã xác minh Shelly bật và timer đang hoạt động.'
            : 'Chưa xác minh được ON/timer. Mở Sạc pin để đọc lại hoặc dừng sạc; không gửi lại ON.',
        ok ? 'verified' : 'unknown',
      );
    }
    if (tool == 'stop_charging') {
      if (live.session?.sessionId != evidence['sessionId'] ||
          live.session?.deviceId != evidence['deviceId'] ||
          live.session?.version != evidence['version']) {
        return _result(
          false,
          'Phiên đã thay đổi. Hãy đọc lại và xác nhận yêu cầu mới.',
          'expired',
        );
      }
      final stopped = await repo.service.stop(
        evidence['sessionId'] as String,
        expectedVersion: evidence['version'] as int,
        idempotencyKey: operationId,
      );
      _guard(owner, vehicle.vehicleId, generation);
      final readback = await repo.live(vehicleId: vehicle.vehicleId);
      _guard(owner, vehicle.vehicleId, generation);
      final ok =
          (stopped == null || stopped.relayVerified) &&
          readback.status.online &&
          !readback.status.relay &&
          readback.status.deviceId == evidence['deviceId'];
      return _result(
        ok,
        ok
            ? 'Đã đọc lại và xác minh Shelly OFF.'
            : 'Chưa xác minh được OFF. Mở Sạc pin để xử lý an toàn.',
        ok ? 'verified' : 'unknown',
      );
    }
    return _result(false, 'Hành động không được hỗ trợ.', 'unsupported');
  }
}
