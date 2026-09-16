import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_service.dart';

/// Dữ liệu tiến độ Onboarding
class OnboardingProgress {
  final int registrationFlowVersion;
  final bool isCompleted;
  final String? onboardingCompletedAt;
  final String name;
  final String phone;
  final String? dateOfBirth;
  final bool isProfileComplete;
  final bool hasVehicle;
  final int vehicleCount;
  final List<Map<String, dynamic>> vehicles;
  final String shellyStatus;

  const OnboardingProgress({
    required this.registrationFlowVersion,
    required this.isCompleted,
    this.onboardingCompletedAt,
    required this.name,
    required this.phone,
    this.dateOfBirth,
    required this.isProfileComplete,
    required this.hasVehicle,
    required this.vehicleCount,
    required this.vehicles,
    required this.shellyStatus,
  });

  int? get age => OnboardingService.calculateAge(dateOfBirth);

  factory OnboardingProgress.fromJson(Map<String, dynamic> json) {
    final profile = (json['profile'] as Map<String, dynamic>?) ?? {};
    final vehicle = (json['vehicle'] as Map<String, dynamic>?) ?? {};
    final shelly = (json['shelly'] as Map<String, dynamic>?) ?? {};

    return OnboardingProgress(
      registrationFlowVersion: json['registrationFlowVersion'] as int? ?? 1,
      isCompleted: json['isCompleted'] as bool? ?? false,
      onboardingCompletedAt: json['onboardingCompletedAt'] as String?,
      name: profile['name']?.toString() ?? '',
      phone: profile['phone']?.toString() ?? '',
      dateOfBirth: profile['dateOfBirth']?.toString(),
      isProfileComplete: profile['isComplete'] as bool? ?? false,
      hasVehicle: vehicle['hasVehicle'] as bool? ?? false,
      vehicleCount: vehicle['count'] as int? ?? 0,
      vehicles: (vehicle['vehicles'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      shellyStatus: shelly['status']?.toString() ?? 'pending',
    );
  }
}

/// Dịch vụ quản lý luồng Onboarding & Profile API
class OnboardingService {
  final ApiService _api;

  OnboardingService({ApiService? api}) : _api = api ?? ApiService();

  /// Chuyển đổi chuỗi ngày sinh bất kỳ (dd/MM/yyyy hoặc yyyy-MM-dd) sang DateTime
  static DateTime? parseDateOfBirth(String? dob) {
    if (dob == null || dob.trim().isEmpty) return null;
    final trimmed = dob.trim();
    // Thử định dạng dd/MM/yyyy
    final dmyRegex = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');
    final dmyMatch = dmyRegex.firstMatch(trimmed);
    if (dmyMatch != null) {
      final day = int.tryParse(dmyMatch.group(1)!);
      final month = int.tryParse(dmyMatch.group(2)!);
      final year = int.tryParse(dmyMatch.group(3)!);
      if (day != null && month != null && year != null) {
        try {
          final dt = DateTime(year, month, day);
          if (dt.year == year && dt.month == month && dt.day == day) {
            return dt;
          }
        } catch (_) {}
      }
      return null;
    }
    // Thử định dạng yyyy-MM-dd
    final ymdRegex = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');
    final ymdMatch = ymdRegex.firstMatch(trimmed);
    if (ymdMatch != null) {
      final year = int.tryParse(ymdMatch.group(1)!);
      final month = int.tryParse(ymdMatch.group(2)!);
      final day = int.tryParse(ymdMatch.group(3)!);
      if (day != null && month != null && year != null) {
        try {
          final dt = DateTime(year, month, day);
          if (dt.year == year && dt.month == month && dt.day == day) {
            return dt;
          }
        } catch (_) {}
      }
      return null;
    }
    return DateTime.tryParse(trimmed);
  }

  /// Chuyển đổi định dạng ngày sinh sang chuẩn YYYY-MM-DD gửi lên server
  static String? toServerDateFormat(String? dob) {
    final dt = parseDateOfBirth(dob);
    if (dt == null) return null;
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  /// Chuyển đổi định dạng ngày sinh sang chuẩn dd/MM/yyyy hiển thị cho người dùng
  static String? toDisplayDateFormat(String? dob) {
    final dt = parseDateOfBirth(dob);
    if (dt == null) return null;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year.toString().padLeft(4, '0')}';
  }

  /// Validate ngày sinh (hỗ trợ dd/MM/yyyy hoặc YYYY-MM-DD)
  /// - Tùy chọn (null hoặc rỗng là hợp lệ khi bỏ qua)
  /// - Không được ở tương lai
  /// - Tuổi không được vượt quá 120
  static String? validateDateOfBirth(String? dob) {
    if (dob == null || dob.trim().isEmpty) return null;
    final parsed = parseDateOfBirth(dob);
    if (parsed == null) {
      return 'Định dạng ngày sinh phải là dd/mm/yyyy';
    }
    final now = DateTime.now();
    if (parsed.isAfter(now)) {
      return 'Ngày sinh không thể ở tương lai';
    }
    final age =
        now.year -
        parsed.year -
        ((now.month < parsed.month ||
                (now.month == parsed.month && now.day < parsed.day))
            ? 1
            : 0);
    if (age > 120) {
      return 'Tuổi không hợp lệ (vượt quá 120 tuổi)';
    }
    return null;
  }

  /// Tính tuổi từ chuỗi ngày sinh (hỗ trợ cả dd/MM/yyyy và yyyy-MM-dd)
  static int? calculateAge(String? dob) {
    if (dob == null || dob.trim().isEmpty) return null;
    final parsed = parseDateOfBirth(dob);
    if (parsed == null) return null;
    final now = DateTime.now();
    final age =
        now.year -
        parsed.year -
        ((now.month < parsed.month ||
                (now.month == parsed.month && now.day < parsed.day))
            ? 1
            : 0);
    if (age < 0 || age > 120) return null;
    return age;
  }

  /// Lấy tiến độ Onboarding từ server
  Future<OnboardingProgress?> fetchOnboardingStatus() async {
    try {
      final res = await _api.get('/api/user/onboarding');
      if (res['success'] == true && res['data'] is Map) {
        return OnboardingProgress.fromJson(
          Map<String, dynamic>.from(res['data'] as Map),
        );
      }
    } catch (e) {
      debugPrint('[OnboardingService] Fetch status error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>> bootstrapRegistration({
    required String name,
    String? phone,
  }) async {
    try {
      return await _api.post('/api/mobile/registration-bootstrap', {
        'name': name.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      });
    } catch (e) {
      return {'success': false, 'error': 'Unable to bootstrap account: $e'};
    }
  }

  /// Cập nhật thông tin profile (họ tên, phone, ngày sinh, và dữ liệu khảo sát cá nhân hóa)
  Future<Map<String, dynamic>> updateProfile({
    required String name,
    String? phone,
    String? dateOfBirth,
    double? avgDailyDistanceKm,
    String? usagePurpose,
    double? typicalSocWhenCharge,
  }) async {
    try {
      final dobErr = validateDateOfBirth(dateOfBirth);
      if (dobErr != null) {
        return {'success': false, 'error': dobErr};
      }

      final serverDob = toServerDateFormat(dateOfBirth);

      final payload = <String, dynamic>{
        'name': name.trim(),
        if (phone != null) 'phone': phone.trim(),
        if (serverDob != null)
          'dateOfBirth': serverDob
        else
          'dateOfBirth': null,
        if (avgDailyDistanceKm != null) 'avgDailyDistanceKm': avgDailyDistanceKm,
        if (usagePurpose != null && usagePurpose.isNotEmpty)
          'usagePurpose': usagePurpose,
        if (typicalSocWhenCharge != null)
          'typicalSocWhenCharge': typicalSocWhenCharge,
      };

      final res = await _api.patch('/api/user/profile', payload);
      return res;
    } catch (e) {
      return {'success': false, 'error': 'Lỗi cập nhật hồ sơ: $e'};
    }
  }

  /// Xác nhận hoàn tất Onboarding
  /// Điều kiện: User có họ tên và ít nhất 1 xe active
  Future<Map<String, dynamic>> completeOnboarding({
    String shellyStatus = 'skipped',
  }) async {
    try {
      final res = await _api.post('/api/user/onboarding/complete', {
        'shellyStatus': shellyStatus,
      });
      return res;
    } catch (e) {
      return {'success': false, 'error': 'Lỗi hoàn tất onboarding: $e'};
    }
  }
}

/// Provider cho OnboardingService
final onboardingServiceProvider = Provider<OnboardingService>((ref) {
  return OnboardingService();
});
