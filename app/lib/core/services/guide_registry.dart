import 'package:flutter/material.dart';

enum GuideCategory {
  gettingStarted,
  vehicle,
  charging,
  trips,
  ai,
  account,
  troubleshooting,
}

extension GuideCategoryExtension on GuideCategory {
  String get nameVi {
    switch (this) {
      case GuideCategory.gettingStarted:
        return 'Bắt đầu';
      case GuideCategory.vehicle:
        return 'Xe';
      case GuideCategory.charging:
        return 'Sạc';
      case GuideCategory.trips:
        return 'Chuyến đi';
      case GuideCategory.ai:
        return 'AI';
      case GuideCategory.account:
        return 'Tài khoản';
      case GuideCategory.troubleshooting:
        return 'Xử lý lỗi';
    }
  }

  String get nameEn {
    switch (this) {
      case GuideCategory.gettingStarted:
        return 'Getting Started';
      case GuideCategory.vehicle:
        return 'Vehicle';
      case GuideCategory.charging:
        return 'Charging';
      case GuideCategory.trips:
        return 'Trips';
      case GuideCategory.ai:
        return 'AI';
      case GuideCategory.account:
        return 'Account';
      case GuideCategory.troubleshooting:
        return 'Troubleshooting';
    }
  }

  IconData get icon {
    switch (this) {
      case GuideCategory.gettingStarted:
        return Icons.rocket_launch_rounded;
      case GuideCategory.vehicle:
        return Icons.electric_scooter_rounded;
      case GuideCategory.charging:
        return Icons.ev_station_rounded;
      case GuideCategory.trips:
        return Icons.navigation_rounded;
      case GuideCategory.ai:
        return Icons.psychology_rounded;
      case GuideCategory.account:
        return Icons.person_rounded;
      case GuideCategory.troubleshooting:
        return Icons.build_circle_rounded;
    }
  }
}

/// Mô hình một bài hướng dẫn trong Thư viện trợ giúp
class GuideItem {
  final String id;
  final GuideCategory category;
  final String titleVi;
  final String titleEn;
  final String summaryVi;
  final String summaryEn;
  final List<String> prerequisitesVi;
  final List<String> prerequisitesEn;
  final List<String> stepsVi;
  final List<String> stepsEn;
  final String expectedResultVi;
  final String expectedResultEn;
  final int? targetTab; // 0: Overview, 1: Charge, 2: History, 3: More
  final String? tourId;

  const GuideItem({
    required this.id,
    required this.category,
    required this.titleVi,
    required this.titleEn,
    required this.summaryVi,
    required this.summaryEn,
    required this.prerequisitesVi,
    required this.prerequisitesEn,
    required this.stepsVi,
    required this.stepsEn,
    required this.expectedResultVi,
    required this.expectedResultEn,
    this.targetTab,
    this.tourId,
  });

  String title(String languageCode) => languageCode == 'en' ? titleEn : titleVi;
  String summary(String languageCode) =>
      languageCode == 'en' ? summaryEn : summaryVi;
  List<String> prerequisites(String languageCode) =>
      languageCode == 'en' ? prerequisitesEn : prerequisitesVi;
  List<String> steps(String languageCode) =>
      languageCode == 'en' ? stepsEn : stepsVi;
  String expectedResult(String languageCode) =>
      languageCode == 'en' ? expectedResultEn : expectedResultVi;
}

/// Spotlight Coach Mark Step Data
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

/// Registry toàn diện các hướng dẫn sử dụng và spotlight coach mark
class GuideRegistry {
  static const String overviewTourId = 'tour_overview_v1';

  // GlobalKeys cho Spotlight Tour anchors
  static final GlobalKey keyVehicleSwitcher = GlobalKey(
    debugLabel: 'anchor_vehicle_switcher',
  );
  static final GlobalKey keyCustomizeDashboard = GlobalKey(
    debugLabel: 'anchor_customize_dashboard',
  );
  static final GlobalKey keyBatteryHealthCard = GlobalKey(
    debugLabel: 'anchor_battery_health_card',
  );
  static final GlobalKey keyChargeTab = GlobalKey(
    debugLabel: 'anchor_charge_tab',
  );
  static final GlobalKey keyTripPlannerAction = GlobalKey(
    debugLabel: 'anchor_trip_planner_action',
  );
  static final GlobalKey keyMoreSettingsTab = GlobalKey(
    debugLabel: 'anchor_more_settings_tab',
  );

