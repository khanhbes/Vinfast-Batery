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
}
