import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../core/utils/battery_bot_faq.dart';
import '../models/function_call_action.dart';
import 'assistant_api.dart';
import 'local_chat_engine.dart';

/// Reversal of a one-tap change ("hoàn tác").
class AssistantUndo {
  const AssistantUndo(this.label, this.run);
  final String label;
  final Future<void> Function() run;
}

/// What BatteryBot v2 may do inside the app. Implemented by the shell with
/// the same repositories/providers the screens use (Task 124).
abstract interface class AssistantActionHost {
  /// App context for the prompt: selected vehicle, vehicle list, screen,
  /// tariff, Shelly link, on-device usage summary. Never credentials.
  Map<String, dynamic> context();

  /// Opens a screen immediately (navigation needs no confirmation).
  Future<bool> navigate(String screen, {String? sessionId});

  /// Task 126: opens a screen pre-filled for the user to finish, never
  /// energizing anything: `plan_trip` (Lộ trình) and
  /// `prepare_target_charging` (Charge tab with the target set; the user
  /// still slides to start).
  Future<bool> prepare(String name, Map<String, dynamic> args);

  /// Applies a confirmed data/setting change. Returns how to undo it, or
  /// throws [AssistantActionError] with a user-facing reason.
  Future<AssistantUndo?> apply(String name, Map<String, dynamic> args);
}

class AssistantActionError implements Exception {
  const AssistantActionError(this.message);
  final String message;
  @override
  String toString() => message;
}

class _Pending {
  _Pending(this.name, this.args, this.uid);
  final String name;
  final Map<String, dynamic> args;
  final String? uid;
  bool consumed = false;
}

/// BatteryBot v2: Gemini through the API for understanding and answers, the
/// existing on-device engine for anything that touches the charger or the
/// reminder store (its verified gateway, cards and slide-to-confirm stay the
/// only path), and as the basic mode when the server is unavailable.
class HybridAssistantEngine implements LocalChatEngine {
  HybridAssistantEngine({
    required this.api,
    required this.local,
    required this.host,
    required this.uidResolver,
  });

  final AssistantApi api;
  final LocalChatEngine local;
  final AssistantActionHost host;
  final String? Function() uidResolver;

  final List<Map<String, String>> _history = [];
  final Map<String, _Pending> _pending = {};
  AssistantUndo? _lastUndo;
  int _generation = 0;
  bool _disposed = false;

  /// Notified when the server changed what BatteryBot remembers.
  void Function()? onMemoryChanged;

  static const _riskyLocal = {
    'start_timed_charging',
    'stop_charging',
    'create_reminder',
    'edit_reminder',
    'cancel_reminder',
  };
  static const _prepare = {
    'plan_trip',
    'prepare_target_charging',
    // QA 135: these open a screen pre-filled; the owner confirms there.
    'open_premium',
    'contact_support',
    'update_charge_target',
    'set_night_plan',
  };
  static const _oneTap = {
    'update_battery_level',
    'update_odometer',
    'select_vehicle',
    'set_target_soc',
    'set_electricity_price',
    'set_app_setting',
    'start_trial',
    'apply_promo_code',
  };

  void _remember(String role, String text) {
    if (text.trim().isEmpty) return;
    _history.add({'role': role, 'text': text});
    while (_history.length > 10) {
      _history.removeAt(0);
    }
  }

  @override
  Future<LocalChatReply> reply(String message) async {
    if (_disposed) return const LocalChatReply('Hãy mở lại trợ lý.');
    final normalized = BatteryBotFaq.normalize(message);
    if (const {'hoan tac', 'undo', 'quay lai nhu cu'}.contains(normalized)) {
      return _undo();
    }
    final generation = _generation;
    final uid = uidResolver();
    final AssistantTurn turn;
    try {
      turn = await api.chat(
        message: message,
        history: List.of(_history),
        context: host.context(),
      );
    } on AssistantUnavailable catch (error) {
      return _basic(message, error);
    }
    if (_disposed || generation != _generation || uid != uidResolver()) {
      return const LocalChatReply('Tài khoản đã thay đổi. Hãy hỏi lại.');
    }
    if (turn.memoryChanged) onMemoryChanged?.call();
    _remember('user', message);
    _remember('assistant', turn.reply);
    if (turn.actions.isEmpty) {
      return LocalChatReply(turn.reply, card: turn.card);
    }
    final acted = await _act(turn.actions.first, turn.reply, uid);
    return turn.card == null || acted.card != null
        ? acted
        : LocalChatReply(acted.text, card: turn.card, action: acted.action);
  }

