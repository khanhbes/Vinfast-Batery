import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'api_service.dart';
import '../models/onboarding_draft.dart';
import 'api_result.dart';

/// Dữ liệu tiến độ Onboarding
class OnboardingProgress {
  final int registrationFlowVersion;
  final bool isCompleted;
  final String? onboardingCompletedAt;
  final String name;
  final String phone;
  final String? dateOfBirth;
  final double? avgDailyDistanceKm;
  final String? usagePurpose;
  final double? typicalSocWhenCharge;
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
    this.avgDailyDistanceKm,
    this.usagePurpose,
    this.typicalSocWhenCharge,
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
      avgDailyDistanceKm: (profile['avgDailyDistanceKm'] as num?)?.toDouble(),
      usagePurpose: profile['usagePurpose']?.toString(),
      typicalSocWhenCharge: (profile['typicalSocWhenCharge'] as num?)?.toDouble(),
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
  final OnboardingDraftRepository _drafts;

  OnboardingService({ApiService? api, OnboardingDraftRepository? drafts})
      : _api = api ?? ApiService(),
        _drafts = drafts ?? OnboardingDraftRepository();

  Future<OnboardingDraft?> loadDraft(String uid) => _drafts.load(uid);

  Future<bool> saveDraft(OnboardingDraft draft) => _drafts.save(draft);

  Future<void> clearDraft(String uid) => _drafts.clear(uid);

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
    if (age < 16) {
      return 'Người dùng phải từ đủ 16 tuổi trở lên';
    }
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
      debugPrint('[OnboardingService] Bootstrap error: $e');
      return {'success': false, 'error': 'Không thể khởi tạo tài khoản.', 'code': 'bootstrapFailed', 'retryable': true};
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
        'dateOfBirth': serverDob,
        if (avgDailyDistanceKm != null) 'avgDailyDistanceKm': avgDailyDistanceKm,
        if (usagePurpose != null && usagePurpose.isNotEmpty)
          'usagePurpose': usagePurpose,
        if (typicalSocWhenCharge != null) 'typicalSocWhenCharge': typicalSocWhenCharge,
      };

      final res = await _api.patch('/api/user/profile', payload);
      return res;
    } catch (e) {
      debugPrint('[OnboardingService] Profile update error: $e');
      return {'success': false, 'error': 'Không thể cập nhật hồ sơ.', 'code': 'profileUpdateFailed', 'retryable': true};
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
      debugPrint('[OnboardingService] Complete onboarding error: $e');
      return {'success': false, 'error': 'Không thể hoàn tất onboarding.', 'code': 'onboardingCompleteFailed', 'retryable': true};
    }
  }

  Future<ApiResult<Map<String, dynamic>>> commitDraft(OnboardingDraft draft) async {
    final result = await _api.postResult<Map<String, dynamic>>(
      '/api/mobile/onboarding/commit',
      {
        'schemaVersion': 1,
        'operationId': draft.operationId,
        'profile': {
          'name': draft.name,
          if (draft.phone != null) 'phone': draft.phone,
          if (draft.dateOfBirth != null)
            'dateOfBirth': toServerDateFormat(draft.dateOfBirth),
          if (draft.avgDailyDistanceKm != null)
            'avgDailyDistanceKm': draft.avgDailyDistanceKm,
          if (draft.usagePurpose != null) 'usagePurpose': draft.usagePurpose,
          if (draft.typicalSocWhenCharge != null)
            'typicalSocWhenCharge': draft.typicalSocWhenCharge,
        },
        'vehicle': {
          'catalogId': draft.catalogId,
          if (draft.nickname != null) 'nickname': draft.nickname,
          if (draft.licensePlate != null) 'licensePlate': draft.licensePlate,
          'initialOdo': draft.initialOdo,
        },
        'shellyStatus': draft.shellyStatus,
      },
      idempotencyKey: draft.operationId,
      decode: (value) => value is Map<String, dynamic>
          ? value
          : value is Map
              ? Map<String, dynamic>.from(value)
              : null,
    );
    return result;
  }
}

/// Foreground/connection recovery worker. It is intentionally single-flight:
/// multiple AuthGate rebuilds or connectivity callbacks cannot submit the same
/// onboarding operation concurrently.
class OnboardingSyncCoordinator {
  static final OnboardingSyncCoordinator shared = OnboardingSyncCoordinator();

  static const _backoff = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 3),
    Duration(hours: 6),
  ];

  OnboardingSyncCoordinator({OnboardingService? service})
      : _service = service ?? OnboardingService();

  final OnboardingService _service;
  bool _running = false;

  Future<ApiResult<Map<String, dynamic>>?> syncIfPending(String uid) async {
    if (_running) return null;
    _running = true;
    try {
      final draft = await _service.loadDraft(uid);
      if (draft == null || draft.state == OnboardingDraftState.failedPermanent) {
        return null;
      }
      if (draft.nextAttemptAt != null &&
          draft.nextAttemptAt!.isAfter(DateTime.now().toUtc())) {
        return null;
      }
      if (draft.attemptCount >= _backoff.length) return null;
      // Offline is an expected state, not a failed delivery attempt. The
      // connectivity callback will retry after the network recovers.
      if (await Connectivity().checkConnectivity() == ConnectivityResult.none) {
        return null;
      }
      final syncing = draft.copyWith(
        state: OnboardingDraftState.syncing,
        attemptCount: draft.attemptCount + 1,
        revision: draft.revision + 1,
        updatedAt: DateTime.now().toUtc(),
      );
      await _service.saveDraft(syncing);
      final result = await _service.commitDraft(syncing);
      if (result.success) {
        // Do not delete the durable draft until the authoritative profile and
        // vehicle readback confirms the commit. A lost response can then be
        // retried safely with the same idempotency key.
        final confirmed = await _service.fetchOnboardingStatus();
        if (confirmed?.isCompleted == true && confirmed?.hasVehicle == true) {
          await _service.clearDraft(uid);
        } else {
          await _service.saveDraft(syncing.copyWith(
            state: OnboardingDraftState.failedRetryable,
            nextAttemptAt: DateTime.now().toUtc().add(_backoff.first),
            lastErrorCode: 'syncVerificationPending',
            lastErrorMessage: 'Đang xác minh dữ liệu đã đồng bộ.',
            updatedAt: DateTime.now().toUtc(),
          ));
        }
      } else {
        final retryIndex = (syncing.attemptCount - 1).clamp(0, _backoff.length - 1).toInt();
        await _service.saveDraft(syncing.copyWith(
          state: result.retryable
              ? OnboardingDraftState.failedRetryable
              : OnboardingDraftState.failedPermanent,
          nextAttemptAt: result.retryable
              ? DateTime.now().toUtc().add(_backoff[retryIndex])
              : null,
          lastErrorCode: result.code,
          lastErrorMessage: result.userMessage,
          updatedAt: DateTime.now().toUtc(),
        ));
      }
      return result;
    } finally {
      _running = false;
    }
  }
}

/// Provider cho OnboardingService
final onboardingServiceProvider = Provider<OnboardingService>((ref) {
  return OnboardingService();
});
