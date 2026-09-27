import 'package:flutter/material.dart';

enum GuideCategory { gettingStarted, vehicle, charging, history, settings }

extension GuideCategoryExtension on GuideCategory {
  String get nameVi => switch (this) {
    GuideCategory.gettingStarted => 'Bắt đầu',
    GuideCategory.vehicle => 'Xe và pin',
    GuideCategory.charging => 'Sạc pin',
    GuideCategory.history => 'Lịch sử',
    GuideCategory.settings => 'Cài đặt',
  };

  String get nameEn => switch (this) {
    GuideCategory.gettingStarted => 'Getting started',
    GuideCategory.vehicle => 'Vehicle and battery',
    GuideCategory.charging => 'Charging',
    GuideCategory.history => 'History',
    GuideCategory.settings => 'Settings',
  };

  IconData get icon => switch (this) {
    GuideCategory.gettingStarted => Icons.waving_hand_rounded,
    GuideCategory.vehicle => Icons.electric_scooter_rounded,
    GuideCategory.charging => Icons.ev_station_rounded,
    GuideCategory.history => Icons.history_rounded,
    GuideCategory.settings => Icons.settings_rounded,
  };
}

enum GuideDestination {
  overview,
  charging,
  history,
  settings,
  shellySetup,
  batteryBot,
}

extension GuideDestinationExtension on GuideDestination {
  String actionLabel(String languageCode) {
    final english = languageCode == 'en';
    return switch (this) {
      GuideDestination.overview => english ? 'Open Overview' : 'Mở Tổng quan',
      GuideDestination.charging => english ? 'Open Charging' : 'Mở Sạc pin',
      GuideDestination.history => english ? 'Open History' : 'Mở Lịch sử',
      GuideDestination.settings => english ? 'Open Settings' : 'Mở Cài đặt',
      GuideDestination.shellySetup =>
        english ? 'Start Shelly setup' : 'Bắt đầu thiết lập Shelly',
      GuideDestination.batteryBot =>
        english ? 'Ask BatteryBot' : 'Hỏi BatteryBot',
    };
  }

  int? get tabIndex => switch (this) {
    GuideDestination.overview => 0,
    GuideDestination.charging => 1,
    GuideDestination.history => 2,
    GuideDestination.settings => 3,
    GuideDestination.shellySetup || GuideDestination.batteryBot => null,
  };
}

class GuideItem {
  final String id;
  final GuideCategory category;
  final String titleVi;
  final String titleEn;
  final String summaryVi;
  final String summaryEn;
  final List<String> stepsVi;
  final List<String> stepsEn;
  final String? noteVi;
  final String? noteEn;
  final GuideDestination destination;

  const GuideItem({
    required this.id,
    required this.category,
    required this.titleVi,
    required this.titleEn,
    required this.summaryVi,
    required this.summaryEn,
    required this.stepsVi,
    required this.stepsEn,
    required this.destination,
    this.noteVi,
    this.noteEn,
  });

  String title(String languageCode) => languageCode == 'en' ? titleEn : titleVi;
  String summary(String languageCode) =>
      languageCode == 'en' ? summaryEn : summaryVi;
  List<String> steps(String languageCode) =>
      languageCode == 'en' ? stepsEn : stepsVi;
  String? note(String languageCode) => languageCode == 'en' ? noteEn : noteVi;
}

class CoachMarkStep {
  final String id;
  final String titleVi;
  final String titleEn;
  final String descriptionVi;
  final String descriptionEn;
  final GlobalKey anchorKey;
  final Alignment tooltipAlignment;

  const CoachMarkStep({
    required this.id,
    required this.titleVi,
    required this.titleEn,
    required this.descriptionVi,
    required this.descriptionEn,
    required this.anchorKey,
    this.tooltipAlignment = Alignment.bottomCenter,
  });

  String title(String languageCode) => languageCode == 'en' ? titleEn : titleVi;
  String description(String languageCode) =>
      languageCode == 'en' ? descriptionEn : descriptionVi;
}

class GuideRegistry {
  static const String overviewTourId = 'tour_overview_v2';

