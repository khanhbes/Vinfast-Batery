import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/utils/app_error_formatter.dart';
import 'package:vinfast_battery/core/utils/error_mapper.dart';

void main() {
  test('legacy mapper never returns a short untrusted string', () {
    for (final raw in <Object?>[
      null,
      '',
      'secret-token',
      'uid=private-user',
      'internal.lan',
      '{"token":"private"}',
      'Thông tin riêng của private-user',
    ]) {
      expect(UserFriendlyErrorMapper.map(raw), AppErrorFormatter.fallback);
    }
  });

  test(
    'authored copy has an exact boundary, not a trusted source heuristic',
    () {
      expect(
        AppNoticeCopy.approved('Chưa xác nhận được ổ sạc đã tắt'),
        'Chưa xác nhận được ổ sạc đã tắt',
      );
      expect(
        AppNoticeCopy.approved('Hãy kiểm tra ổ sạc trực tiếp.'),
        isNotNull,
      );
      expect(
        AppNoticeCopy.approved('Hãy kiểm tra ổ sạc trực tiếp. key=private'),
        isNull,
      );
      expect(
        AppNoticeCopy.approved('{"source":"local","message":"secret"}'),
        isNull,
      );
      expect(AppNoticeCopy.approved('Đã chọn device-private'), isNull);
      expect(AppNoticeCopy.approved('IP: 192.0.2.4'), isNull);
    },
  );

  test('telemetry warning allows bounded numeric templates only', () {
    expect(AppNoticeCopy.approved('Shelly sẽ tự ngắt sau 1 giờ.'), isNotNull);
    expect(AppNoticeCopy.approved('Hẹn giờ 30 phút.'), isNotNull);
    expect(AppNoticeCopy.approved('Dòng điện đang cao (11.5 A).'), isNotNull);
    expect(
      AppNoticeCopy.approved('Nhiệt độ Shelly đang cao (70.0 °C).'),
      isNotNull,
    );
    expect(AppNoticeCopy.approved('Dòng điện đang cao (secret A).'), isNull);
    expect(
      AppNoticeCopy.approved('Dòng điện đang cao (11.5 A).\nsecret'),
      isNull,
    );
    expect(
      AppNoticeCopy.category('Dòng điện đang cao (11.5 A).'),
      AppNoticeCopy.category('Dòng điện đang cao (11.6 A).'),
    );
  });

  test('known codes map without echoing provider payload', () {
    expect(
      AppNoticeCopy.error('permission-denied uid=private'),
      AppErrorFormatter.format('permission-denied'),
    );
    expect(
      AppNoticeCopy.error('failed-precondition key=private'),
      isNot(contains('đồng bộ')),
    );
    expect(AppNoticeCopy.actionLabel('private-token'), 'Mở');
  });
}
