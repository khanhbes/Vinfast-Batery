import 'dart:async';
import 'package:uuid/uuid.dart';
import '../../../core/utils/battery_bot_faq.dart';
import '../models/function_call_action.dart';

class LocalChatReply {
  const LocalChatReply(this.text, {this.card, this.action});
  final String text;
  final Map<String, dynamic>? card;
  final FunctionCallAction? action;
}

abstract interface class LocalChatEngine {
  Future<LocalChatReply> reply(String message);
  Future<Map<String, dynamic>> confirm(String callId, bool confirmed);
  void cancel();
  void dispose();
}

/// Live context belongs to the application, never to model-generated arguments.
abstract interface class ChatToolGateway {
  String? get uid;
  String? get vehicleId;
  void invalidate();
  Future<LocalChatReply> read(String tool, String question);
  Future<Map<String, dynamic>> prepare(String tool, String question);
  Future<Map<String, dynamic>> execute(
    String tool,
    Map<String, dynamic> evidence,
    String operationId,
  );
}

class AppKnowledgeRepository {
  static const outsideScope =
      'Mình hỗ trợ các chức năng của VinFast Battery. Bạn muốn hỏi về xe, pin, sạc hay Shelly?';
  String answer(String question) {
    final text = BatteryBotFaq.normalize(question);
    if (RegExp(r'\b(bao hanh|bao duong|lich hen)\b').hasMatch(text)) {
      return 'Bạn có thể lưu lịch bảo hành hoặc bảo dưỡng cho xe. Kiểm tra ngày và nội dung trước khi xác nhận; ngày hết bảo hành do bạn cung cấp, không phải xác nhận của hãng.';
    }
    if (RegExp(r'\b(ai|hoc ca nhan|du doan)\b').hasMatch(text)) {
      return 'Dự đoán cần model và dữ liệu phù hợp trên điện thoại. Kết quả là ước tính, không phải số đo BMS hay quyền bật sạc.';
    }
    if (BatteryBotFaq.actionFor(question) == null) return outsideScope;
    return BatteryBotFaq.answerFor(question);
  }
}

class _Proposal {
  _Proposal(
    this.tool,
    this.uid,
    this.vehicleId,
    this.generation,
    this.evidence,
  );
  final String tool;
  final String uid;
  final String vehicleId;
  final int generation;
  final Map<String, dynamic> evidence;
  bool consumed = false;
  Map<String, dynamic>? receipt;
}

/// Deterministic tool boundary: knowledge/LLM text cannot execute a command.
class BatteryBotLocalEngine implements LocalChatEngine {
  BatteryBotLocalEngine({this.tools, AppKnowledgeRepository? knowledge})
    : knowledge = knowledge ?? AppKnowledgeRepository();
  final ChatToolGateway? tools;
  final AppKnowledgeRepository knowledge;
  final Map<String, _Proposal> _proposals = {};
  int _generation = 0;
  bool _disposed = false;

  static bool isSensitive(String text) =>
      RegExp(
        r'(cloud\s*key|auth[_ -]?key|api[_ -]?key|password|mat khau|bearer\s+[a-z0-9._-]{16,})',
        caseSensitive: false,
      ).hasMatch(BatteryBotFaq.normalize(text)) ||
      RegExp(r'\b[A-Za-z0-9_-]{32,}\b').hasMatch(text) ||
      RegExp(r'[^\s@]+@[^\s@]+\.[^\s@]+').hasMatch(text);

  static String? toolFor(String question) {
    final text = BatteryBotFaq.normalize(question);
    if (RegExp(
      r'\b(ignore|bo qua|vuot qua|bypass|system prompt|bo luat|bo quy tac)\b',
    ).hasMatch(text)) {
      return null;
    }
    final guidance = RegExp(
      r'\b(cach|huong dan|o dau|lam sao|tai sao|vi sao|khong|dung bat|chua)\b',
    ).hasMatch(text);
    if (RegExp(r'\b(dang sac khong)\b').hasMatch(text)) {
      return 'charger_status';
    }
    if (!guidance &&
        RegExp(
          r'\b(bat sac|bat shelly|bat o cam|bat dau sac)\b',
        ).hasMatch(text)) {
      return 'start_timed_charging';
    }
    if (!guidance &&
        RegExp(r'\b(dung sac|tat sac|tat shelly|tat o cam)\b').hasMatch(text)) {
      return 'stop_charging';
    }
    if (!guidance &&
        RegExp(r'\b(huy|xoa|sua|doi)\b').hasMatch(text) &&
        RegExp(r'\b(bao hanh|bao duong|lich hen)\b').hasMatch(text)) {
      return RegExp(r'\b(huy|xoa)\b').hasMatch(text)
          ? 'cancel_reminder'
          : 'edit_reminder';
    }
    if (!guidance &&
        RegExp(r'\b(tao|dat|nhac|luu)\b').hasMatch(text) &&
        RegExp(r'\b(bao hanh|bao duong|lich hen)\b').hasMatch(text)) {
      return 'create_reminder';
    }
    if (RegExp(r'\b(lich su)\b').hasMatch(text) && !guidance) {
      return 'charging_history';
    }
    if (RegExp(r'\b(xem lich|lich bao hanh|lich bao duong)\b').hasMatch(text) &&
        !guidance) {
      return 'reminders';
    }
    if (RegExp(
      r'\b(quang duong|di duoc|di bao xa|con di|du km)\b',
    ).hasMatch(text)) {
      return 'predict_range';
    }
    if (RegExp(
      r'\b(sac bao lau|sac bao nhieu|thoi gian sac|tien sac|chi phi sac|du doan sac)\b',
    ).hasMatch(text)) {
      return 'predict_charging';
    }
    if (!guidance &&
        RegExp(
          r'\b(trang thai shelly|shelly dang|dang sac khong)\b',
        ).hasMatch(text)) {
      return 'charger_status';
    }
    if (!guidance &&
        RegExp(r'\b(pin con|pin bao nhieu|muc pin)\b').hasMatch(text)) {
      return 'battery_status';
    }
    return null;
  }

