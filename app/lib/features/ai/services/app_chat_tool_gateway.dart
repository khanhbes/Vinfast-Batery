import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/models/smart_charger_binding.dart';
import '../../../data/models/smart_charger_capabilities.dart';
import '../../../data/models/smart_charging_session.dart';
import '../../../data/repositories/smart_charger_repository.dart';
import '../../../data/services/server_smart_charger_service.dart';
import '../../../data/services/charging_tflite_runner.dart';
import '../../../data/services/account_reminder_service.dart';
import '../../../data/services/shelly_connection_coordinator.dart';
import '../../../core/utils/battery_bot_faq.dart';
import 'local_chat_engine.dart';
import '../../achievements/models/achievement.dart';
import '../../achievements/services/achievement_signals.dart';
import '../../../data/services/smart_charger_service.dart';

class AppChatToolGateway implements ChatToolGateway {
  AppChatToolGateway({
    required this.selectedVehicle,
    required this.reminders,
    String? Function()? uidResolver,
    ServerSmartChargerRepository? serverRepository,
    ShellyConnectionCoordinator? connectionCoordinator,
  }) : _uidResolver = uidResolver ?? _firebaseUid,
       _injectedRepository = serverRepository,
       _connections =
           connectionCoordinator ?? ShellyConnectionCoordinator.shared;
  final VehicleModel? Function() selectedVehicle;
  final AccountReminderService reminders;
  final String? Function() _uidResolver;
  final ServerSmartChargerRepository? _injectedRepository;
  final ShellyConnectionCoordinator _connections;
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
    if (_injectedRepository != null) return _injectedRepository;
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
  static const _mutationTools = {
    'create_reminder',
    'edit_reminder',
    'cancel_reminder',
    'start_timed_charging',
    'stop_charging',
  };
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

