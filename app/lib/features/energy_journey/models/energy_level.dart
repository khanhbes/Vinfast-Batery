import 'package:flutter/material.dart';

import '../../../../core/theme/cockpit_design_system.dart';

/// Represents one of the 36 gamified energy levels in the EV charging journey.
class EnergyLevel {
  const EnergyLevel({
    required this.level,
    required this.name,
    required this.thresholdKWh,
    required this.tier,
    required this.tierName,
    required this.icon,
    required this.description,
    required this.badgeColor,
  });

  final int level;
  final String name;
  final double thresholdKWh;
  final int tier; // 1 to 6
  final String tierName;
  final IconData icon;
  final String description;
  final Color badgeColor;

  /// Complete 36-level progression based on cumulative charged kWh.
  static const List<EnergyLevel> allLevels = [
    // Tier 1: Hạt mầm (0 - 50 kWh)
    EnergyLevel(
      level: 1,
      name: 'Tia lửa đầu tiên',
      thresholdKWh: 0.0,
      tier: 1,
      tierName: 'Hạt mầm',
      icon: Icons.bolt_rounded,
      description: 'Khởi đầu chuyến hành trình xanh với lần sạc thông minh đầu tiên.',
      badgeColor: CockpitColors.emerald,
    ),
    EnergyLevel(
      level: 2,
      name: 'Đom đóm đêm',
      thresholdKWh: 5.0,
      tier: 1,
      tierName: 'Hạt mầm',
      icon: Icons.flare_rounded,
      description: 'Ánh sáng le lói dẫn đường qua những con phố tĩnh lặng.',
      badgeColor: CockpitColors.emerald,
    ),
    EnergyLevel(
      level: 3,
      name: 'Ngọn nến nhỏ',
      thresholdKWh: 12.0,
      tier: 1,
      tierName: 'Hạt mầm',
      icon: Icons.wb_incandescent_outlined,
      description: 'Duy trì năng lượng bền bỉ và ấm áp cho từng kilomet di chuyển.',
      badgeColor: CockpitColors.emerald,
    ),
    EnergyLevel(
      level: 4,
      name: 'Đèn pin sinh thái',
      thresholdKWh: 22.0,
      tier: 1,
      tierName: 'Hạt mầm',
      icon: Icons.flashlight_on_rounded,
      description: 'Chùm sáng rõ ràng mở rộng tầm nhìn cho hành trình đô thị.',
      badgeColor: CockpitColors.emerald,
    ),
    EnergyLevel(
      level: 5,
      name: 'Bóng đèn huỳnh quang',
      thresholdKWh: 35.0,
      tier: 1,
      tierName: 'Hạt mầm',
      icon: Icons.lightbulb_outline_rounded,
      description: 'Hiệu suất năng lượng bắt đầu tạo ra sự khác biệt đo lường được.',
      badgeColor: CockpitColors.emerald,
    ),
    EnergyLevel(
      level: 6,
      name: 'Đèn LED công suất cao',
      thresholdKWh: 50.0,
      tier: 1,
      tierName: 'Hạt mầm',
      icon: Icons.lightbulb_rounded,
      description: 'Tiết kiệm và sáng rực, biểu trưng cho sự chuyển đổi giao thông xanh.',
      badgeColor: CockpitColors.emerald,
    ),

    // Tier 2: Khởi nguyên (50 - 200 kWh)
    EnergyLevel(
      level: 7,
      name: 'Ngọn đuốc xanh',
      thresholdKWh: 70.0,
      tier: 2,
      tierName: 'Khởi nguyên',
      icon: Icons.local_fire_department_rounded,
      description: 'Ngọn lửa tiên phong khẳng định phong cách sống không khí thải.',
      badgeColor: Color(0xFF10B981),
    ),
    EnergyLevel(
      level: 8,
      name: 'Đèn bão ven biển',
      thresholdKWh: 95.0,
      tier: 2,
      tierName: 'Khởi nguyên',
      icon: Icons.wb_twilight_rounded,
      description: 'Vững vàng trước gió bão, đồng hành trên mọi cung đường duyên hải.',
      badgeColor: Color(0xFF10B981),
    ),
    EnergyLevel(
      level: 9,
      name: 'Hải đăng cổ tích',
      thresholdKWh: 125.0,
      tier: 2,
      tierName: 'Khởi nguyên',
      icon: Icons.cell_tower_rounded,
      description: 'Cột mốc chỉ đường an toàn cho cả đội xe điện cùng lăn bánh.',
      badgeColor: Color(0xFF10B981),
    ),
    EnergyLevel(
      level: 10,
      name: 'Đèn chùm pha lê',
      thresholdKWh: 160.0,
      tier: 2,
      tierName: 'Khởi nguyên',
      icon: Icons.diamond_outlined,
      description: 'Tinh xảo và đẳng cấp trong quản lý chu kỳ pin thông minh.',
      badgeColor: Color(0xFF10B981),
    ),
    EnergyLevel(
      level: 11,
      name: 'Trụ đèn quảng trường',
      thresholdKWh: 200.0,
      tier: 2,
      tierName: 'Khởi nguyên',
      icon: Icons.wb_sunny_outlined,
      description: 'Điểm tụ năng lượng trung tâm thắp sáng cả không gian cộng đồng.',
      badgeColor: Color(0xFF10B981),
    ),
    EnergyLevel(
      level: 12,
      name: 'Dàn đèn sân khấu',
      thresholdKWh: 250.0,
      tier: 2,
      tierName: 'Khởi nguyên',
      icon: Icons.theater_comedy_rounded,
      description: 'Tỏa sáng rực rỡ, sẵn sàng cho những chặng đường dài bứt phá.',
      badgeColor: Color(0xFF10B981),
    ),

    // Tier 3: Đô thị (200 - 600 kWh)
    EnergyLevel(
      level: 13,
      name: 'Đèn đường phố hoa lệ',
      thresholdKWh: 310.0,
      tier: 3,
      tierName: 'Đô thị',
      icon: Icons.nightlife_rounded,
      description: 'Hàng ngàn kilomet không tiếng ồn trên các đại lộ về đêm.',
      badgeColor: Color(0xFF06B6D4),
    ),
    EnergyLevel(
      level: 14,
      name: 'Biển quảng cáo Neon',
      thresholdKWh: 380.0,
      tier: 3,
      tierName: 'Đô thị',
      icon: Icons.blur_on_rounded,
      description: 'Dấu ấn hiện đại của thế hệ di chuyển thuần điện tương lai.',
      badgeColor: Color(0xFF06B6D4),
    ),
    EnergyLevel(
      level: 15,
      name: 'Trạm biến áp khu phố',
      thresholdKWh: 460.0,
      tier: 3,
      tierName: 'Đô thị',
      icon: Icons.power_rounded,
      description: 'Điều phối dòng điện sinh hoạt an toàn, cân bằng tải thông minh.',
      badgeColor: Color(0xFF06B6D4),
    ),
    EnergyLevel(
      level: 16,
      name: 'Hệ thống điện tòa nhà',
      thresholdKWh: 550.0,
      tier: 3,
      tierName: 'Đô thị',
      icon: Icons.apartment_rounded,
      description: 'Cung cấp năng lượng liên tục cho các cao ốc thông minh.',
      badgeColor: Color(0xFF06B6D4),
    ),
    EnergyLevel(
      level: 17,
      name: 'Công viên ánh sáng',
      thresholdKWh: 650.0,
      tier: 3,
      tierName: 'Đô thị',
      icon: Icons.park_rounded,
      description: 'Không gian xanh hòa quyện cùng công nghệ năng lượng tái tạo.',
      badgeColor: Color(0xFF06B6D4),
    ),
    EnergyLevel(
      level: 18,
      name: 'Cây cầu rực rỡ',
      thresholdKWh: 760.0,
      tier: 3,
      tierName: 'Đô thị',
      icon: Icons.location_city_rounded,
      description: 'Cầu nối xanh giữa các vùng kinh tế trọng điểm đất nước.',
      badgeColor: Color(0xFF06B6D4),
    ),

    // Tier 4: Trạm phát (600 - 1500 kWh)
    EnergyLevel(
      level: 19,
      name: 'Máy phát Turbine gió',
      thresholdKWh: 880.0,
      tier: 4,
      tierName: 'Trạm phát',
      icon: Icons.air_rounded,
      description: 'Biến từng luồng gió mát lành thành sức kéo mãnh liệt cho bánh xe.',
      badgeColor: Color(0xFF3B82F6),
    ),
    EnergyLevel(
      level: 20,
      name: 'Thủy điện mini',
      thresholdKWh: 1010.0,
      tier: 4,
      tierName: 'Trạm phát',
      icon: Icons.water_drop_rounded,
      description: 'Dòng chảy tự nhiên biến thành công năng tuần hoàn vô tận.',
      badgeColor: Color(0xFF3B82F6),
    ),
    EnergyLevel(
      level: 21,
      name: 'Động cơ hơi nước điện',
      thresholdKWh: 1150.0,
      tier: 4,
      tierName: 'Trạm phát',
      icon: Icons.cyclone_rounded,
      description: 'Kết hợp cơ khí chính xác và truyền động điện siêu êm ái.',
      badgeColor: Color(0xFF3B82F6),
    ),
    EnergyLevel(
      level: 22,
      name: 'Trạm tích năng pin',
      thresholdKWh: 1300.0,
      tier: 4,
      tierName: 'Trạm phát',
      icon: Icons.battery_charging_full_rounded,
      description: 'Ngân hàng năng lượng đệm sẵn sàng cho mọi nhu cầu cao điểm.',
      badgeColor: Color(0xFF3B82F6),
    ),
    EnergyLevel(
      level: 23,
      name: 'Lò phản ứng nhiệt',
      thresholdKWh: 1460.0,
      tier: 4,
      tierName: 'Trạm phát',
      icon: Icons.heat_pump_rounded,
      description: 'Kiểm soát nhiệt độ hoàn hảo để kéo dài tuổi thọ cell pin LFP.',
      badgeColor: Color(0xFF3B82F6),
    ),
    EnergyLevel(
      level: 24,
      name: 'Nhà máy điện mặt trời',
      thresholdKWh: 1630.0,
      tier: 4,
      tierName: 'Trạm phát',
      icon: Icons.solar_power_rounded,
      description: 'Hấp thu nguồn quang năng vô tận phủ xanh từng dặm đường.',
      badgeColor: Color(0xFF3B82F6),
    ),

    // Tier 5: Lưới điện (1500 - 3500 kWh)
    EnergyLevel(
      level: 25,
      name: 'Lưới điện siêu cao thế',
      thresholdKWh: 1810.0,
      tier: 5,
      tierName: 'Lưới điện',
      icon: Icons.electric_bolt_rounded,
      description: 'Mạch máu năng lượng 500kV kết nối thông suốt Bắc - Nam.',
      badgeColor: Color(0xFF8B5CF6),
    ),
    EnergyLevel(
      level: 26,
      name: 'Trung tâm điều độ vùng',
      thresholdKWh: 2000.0,
      tier: 5,
      tierName: 'Lưới điện',
      icon: Icons.hub_rounded,
      description: 'Bộ não AI phân phối tải điện sạc tối ưu trên toàn mạng lưới.',
      badgeColor: Color(0xFF8B5CF6),
    ),
    EnergyLevel(
      level: 27,
      name: 'Thành phố tương lai',
      thresholdKWh: 2200.0,
      tier: 5,
      tierName: 'Lưới điện',
      icon: Icons.domain_rounded,
      description: 'Quy hoạch 100% phương tiện di chuyển phát thải bằng không.',
      badgeColor: Color(0xFF8B5CF6),
    ),
    EnergyLevel(
      level: 28,
      name: 'Siêu đô thị Megacity',
      thresholdKWh: 2410.0,
      tier: 5,
      tierName: 'Lưới điện',
      icon: Icons.corporate_fare_rounded,
      description: 'Mật độ năng lượng khổng lồ vận hành nhịp nhàng không khói bụi.',
      badgeColor: Color(0xFF8B5CF6),
    ),
    EnergyLevel(
      level: 29,
      name: 'Đảo quốc xanh năng lượng',
      thresholdKWh: 2630.0,
      tier: 5,
      tierName: 'Lưới điện',
      icon: Icons.forest_rounded,
      description: 'Tự chủ năng lượng sạch 100%, hài hòa cùng hệ sinh thái biển.',
      badgeColor: Color(0xFF8B5CF6),
    ),
    EnergyLevel(
      level: 30,
      name: 'Lục địa xanh không khói',
      thresholdKWh: 2860.0,
      tier: 5,
      tierName: 'Lưới điện',
      icon: Icons.public_rounded,
      description: 'Tầm nhìn tương lai về một địa cầu tươi đẹp cho thế hệ mai sau.',
      badgeColor: Color(0xFF8B5CF6),
    ),

    // Tier 6: Vũ trụ (3500 - 5000+ kWh)
    EnergyLevel(
      level: 31,
      name: 'Vành đai năng lượng quỹ đạo',
      thresholdKWh: 3100.0,
      tier: 6,
      tierName: 'Vũ trụ',
      icon: Icons.track_changes_rounded,
      description: 'Tấm khiên năng lượng quay quanh khí quyển, truyền sóng điện không dây.',
      badgeColor: Color(0xFFEC4899),
    ),
    EnergyLevel(
      level: 32,
      name: 'Trạm không gian Orbital',
      thresholdKWh: 3350.0,
      tier: 6,
      tierName: 'Vũ trụ',
      icon: Icons.satellite_alt_rounded,
      description: 'Tiền đồn khám phá vũ trụ chạy bằng năng lượng ion siêu bền bỉ.',
      badgeColor: Color(0xFFEC4899),
    ),
    EnergyLevel(
      level: 33,
      name: 'Căn cứ năng lượng Mặt trăng',
      thresholdKWh: 3610.0,
      tier: 6,
      tierName: 'Vũ trụ',
      icon: Icons.dark_mode_rounded,
      description: 'Khai thác Helium-3 mở ra kỷ nguyên năng lượng vô tận mới.',
      badgeColor: Color(0xFFEC4899),
    ),
    EnergyLevel(
      level: 34,
      name: 'Phản ứng nhiệt hạch sao',
      thresholdKWh: 3880.0,
      tier: 6,
      tierName: 'Vũ trụ',
      icon: Icons.stars_rounded,
      description: 'Làm chủ bí mật năng lượng của các vì sao giữa vũ trụ bao la.',
      badgeColor: Color(0xFFEC4899),
    ),
    EnergyLevel(
      level: 35,
      name: 'Lõi siêu sao Neutron',
      thresholdKWh: 4160.0,
      tier: 6,
      tierName: 'Vũ trụ',
      icon: Icons.blur_circular_rounded,
      description: 'Mật độ năng lượng vô địch, bền bỉ qua hàng triệu chu kỳ hoạt động.',
      badgeColor: Color(0xFFEC4899),
    ),
    EnergyLevel(
      level: 36,
      name: 'Mặt trời nhân tạo',
      thresholdKWh: 4450.0,
      tier: 6,
      tierName: 'Vũ trụ',
      icon: Icons.wb_sunny_rounded,
      description: 'Đỉnh cao vĩ đại của hành trình sạc: Nguồn năng lượng thuần khiết và vĩnh cửu.',
      badgeColor: Color(0xFFF59E0B),
    ),
  ];

  /// Finds the corresponding level for a given amount of cumulative kWh.
  static EnergyLevel fromKWh(double kwh) {
    for (var i = allLevels.length - 1; i >= 0; i--) {
      if (kwh >= allLevels[i].thresholdKWh) {
        return allLevels[i];
      }
    }
    return allLevels.first;
  }

  /// Gets the next level, or null if already at max level.
  EnergyLevel? get nextLevel {
    if (level >= allLevels.length) return null;
    return allLevels[level]; // 0-indexed: level 1's next is at index 1 (level 2)
  }
}
