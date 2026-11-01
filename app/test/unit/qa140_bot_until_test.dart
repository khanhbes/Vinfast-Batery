import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/ai/services/app_chat_tool_gateway.dart';

/// QA 140: Pinova Bot "sạc đến 9:30" — the gateway reads the clock time and
/// the server times the outlet from it.
void main() {
  final now = DateTime(2026, 11, 1, 7, 0);

  test('a clock time in the action is today, or tomorrow once passed', () {
    expect(
      AppChatToolGateway.parseStopAt('bật sạc 150 phút đến 09:30', now),
      DateTime(2026, 11, 1, 9, 30),
    );
    expect(
      AppChatToolGateway.parseStopAt('bật sạc 30 phút đến 06:30', now),
      DateTime(2026, 11, 2, 6, 30),
    );
  });

  test('a target % is not a clock time; minutes alone still parse', () {
    expect(
      AppChatToolGateway.parseStopAt('bật sạc 265 phút đến 85%', now),
      isNull,
    );
    expect(AppChatToolGateway.parseStopAt('bật sạc 30 phút', now), isNull);
    expect(
      AppChatToolGateway.parseDuration('bật sạc 150 phút đến 09:30'),
      9000,
    );
    expect(
      AppChatToolGateway.parseTimedTarget(
        'bật sạc 150 phút đến 09:30 đến 85%',
        40,
      ),
      85,
    );
  });
}
