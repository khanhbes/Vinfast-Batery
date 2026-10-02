import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/vehicle_model.dart';
import '../providers/app_state_providers.dart';
import '../providers/vehicle_context_provider.dart';
import '../widgets/battery_bot_mascot.dart';

/// Coordinator quản lý ngữ cảnh và bong bóng thoại chủ động (Proactive Assistant)
class AssistantContextCoordinator extends ChangeNotifier {
  AssistantContextCoordinator({
    this.cooldownDuration = const Duration(minutes: 15),
    this.bubbleDisplayDuration = const Duration(seconds: 6),
  });

  final Duration cooldownDuration;
  final Duration bubbleDisplayDuration;

  bool _isBubbleVisible = false;
  String? _bubbleText;
  BatteryBotMood _bubbleMood = BatteryBotMood.idle;
  List<String> _quickActionChips = const [];
  Timer? _bubbleTimer;

  final Map<String, DateTime> _triggerCooldowns = {};

  bool get isBubbleVisible => _isBubbleVisible;
  String? get bubbleText => _bubbleText;
  BatteryBotMood get bubbleMood => _bubbleMood;
  List<String> get quickActionChips => _quickActionChips;

  /// Hiển thị bóng bóng thoại có hẹn giờ tự đóng
  void showBubble(
    String text, {
    BatteryBotMood mood = BatteryBotMood.idle,
    List<String> chips = const [],
    Duration? duration,
  }) {
    _bubbleTimer?.cancel();
    _bubbleText = text;
    _bubbleMood = mood;
    _quickActionChips = chips;
    _isBubbleVisible = true;
    notifyListeners();

    _bubbleTimer = Timer(duration ?? bubbleDisplayDuration, () {
      dismissBubble();
    });
  }

  /// Ẩn bóng bóng thoại
  void dismissBubble() {
    _bubbleTimer?.cancel();
    _bubbleTimer = null;
    if (_isBubbleVisible) {
      _isBubbleVisible = false;
      notifyListeners();
    }
  }

  /// Kiểm tra và kích hoạt thông điệp chủ động theo ngữ cảnh
  bool evaluateContext({
    VehicleModel? vehicle,
    int? currentTab,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();

    // 1. Cảnh báo pin yếu (< 20%)
    if (vehicle != null && vehicle.currentBattery < 20) {
      if (_canTrigger('low_battery_${vehicle.vehicleId}', currentTime)) {
        _recordTrigger('low_battery_${vehicle.vehicleId}', currentTime);
        showBubble(
          'Pin xe chỉ còn ${vehicle.currentBattery}%. Bạn có muốn mình chuẩn bị lịch sạc thông minh không?',
          mood: BatteryBotMood.thinking,
          chips: const ['Làm sao dừng sạc?', 'Kết nối Shelly', 'Xem pin ở đâu?'],
        );
        return true;
      }
    }

    // 2. Chào buổi sáng (06:00 - 08:59)
    if (currentTime.hour >= 6 && currentTime.hour < 9) {
      final dateKey = 'morning_${currentTime.year}_${currentTime.month}_${currentTime.day}';
      if (_canTrigger(dateKey, currentTime)) {
        _recordTrigger(dateKey, currentTime);
        final batteryText = vehicle != null ? 'Pin xe đang ở mức ${vehicle.currentBattery}%' : 'Hệ thống đã sẵn sàng';
        showBubble(
          'Chào buổi sáng! $batteryText, sẵn sàng cho ngày mới rồi nhé!',
          mood: BatteryBotMood.greeting,
          chips: const ['Xem pin ở đâu?', 'Làm sao dừng sạc?', 'Kết nối Shelly'],
        );
        return true;
      }
    }

    // 3. Gợi ý tại tab Sạc pin (currentTab == 1)
    if (currentTab == 1) {
      if (_canTrigger('tab_charge_hint', currentTime)) {
        _recordTrigger('tab_charge_hint', currentTime);
        showBubble(
          'Mẹo: Bạn có thể cài đặt mức pin mục tiêu 80-90% để bảo vệ tuổi thọ pin lâu nhất!',
          mood: BatteryBotMood.charging,
          chips: const ['Làm sao dừng sạc?', 'Vì sao nút sạc bị khóa?', 'Kết nối Shelly'],
        );
        return true;
      }
    }

    return false;
  }

  bool _canTrigger(String key, DateTime now) {
    final lastTime = _triggerCooldowns[key];
    if (lastTime == null) return true;
    return now.difference(lastTime) >= cooldownDuration;
  }

  void _recordTrigger(String key, DateTime now) {
    _triggerCooldowns[key] = now;
  }

  @override
  void dispose() {
    _bubbleTimer?.cancel();
    super.dispose();
  }
}

/// Provider cho AssistantContextCoordinator
final assistantContextCoordinatorProvider =
    ChangeNotifierProvider<AssistantContextCoordinator>((ref) {
  final coordinator = AssistantContextCoordinator();

  // Tự động lắng nghe thay đổi tab
  ref.listen<int>(currentTabProvider, (_, nextTab) {
    final vehicleContext = ref.read(vehicleContextProvider);
    coordinator.evaluateContext(
      vehicle: vehicleContext.vehicle,
      currentTab: nextTab,
    );
  });

  // Tự động lắng nghe thay đổi xe
  ref.listen(vehicleContextProvider, (_, nextContext) {
    final currentTab = ref.read(currentTabProvider);
    coordinator.evaluateContext(
      vehicle: nextContext.vehicle,
      currentTab: currentTab,
    );
  });

  return coordinator;
});
