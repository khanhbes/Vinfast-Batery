import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/utils/battery_bot_faq.dart';

void main() {
  group('BatteryBot Vietnamese FAQ', () {
    test('folds all Vietnamese letters, case and combining marks', () {
      const groups = {
        'a': 'àáạảãâầấậẩẫăằắặẳẵ',
        'e': 'èéẹẻẽêềếệểễ',
        'i': 'ìíịỉĩ',
        'o': 'òóọỏõôồốộổỗơờớợởỡ',
        'u': 'ùúụủũưừứựửữ',
        'y': 'ỳýỵỷỹ',
        'd': 'đ',
      };
      for (final entry in groups.entries) {
        for (final letter in entry.value.split('')) {
          expect(BatteryBotFaq.normalize(letter), entry.key);
          expect(BatteryBotFaq.normalize(letter.toUpperCase()), entry.key);
        }
      }
      expect(BatteryBotFaq.normalize('du\u031B\u0300ng sa\u0323c'), 'dung sac');
      expect(BatteryBotFaq.normalize('  LỊCH—SỬ?!\n'), 'lich su');
    });

    const examples = {
      BatteryBotAction.guideVehicle: [
        'Xem pin ở đâu?',
        'xem pin o dau',
        'Đổi xe',
        'battery',
      ],
      BatteryBotAction.guideCharging: [
        'Làm sao dừng sạc?',
        'lam sao dung sac',
        'BẮT ĐẦU SẠC',
        'bat dau sac',
        'Vì sao nút sạc bị khóa?',
        'vi sao nut sac bi khoa',
        'du\u031B\u0300ng sa\u0323c',
        'Làm sao dừng sạc Shelly?',
        'Vì sao kết nối Shelly xong mà nút sạc bị khóa?',
      ],
      BatteryBotAction.guideHistory: [
        'Mở lịch sử',
        'mo lich su',
        'Xem phiên sạc',
        'xem phien sac',
        'LI\u0323CH SU\u031B\u0309',
        'Lịch sử sạc Shelly',
      ],
      BatteryBotAction.shellySetup: [
        'Kết nối Shelly',
        'ket noi shelly',
        'KẾT NỐI',
        'ket-noi',
      ],
    };
    for (final entry in examples.entries) {
      for (final question in entry.value) {
        test('$question resolves to ${entry.key.name}', () {
          expect(BatteryBotFaq.actionFor(question), entry.key);
        });
      }
    }

    test('every suggestion opens its intended destination', () {
      expect(BatteryBotFaq.suggestions.map(BatteryBotFaq.actionFor), [
        BatteryBotAction.guideVehicle,
        BatteryBotAction.guideCharging,
        BatteryBotAction.shellySetup,
        BatteryBotAction.guideCharging,
      ]);
    });

    test('unrelated words do not match partial keywords', () {
      for (final question in [
        '',
        '😀',
        'xin chào',
        'xem thời tiết',
        'spinning',
      ]) {
        expect(BatteryBotFaq.actionFor(question), isNull);
      }
    });
  });
}
