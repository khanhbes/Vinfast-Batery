/// Whether the saved battery % can start a charge without asking (QA 148).
///
/// The saved number is the last reading or the estimate when a charge ended. It
/// knows nothing about riding since then, and the energy to deliver comes from it:
/// saved 80 %, really 40 %, target 90 % stops at about 50 %. The scooter has no BMS
/// link, so only the owner can say what the gauge shows now.
abstract final class StartSocFreshness {
  static const window = Duration(hours: 2);
  static const _estimated = 'smart_charge_estimated';

  static bool isFresh(DateTime? savedAt, String? source, DateTime now) {
    if (savedAt == null || source == _estimated) return false;
    return now.difference(savedAt) < window;
  }

  /// One line for a number that is not fresh.
  static String staleNote(DateTime? savedAt, String? source, DateTime now) {
    final age = _age(savedAt, now);
    final what = source == _estimated
        ? 'Số ước tính sau lần sạc trước${age == null ? '' : ', $age'}.'
        : age == null
        ? 'Chưa rõ số này lưu từ khi nào.'
        : 'Số này lưu từ $age.';
    return '$what Pin đã giảm nếu xe đã chạy, hãy đọc lại trên đồng hồ xe.';
  }

  static String? _age(DateTime? savedAt, DateTime now) {
    if (savedAt == null) return null;
    final age = now.difference(savedAt);
    if (age.inDays >= 1) return '${age.inDays} ngày trước';
    if (age.inHours >= 1) return '${age.inHours} giờ trước';
    return 'vài phút trước';
  }
}
