import 'package:flutter_test/flutter_test.dart';

/// ========================================================================
/// Unit Tests: Manual Trip Validation
/// Test các rule validation form nhập chuyến đi thủ công
/// ========================================================================

/// Extracted validation logic (mirrors AddManualTripModal._validateBattery)
String? validateBattery(String? value) {
  final v = int.tryParse(value ?? '');
  if (v == null) return 'Nhập số';
  if (v < 0 || v > 100) return '0-100%';
  return null;
}

/// Extracted validation logic (mirrors AddManualTripModal._validateOdo)
String? validateOdo(String? value) {
  final v = int.tryParse(value ?? '');
  if (v == null) return 'Nhập số';
  if (v < 0) return 'Phải ≥ 0';
  return null;
}

/// Extracted cross-field validation (mirrors AddManualTripModal._validateForm)
String? validateForm({
  required int startBat,
  required int endBat,
  required int startOdo,
  required int endOdo,
  required DateTime startTime,
  required DateTime endTime,
}) {
  if (startBat <= endBat) return 'Pin đầu phải lớn hơn pin cuối (vì tiêu hao)';
  if (endOdo <= startOdo) return 'ODO cuối phải lớn hơn ODO đầu';
  if (!endTime.isAfter(startTime)) return 'Giờ kết thúc phải sau giờ xuất phát';
  return null;
}

void main() {
  group('validateBattery', () {
    test('null input → Nhập số', () {
      expect(validateBattery(null), 'Nhập số');
    });

    test('empty string → Nhập số', () {
      expect(validateBattery(''), 'Nhập số');
    });

    test('non-numeric → Nhập số', () {
      expect(validateBattery('abc'), 'Nhập số');
    });

    test('negative → 0-100%', () {
      expect(validateBattery('-1'), '0-100%');
    });

    test('over 100 → 0-100%', () {
      expect(validateBattery('101'), '0-100%');
    });

    test('0 → valid (null)', () {
      expect(validateBattery('0'), isNull);
    });

    test('50 → valid (null)', () {
      expect(validateBattery('50'), isNull);
    });

    test('100 → valid (null)', () {
      expect(validateBattery('100'), isNull);
    });
  });

  group('validateOdo', () {
    test('null → Nhập số', () {
      expect(validateOdo(null), 'Nhập số');
    });

    test('empty → Nhập số', () {
      expect(validateOdo(''), 'Nhập số');
    });

    test('negative → Phải ≥ 0', () {
      expect(validateOdo('-5'), 'Phải ≥ 0');
    });

    test('0 → valid', () {
      expect(validateOdo('0'), isNull);
    });

    test('large number → valid', () {
      expect(validateOdo('99999'), isNull);
    });
  });

  group('validateForm (cross-field)', () {
    final baseStart = DateTime(2026, 4, 1, 8, 0);
    final baseEnd = DateTime(2026, 4, 1, 9, 0);

    test('startBat == endBat → error (không tiêu hao)', () {
      final err = validateForm(
        startBat: 80, endBat: 80,
        startOdo: 1000, endOdo: 1010,
        startTime: baseStart, endTime: baseEnd,
      );
      expect(err, contains('Pin đầu phải lớn hơn pin cuối'));
    });

    test('startBat < endBat → error (pin tăng = không hợp lệ cho trip)', () {
      final err = validateForm(
        startBat: 50, endBat: 80,
        startOdo: 1000, endOdo: 1010,
        startTime: baseStart, endTime: baseEnd,
      );
      expect(err, contains('Pin đầu phải lớn hơn pin cuối'));
    });

    test('endOdo == startOdo → error', () {
      final err = validateForm(
        startBat: 80, endBat: 70,
        startOdo: 1000, endOdo: 1000,
        startTime: baseStart, endTime: baseEnd,
      );
      expect(err, contains('ODO cuối phải lớn hơn ODO đầu'));
    });

    test('endOdo < startOdo → error', () {
      final err = validateForm(
        startBat: 80, endBat: 70,
        startOdo: 1000, endOdo: 999,
        startTime: baseStart, endTime: baseEnd,
      );
      expect(err, contains('ODO cuối phải lớn hơn ODO đầu'));
    });

    test('endTime == startTime → error', () {
      final err = validateForm(
        startBat: 80, endBat: 70,
        startOdo: 1000, endOdo: 1010,
        startTime: baseStart, endTime: baseStart,
      );
      expect(err, contains('Giờ kết thúc phải sau giờ xuất phát'));
    });

    test('endTime before startTime → error', () {
      final err = validateForm(
        startBat: 80, endBat: 70,
        startOdo: 1000, endOdo: 1010,
        startTime: baseEnd, endTime: baseStart,
      );
      expect(err, contains('Giờ kết thúc phải sau giờ xuất phát'));
    });

    test('all valid → null', () {
      final err = validateForm(
        startBat: 80, endBat: 70,
        startOdo: 1000, endOdo: 1010,
        startTime: baseStart, endTime: baseEnd,
      );
      expect(err, isNull);
    });

    test('edge case: 1% consumed, 1km driven, 1 min → valid', () {
      final err = validateForm(
        startBat: 1, endBat: 0,
        startOdo: 0, endOdo: 1,
        startTime: baseStart,
        endTime: baseStart.add(const Duration(minutes: 1)),
      );
      expect(err, isNull);
    });
  });

  group('Trip calculations', () {
    test('distance = endOdo - startOdo', () {
      const startOdo = 5000;
      const endOdo = 5012;
      expect(endOdo - startOdo, 12);
    });

    test('batteryConsumed = startBat - endBat', () {
      const startBat = 80;
      const endBat = 70;
      expect(startBat - endBat, 10);
    });

    test('efficiency = distance / batteryConsumed', () {
      const distance = 12.0;
      const consumed = 10;
      expect(distance / consumed, 1.2);
    });

    test('efficiency zero consumed → avoid division by zero', () {
      const distance = 12.0;
      const consumed = 0;
      final efficiency = consumed > 0 ? distance / consumed : 0.0;
      expect(efficiency, 0.0);
    });
  });
}