  Future<T> _backendRead<T>(
    String owner,
    String vehicle,
    int generation,
    Future<T> Function() read,
  ) async {
    _guard(owner, vehicle, generation);
    try {
      final result = await read();
      _guard(owner, vehicle, generation);
      return result;
    } catch (_) {
      if (uid == owner && vehicleId == vehicle && generation == _generation) {
        _connections.markServerUnavailable(uid: owner, vehicleId: vehicle);
      }
      rethrow;
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
        final repo = _server;
        final binding = await _backendRead(
          owner,
          vehicle.vehicleId,
          generation,
          () => repo.binding(vehicleId: vehicle.vehicleId),
        );
        _guard(owner, vehicle.vehicleId, generation);
        if (binding == null) {
          return const LocalChatReply(
            'Xe này chưa có bộ sạc Shelly đã liên kết. Mở thiết lập để nhập mã kết nối.',
          );
        }
        final live = await _backendRead(
          owner,
          vehicle.vehicleId,
          generation,
          () => repo.live(vehicleId: vehicle.vehicleId),
        );
        _guard(owner, vehicle.vehicleId, generation);
        _connections.updateServerSnapshot(
          uid: owner,
          vehicleId: vehicle.vehicleId,
          binding: binding,
          status: live.status,
          capabilities: live.capabilities,
        );
        if (!live.status.online) {
          return const LocalChatReply(
            'Shelly tạm mất kết nối. Không thể xác nhận trạng thái relay.',
          );
        }
        if (!sameShellyDevice(live.status.deviceId, binding.deviceId)) {
          return const LocalChatReply(
            'Chưa xác minh được đúng Shelly đã liên kết. Hãy đọc lại trong Sạc pin.',
          );
        }
        final st = live.status;
        final timer = st.relay && (st.timerRemaining?.inSeconds ?? 0) > 0
            ? ' Hẹn giờ còn ${(st.timerRemaining!.inSeconds / 60).ceil()} phút.'
            : '';
        return LocalChatReply(
          'Shelly ${st.relay ? 'đang bật' : 'đã tắt'} theo lần đọc mới nhất từ máy chủ. '
          'Công suất ${st.powerW.toStringAsFixed(1)} W · Điện áp ${st.voltageV.toStringAsFixed(1)} V · '
          'Dòng ${st.currentA.toStringAsFixed(2)} A.$timer',
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
    if (!_mutationTools.contains(tool)) {
      return {'allowed': false, 'userMessage': 'Hành động không được hỗ trợ.'};
    }
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
    // Binding and live status are independent reads: fetch them together
    // (Task 122) instead of one round trip after the other.
    final bindingRead = _backendRead(
      owner,
      vehicle.vehicleId,
      generation,
      () => repo.binding(vehicleId: vehicle.vehicleId),
    );
    final liveRead = _backendRead(
      owner,
      vehicle.vehicleId,
      generation,
      () => repo.live(vehicleId: vehicle.vehicleId),
    );
    liveRead.ignore();
    final binding = await bindingRead;
    _guard(owner, vehicle.vehicleId, generation);
    if (binding == null ||
        binding.mode != SmartChargerConnectionMode.serverCloud) {
      return {
        'allowed': false,
        'userMessage':
            'Hãy kết nối Shelly qua máy chủ trước khi điều khiển trong chat. Mở Cài đặt → Sạc thông minh Shelly và nhập mã kết nối 6 ký tự do quản trị viên cấp.',
      };
    }
    final live = await liveRead;
    _guard(owner, vehicle.vehicleId, generation);
    _connections.updateServerSnapshot(
      uid: owner,
      vehicleId: vehicle.vehicleId,
      binding: binding,
      status: live.status,
    );
    if (!live.status.online ||
        !sameShellyDevice(live.status.deviceId, binding.deviceId)) {
      return {
        'allowed': false,
        'userMessage':
            'Chưa xác minh được đúng Shelly. Hãy mở Sạc pin để kiểm tra.',
      };
    }
    if (tool == 'stop_charging') {
      final session = live.session;
      if (session == null) {
        final caps =
            live.capabilities ??
            await _backendRead<SmartChargerCapabilities>(
              owner,
              vehicle.vehicleId,
              generation,
              () => repo.capabilities(vehicleId: vehicle.vehicleId),
            );
        _guard(owner, vehicle.vehicleId, generation);
        _connections.updateServerSnapshot(
          uid: owner,
          vehicleId: vehicle.vehicleId,
          binding: binding,
          status: live.status,
          capabilities: caps,
        );
        if (!live.status.relay || !caps.canManualOff) {
          return {
            'allowed': false,
            'userMessage': live.status.relay
                ? 'Máy chủ chưa cho phép dừng bộ sạc này. Mở Sạc pin để xử lý an toàn.'
                : 'Shelly đã tắt theo trạng thái vừa đọc.',
          };
        }
        // A second member sees hardware, never the first member's private log.
        return {
          'allowed': true,
          'title': 'Xác nhận tắt bộ sạc',
          'description': '${vehicle.displayName} · ${binding.displayName}',
          'safetyNote':
              'Ổ cắm đang bật. Thao tác này có thể dừng phiên đang dùng chung; chỉ báo đã tắt sau khi đọc lại OFF.',
          'deviceId': binding.deviceId,
          'bindingOnlyStop': true,
        };
      }
      if (!sameShellyDevice(session.deviceId, binding.deviceId)) {
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
    final caps =
        live.capabilities ??
        await _backendRead<SmartChargerCapabilities>(
          owner,
          vehicle.vehicleId,
          generation,
          () => repo.capabilities(vehicleId: vehicle.vehicleId),
        );
    _guard(owner, vehicle.vehicleId, generation);
    _connections.updateServerSnapshot(
      uid: owner,
      vehicleId: vehicle.vehicleId,
      binding: binding,
      status: live.status,
      capabilities: caps,
    );
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
          'Chỉ báo bật thành công sau khi đọc lại thấy ổ đã bật và hẹn giờ đang chạy. Không tự gửi lại lệnh bật khi mất phản hồi.',
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
    if (!_mutationTools.contains(tool)) {
      return _result(false, 'Hành động không được hỗ trợ.', 'unsupported');
    }
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
    // Task 123 (user-approved): no binding + /live round trip before the
    // command. The proposal was built from fresh reads seconds ago, and the
    // server re-checks everything itself before any relay change: expected
    // device, ownership, relay OFF, active session, staging lock, worker and
    // the live safety thresholds. A refusal before the command (409/403/404)
    // is reported plainly; anything after it stays "unknown", never retried.
    final deviceId = evidence['deviceId'] as String;
    final binding = _currentBinding(deviceId);
    // Snapshot before markUnknown() clears the shared view during the command.
    final cachedStatus = _connections.current.status;
    final cachedCapabilities = _connections.current.capabilities;
    void markUnknown() => _connections.markControlUnknown(
      uid: owner,
      vehicleId: vehicle.vehicleId,
      deviceId: deviceId,
    );
    void publish(bool relayOn, {Duration? timerRemaining}) {
      final status = cachedStatus;
      if (binding == null ||
          status == null ||
          !sameShellyDevice(status.deviceId, deviceId)) {
        // Nothing cached to update in place: show "checking" until the next
        // shared read instead of guessing a relay state.
        markUnknown();
        return;
      }
      _connections.updateServerSnapshot(
        uid: owner,
        vehicleId: vehicle.vehicleId,
        binding: binding,
        status: status.withVerifiedRelay(
          relayOn,
          timerRemaining: timerRemaining,
        ),
        capabilities: cachedCapabilities,
        controlResolved: true,
      );
    }

    if (tool == 'start_timed_charging') {
      markUnknown();
      final SmartChargingSession session;
      try {
        session = await repo.service.manualOn(
          Duration(seconds: evidence['durationSeconds'] as int),
          idempotencyKey: operationId,
          vehicleId: vehicle.vehicleId,
          currentSoc: (evidence['currentSoc'] as num).toDouble(),
          expectedDeviceId: deviceId,
        );
      } on SmartChargerException catch (error) {
        _guard(owner, vehicle.vehicleId, generation);
        final refused = _refusedBeforeCommand(error);
        if (refused == null) rethrow;
        return refused;
      }
      _guard(owner, vehicle.vehicleId, generation);
      // The server answers only after its own Shelly readback of relay ON +
      // armed timer on this device (it never retries ON).
      final ok =
          sameShellyDevice(session.deviceId, deviceId) &&
          session.vehicleId == vehicle.vehicleId &&
          session.state == ChargingSessionState.active &&
          session.relayVerified &&
          session.timerVerified;
      if (ok) {
        publish(
          true,
          timerRemaining: Duration(seconds: evidence['durationSeconds'] as int),
        );
        // Explore achievement: a confirmed, verified ON through BatteryBot.
        AchievementSignals.instance.emit(AchievementEvents.botCharge);
      } else {
        markUnknown();
      }
      return _result(
        ok,
        ok
            ? 'Đã xác minh ổ Shelly đang bật và hẹn giờ đang chạy.'
            : 'Chưa xác minh được ổ đã bật và hẹn giờ. Mở Sạc pin để đọc lại hoặc dừng sạc; không gửi lại lệnh bật.',
        ok ? 'verified' : 'unknown',
      );
    }
    if (tool == 'stop_charging') {
      markUnknown();
      final SmartChargingSession? stopped;
      try {
        stopped = evidence['bindingOnlyStop'] == true
            ? await repo.service.off(
                vehicleId: vehicle.vehicleId,
                expectedDeviceId: deviceId,
                operationId: operationId,
              )
            : await repo.service.stop(
                evidence['sessionId'] as String,
                expectedVersion: evidence['version'] as int,
                idempotencyKey: operationId,
              );
      } on SmartChargerException catch (error) {
        _guard(owner, vehicle.vehicleId, generation);
        if (error.statusCode == 404 && evidence['bindingOnlyStop'] != true) {
          // The session ended (usually the device timer) before the
          // confirmation: no OFF was needed. One read (rare path) restores
          // the shared view instead of leaving it "checking".
          try {
            final live = await _backendRead(
              owner,
              vehicle.vehicleId,
              generation,
              () => repo.live(vehicleId: vehicle.vehicleId),
            );
            _guard(owner, vehicle.vehicleId, generation);
            if (binding != null &&
                sameShellyDevice(live.status.deviceId, deviceId)) {
              _connections.updateServerSnapshot(
                uid: owner,
                vehicleId: vehicle.vehicleId,
                binding: binding,
                status: live.status,
                capabilities: live.capabilities ?? cachedCapabilities,
                controlResolved: true,
              );
            }
          } on SmartChargerException {
            // Shown as "checking" until the next shared read.
          }
          return _result(
            false,
            'Phiên sạc đã kết thúc trước khi bạn xác nhận (thường do Shelly tự ngắt theo hẹn giờ); không cần gửi lệnh dừng.',
            'expired',
          );
        }
        final refused = _refusedBeforeCommand(error);
        if (refused == null) rethrow;
        return refused;
      }
      _guard(owner, vehicle.vehicleId, generation);
      if (stopped?.state == ChargingSessionState.stopping &&
          stopped?.lastError == offPendingReadbackCode) {
        // OFF was accepted; Shelly Cloud has not reported it yet. The server
        // finishes the stop on readback; resending OFF is never needed.
        markUnknown();
        return _result(
          false,
          'Đã gửi lệnh tắt; đang chờ Shelly Cloud báo về. Không gửi lại lệnh — Sạc pin sẽ cập nhật khi có xác nhận.',
          'pending',
        );
      }
      final ok =
          stopped == null ||
          (stopped.state.isTerminal &&
              stopped.relayVerified &&
              sameShellyDevice(stopped.deviceId, deviceId));
      if (ok) {
        publish(false);
      } else {
        markUnknown();
      }
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

  /// The binding already shown for this account/vehicle, if it is the same
  /// device the proposal was built for.
  SmartChargerBinding? _currentBinding(String deviceId) {
    final binding = _connections.current.serverBinding;
    if (binding == null ||
        binding.mode != SmartChargerConnectionMode.serverCloud ||
        !sameShellyDevice(binding.deviceId, deviceId)) {
      return null;
    }
    return binding;
  }

  /// Server refusals raised before any relay command (binding changed,
  /// relay already on, staging lock, safety evidence, ...). Null = the
  /// outcome is unknown and must stay unknown.
  Map<String, dynamic>? _refusedBeforeCommand(SmartChargerException error) {
    final status = error.statusCode;
    if (status == null || error.commandMayHaveReachedDevice) return null;
    if (status != 403 && status != 404 && status != 409) return null;
    return _result(
      false,
      error.message.isNotEmpty
          ? error.message
          : 'Máy chủ chưa cho phép thao tác này.',
      status == 409 &&
              (error.code == 'bindingChanged' ||
                  error.code == 'versionConflict')
          ? 'expired'
          : 'blocked',
    );
  }
}