  /// Danh sách các bước trong Tour màn hình Tổng quan
  static List<CoachMarkStep> getOverviewTourSteps() {
    return [
      CoachMarkStep(
        id: 'step_switch_vehicle',
        titleVi: 'Đổi xe & Thông báo',
        titleEn: 'Switch Vehicle & Notifications',
        descriptionVi:
            'Chạm tên xe để đổi xe theo dõi. Chuông thông báo hiển thị cảnh báo an toàn và trạng thái sạc.',
        descriptionEn:
            'Tap the vehicle name at the top to switch vehicle. Bell shows battery alerts.',
        anchorKey: keyVehicleSwitcher,
        tooltipAlignment: Alignment.bottomCenter,
      ),
      CoachMarkStep(
        id: 'step_customize_dashboard',
        titleVi: 'Tùy chỉnh giao diện',
        titleEn: 'Customize Dashboard',
        descriptionVi:
            'Bấm nút "Tùy chỉnh" để sắp xếp vị trí hoặc ẩn/hiện các thẻ widget theo nhu cầu của bạn.',
        descriptionEn:
            'Tap "Customize" to reorder or show/hide widgets to match your preferences.',
        anchorKey: keyCustomizeDashboard,
        tooltipAlignment: Alignment.bottomLeft,
      ),
      CoachMarkStep(
        id: 'step_battery_health',
        titleVi: 'Pin & Quãng đường',
        titleEn: 'Battery & Range',
        descriptionVi:
            'Theo dõi % pin (SoC), độ chai pin (SoH) và ước tính quãng đường còn lại tính bằng AI.',
        descriptionEn:
            'View battery % (SoC), health (SoH), and AI estimated remaining range.',
        anchorKey: keyBatteryHealthCard,
        tooltipAlignment: Alignment.topCenter,
      ),
      CoachMarkStep(
        id: 'step_charge_control',
        titleVi: 'Sạc thông minh',
        titleEn: 'Smart Charge',
        descriptionVi:
            'Chuyển sang tab Sạc để đặt mức pin mục tiêu, ước tính tiền điện và bật/tắt relay an toàn.',
        descriptionEn:
            'Switch to Charge tab to set target SoC, estimate cost, and toggle relay safely.',
        anchorKey: keyChargeTab,
        tooltipAlignment: Alignment.topCenter,
      ),
      CoachMarkStep(
        id: 'step_trip_tracking',
        titleVi: 'Hành trình',
        titleEn: 'Trips & Efficiency',
        descriptionVi:
            'Theo dõi lộ trình di chuyển thực tế và lượng tiêu thụ Wh/km để tối ưu quãng đường.',
        descriptionEn:
            'Record live trips and energy consumption Wh/km to optimize your daily range.',
        anchorKey: keyTripPlannerAction,
        tooltipAlignment: Alignment.bottomCenter,
      ),
      CoachMarkStep(
        id: 'step_garage_and_more',
        titleVi: 'Garage & Cài đặt',
        titleEn: 'Garage & Settings',
        descriptionVi:
            'Thêm xe từ Catalog xe điện, cấu hình bộ sạc Shelly và tùy chỉnh app tại tab Khác.',
        descriptionEn:
            'Add vehicles from Catalog, connect Shelly smart chargers, and adjust settings in More tab.',
        anchorKey: keyMoreSettingsTab,
        tooltipAlignment: Alignment.topCenter,
      ),
    ];
  }