  Future<LocalChatReply> _basic(
    String message,
    AssistantUnavailable error,
  ) async {
    final reply = await local.reply(message);
    final note = error.quota
        ? 'Bạn đã dùng hết lượt AI hôm nay, mình trả lời ở chế độ cơ bản. '
              'Gói Pro/Ultra có 30/100 tin mỗi ngày (Cài đặt → Pinova Premium).\n\n'
        : 'Chế độ cơ bản (chưa kết nối được trợ lý AI).\n\n';
    return LocalChatReply(
      '$note${reply.text}',
      card: reply.card,
      action: reply.action,
    );
  }

  Future<LocalChatReply> _act(
    AssistantAction action,
    String reply,
    String? uid,
  ) async {
    final name = action.name;
    final args = action.args;
    if (name == 'navigate') {
      final screen = args['screen']?.toString() ?? '';
      final opened = await host.navigate(
        screen,
        sessionId: args['session_id']?.toString(),
      );
      return LocalChatReply(
        opened
            ? reply
            : 'Mình chưa mở được màn hình đó. Bạn tìm trong Cài đặt nhé.',
      );
    }
    if (_prepare.contains(name)) {
      final opened = await host.prepare(name, args);
      return LocalChatReply(
        opened
            ? reply
            : name == 'plan_trip'
            ? 'Mình chưa mở được Lộ trình. Bạn hãy chọn xe trước nhé.'
            : name == 'open_premium' || name == 'contact_support'
            ? 'Mình chưa mở được màn đó. Bạn vào Cài đặt nhé.'
            : 'Mình chưa mở được tab Sạc. Bạn hãy chọn xe trước nhé.',
      );
    }
    if (_riskyLocal.contains(name)) {
      final phrase = _localPhrase(name, args);
      if (phrase == null) {
        return const LocalChatReply(
          'Mình chưa đủ thông tin để chuẩn bị thao tác này. Bạn nói rõ ngày hoặc thời lượng nhé.',
        );
      }
      // The on-device engine builds the proposal from fresh reads and owns
      // confirmation (slide-to-confirm for ON) and the verified command.
      final proposal = await local.reply(phrase);
      if (proposal.action == null) return LocalChatReply(proposal.text);
      return LocalChatReply(reply, action: proposal.action);
    }
    if (name == 'set_app_setting' && args['setting'] != 'push_notifications') {
      // Only push notifications are adjustable; the app is Vietnamese only.
      return const LocalChatReply(
        'Hiện ứng dụng chỉ có tiếng Việt nên chưa đổi được ngôn ngữ.',
      );
    }
    if (_oneTap.contains(name)) {
      final id = const Uuid().v4();
      if (_pending.length >= 20) _pending.remove(_pending.keys.first);
      _pending[id] = _Pending(name, Map.unmodifiable(args), uid);
      final card = _card(name, args);
      return LocalChatReply(
        reply,
        action: FunctionCallAction(
          callId: id,
          toolName: 'app_$name',
          args: const {},
          cardData: ActionConfirmationCardData(
            title: card.$1,
            description: card.$2,
          ),
        ),
      );
    }
    return LocalChatReply(reply);
  }

  static String? _localPhrase(String name, Map<String, dynamic> args) {
    String? dmy(Object? iso) {
      final match = RegExp(
        r'^(\d{4})-(\d{2})-(\d{2})$',
      ).firstMatch(iso?.toString() ?? '');
      if (match == null) return null;
      return '${int.parse(match[3]!)}/${int.parse(match[2]!)}/${match[1]}';
    }

    String withDmy(String text) => text.replaceAllMapped(
      RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b'),
      (m) => '${int.parse(m[3]!)}/${int.parse(m[2]!)}/${m[1]}',
    );
    switch (name) {
      case 'start_timed_charging':
        final minutes = (args['minutes'] as num?)?.toInt();
        final target = (args['target_percent'] as num?)?.toInt();
        if (minutes == null) return null;
        // QA 135: the % the user aimed for rides along as the session target.
        return 'bật sạc $minutes phút${target == null ? '' : ' đến $target%'}';
      case 'stop_charging':
        return 'dừng sạc';
      case 'create_reminder':
        final date = dmy(args['date']);
        if (date == null) return null;
        final kind = args['kind'] == 'warranty' ? 'bảo hành' : 'bảo dưỡng';
        final note = (args['note']?.toString() ?? '').trim();
        return 'nhắc $kind${note.isEmpty ? ' xe' : ' $note'} ngày $date';
      case 'edit_reminder':
        final date = dmy(args['new_date']);
        if (date == null) return null;
        return 'đổi lịch ${withDmy(args['target']?.toString() ?? '')} sang $date';
      case 'cancel_reminder':
        return 'hủy lịch ${withDmy(args['target']?.toString() ?? '')}';
    }
    return null;
  }

