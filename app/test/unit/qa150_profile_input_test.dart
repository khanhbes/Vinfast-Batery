import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/settings/profile_screen.dart';

/// QA 150: Hồ sơ saved an empty name and "12" as the phone number.
void main() {
  test('an empty or one-letter name is refused', () {
    expect(profileInputProblem('', '0900000000'), isNotNull);
    expect(profileInputProblem('  A ', '0900000000'), isNotNull);
    expect(profileInputProblem('QA Hai', '0900000000'), isNull);
  });

  test('a phone number needs 9 to 11 digits, or stays empty', () {
    expect(profileInputProblem('QA Hai', '12'), isNotNull);
    expect(profileInputProblem('QA Hai', '090000000a'), isNotNull);
    expect(profileInputProblem('QA Hai', '123456789012'), isNotNull);
    expect(profileInputProblem('QA Hai', ''), isNull);
    expect(profileInputProblem('QA Hai', '090 000 0000'), isNull);
    expect(profileInputProblem('QA Hai', '+84900000000'), isNull);
  });

  test('a password change needs the old one, 6 characters and a match', () {
    expect(passwordChangeProblem('', 'abcdef', 'abcdef'), isNotNull);
    expect(passwordChangeProblem('old123', 'abc', 'abc'), isNotNull);
    expect(passwordChangeProblem('old123', 'abcdef', 'abcdeg'), isNotNull);
    expect(passwordChangeProblem('old123', 'old123', 'old123'), isNotNull);
    expect(passwordChangeProblem('old123', 'abcdef', 'abcdef'), isNull);
  });
}