  /// Thư viện các bài hướng dẫn chi tiết
  static const List<GuideItem> items = [
    // Bắt đầu
    GuideItem(
      id: 'guide_getting_started',
      category: GuideCategory.gettingStarted,
      titleVi: 'Làm quen với ứng dụng EV Battery',
      titleEn: 'Getting Started with EV Battery',
      summaryVi:
          'Hướng dẫn cơ bản các tính năng quản lý pin xe máy điện và cockpit thông minh.',
      summaryEn:
          'Essential overview of EV battery management and cockpit features.',
      prerequisitesVi: ['Đã đăng nhập tài khoản', 'Đã thêm ít nhất 1 xe'],
      prerequisitesEn: [
        'Signed in to your account',
        'At least 1 vehicle registered',
      ],
      stepsVi: [
        'Quan sát thẻ Pin và Quãng đường trên màn hình Tổng quan.',
        'Nhấn "Tùy chỉnh" trên thanh App Bar để sắp xếp các khối hiển thị.',
        'Chuyển đổi qua lại giữa các tab: Sạc, Lịch sử, Khác ở thanh điều hướng dưới.',
      ],
      stepsEn: [
        'Observe the battery and range status on the Overview screen.',
        'Tap "Customize" on the App Bar to reorder or hide widgets.',
        'Navigate between Charge, History, and More using the bottom navigation bar.',
      ],
      expectedResultVi:
          'Nắm rõ cấu trúc 4 tab chính và cá nhân hóa được bố cục màn hình đầu tiên.',
      expectedResultEn:
          'Understand the 4 core workspaces and personalize your Overview layout.',
      targetTab: 0,
      tourId: overviewTourId,
    ),
    GuideItem(
      id: 'guide_customize_overview',
      category: GuideCategory.gettingStarted,
      titleVi: 'Cách tùy chỉnh màn hình Tổng quan',
      titleEn: 'How to Customize Overview Screen',
      summaryVi:
          'Sắp xếp thứ tự, ẩn bớt khối không cần thiết hoặc khôi phục mặc định.',
      summaryEn: 'Reorder, toggle visibility, or restore default widget layout.',
      prerequisitesVi: ['Đang ở màn hình Tổng quan'],
      prerequisitesEn: ['On the Overview workspace'],
      stepsVi: [
        'Bấm nút "Tùy chỉnh" ở góc phải thanh trên cùng.',
        'Dùng biểu tượng kéo để di chuyển vị trí các widget.',
        'Bật hoặc tắt công tắc để ẩn/hiện widget theo ý muốn (phải giữ ít nhất 1 widget).',
        'Bấm "Khôi phục mặc định" nếu muốn đưa về giao diện ban đầu.',
      ],
      stepsEn: [
        'Tap "Customize" in the top App Bar.',
        'Use the drag handle to reorder content widgets.',
        'Toggle the switch to show or hide widgets (at least 1 widget must remain visible).',
        'Tap "Restore defaults" to return to the original layout.',
      ],
      expectedResultVi:
          'Màn hình Tổng quan thay đổi ngay lập tức và được đồng bộ lên tài khoản.',
      expectedResultEn:
          'Overview screen updates immediately and preferences sync with your account.',
      targetTab: 0,
    ),

    // Xe
    GuideItem(
      id: 'guide_add_vehicle_catalog',
      category: GuideCategory.vehicle,
      titleVi: 'Thêm xe từ Catalog xe điện',
      titleEn: 'Add Vehicle from EV Catalog',
      summaryVi:
          'Chọn dòng xe chính xác (Klara, Feliz, Theon, Evo, Vento) để AI tính toán tối ưu.',
      summaryEn:
          'Select the exact EV model for accurate AI consumption models.',
      prerequisitesVi: ['Kết nối mạng Internet', 'Tối đa 2 xe sở hữu active'],
      prerequisitesEn: [
        'Internet connection',
        'Maximum 2 active vehicles owned',
      ],
      stepsVi: [
        'Vào tab "Khác" > Chọn "Garage xe".',
        'Bấm "Thêm xe mới".',
        'Tìm kiếm và chọn đúng mẫu xe từ danh mục đã phát hành.',
        'Nhập tên gợi nhớ (nickname), biển số và ODO hiện tại rồi xác nhận.',
      ],
      stepsEn: [
        'Open the "More" tab > Select "Vehicle Garage".',
        'Tap "Add New Vehicle".',
        'Search and select your exact model from the published catalog.',
        'Enter nickname, license plate, initial ODO and confirm.',
      ],
      expectedResultVi:
          'Xe mới xuất hiện trong bộ chọn xe và tự động áp dụng thông số pin chuẩn.',
      expectedResultEn:
          'Vehicle appears in the switcher with official battery specifications linked.',
      targetTab: 3,
    ),

    // Sạc
    GuideItem(
      id: 'guide_smart_charging',
      category: GuideCategory.charging,
      titleVi: 'Thiết lập Sạc thông minh & Điểm ngắt SoC',
      titleEn: 'Smart Charge & Target SoC Cutoff',
      summaryVi:
          'Bảo vệ tuổi thọ pin bằng cách sạc đến 80-90% và tự động ngắt relay.',
      summaryEn:
          'Protect battery longevity by charging to 80-90% and auto-cutting relay.',
      prerequisitesVi: ['Đã liên kết xe', 'Bộ sạc thông minh Shelly sẵn sàng'],
      prerequisitesEn: ['Linked vehicle', 'Shelly smart charger connected'],
      stepsVi: [
        'Mở tab "Sạc".',
        'Kéo thanh chọn SoC mục tiêu (khuyến nghị 80% cho hàng ngày).',
        'Kiểm tra thời gian sạc ước tính và chi phí tiền điện dự kiến.',
        'Bấm "Bắt đầu sạc".',
      ],
      stepsEn: [
        'Open the "Charge" tab.',
        'Drag the target SoC slider (80% recommended for daily commute).',
        'Check estimated duration and electricity cost.',
        'Tap "Start Charging".',
      ],
      expectedResultVi:
          'Relay bật an toàn, màn hình đếm ngược và tự động ngắt khi đạt mốc pin.',
      expectedResultEn:
          'Relay powers on safely, countdown timer tracks progress and shuts off at target SoC.',
      targetTab: 1,
    ),

    // Chuyến đi
    GuideItem(
      id: 'guide_trip_tracking',
      category: GuideCategory.trips,
      titleVi: 'Ghi nhận chuyến đi & Dự đoán mức pin',
      titleEn: 'Trip Logging & Range Consumption',
      summaryVi:
          'Theo dõi quãng đường di chuyển và độ tiêu hao năng lượng thực tế.',
      summaryEn:
          'Track travel distance and actual energy consumption per kilometer.',
      prerequisitesVi: ['Bật quyền truy cập vị trí (GPS)'],
      prerequisitesEn: ['Location permission (GPS) enabled'],
      stepsVi: [
        'Nhấn nút "Chuyến đi" trên màn hình Tổng quan.',
        'Bấm "Bắt đầu chuyến đi" trước khi khởi hành.',
        'Khi đến nơi, bấm "Kết thúc" để xem thống kê tiêu hao Wh/km.',
      ],
      stepsEn: [
        'Tap "Trip Planner" on the Overview screen.',
        'Tap "Start Trip" before leaving.',
        'Upon arrival, tap "Finish" to inspect Wh/km consumption analytics.',
      ],
      expectedResultVi:
          'Lịch sử chuyến đi được lưu lại và dùng làm dữ liệu học cho AI cá nhân.',
      expectedResultEn:
          'Trip log saved to train and personalize your vehicle AI consumption curve.',
      targetTab: 0,
    ),

    // AI
    GuideItem(
      id: 'guide_ai_explanation',
      category: GuideCategory.ai,
      titleVi: 'Cách AI dự đoán pin & độ lão hóa SoH',
      titleEn: 'How AI Predicts Range and Battery SoH',
      summaryVi:
          'Mô hình Machine Learning phân tích thói quen lái và thời tiết để tính toán.',
      summaryEn:
          'Machine Learning models factor driving behavior, terrain, and temperature.',
      prerequisitesVi: ['Có dữ liệu lịch sử sạc và chuyến đi'],
      prerequisitesEn: ['Historical charge and trip logs'],
      stepsVi: [
        'Mô hình liên tục học từ chu kỳ sạc và độ giảm điện áp.',
        'Tính toán dự đoán quãng đường dựa trên tốc độ trung bình và tải trọng.',
        'Đưa ra khuyến nghị bảo dưỡng khi phát hiện cell pin mất cân bằng.',
      ],
      stepsEn: [
        'Model continuously learns from charge cycles and voltage drop.',
        'Estimates range based on avg speed, payload, and ambient temperature.',
        'Recommends maintenance when cell imbalance is detected.',
      ],
      expectedResultVi:
          'Dự đoán ngày càng chính xác sau mỗi 3-5 chu kỳ sử dụng.',
      expectedResultEn:
          'Predictions become increasingly precise after 3-5 charge cycles.',
      targetTab: 0,
    ),

    // Xử lý lỗi
    GuideItem(
      id: 'guide_troubleshooting',
      category: GuideCategory.troubleshooting,
      titleVi: 'Xử lý lỗi kết nối Shelly & Đồng bộ dữ liệu',
      titleEn: 'Troubleshooting Shelly & Data Sync',
      summaryVi:
          'Khắc phục tình trạng mất mạng, thiết bị sạc ngoại tuyến hoặc dữ liệu chưa đồng bộ.',
      summaryEn:
          'Fix offline charger states, network disconnects, or sync delays.',
      prerequisitesVi: ['Kiểm tra kết nối Wifi hoặc 4G'],
      prerequisitesEn: ['Check Wi-Fi or cellular network'],
      stepsVi: [
        'Nếu Shelly báo offline: kiểm tra nguồn điện cấp và đèn tín hiệu trên thiết bị.',
        'Thử kết nối qua địa chỉ IP mạng nội bộ (LAN) nếu kết nối Cloud gặp sự cố.',
        'Nếu dữ liệu chưa khớp: vào tab Khác > bấm "Đồng bộ ngay".',
      ],
      stepsEn: [
        'If Shelly shows offline: verify power supply and LED indicators on device.',
        'Try fallback local LAN IP connection if Cloud connection is unreachable.',
        'If data is out of sync: open More tab > tap "Sync Now".',
      ],
      expectedResultVi:
          'Khôi phục kết nối điều khiển an toàn và dữ liệu được cập nhật đầy đủ.',
      expectedResultEn:
          'Safe relay control restored and local telemetry synced with the cloud.',
      targetTab: 3,
    ),
  ];

  static List<GuideItem> search(String query, String languageCode) {
    if (query.trim().isEmpty) return items;
    final q = query.toLowerCase().trim();
    return items.where((item) {
      final t = item.title(languageCode).toLowerCase();
      final s = item.summary(languageCode).toLowerCase();
      final cat = item.category.nameVi.toLowerCase();
      return t.contains(q) || s.contains(q) || cat.contains(q);
    }).toList();
  }

  static List<GuideItem> filterByCategory(GuideCategory? category) {
    if (category == null) return items;
    return items.where((item) => item.category == category).toList();
  }
}
