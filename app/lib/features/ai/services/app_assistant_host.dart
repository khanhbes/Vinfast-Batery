import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/beta_capabilities.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/session_service.dart';
import '../../../core/widgets/app_popup.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/services/push_notification_service.dart';
import '../../../data/services/range_estimator.dart';
import '../../../data/services/server_smart_charger_service.dart';
import '../../../data/services/shelly_connection_coordinator.dart';
import '../../../data/services/smart_charge_preferences_service.dart';
import '../../../data/services/trip_energy_model.dart';
import '../../achievements/achievements_screen.dart';
import '../../battery_monitor/battery_monitor_screen.dart';
import '../../maintenance/maintenance_screen.dart';
import '../../notifications/notification_center_screen.dart';
import '../../settings/assistant_memory_screen.dart';
import '../../settings/vehicle_garage_screen.dart';
import '../../smart_charging/shelly_connect_screen.dart';
import '../../trip_planner/trip_planner_screen.dart';
import '../controllers/smart_charging_controller.dart';
import 'hybrid_assistant_engine.dart';
import 'learning_flow.dart';
import '../../../core/providers/entitlement_provider.dart';
import '../../../core/services/pinova_api.dart';
import '../../../data/models/entitlement.dart';
import '../../battery_monitor/battery_health_screen.dart';
import '../../premium/premium_screen.dart';
import '../../smart_charging/night_charging_screen.dart';
import '../../support/help_center_screen.dart';
import '../../support/support_repository.dart';

/// BatteryBot v2 actions executed with the same providers/repositories the
/// screens use (Task 124). Charging and reminders do not pass through here:
/// they stay on the verified on-device gateway.
class AppAssistantActionHost implements AssistantActionHost {
  AppAssistantActionHost(this.ref, {SmartChargePreferencesService? preferences})
    : _preferences = preferences ?? SmartChargePreferencesService() {
    unawaited(_loadTariff());
    unawaited(_loadPush());
  }

  final Ref ref;
  final SmartChargePreferencesService _preferences;
  double? _tariff;
  bool? _push;

  static const _tabs = {
    'overview': 0,
    'charge': 1,
    'history': 2,
    'settings': 3,
  };
  static const _tabNames = ['overview', 'charge', 'history', 'settings'];

  Future<void> _loadTariff() async {
    try {
      _tariff = (await _preferences.load()).tariffVndPerKwh;
    } on Object {
      _tariff = null;
    }
  }

  Future<void> _loadPush() async {
    try {
      _push = await PushNotificationService.instance.isEnabledByUser();
    } on Object {
      _push = null;
    }
  }

  VehicleModel? get _vehicle => ref.read(vehicleContextProvider).vehicle;

  @override
  Map<String, dynamic> context() {
    final vehicle = _vehicle;
    final vehicles = ref.read(allVehiclesProvider).valueOrNull ?? const [];
    final tab = ref.read(currentTabProvider);
    final connection = ShellyConnectionCoordinator.shared.current;
    double? target;
    if (vehicle != null) {
      try {
        target = ref
            .read(
              smartChargingControllerProvider(
                SmartChargingControllerArgs(
                  vehicleId: vehicle.vehicleId,
                  currentSoc: vehicle.currentBattery.toDouble(),
                ),
              ),
            )
            .draft
            .targetSoc;
      } on Object {
        target = null;
      }
    }
    return {
      'screen': tab >= 0 && tab < _tabNames.length
          ? _tabNames[tab]
          : 'overview',
      'vehicleId': vehicle?.vehicleId,
      if (vehicle != null)
        'vehicle': {
          'name': vehicle.nickname?.trim().isNotEmpty == true
              ? vehicle.nickname
              : vehicle.vehicleName,
          'model': vehicle.vinfastModelName ?? vehicle.vehicleName,
          if (vehicle.hasBatteryData) 'batteryPercent': vehicle.currentBattery,
          'odoKm': vehicle.currentOdo,
          if (vehicle.hasSohData) 'sohPercent': vehicle.stateOfHealth,
          if (vehicle.batteryCapacityWh > 0)
            'capacityWh': vehicle.batteryCapacityWh,
          if (vehicle.hasEfficiencyData)
            'kmPerPercent': vehicle.defaultEfficiency,
          'rangeKm': estimateRangeKm(vehicle)?.round(),
          'targetSoc': ?target?.round(),
        },
      'vehicles': [
        for (final item in vehicles.where((v) => !v.isArchived).take(10))
          {
            'name': item.nickname?.trim().isNotEmpty == true
                ? item.nickname
                : item.vehicleName,
          },
      ],
      'tariffVndPerKwh': ?_tariff?.round(),
      'shellyLinked': connection.isLinked,
      'shellyState': connection.connectionLabel,
      if (!connection.readyForControl)
        'chargeLockReason': connection.chatLockExplanation,
      if (connection.status != null) 'shellyRelayOn': connection.status!.relay,
      'settings': {'pushNotifications': ?_push, 'language': 'vi'},
    };
  }

