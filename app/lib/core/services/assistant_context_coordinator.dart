import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/vehicle_model.dart';
import '../../features/tips/tip_library.dart';
import '../providers/app_state_providers.dart';
import '../providers/vehicle_context_provider.dart';
import '../widgets/battery_bot_mascot.dart';

/// Coordinator quản lý ngữ cảnh và bong bóng thoại chủ động (Proactive Assistant)
class AssistantContextCoordinator extends ChangeNotifier {
  AssistantContextCoordinator({
    this.cooldownDuration = const Duration(minutes: 15),
    this.bubbleDisplayDuration = const Duration(seconds: 6),
    this.idleDockAfter = const Duration(seconds: 6),
    TipLibrary? tips,
  }) : _tips = tips {
    _scheduleIdleDock();
  }

  /// QA 163: the "Mẹo nhỏ" list and its daily switch.
  final TipLibrary? _tips;
  TipLibrary get tips => _tips ?? TipLibrary.instance;

  /// The tip the bubble tells, so a tap opens it in "Mẹo nhỏ".
  String? _bubbleTipId;
  String? get bubbleTipId => _bubbleTipId;

  /// The last bubble of any kind: a tip waits 2 hours after another one.
  DateTime? _lastBubbleAt;
  static const tipAfterOtherBubble = Duration(hours: 2);
  static const tipBubbleDuration = Duration(seconds: 8);

  final Duration cooldownDuration;
  final Duration bubbleDisplayDuration;

  /// The bot tucks into the edge after this long at rest, so it stops
  /// covering cards (QA 130: "sức khỏe pin" sat under it on the Overview).
  /// Scrolling up, a bubble or a tap brings it back.
  final Duration idleDockAfter;
  Timer? _idleDockTimer;

  void _scheduleIdleDock() {
    _idleDockTimer?.cancel();
    _idleDockTimer = Timer(idleDockAfter, () {
      if (_isBubbleVisible) {
        _scheduleIdleDock();
      } else {
        setDocked(true);
      }
    });
  }

  bool _isBubbleVisible = false;
  bool _isDocked = false;
  String? _bubbleText;
  BatteryBotMood _bubbleMood = BatteryBotMood.idle;
  List<String> _quickActionChips = const [];
  Timer? _bubbleTimer;

  final Map<String, DateTime> _triggerCooldowns = {};

  bool get isBubbleVisible => _isBubbleVisible;
  bool get isDocked => _isDocked;

  /// QA 149: while the user scrolls down the bot steps off the screen, so
  /// tiles and history cards no longer slide under it; it comes back tucked
  /// in once the scroll stops.
  bool _isScrollingAway = false;
  bool get isScrollingAway => _isScrollingAway;
  void setScrollingAway(bool away) {
    if (_isScrollingAway == away) return;
    _isScrollingAway = away;
    notifyListeners();
  }

  String? get bubbleText => _bubbleText;
  BatteryBotMood get bubbleMood => _bubbleMood;

  /// QA 151: a short expression for something that just happened (a
  /// finished charge), shown by the floating bot without a bubble.
  BatteryBotMood? _reaction;
  Timer? _reactionTimer;
  static const reactionHold = Duration(seconds: 6);

  void react(BatteryBotMood mood) {
    _reactionTimer?.cancel();
    _reaction = mood;
    notifyListeners();
    _reactionTimer = Timer(reactionHold, () {
      _reaction = null;
      notifyListeners();
    });
  }

  /// The face of the bot when it has nothing to say: the reaction in
  /// progress, else what is really going on (charging), else the hour
  /// (asleep from 23:00 to 05:00).
  BatteryBotMood restingMood({required bool charging, DateTime? now}) {
    final reaction = _reaction;
    if (reaction != null) return reaction;
    if (charging) return BatteryBotMood.charging;
    final hour = (now ?? DateTime.now()).hour;
    return hour >= 23 || hour < 5 ? BatteryBotMood.sleepy : BatteryBotMood.idle;
  }

  List<String> get quickActionChips => _quickActionChips;

  /// Cập nhật trạng thái neo thu nhỏ (Auto-docking) khi người dùng cuộn trang
  void setDocked(bool docked) {
    if (docked) {
      _idleDockTimer?.cancel();
    } else {
      _scheduleIdleDock();
    }
    if (_isDocked != docked) {
      _isDocked = docked;
      notifyListeners();
    }
  }

