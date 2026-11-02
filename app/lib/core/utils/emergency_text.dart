/// Fire, smoke, explosion, shock and burning smell in a chat message
/// (QA 143). The same words as the server (`assistant/guardrails.py`), so
/// the basic on-device mode (offline, quota used up) answers them too.
///
/// Single accented words are safe ("cháy" is not "chạy"); without accents
/// only phrases count, because "chay" is also "chạy" and "khoi" "khỏi".
abstract final class EmergencyText {
  static final _pattern = RegExp(
    r'(?<![\p{L}\p{N}])(?:'
    r'cháy|bốc\s*cháy|khói|khét|nổ|phát\s*nổ|chập(?:\s*điện|\s*cháy)?|tia\s*lửa|lửa|'
    r'giật\s*điện|điện\s*giật|bị\s*giật|sốc\s*điện|phồng\s*pin|pin\s*(?:bị\s*)?phồng|'
    r'boc\s*chay|boc\s*khoi|co\s*khoi|mui\s*khet|bi\s*chay|chay\s*pin|pin\s*chay|'
    r'chay\s*o\s*cam|o\s*cam\s*chay|chay\s*no|phat\s*no|no\s*pin|pin\s*no|chap\s*dien|'
    r'dien\s*giat|giat\s*dien|bi\s*giat|soc\s*dien|tia\s*lua|phong\s*pin|pin\s*phong|'
    r'fire|smoke|smoking|burning|explod\p{L}*|sparks?|electric\s*shock'
    r')(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  /// A question about prevention is not an emergency when nothing is
  /// happening now ("sạc qua đêm có sợ cháy không?").
  static final _hypothetical = RegExp(
    r'(phòng\s*cháy|chống\s*cháy|nguy\s*cơ|sợ|có\s*thể|liệu|có\s+bị\s+\S+\s+không|'
    r'có\s+\S+\s+không|làm\s*sao\s*để\s*tránh|tránh|risk|prevent|could|might)',
    caseSensitive: false,
    unicode: true,
  );
  static final _now = RegExp(
    r'(đang|bị|rồi|có\s*khói|bốc|ngay|cứu|help|now|dang|roi|cuu)',
    caseSensitive: false,
    unicode: true,
  );

  static bool matches(String message) {
    final text = message.toLowerCase();
    if (!_pattern.hasMatch(text)) return false;
    return !(_hypothetical.hasMatch(text) && !_now.hasMatch(text));
  }

  /// The server's emergency reply, without the support ticket (offline).
  static const reply =
      '⚠️ **CẢNH BÁO AN TOÀN KHẨN CẤP**: Bạn hãy **ngắt cầu dao (aptomat) '
      'tổng ngay** nếu đảm bảo an toàn, **không chạm tay trần** vào ổ cắm hay '
      'xe, đưa mọi người ra xa ít nhất 5 mét và gọi ngay **114** (Cứu hỏa) '
      'hoặc **115** (Cấp cứu).';
}