  @override
  Future<LocalChatReply> reply(String message) async {
    if (_disposed) return const LocalChatReply('Hãy mở lại trợ lý.');
    if (isSensitive(message)) {
      return const LocalChatReply(
        'Không gửi thông tin tài khoản hoặc khóa truy cập trong chat. Hãy nhập tại màn hình thiết lập.',
      );
    }
    final tool = toolFor(message);
    if (tool == null || tools == null) {
      return LocalChatReply(knowledge.answer(message));
    }
    final gateway = tools!;
    final uid = gateway.uid;
    final vehicle = gateway.vehicleId;
    final generation = _generation;
    bool current() =>
        !_disposed &&
        generation == _generation &&
        uid == gateway.uid &&
        vehicle == gateway.vehicleId;
    if (uid == null) {
      return const LocalChatReply('Hãy đăng nhập để xem dữ liệu của bạn.');
    }
    if (vehicle == null || vehicle.isEmpty) {
      return const LocalChatReply('Bạn hãy chọn xe trước nhé.');
    }
    try {
      if (!{
        'start_timed_charging',
        'stop_charging',
        'create_reminder',
        'edit_reminder',
        'cancel_reminder',
      }.contains(tool)) {
        final result = await gateway
            .read(tool, message)
            .timeout(const Duration(seconds: 20));
        return current()
            ? result
            : const LocalChatReply(
                'Tài khoản hoặc xe đã thay đổi. Hãy hỏi lại.',
              );
      }
      final evidence = await gateway
          .prepare(tool, message)
          .timeout(const Duration(seconds: 20));
      if (!current()) {
        return const LocalChatReply(
          'Tài khoản hoặc xe đã thay đổi. Hãy hỏi lại.',
        );
      }
      if (evidence['allowed'] != true) {
        return LocalChatReply(
          evidence['userMessage'] as String? ??
              'Hãy mở màn hình tương ứng để kiểm tra.',
        );
      }
      final id = const Uuid().v4();
      if (_proposals.length >= 50) _proposals.remove(_proposals.keys.first);
      _proposals[id] = _Proposal(
        tool,
        uid,
        vehicle,
        generation,
        Map.unmodifiable(evidence),
      );
      return LocalChatReply(
        'Kiểm tra thông tin rồi xác nhận nếu bạn muốn thực hiện.',
        action: FunctionCallAction(
          callId: id,
          toolName: tool,
          // IDs, credentials and executable arguments are never serialized in chat.
          args: const {},
          cardData: ActionConfirmationCardData(
            title: evidence['title'] as String,
            description: evidence['description'] as String,
            estimatedTime: evidence['estimatedTime'] as String?,
            safetyNote: evidence['safetyNote'] as String?,
          ),
        ),
      );
    } on Object {
      cancel();
      return const LocalChatReply(
        'Chưa đọc được dữ liệu. Hãy thử lại hoặc mở màn hình tương ứng.',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> confirm(String callId, bool confirmed) async {
    final proposal = _proposals[callId];
    Map<String, dynamic> result(bool success, String message, String status) =>
        {
          'success': success,
          'status': status,
          'data': {'success': success, 'message': message},
          'message': message,
        };
    if (_disposed ||
        proposal == null ||
        proposal.generation != _generation ||
        proposal.uid != tools?.uid ||
        proposal.vehicleId != tools?.vehicleId) {
      return result(false, 'Yêu cầu đã hết hiệu lực. Hãy hỏi lại.', 'expired');
    }
    if (proposal.receipt != null) return proposal.receipt!;
    if (proposal.consumed) {
      return result(
        false,
        'Đang xác minh thao tác. Không gửi lại lệnh.',
        'pending',
      );
    }
    // Consume before await: double-tap, timeout and replay cannot send ON twice.
    proposal.consumed = true;
    if (!confirmed) {
      return proposal.receipt = result(true, 'Đã hủy yêu cầu.', 'cancelled');
    }
    try {
      final receipt = await tools!
          .execute(proposal.tool, proposal.evidence, callId)
          .timeout(const Duration(seconds: 30));
      if (proposal.generation != _generation ||
          proposal.uid != tools?.uid ||
          proposal.vehicleId != tools?.vehicleId) {
        return result(
          false,
          'Tài khoản hoặc xe đã thay đổi. Kiểm tra trạng thái trước khi thao tác tiếp.',
          'expired',
        );
      }
      return proposal.receipt = receipt;
    } on Object {
      tools?.invalidate();
      return proposal.receipt = result(
        false,
        proposal.tool.endsWith('_reminder')
            ? 'Chưa xác minh được kết quả. Hãy xem lịch nhắc trước khi thao tác tiếp.'
            : 'Chưa xác minh được kết quả. Hãy mở Sạc pin để kiểm tra; không gửi lại lệnh bật.',
        'unknown',
      );
    }
  }

  @override
  void cancel() {
    _generation++;
    tools?.invalidate();
    _proposals.clear();
  }

  @override
  void dispose() {
    cancel();
    _disposed = true;
  }
}