  static final GlobalKey keyVehicleSwitcher = GlobalKey(
    debugLabel: 'anchor_vehicle_switcher',
  );
  static final GlobalKey keyCustomizeDashboard = GlobalKey(
    debugLabel: 'anchor_customize_dashboard',
  );
  static final GlobalKey keyBatterySummary = GlobalKey(
    debugLabel: 'anchor_vehicle_battery_summary',
  );
  static final GlobalKey keyBatteryHealthCard = GlobalKey(
    debugLabel: 'anchor_battery_health_card',
  );
  static final GlobalKey keyTripPlannerAction = GlobalKey(
    debugLabel: 'anchor_trip_planner_action',
  );
  static final GlobalKey keyChargeTab = GlobalKey(
    debugLabel: 'anchor_charge_tab',
  );
  static final GlobalKey keyHistoryTab = GlobalKey(
    debugLabel: 'anchor_history_tab',
  );
  static final GlobalKey keyMoreSettingsTab = GlobalKey(
    debugLabel: 'anchor_more_settings_tab',
  );

  static List<CoachMarkStep> getOverviewTourSteps() => [
    CoachMarkStep(
      id: 'step_vehicle_and_battery',
      titleVi: 'Xe và pin',
      titleEn: 'Vehicle and battery',
      descriptionVi:
          'Đây là xe đang chọn và thông tin pin. Chạm tên xe để chuyển xe.',
      descriptionEn:
          'See the selected vehicle and battery. Tap the vehicle name to switch vehicles.',
      anchorKey: keyBatterySummary,
    ),
    CoachMarkStep(
      id: 'step_charging',
      titleVi: 'Sạc pin',
      titleEn: 'Charging',
      descriptionVi:
          'Mở tab này để xem trạng thái bộ sạc và các thao tác đang khả dụng.',
      descriptionEn:
          'Open this tab to see charger status and available actions.',
      anchorKey: keyChargeTab,
      tooltipAlignment: Alignment.topCenter,
    ),
    CoachMarkStep(
      id: 'step_history',
      titleVi: 'Lịch sử',
      titleEn: 'History',
      descriptionVi:
          'Xem lại các phiên sạc đã lưu và mở một phiên để xem chi tiết.',
      descriptionEn: 'Review saved charging sessions and open one for details.',
      anchorKey: keyHistoryTab,
      tooltipAlignment: Alignment.topCenter,
    ),
    CoachMarkStep(
      id: 'step_settings',
      titleVi: 'Cài đặt',
      titleEn: 'Settings',
      descriptionVi: 'Quản lý tài khoản, xe và mở lại hướng dẫn tại đây.',
      descriptionEn:
          'Manage your account and vehicles, or replay this guide here.',
      anchorKey: keyMoreSettingsTab,
      tooltipAlignment: Alignment.topCenter,
    ),
  ];

