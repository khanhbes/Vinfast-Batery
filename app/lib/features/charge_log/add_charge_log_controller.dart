import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/charge_log_model.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/repositories/charge_log_repository.dart';
import '../../data/services/charge_tracking_service.dart';

// ============================================================================
// State class cho AddChargeLog
// ============================================================================

/// Trạng thái của form nhập nhật ký sạc
class AddChargeLogState {
  final bool isLoading;
  final bool isSaved;
  final String? errorMessage;
  final VehicleModel? vehicle;

  // Form values
  final DateTime? startTime;
  final DateTime? endTime;

  const AddChargeLogState({
    this.isLoading = false,
    this.isSaved = false,
    this.errorMessage,
    this.vehicle,
    this.startTime,
    this.endTime,
  });

  AddChargeLogState copyWith({
    bool? isLoading,
    bool? isSaved,
    String? errorMessage,
    VehicleModel? vehicle,
    DateTime? startTime,
    DateTime? endTime,
    bool clearError = false,
    bool clearStartTime = false,
    bool clearEndTime = false,
  }) {
    return AddChargeLogState(
      isLoading: isLoading ?? this.isLoading,
      isSaved: isSaved ?? this.isSaved,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      vehicle: vehicle ?? this.vehicle,
      startTime: clearStartTime ? null : (startTime ?? this.startTime),
      endTime: clearEndTime ? null : (endTime ?? this.endTime),
    );
  }
}

// ============================================================================
// Controller / Notifier (Riverpod StateNotifier)
// ============================================================================

class AddChargeLogNotifier extends StateNotifier<AddChargeLogState> {
  final ChargeLogRepository _repository;

  AddChargeLogNotifier(this._repository)
      : super(const AddChargeLogState());

  /// Load thông tin xe để validation ODO
  Future<void> loadVehicle(String vehicleId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final vehicle = await _repository.getVehicle(vehicleId);
      if (vehicle == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Không tìm thấy xe với ID: $vehicleId',
        );
        return;
      }
      state = state.copyWith(isLoading: false, vehicle: vehicle);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi khi tải thông tin xe: ${e.toString()}',
      );
    }
  }

  /// Cập nhật thời gian bắt đầu sạc
  void setStartTime(DateTime dateTime) {
    state = state.copyWith(startTime: dateTime, clearError: true);
  }

  /// Cập nhật thời gian kết thúc sạc
  void setEndTime(DateTime dateTime) {
    state = state.copyWith(endTime: dateTime, clearError: true);
  }

  /// Xóa thông báo lỗi
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  // --------------------------------------------------------------------------
  // VALIDATION
  // --------------------------------------------------------------------------

  /// Validate mức pin (0-100, là số nguyên)
  String? validateBatteryPercent(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName không được để trống';
    }
    final intValue = int.tryParse(value.trim());
    if (intValue == null) {
      return '$fieldName phải là số nguyên';
    }
    if (intValue < 0 || intValue > 100) {
      return '$fieldName phải nằm trong khoảng 0-100';
    }
    return null;
  }

  /// Validate ODO
  String? validateOdo(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'ODO không được để trống';
    }
    final intValue = int.tryParse(value.trim());
    if (intValue == null) {
      return 'ODO phải là số nguyên';
    }
    if (state.vehicle != null && intValue < state.vehicle!.currentOdo) {
      return 'ODO ($intValue km) phải ≥ ODO hiện tại (${state.vehicle!.currentOdo} km)';
    }
    return null;
  }

  /// Validate toàn bộ form trước khi lưu
  String? validateForm({
    required String startBattery,
    required String endBattery,
    required String odo,
  }) {
    // Validate pin trước sạc
    final startErr = validateBatteryPercent(startBattery, 'Mức pin trước sạc');
    if (startErr != null) return startErr;

    // Validate pin sau sạc
    final endErr = validateBatteryPercent(endBattery, 'Mức pin sau sạc');
    if (endErr != null) return endErr;

    // endBatteryPercent > startBatteryPercent
    final startVal = int.parse(startBattery.trim());
    final endVal = int.parse(endBattery.trim());
    if (endVal <= startVal) {
      return 'Mức pin sau sạc ($endVal%) phải lớn hơn mức pin trước sạc ($startVal%)';
    }

    // Validate ODO
    final odoErr = validateOdo(odo);
    if (odoErr != null) return odoErr;

    // Validate thời gian
    if (state.startTime == null) {
      return 'Vui lòng chọn thời gian bắt đầu sạc';
    }
    if (state.endTime == null) {
      return 'Vui lòng chọn thời gian kết thúc sạc';
    }
    if (!state.endTime!.isAfter(state.startTime!)) {
      return 'Thời gian kết thúc phải sau thời gian bắt đầu sạc';
    }

    // Validate overlap với charge session đang chạy
    final chargeService = ChargeTrackingService();
    if (chargeService.isCharging) {
      return 'Đang có phiên sạc đang chạy. Vui lòng kết thúc phiên sạc trước khi nhập thủ công.';
    }

    return null; // Hợp lệ
  }

  // --------------------------------------------------------------------------
  // SAVE
  // --------------------------------------------------------------------------

  /// Lưu nhật ký sạc vào Firestore
  Future<bool> saveChargeLog({
    required String startBattery,
    required String endBattery,
    required String odo,
    required String vehicleId,
  }) async {
    // Validate form
    final error = validateForm(
      startBattery: startBattery,
      endBattery: endBattery,
      odo: odo,
    );
    if (error != null) {
      state = state.copyWith(errorMessage: error);
      return false;
    }

    // Set loading
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final chargeLog = ChargeLogModel(
        vehicleId: vehicleId,
        startTime: state.startTime!,
        endTime: state.endTime!,
        startBatteryPercent: int.parse(startBattery.trim()),
        endBatteryPercent: int.parse(endBattery.trim()),
        odoAtCharge: int.parse(odo.trim()),
      );

      await _repository.saveChargeLogAndUpdateOdo(
        chargeLog: chargeLog,
        vehicleId: vehicleId,
        newOdo: chargeLog.odoAtCharge,
      );

      state = state.copyWith(isLoading: false, isSaved: true);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi khi lưu nhật ký sạc: ${e.toString()}',
      );
      return false;
    }
  }
}

// ============================================================================
// Riverpod Provider
// ============================================================================

final addChargeLogProvider =
    StateNotifierProvider.autoDispose<AddChargeLogNotifier, AddChargeLogState>(
  (ref) {
    final repository = ref.watch(chargeLogRepositoryProvider);
    return AddChargeLogNotifier(repository);
  },
);