  static (String, String) _card(
    String name,
    Map<String, dynamic> args,
  ) => switch (name) {
    'update_battery_level' => (
      'Cập nhật mức pin',
      'Đặt mức pin hiện tại thành ${args['percent']}% (theo đồng hồ xe).',
    ),
    'update_odometer' => ('Cập nhật ODO', 'Đặt số ODO thành ${args['km']} km.'),
    'select_vehicle' => (
      'Đổi xe đang chọn',
      'Chuyển sang xe ${args['vehicle_name']}.',
    ),
    'set_target_soc' => (
      'Đặt mục tiêu sạc',
      'Mức muốn sạc tới: ${args['percent']}%.',
    ),
    'set_electricity_price' => (
      'Đặt giá điện',
      'Giá điện ${args['vnd_per_kwh']} đ/kWh để tính chi phí sạc.',
    ),
    'set_app_setting' => _settingCard(args),
    'start_trial' => (
      'Dùng thử Ultra 7 ngày',
      'Mở mọi tính năng Ultra miễn phí 7 ngày (một lần mỗi tài khoản), không cần thanh toán.',
    ),
    'apply_promo_code' => (
      'Áp mã khuyến mãi',
      'Kiểm tra mã ${args['code']} và giữ cho lần mua đầu.',
    ),
    _ => ('Xác nhận thao tác', 'Kiểm tra rồi xác nhận.'),
  };

  static (String, String) _settingCard(Map<String, dynamic> args) {
    final value = args['value']?.toString();
    return value == 'on'
        ? (
            'Bật thông báo đẩy',
            'Nhận báo sạc xong, cảnh báo an toàn và cập nhật tức thì từ máy khác. Điện thoại có thể hỏi quyền thông báo.',
          )
        : (
            'Tắt thông báo đẩy',
            'Không nhận báo sạc xong và cảnh báo trên máy này; trạng thái sạc từ máy khác chỉ cập nhật ở lần đọc kế tiếp.',
          );
  }

  Map<String, dynamic> _result(bool ok, String message, String status) => {
    'success': ok,
    'status': status,
    'data': {'success': ok, 'message': message},
    'message': message,
  };

  @override
  Future<Map<String, dynamic>> confirm(String callId, bool confirmed) async {
    final pending = _pending[callId];
    if (pending == null) return local.confirm(callId, confirmed);
    if (pending.uid != uidResolver()) {
      return _result(false, 'Tài khoản đã thay đổi. Hãy hỏi lại.', 'expired');
    }
    if (pending.consumed) {
      return _result(false, 'Thao tác này đã được xử lý.', 'expired');
    }
    pending.consumed = true;
    if (!confirmed) return _result(true, 'Đã hủy.', 'cancelled');
    try {
      final undo = await host.apply(pending.name, pending.args);
      _lastUndo = undo;
      return _result(
        true,
        undo == null
            ? 'Đã cập nhật.'
            : 'Đã cập nhật. Nhắn "hoàn tác" nếu muốn quay lại.',
        'verified',
      );
    } on AssistantActionError catch (error) {
      return _result(false, error.message, 'blocked');
    } on Object {
      return _result(
        false,
        'Chưa cập nhật được. Hãy thử lại trong màn hình tương ứng.',
        'unknown',
      );
    }
  }

  Future<LocalChatReply> _undo() async {
    final undo = _lastUndo;
    _lastUndo = null;
    if (undo == null) {
      return const LocalChatReply('Không có thay đổi nào để hoàn tác.');
    }
    try {
      await undo.run();
      return LocalChatReply('Đã hoàn tác: ${undo.label}.');
    } on Object {
      return const LocalChatReply(
        'Chưa hoàn tác được. Hãy sửa trong màn hình tương ứng.',
      );
    }
  }

  @override
  void cancel() {
    _generation++;
    _history.clear();
    _pending.clear();
    _lastUndo = null;
    local.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    _pending.clear();
    local.dispose();
    api.close();
  }
}
