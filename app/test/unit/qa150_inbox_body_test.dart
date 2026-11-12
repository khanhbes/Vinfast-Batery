import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/notifications/notification_center_screen.dart';

/// QA 150: notification bodies repeated their title (seen on the phone).
void main() {
  test('the repeated title is dropped', () {
    expect(
      inboxBody('Đã dừng sạc', 'Đã dừng sạc. Shelly đã xác nhận tắt.'),
      'Shelly đã xác nhận tắt.',
    );
    expect(
      inboxBody(
        'Đã sạc đến khoảng 80%',
        'Đã sạc đến khoảng 80% (ước tính), ổ cắm đã tự ngắt.',
      ),
      'Đã sạc đến khoảng 80% (ước tính), ổ cắm đã tự ngắt.',
    );
  });

  test('"open the app" becomes where to look', () {
    expect(
      inboxBody(
        'Phiên sạc bị ngắt',
        'Phiên sạc bị ngắt trước giờ dự kiến. Mở app để kiểm tra.',
      ),
      'Phiên sạc bị ngắt trước giờ dự kiến. Mở Sạc pin để xem chi tiết.',
    );
  });

  test('a body that is its own sentence stays as written', () {
    expect(
      inboxBody('Bảo dưỡng đã quá hạn', 'Kiểm tra phanh (quá 320 km).'),
      'Kiểm tra phanh (quá 320 km).',
    );
    expect(inboxBody('Đã dừng sạc', 'Đã dừng sạc'), 'Đã dừng sạc');
  });
}
