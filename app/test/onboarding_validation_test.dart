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
      expect(OnboardingService.validateDateOfBirth('20/05/1995'), isNull);
      expect(OnboardingService.validateDateOfBirth('31/12/2000'), isNull);
    });

    test('Invalid format returns error message', () {
      expect(OnboardingService.validateDateOfBirth('20-05-1995'), contains('dd/mm/yyyy'));
      expect(OnboardingService.validateDateOfBirth('1995/05/20'), contains('dd/mm/yyyy'));
      expect(OnboardingService.validateDateOfBirth('not-a-date'), contains('dd/mm/yyyy'));
    });

    test('Future date returns error', () {
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      final tomorrowStr = DateFormat('yyyy-MM-dd').format(tomorrow);
      expect(OnboardingService.validateDateOfBirth(tomorrowStr), contains('tương lai'));
      final tomorrowStrDmy = DateFormat('dd/MM/yyyy').format(tomorrow);
      expect(OnboardingService.validateDateOfBirth(tomorrowStrDmy), contains('tương lai'));
    });

    test('Age over 120 returns error', () {
      expect(OnboardingService.validateDateOfBirth('1890-01-01'), contains('120'));
      expect(OnboardingService.validateDateOfBirth('01/01/1890'), contains('120'));
    });

    test('Calculates age accurately for both yyyy-MM-dd and dd/MM/yyyy', () {
      expect(OnboardingService.calculateAge(null), isNull);
      expect(OnboardingService.calculateAge(''), isNull);

      final now = DateTime.now();
      final birth20YearsAgo = DateTime(now.year - 20, now.month, now.day);
      final strYmd = DateFormat('yyyy-MM-dd').format(birth20YearsAgo);
      final strDmy = DateFormat('dd/MM/yyyy').format(birth20YearsAgo);
      expect(OnboardingService.calculateAge(strYmd), equals(20));
      expect(OnboardingService.calculateAge(strDmy), equals(20));
    });

    test('Formats date conversions correctly', () {
      expect(OnboardingService.toServerDateFormat('20/05/1995'), equals('1995-05-20'));
      expect(OnboardingService.toDisplayDateFormat('1995-05-20'), equals('20/05/1995'));
    });
  });
}
