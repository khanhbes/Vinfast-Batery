import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/charge_progress_notification.dart';

void main() {
  final now = DateTime.utc(2026, 10, 16, 3, 0);
  Map<String, dynamic> push({
    String soc = '40.0',
    String power = '440',
    String remaining = '8509',
    String mode = 'target',
    DateTime? sentAt,
  }) => {
    'event': 'smart_charge_progress',
    'sessionId': 's1',
    'soc': soc,
    'targetSoc': '80',
    'stopMode': mode,
    'powerW': power,
    'remainingSeconds': remaining,
    'ceilingAt': now.add(const Duration(hours: 4)).toIso8601String(),
    'sentAt': (sentAt ?? now).toIso8601String(),
  };

  test('target charge: %, power, finish time and a countdown', () {
    final content = ChargeProgressContent.from(push(), now)!;
    expect(content.title, 'Đang sạc ~40% → 80%');
    expect(content.body, contains('440 W'));
    expect(content.body, contains('xong ~'));
    expect(content.progress, 40);
    expect(content.finishAt, now.add(const Duration(seconds: 8509)));
  });

  test('a push that waited in the queue counts from when it was sent', () {
    final sent = now.subtract(const Duration(minutes: 3));
    final content = ChargeProgressContent.from(push(sentAt: sent), now)!;
    expect(content.finishAt, sent.add(const Duration(seconds: 8509)));
    expect(content.body, contains('cập nhật'));
  });

  test('scooter not drawing power says so; unknown % is never invented', () {
    final idle = ChargeProgressContent.from(push(power: '2'), now)!;
    expect(idle.body, contains('Xe chưa nhận điện'));
    final unknown = ChargeProgressContent.from(
      push(soc: '', mode: 'timer', remaining: ''),
      now,
    )!;
    expect(unknown.title, 'Đang sạc —');
    expect(unknown.progress, isNull);
    expect(unknown.finishAt, isNull);
    expect(unknown.body, contains('tự tắt'));
  });

  test('other events are not progress', () {
    expect(ChargeProgressContent.from({'event': 'smart_charge'}, now), isNull);
  });

  test('a connection gap says the charge continues on the device timer', () {
    final content = ChargeProgressContent.from({
      ...push(),
      'link': 'lost',
    }, now)!;
    expect(content.title, 'Đang sạc ~40% → 80%');
    expect(content.body, contains('Tạm mất kết nối với ổ'));
    expect(content.body, contains('tự tắt muộn nhất'));
    expect(content.finishAt, isNull);
  });
}