  NavigatorState? get _navigator => AppPopup.navigatorKey.currentState;

  @override
  Future<bool> navigate(String screen, {String? sessionId}) async {
    final navigator = _navigator;
    if (navigator == null) return false;
    // Close the assistant (and any page above the shell) first.
    navigator.popUntil((route) => route.isFirst);
    final tab = _tabs[screen];
    if (tab != null) {
      ref.read(currentTabProvider.notifier).state = tab;
      return true;
    }
    final vehicle = _vehicle;
    if (screen == 'session_detail') {
      if (vehicle != null && sessionId != null) {
        ref.read(pendingSmartChargeTargetProvider.notifier).state = (
          vehicleId: vehicle.vehicleId,
          sessionId: sessionId,
        );
      }
      ref.read(currentTabProvider.notifier).state = 2;
      return true;
    }
    final Widget? page = switch (screen) {
      'maintenance' => const MaintenanceScreen(),
      'achievements' => const AchievementsScreen(),
      'battery_monitor' => BatteryMonitorScreen(vehicle: vehicle),
      'trip_planner' =>
        vehicle == null ? null : TripPlannerScreen(vehicle: vehicle),
      'notifications' => const NotificationCenterScreen(),
      'garage' || 'vehicle_specs' => const VehicleGarageScreen(),
      'shelly_setup' => const ShellyConnectScreen(),
      'assistant_memory' => const AssistantMemoryScreen(),
      // QA 135
      'premium' => const PremiumScreen(),
      'help' => const HelpCenterScreen(),
      'night_charging' =>
        vehicle == null
            ? null
            : _gated(
                PremiumFeature.nightCharging,
                NightChargingScreen(
                  vehicleId: vehicle.vehicleId,
                  currentSoc: vehicle.currentBattery.toDouble(),
                  currentOdoKm: vehicle.currentOdo.toDouble(),
                ),
              ),
      'battery_health' =>
        vehicle == null
            ? null
            : _gated(
                PremiumFeature.batteryHealth,
                BatteryHealthScreen(vehicleId: vehicle.vehicleId),
              ),
      _ => null,
    };
    if (page == null) return false;
    unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => page)));
    return true;
  }

  /// The screen, or Pinova Premium pointing at it when the plan lacks it.
  Widget _gated(PremiumFeature feature, Widget page) =>
      ref.read(entitlementProvider).allows(feature)
      ? page
      : PremiumScreen(highlight: feature);

  @override
  Future<bool> prepare(String name, Map<String, dynamic> args) async {
    final vehicle = _vehicle;
    final navigator = _navigator;
    if (navigator == null) return false;
    // QA 135: plan and support screens need no vehicle.
    if (name == 'open_premium') {
      navigator.popUntil((route) => route.isFirst);
      final feature = PremiumFeature.values
          .where((f) => f.id == args['feature'])
          .firstOrNull;
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => PremiumScreen(highlight: feature),
          ),
        ),
      );
      return true;
    }
    if (name == 'contact_support') {
      navigator.popUntil((route) => route.isFirst);
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => HelpCenterScreen(
              draft: (
                category: SupportCategory.parse(args['category']),
                subject: args['subject']?.toString() ?? '',
                message: args['message']?.toString() ?? '',
              ),
            ),
          ),
        ),
      );
      return true;
    }
    if (vehicle == null) return false;
    navigator.popUntil((route) => route.isFirst);
    if (name == 'update_charge_target') {
      // The Charge tab opens its "Đổi mục tiêu" sheet when a target charge
      // runs (raising still needs the ON-style confirmation there).
      final percent = (args['percent'] as num?)?.toDouble();
      if (percent == null || percent < 1 || percent > 100) return false;
      ref.read(pendingChargeTargetSocProvider.notifier).state = (
        vehicleId: vehicle.vehicleId,
        targetSoc: percent,
      );
      ref.read(currentTabProvider.notifier).state = 1;
      return true;
    }
    if (name == 'set_night_plan') {
      final wake = RegExp(
        r'^(\d{1,2}):(\d{2})$',
      ).firstMatch(args['wake_at']?.toString() ?? '');
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => _gated(
              PremiumFeature.nightCharging,
              NightChargingScreen(
                vehicleId: vehicle.vehicleId,
                currentSoc: vehicle.currentBattery.toDouble(),
                currentOdoKm: vehicle.currentOdo.toDouble(),
                initialTarget: (args['target_percent'] as num?)?.toInt(),
                initialWake: wake == null
                    ? null
                    : TimeOfDay(
                        hour: int.parse(wake[1]!),
                        minute: int.parse(wake[2]!),
                      ),
              ),
            ),
          ),
        ),
      );
      return true;
    }
    if (name == 'prepare_target_charging') {
      final percent = (args['percent'] as num?)?.toDouble();
      if (percent == null || percent < 1 || percent > 100) return false;
      ref.read(pendingChargeTargetSocProvider.notifier).state = (
        vehicleId: vehicle.vehicleId,
        targetSoc: percent,
      );
      ref.read(currentTabProvider.notifier).state = 1;
      return true;
    }
    if (name == 'plan_trip' && BetaCapabilities.tripPlanner) {
      TripSpeed speed(Object? value) => switch (value) {
        'slow' => TripSpeed.slow,
        'fast' => TripSpeed.fast,
        _ => TripSpeed.normal,
      };
      TripWeather weather(Object? value) => switch (value) {
        'rain' => TripWeather.rain,
        'hot' => TripWeather.hot,
        'cold' => TripWeather.cold,
        _ => TripWeather.dry,
      };
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => TripPlannerScreen(
              vehicle: vehicle,
              initialDestination: args['destination']?.toString(),
              initialDistanceKm: (args['distance_km'] as num?)?.toDouble(),
              initialConditions: TripConditions(
                speed: speed(args['speed']),
                riders: (args['riders'] as num?)?.toInt() == 2 ? 2 : 1,
                cargoKg: ((args['cargo_kg'] as num?)?.toDouble() ?? 0).clamp(
                  0,
                  40,
                ),
                weather: weather(args['weather']),
                hilly: args['hilly'] == true,
                roundTrip: args['round_trip'] == true,
              ),
            ),
          ),
        ),
      );
      return true;
    }
    return false;
  }

  @override
  Future<AssistantUndo?> apply(String name, Map<String, dynamic> args) async {
    final vehicle = _vehicle;
    switch (name) {
      case 'update_battery_level':
        if (vehicle == null) {
          throw const AssistantActionError('Bạn hãy chọn xe trước.');
        }
        final percent = (args['percent'] as num).toInt().clamp(0, 100);
        final previous = vehicle.currentBattery;
        await _writeVehicle(vehicle.vehicleId, {
          'currentBattery': percent,
          'lastBatteryPercent': percent,
          'hasBatteryData': true,
        });
        final reading = await _logReading(
          vehicle.vehicleId,
          soc: percent.toDouble(),
        );
        return AssistantUndo('mức pin về $previous%', () async {
          await _writeVehicle(vehicle.vehicleId, {
            'currentBattery': previous,
            'lastBatteryPercent': previous,
          });
          await _voidReading(vehicle.vehicleId, reading);
        });
      case 'update_odometer':
        if (vehicle == null) {
          throw const AssistantActionError('Bạn hãy chọn xe trước.');
        }
        final km = (args['km'] as num).toInt();
        final previous = vehicle.currentOdo;
        if (km < previous) {
          throw AssistantActionError(
            'ODO mới ($km km) nhỏ hơn ODO hiện tại ($previous km). Nếu nhập nhầm trước đó, hãy sửa trong Xe của tôi.',
          );
        }
        await _writeVehicle(vehicle.vehicleId, {
          'currentOdo': km,
          'hasOdoData': true,
        });
        final reading = await _logReading(
          vehicle.vehicleId,
          odoKm: km.toDouble(),
        );
        return AssistantUndo('ODO về $previous km', () async {
          await _writeVehicle(vehicle.vehicleId, {'currentOdo': previous});
          await _voidReading(vehicle.vehicleId, reading);
        });
      case 'select_vehicle':
        final wanted = args['vehicle_name']?.toString().toLowerCase() ?? '';
        final vehicles = ref.read(allVehiclesProvider).valueOrNull ?? const [];
        VehicleModel? match;
        for (final item in vehicles.where((v) => !v.isArchived)) {
          final names = [
            item.nickname ?? '',
            item.vehicleName,
          ].map((n) => n.toLowerCase());
          if (names.contains(wanted)) match = item;
        }
        if (match == null) {
          throw const AssistantActionError(
            'Không tìm thấy xe đó trong danh sách xe của bạn.',
          );
        }
        final previous = ref.read(selectedVehicleIdProvider);
        await _select(match.vehicleId);
        return previous.isEmpty
            ? null
            : AssistantUndo('chọn lại xe trước', () => _select(previous));
      case 'set_target_soc':
        if (vehicle == null) {
          throw const AssistantActionError('Bạn hãy chọn xe trước.');
        }
        final controller = ref.read(
          smartChargingControllerProvider(
            SmartChargingControllerArgs(
              vehicleId: vehicle.vehicleId,
              currentSoc: vehicle.currentBattery.toDouble(),
            ),
          ).notifier,
        );
        final previous = controller.currentUiState.draft.targetSoc;
        controller.updateDraft(targetSoc: (args['percent'] as num).toDouble());
        return AssistantUndo(
          'mục tiêu sạc về ${previous.round()}%',
          () async => controller.updateDraft(targetSoc: previous),
        );
      case 'set_electricity_price':
        final previous = _tariff;
        final value = (args['vnd_per_kwh'] as num).toDouble();
        await _preferences.saveTariff(value);
        _tariff = value;
        return AssistantUndo(
          previous == null
              ? 'bỏ giá điện vừa đặt'
              : 'giá điện về ${previous.round()} đ/kWh',
          () async {
            await _preferences.saveTariff(previous);
            _tariff = previous;
          },
        );
      case 'set_app_setting':
        return _applySetting(
          args['setting']?.toString(),
          args['value']?.toString(),
        );
      // QA 135: the plan actions run on the server; no undo.
      case 'start_trial':
        try {
          await ref.read(entitlementProvider.notifier).startTrial();
        } on PinovaApiException catch (error) {
          throw AssistantActionError(
            error.message ?? 'Chưa mở được dùng thử. Hãy thử lại.',
          );
        }
        return null;
      case 'apply_promo_code':
        try {
          await ref
              .read(entitlementProvider.notifier)
              .redeemPromo(args['code']?.toString() ?? '');
        } on PinovaApiException catch (error) {
          throw AssistantActionError(
            error.message ?? 'Chưa kiểm tra được mã. Hãy thử lại.',
          );
        }
        return null;
    }
    throw const AssistantActionError('Thao tác này chưa được hỗ trợ.');
  }

  Future<AssistantUndo?> _applySetting(String? setting, String? value) async {
    switch (setting) {
      case 'push_notifications':
        final push = PushNotificationService.instance;
        final previous = await push.isEnabledByUser();
        final wanted = value == 'on';
        final result = await push.setEnabledByUser(wanted);
        _push = result;
        if (wanted && !result) {
          throw const AssistantActionError(
            'Điện thoại chưa cho phép thông báo. Bạn bật quyền thông báo cho app trong Cài đặt của điện thoại.',
          );
        }
        return previous == result
            ? null
            : AssistantUndo(
                previous ? 'bật lại thông báo đẩy' : 'tắt thông báo đẩy',
                () async => _push = await push.setEnabledByUser(previous),
              );
    }
    throw const AssistantActionError('Cài đặt này chưa được hỗ trợ.');
  }

  /// Task 127: a battery/ODO update from chat is also a learning reading
  /// (two readings without a charge between become a ride). Best effort.
  Future<String?> _logReading(
    String vehicleId, {
    double? soc,
    double? odoKm,
  }) async {
    ServerSmartChargerService? api;
    try {
      api = ServerSmartChargerService();
      final result = await api.addBatteryReading(
        vehicleId,
        soc: soc,
        odoKm: odoKm,
        source: 'chat',
      );
      unawaited(TrainingReadiness.check(result.status));
      return result.readingId.isEmpty ? null : result.readingId;
    } on Object {
      return null;
    } finally {
      api?.close();
    }
  }

  Future<void> _voidReading(String vehicleId, String? readingId) async {
    if (readingId == null) return;
    ServerSmartChargerService? api;
    try {
      api = ServerSmartChargerService();
      await api.voidBatteryReading(vehicleId, readingId);
    } on Object {
      // The vehicle value is already restored; the reading stays harmless.
    } finally {
      api?.close();
    }
  }

  Future<void> _writeVehicle(
    String vehicleId,
    Map<String, dynamic> fields,
  ) async {
    await FirebaseFirestore.instance
        .collection('Vehicles')
        .doc(vehicleId)
        .update({...fields, 'updatedAt': FieldValue.serverTimestamp()});
    ref.invalidate(vehicleProvider(vehicleId));
    ref.invalidate(allVehiclesProvider);
  }

  Future<void> _select(String vehicleId) async {
    await SessionService().setSelectedVehicleId(vehicleId);
    ref.read(selectedVehicleIdProvider.notifier).state = vehicleId;
  }
}