  /// Hiển thị bóng bóng thoại có hẹn giờ tự đóng
  void showBubble(
    String text, {
    BatteryBotMood mood = BatteryBotMood.idle,
    List<String> chips = const [],
    Duration? duration,
    String? tipId,
  }) {
    _bubbleTimer?.cancel();
    _bubbleText = text;
    _bubbleMood = mood;
    _bubbleTipId = tipId;
    _lastBubbleAt = DateTime.now();
    _quickActionChips = chips;
    _isBubbleVisible = true;
    // A bubble needs the full button to speak from; it tucks in again
    // after the bubble and a pause.
    _isDocked = false;
    _scheduleIdleDock();
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
    bool charging = false,
  }) {
    final currentTime = now ?? DateTime.now();

    // 1. Cảnh báo pin yếu (< 20%). QA 149: never while the vehicle charges
    // (it offered to plan a charge for "9%" during a running one).
    if (vehicle != null && vehicle.currentBattery < 20 && !charging) {
      if (_canTrigger('low_battery_${vehicle.vehicleId}', currentTime)) {
        _recordTrigger('low_battery_${vehicle.vehicleId}', currentTime);
        showBubble(
          'Pin xe chỉ còn ${vehicle.currentBattery}%. Bạn có muốn mình chuẩn bị lịch sạc thông minh không?',
          mood: BatteryBotMood.worried,
          chips: const [
            'Làm sao dừng sạc?',
            'Kết nối Shelly',
            'Xem pin ở đâu?',
          ],
        );
        return true;
      }
    }

    // 2. Chào buổi sáng (06:00 - 08:59), unless turned off (QA 163).
    if (currentTime.hour >= 6 &&
        currentTime.hour < 9 &&
        (!tips.loaded || tips.morningEnabled)) {
      final dateKey =
          'morning_${currentTime.year}_${currentTime.month}_${currentTime.day}';
      if (_canTrigger(dateKey, currentTime)) {
        _recordTrigger(dateKey, currentTime);
        final batteryText = vehicle == null
            ? 'Hệ thống đã sẵn sàng'
            : charging
            ? 'Xe đang sạc'
            : 'Pin xe đang ở mức ${vehicle.currentBattery}%';
        showBubble(
          'Chào buổi sáng! $batteryText, sẵn sàng cho ngày mới rồi nhé!',
          mood: BatteryBotMood.greeting,
          chips: const [
            'Xem pin ở đâu?',
            'Làm sao dừng sạc?',
            'Kết nối Shelly',
          ],
        );
        return true;
      }
    }

    // No tip bubble on the Charge tab: it covered the % dial and repeated
    // the "80% · Bảo vệ pin · Khuyên dùng" chip right below it (QA 129).

    // 3. QA 163 (owner's choice): one tip a day, for this moment and this
    // battery, never on the Charge tab, 2 hours after another bubble.
    final last = _lastBubbleAt;
    if (currentTab != AppTab.charge &&
        tips.loaded &&
        tips.dailyEnabled &&
        !tips.toldToday(currentTime) &&
        (last == null || currentTime.difference(last) >= tipAfterOtherBubble)) {
      final leadAcid = _leadAcid(vehicle);
      final tip = tips.today(
        now: currentTime,
        leadAcid: leadAcid,
        batteryPercent: vehicle != null && vehicle.hasBatteryData
            ? vehicle.currentBattery
            : null,
        charging: charging,
      );
      if (tip != null) {
        unawaited(tips.markTold(currentTime));
        showBubble(
          'Mẹo: ${tip.title}',
          mood: BatteryBotMood.happy,
          tipId: tip.id,
          duration: tipBubbleDuration,
        );
        return true;
      }
    }

    return false;
  }

  static bool? _leadAcid(VehicleModel? vehicle) {
    final chemistry = vehicle?.batteryType?.trim() ?? '';
    if (chemistry.isEmpty || chemistry.toLowerCase() == 'unknown') return null;
    return isLeadAcidChemistry(chemistry);
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
    _idleDockTimer?.cancel();
    _reactionTimer?.cancel();
    super.dispose();
  }
}

/// Provider cho AssistantContextCoordinator
final assistantContextCoordinatorProvider =
    ChangeNotifierProvider<AssistantContextCoordinator>((ref) {
      final coordinator = AssistantContextCoordinator();

      // Tự động lắng nghe thay đổi tab
      // No Firebase (widget tests): no session source, so not charging.
      bool charging(VehicleModel? vehicle) =>
          vehicle != null &&
          Firebase.apps.isNotEmpty &&
          ref
              .read(activeChargingSessionProvider)
              .sessions
              .any((s) => s.vehicleId == vehicle.vehicleId);

      // QA 163: the daily tip needs the list; a tip can come once it is in.
      // Not without Firebase (widget tests): no bubble timers left behind.
      if (Firebase.apps.isNotEmpty) {
        unawaited(
          coordinator.tips.load().then((_) {
            final vehicleContext = ref.read(vehicleContextProvider);
            coordinator.evaluateContext(
              vehicle: vehicleContext.vehicle,
              currentTab: ref.read(currentTabProvider),
              charging: charging(vehicleContext.vehicle),
            );
          }),
        );
      }

      ref.listen<int>(currentTabProvider, (_, nextTab) {
        final vehicleContext = ref.read(vehicleContextProvider);
        coordinator.evaluateContext(
          vehicle: vehicleContext.vehicle,
          currentTab: nextTab,
          charging: charging(vehicleContext.vehicle),
        );
      });

      // Tự động lắng nghe thay đổi xe
      ref.listen(vehicleContextProvider, (_, nextContext) {
        final currentTab = ref.read(currentTabProvider);
        coordinator.evaluateContext(
          vehicle: nextContext.vehicle,
          currentTab: currentTab,
          charging: charging(nextContext.vehicle),
        );
      });

      return coordinator;
    });
