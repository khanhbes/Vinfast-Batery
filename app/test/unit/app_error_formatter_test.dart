import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/utils/app_error_formatter.dart';

void main() {
  group('Untrusted error presentation', () {
    final values = <Object?>[
      null,
      '',
      'token=qa-secret',
      'uid=qa-account',
      'qa.internal',
      'Exception: password=qa-secret',
      Exception('https://qa.invalid/path?key=qa-secret'),
      '{"key":"qa-secret"}',
      'Chưa tải được dữ liệu: uid=qa-account',
    ];
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      test('unknown error uses fixed fallback: case $index', () {
        expect(AppErrorFormatter.format(value), AppErrorFormatter.fallback);
      });
    }

    test('missing index is not described as a successful background sync', () {
      final message = AppErrorFormatter.format(
        '[cloud_firestore/FAILED_PRECONDITION] requires an index uid=qa-account',
      );
      expect(message, contains('tạm chưa khả dụng'));
      expect(message, isNot(contains('đồng bộ')));
      expect(message, isNot(contains('qa-account')));
    });

    test('permission failure does not expose account details', () {
      expect(
        AppErrorFormatter.format('PERMISSION_DENIED uid=qa-account'),
        'Chưa thể truy cập dữ liệu. Vui lòng thử lại hoặc liên hệ hỗ trợ.',
      );
    });

    test('timeout never proves that internet is disconnected', () {
      final message = AppErrorFormatter.format(TimeoutException('qa.internal'));
      expect(message, contains('Chưa nhận được phản hồi'));
      expect(message, isNot(contains('qa.internal')));
      expect(message, isNot(contains('Không có kết nối')));
    });

    test('device failure does not claim that relay is off', () {
      final message = AppErrorFormatter.format('device_offline id=qa-device');
      expect(message, contains('đọc trạng thái'));
      expect(message, isNot(contains('đã tắt')));
      expect(message, isNot(contains('qa-device')));
    });

    test('invalid credential failures all have the same message', () {
      for (final code in [
        'wrong-password',
        'user-not-found',
        'invalid-credential',
      ]) {
        expect(
          AppErrorFormatter.format(code),
          'Email hoặc mật khẩu không chính xác.',
        );
      }
    });
  });
}
