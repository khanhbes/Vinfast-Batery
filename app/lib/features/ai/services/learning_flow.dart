import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/app_error_formatter.dart';
import '../../../core/widgets/app_popup.dart';
import '../../../data/models/vehicle_learning_status.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/services/server_smart_charger_service.dart';
import '../../settings/personal_ai_settings_screen.dart';
import '../widgets/battery_reading_sheet.dart';

/// Task 127: data is collected silently; when a model has enough new data
/// the owner is told once (notification + in-app hint) and trains it from
/// "AI cá nhân". Never trains on its own.
abstract final class TrainingReadiness {
  static String _key(String vehicleId, String model) =>
      'training_ready_notified_${vehicleId}_$model';

  /// Models that just became ready and were not announced in this training
  /// cycle (the trained count changes after every training).
  static Future<List<String>> newlyReady(VehicleLearningStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    final ready = <String>[];
    for (final (model, value) in [
      ('charge', status.charge),
      ('trip', status.trip),
    ]) {
      if (!value.ready) continue;
      final key = _key(status.vehicleId, model);
      final marker = '${value.trained}';
      if (prefs.getString(key) == marker) continue;
      await prefs.setString(key, marker);
      ready.add(model);
    }
    return ready;
  }

  /// Notify for models that crossed their threshold; returns them.
  static Future<List<String>> check(VehicleLearningStatus? status) async {
    if (status == null || !status.consentEnabled || status.vehicleId.isEmpty) {
      return const [];
    }
    final ready = await newlyReady(status);
    if (ready.isEmpty) return ready;
    final names = ready
        .map((m) => m == 'charge' ? 'dự đoán sạc' : 'hao pin theo lộ trình')
        .join(' và ');
    try {
      await NotificationService().showTrainingReady(
        vehicleId: status.vehicleId,
        message:
            'Đã đủ dữ liệu mới để huấn luyện mô hình $names. Bấm để mở AI cá nhân và huấn luyện.',
      );
    } on Object {
      // The in-app hint below still tells the owner.
    }
    return ready;
  }

  /// Re-read the server status (after a confirmation, on app open) and tell
  /// the owner in-app as well when a model just became ready.
  static Future<void> refresh(
    String vehicleId, {
    ServerSmartChargerService? service,
  }) async {
    if (vehicleId.isEmpty) return;
    ServerSmartChargerService? api;
    try {
      api = service ?? ServerSmartChargerService();
      final status = await api.learningStatus(vehicleId);
      final ready = await check(status);
      if (ready.isEmpty) return;
      AppPopup.showInfo(
        'Đủ dữ liệu để huấn luyện AI',
        detail: 'Mở AI cá nhân và bấm Huấn luyện để dự đoán sát xe bạn hơn.',
        action: () {
          final context = AppPopup.navigatorKey.currentContext;
          if (context != null) openSettings(context, vehicleId);
        },
      );
    } on Object {
      // Readiness is a hint; never block the flow that called it.
    } finally {
      if (service == null) api?.close();
    }
  }

  static final Set<String> _checkedThisRun = {};

  /// [refresh] at most once per vehicle per app run (app open).
  static void refreshOnce(String vehicleId) {
    if (vehicleId.isEmpty || !_checkedThisRun.add(vehicleId)) return;
    unawaited(refresh(vehicleId));
  }

  static void openSettings(BuildContext context, String vehicleId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PersonalAiSettingsScreen(vehicleId: vehicleId),
      ),
    );
  }
}

/// Open the reading sheet, save to the server, report what was learned.
abstract final class BatteryReadingFlow {
  static Future<BatteryReadingResult?> run(
    BuildContext context, {
    required String vehicleId,
    double? currentSoc,
    double? currentOdoKm,
    ServerSmartChargerService? service,
    DashboardReadFn? reader,
  }) async {
    final input = await BatteryReadingSheet.show(
      context,
      initialSoc: currentSoc,
      currentOdoKm: currentOdoKm,
      reader: reader,
    );
    if (input == null) return null;
    final api = service ?? ServerSmartChargerService();
    try {
      final result = await api.addBatteryReading(
        vehicleId,
        soc: input.soc,
        odoKm: input.odoKm,
        source: input.source,
      );
      final km = result.rideKm;
      AppPopup.showSuccess(
        km == null
            ? 'Đã lưu số trên đồng hồ xe.'
            : 'Đã lưu. Ghi nhận chuyến ${km.toStringAsFixed(1)} km dùng '
                  '${result.rideUsedPct?.round() ?? 0}% pin để AI học.',
      );
      await TrainingReadiness.check(result.status);
      return result;
    } catch (error) {
      AppPopup.showError(
        'Chưa lưu được',
        detail: AppErrorFormatter.format(error),
      );
      return null;
    } finally {
      if (service == null) api.close();
    }
  }
}