  static const List<GuideItem> items = [
    GuideItem(
      id: 'guide_vehicle_battery',
      category: GuideCategory.vehicle,
      titleVi: 'Xem xe và pin',
      titleEn: 'View your vehicle and battery',
      summaryVi: 'Xem xe đang chọn và tình trạng pin trên màn hình Tổng quan.',
      summaryEn: 'See your selected vehicle and battery status on Overview.',
      stepsVi: ['Mở tab Tổng quan.', 'Chạm tên xe phía trên để đổi xe.'],
      stepsEn: [
        'Open Overview.',
        'Tap the vehicle name at the top to switch vehicles.',
      ],
      destination: GuideDestination.overview,
    ),
    GuideItem(
      id: 'guide_charging',
      category: GuideCategory.charging,
      titleVi: 'Bắt đầu hoặc dừng sạc',
      titleEn: 'Start or stop charging',
      summaryVi: 'Kiểm tra trạng thái sạc trước khi dùng nút điều khiển.',
      summaryEn: 'Check charging status before using a control.',
      stepsVi: [
        'Mở tab Sạc pin.',
        'Kiểm tra xe và trạng thái kết nối.',
        'Chỉ chạm Bắt đầu/Dừng khi nút được mở; chờ xác nhận trạng thái.',
      ],
      stepsEn: [
        'Open Charging.',
        'Check vehicle and connection status.',
        'Use Start/Stop only when enabled, then wait for confirmation.',
      ],
      noteVi:
          'Nếu nút đang khóa, hãy hoàn tất thiết lập hoặc kết nối mạng trước.',
      noteEn:
          'If a control is disabled, finish setup or restore the network connection first.',
      destination: GuideDestination.charging,
    ),
    GuideItem(
      id: 'guide_history',
      category: GuideCategory.history,
      titleVi: 'Xem lịch sử sạc',
      titleEn: 'View charging history',
      summaryVi: 'Tìm phiên sạc đã lưu và xem số liệu của từng phiên.',
      summaryEn: 'Find saved sessions and review their details.',
      stepsVi: [
        'Mở tab Lịch sử.',
        'Chọn khoảng thời gian nếu có bộ lọc.',
        'Chạm một phiên để xem chi tiết.',
      ],
      stepsEn: [
        'Open History.',
        'Choose a time period if a filter is available.',
        'Tap a session to view details.',
      ],
      destination: GuideDestination.history,
    ),
    GuideItem(
      id: 'guide_settings',
      category: GuideCategory.settings,
      titleVi: 'Cài đặt và quản lý xe',
      titleEn: 'Settings and vehicles',
      summaryVi: 'Quản lý hồ sơ, xe và tùy chọn ứng dụng.',
      summaryEn: 'Manage your profile, vehicles, and app preferences.',
      stepsVi: [
        'Mở tab Cài đặt.',
        'Chọn mục muốn cập nhật.',
        'Mở Hướng dẫn để xem lại tour.',
      ],
      stepsEn: [
        'Open Settings.',
        'Choose what you want to update.',
        'Open Guides to replay the tour.',
      ],
      destination: GuideDestination.settings,
    ),
    GuideItem(
      id: 'guide_shelly_setup',
      category: GuideCategory.charging,
      titleVi: 'Kết nối Shelly Smart Charge',
      titleEn: 'Connect Shelly Smart Charge',
      summaryVi: 'Kết nối ổ cắm và xác minh an toàn trước khi điều khiển.',
      summaryEn: 'Connect the plug and verify safety before enabling controls.',
      stepsVi: [
        'Ưu tiên điện thoại và Shelly cùng Wi-Fi; chọn Kết nối qua Wi-Fi.',
        'Nếu không dùng được Wi-Fi, chọn Shelly Cloud.',
        'Bạn cũng có thể nhập mã kết nối 6 ký tự do quản trị viên cấp.',
      ],
      stepsEn: [
        'Prefer the same Wi-Fi for phone and Shelly, then choose Wi-Fi connection.',
        'Choose Shelly Cloud if Wi-Fi pairing is unavailable.',
        'You can also enter a 6-character code from an administrator.',
      ],
      noteVi:
          'Trước Kiểm tra an toàn, rút xe và mọi tải. Ổ cắm có thể bật tối đa 5 giây. Chỉ tiếp tục sau khi xác nhận đã rút tải; hoàn tất khi ứng dụng đọc lại relay đã tắt. Hướng dẫn không tự bật hoặc tắt ổ cắm.',
      noteEn:
          'Before Safety Check, unplug the vehicle and every load. The outlet may turn on for up to 5 seconds. Continue only after confirming it is unplugged; setup completes after the app reads the relay off. This guide never switches the outlet.',
      destination: GuideDestination.shellySetup,
    ),
  ];

  static List<GuideItem> search(String query, String languageCode) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return items;
    return items
        .where(
          (item) => [
            item.title(languageCode),
            item.summary(languageCode),
            ...item.steps(languageCode),
          ].join(' ').toLowerCase().contains(normalized),
        )
        .toList();
  }

  static List<GuideItem> filterByCategory(GuideCategory? category) =>
      category == null
      ? items
      : items.where((item) => item.category == category).toList();
}
