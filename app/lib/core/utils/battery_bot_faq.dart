/// Presentation-only destinations. BatteryBot never issues charger commands.
enum BatteryBotAction { guideVehicle, guideCharging, guideHistory, shellySetup }

class BatteryBotFaq {
  BatteryBotFaq._();

  static const suggestions = [
    'Xem pin ở đâu?',
    'Làm sao dừng sạc?',
    'Kết nối Shelly',
    'Vì sao nút sạc bị khóa?',
  ];

  static const _vietnameseLetters = {
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'e': 'èéẹẻẽêềếệểễ',
    'i': 'ìíịỉĩ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'u': 'ùúụủũưừứựửữ',
    'y': 'ỳýỵỷỹ',
    'd': 'đ',
  };

  /// Fold both precomposed Vietnamese letters and decomposed combining marks.
  /// The same normalization is applied to questions and FAQ keywords.
  static String normalize(String value) {
    var text = value.toLowerCase();
    for (final entry in _vietnameseLetters.entries) {
      text = text.replaceAll(RegExp('[${entry.value}]'), entry.key);
    }
    return text
        .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  static BatteryBotAction? actionFor(String question) {
    final text = ' ${normalize(question)} ';
    bool matches(List<String> keywords) =>
        keywords.any((keyword) => text.contains(' ${normalize(keyword)} '));

    // Prefer the requested task over a product name in the same question.
    // For example, "dừng sạc Shelly" must not send the user to setup.
    if (matches(['dừng sạc', 'bắt đầu sạc', 'khóa'])) {
      return BatteryBotAction.guideCharging;
    }
    if (matches(['lịch sử', 'phiên sạc'])) {
      return BatteryBotAction.guideHistory;
    }
    if (matches(['Shelly', 'kết nối'])) {
      return BatteryBotAction.shellySetup;
    }
    if (matches(['pin', 'xe', 'battery'])) {
      return BatteryBotAction.guideVehicle;
    }
    return null;
  }

  /// Offline guidance, not a live device reading or a generative model.
  static String answerFor(String question) => switch (actionFor(question)) {
    BatteryBotAction.guideVehicle =>
      'Mở Tổng quan, chọn xe rồi xem mức pin và thời điểm cập nhật. Mình không có số đo trực tiếp trong cuộc trò chuyện này.',
    BatteryBotAction.guideCharging =>
      'Mở Sạc pin để xem điều kiện bật sạc hoặc dùng Dừng sạc. Nếu nút bị khóa, kiểm tra thông báo kết nối và an toàn. Mình không tự bật hoặc tắt ổ cắm.',
    BatteryBotAction.guideHistory =>
      'Mở Lịch sử, chọn xe và khoảng thời gian. Chạm một phiên để xem điện năng và chi phí đã ghi nhận.',
    BatteryBotAction.shellySetup =>
      'Mở Cài đặt → Sạc thông minh Shelly để kết nối. Trước kiểm tra an toàn, rút mọi tải và chỉ tiếp tục khi bạn đang giám sát thiết bị.',
    null =>
      'Mình là trợ lý hướng dẫn chạy trên điện thoại. Bạn muốn xem pin, kết nối Shelly, tìm lịch sử hay tìm nút dừng sạc?',
  };
}
