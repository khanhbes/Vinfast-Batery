import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:vinfast_battery/core/services/onboarding_service.dart';

void main() {
  group('Onboarding Date of Birth Validation Tests', () {
    test('Null or empty date of birth is valid (optional)', () {
      expect(OnboardingService.validateDateOfBirth(null), isNull);
      expect(OnboardingService.validateDateOfBirth(''), isNull);
      expect(OnboardingService.validateDateOfBirth('   '), isNull);
    });

    test('Valid date of birth returns null (no error)', () {
      expect(OnboardingService.validateDateOfBirth('1995-05-20'), isNull);
      expect(OnboardingService.validateDateOfBirth('2000-12-31'), isNull);
    });

    test('Invalid format returns error message', () {
      expect(OnboardingService.validateDateOfBirth('20-05-1995'), contains('YYYY-MM-DD'));
      expect(OnboardingService.validateDateOfBirth('1995/05/20'), contains('YYYY-MM-DD'));
      expect(OnboardingService.validateDateOfBirth('not-a-date'), contains('YYYY-MM-DD'));
    });

    test('Future date returns error', () {
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      final tomorrowStr = DateFormat('yyyy-MM-dd').format(tomorrow);
      expect(OnboardingService.validateDateOfBirth(tomorrowStr), contains('tương lai'));
    });

    test('Age over 120 returns error', () {
      expect(OnboardingService.validateDateOfBirth('1890-01-01'), contains('120'));
    });

    test('Calculates age accurately', () {
      expect(OnboardingService.calculateAge(null), isNull);
      expect(OnboardingService.calculateAge(''), isNull);

      final now = DateTime.now();
      final birth20YearsAgo = DateTime(now.year - 20, now.month, now.day);
      final str = DateFormat('yyyy-MM-dd').format(birth20YearsAgo);
      expect(OnboardingService.calculateAge(str), equals(20));
    });
  });
}
