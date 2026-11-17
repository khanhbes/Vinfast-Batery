import 'package:shared_preferences/shared_preferences.dart';

/// One Pinova Bot release, in the owner's words.
class BotRelease {
  const BotRelease(this.version, this.date, this.changes);
  final String version;
  final String date;
  final List<String> changes;
}

/// QA 163 (owner's choice): Pinova Bot has its own version, shown in Giới
/// thiệu with what changed. Raise [current] and add a release on top of
/// [releases] whenever the bot changes (AGENTS.md).
abstract final class PinovaBotRelease {
  static const current = '3.3.0';

  static const releases = <BotRelease>[
    BotRelease('3.3.0', '17/11/2026', [
      'Chữ hiện dần ngay khi Pinova Bot đang viết, kèm việc Bot đang làm (ví dụ đang xem ổ Shelly).',
      'Nói để hỏi và nghe Bot đọc câu trả lời (Android).',
      'Gửi ảnh đèn báo, bộ sạc hay ổ Shelly để Bot xem (gói Pro, Ultra).',
      'Lịch sử chat tìm được, chia theo ngày, đổi tên và xóa có hoàn tác; mở lại đoạn cũ thì Bot nhớ đoạn đó.',
      'Sức khỏe pin nói theo mức so với lúc bắt đầu theo dõi; câu hỏi ngoài hướng dẫn vẫn được trả lời theo thông tin chung.',
    ]),
    BotRelease('3.2.0', '16/11/2026', [
      'Cài đặt riêng cho Pinova Bot: giọng trả lời, độ dài, cách gọi bạn và điều Bot nên biết về bạn.',
      'Mỗi ngày một mẹo nhỏ về đi xe, sạc và giữ pin bền; xem đủ ở Tiện ích → Mẹo nhỏ.',
      'Trả lời thẳng vào ý chính, hỏi lại khi câu hỏi chưa rõ, gợi ý câu hỏi tiếp theo.',
      'Thêm nút Hỏi lại và Dừng trả lời; lần đầu mở có phần giới thiệu ngắn.',
    ]),
    BotRelease('3.1.0', '12/11/2026', [
      'Biểu cảm theo việc thật: lo lắng khi có cảnh báo, vui khi sạc xong.',
      'Nhớ đoạn chat gần nhất trong 30 phút.',
    ]),
    BotRelease('3.0.0', '15/10/2026', [
      'Pinova Bot dùng AI qua máy chủ Pinova: trả lời về xe, pin, sạc và ổ Shelly.',
      'Làm giúp: bật sạc theo giờ, sạc đến %, dừng sạc, cập nhật % pin và ODO (luôn hỏi lại trước).',
      'Ghi nhớ điều bạn kể, xem và xóa được.',
    ]),
  ];

  static const _seenKey = 'assistant.bot_version_seen.v1';

  /// The version this phone last showed, or null the first time.
  static Future<String?> seen() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_seenKey);
    } on Object {
      return current; // no storage: never nag
    }
  }

  static Future<void> markSeen() async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _seenKey,
        current,
      );
    } on Object {
      // Shown again next time; harmless.
    }
  }
}
