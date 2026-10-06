import 'package:flutter/material.dart';

import '../../../core/theme/cockpit_design_system.dart';

/// Teaser card placed on the AI Charging screen to introduce and link
/// to the Energy Journey gamification screen.
class EnergyJourneyTeaserCard extends StatelessWidget {
  const EnergyJourneyTeaserCard({
    super.key,
    required this.totalKWh,
    required this.onTap,
  });

  final double totalKWh;
  final VoidCallback onTap;

  /// Helper to calculate level info given total kWh.
  /// (36 levels, progressive thresholds).
  static ({
    int level,
    String name,
    double nextThreshold,
    double prevThreshold,
    IconData icon,
  })
  calculateLevel(double kwh) {
    const milestones = [
      (0.0, 'Tia lửa đầu tiên', Icons.bolt_rounded),
      (5.0, 'Đom đóm đêm', Icons.flare_rounded),
      (12.0, 'Ngọn nến nhỏ', Icons.wb_incandescent_outlined),
      (22.0, 'Đèn pin sinh thái', Icons.flashlight_on_rounded),
      (35.0, 'Bóng đèn huỳnh quang', Icons.lightbulb_outline_rounded),
      (50.0, 'Đèn LED công suất cao', Icons.lightbulb_rounded),
      (70.0, 'Ngọn đuốc xanh', Icons.local_fire_department_rounded),
      (95.0, 'Đèn bão ven biển', Icons.wb_twilight_rounded),
      (125.0, 'Hải đăng cổ tích', Icons.cell_tower_rounded),
      (160.0, 'Đèn chùm pha lê', Icons.diamond_outlined),
      (200.0, 'Trụ đèn quảng trường', Icons.wb_sunny_outlined),
      (250.0, 'Dàn đèn sân khấu', Icons.theater_comedy_rounded),
      (310.0, 'Đèn đường phố hoa lệ', Icons.nightlife_rounded),
      (380.0, 'Biển quảng cáo Neon', Icons.blur_on_rounded),
      (460.0, 'Trạm biến áp khu phố', Icons.power_rounded),
      (550.0, 'Hệ thống điện tòa nhà', Icons.apartment_rounded),
      (650.0, 'Công viên ánh sáng', Icons.park_rounded),
      (760.0, 'Cây cầu rực rỡ', Icons.location_city_rounded),
      (880.0, 'Máy phát Turbine gió', Icons.air_rounded),
      (1010.0, 'Thủy điện mini', Icons.water_drop_rounded),
      (1150.0, 'Động cơ hơi nước điện', Icons.cyclone_rounded),
      (1300.0, 'Trạm tích năng pin', Icons.battery_charging_full_rounded),
      (1460.0, 'Lò phản ứng nhiệt', Icons.heat_pump_rounded),
      (1630.0, 'Nhà máy điện mặt trời', Icons.solar_power_rounded),
      (1810.0, 'Lưới điện siêu cao thế', Icons.electric_bolt_rounded),
      (2000.0, 'Trung tâm điều độ vùng', Icons.hub_rounded),
      (2200.0, 'Thành phố tương lai', Icons.domain_rounded),
      (2410.0, 'Siêu đô thị Megacity', Icons.corporate_fare_rounded),
      (2630.0, 'Đảo quốc xanh năng lượng', Icons.forest_rounded),
      (2860.0, 'Lục địa xanh không khói', Icons.public_rounded),
      (3100.0, 'Vành đai năng lượng quỹ đạo', Icons.track_changes_rounded),
      (3350.0, 'Trạm không gian Orbital', Icons.satellite_alt_rounded),
      (3610.0, 'Căn cứ năng lượng Mặt trăng', Icons.dark_mode_rounded),
      (3880.0, 'Phản ứng nhiệt hạch sao', Icons.stars_rounded),
      (4160.0, 'Lõi siêu sao Neutron', Icons.blur_circular_rounded),
      (4450.0, 'Mặt trời nhân tạo', Icons.wb_sunny_rounded),
    ];

    var currentLevel = 1;
    var currentName = milestones[0].$2;
    var currentIcon = milestones[0].$3;
    var prevThresh = 0.0;
    var nextThresh = milestones[1].$1;

    for (var i = milestones.length - 1; i >= 0; i--) {
      if (kwh >= milestones[i].$1) {
        currentLevel = i + 1;
        currentName = milestones[i].$2;
        currentIcon = milestones[i].$3;
        prevThresh = milestones[i].$1;
        nextThresh = i < milestones.length - 1
            ? milestones[i + 1].$1
            : milestones[i].$1 + 500;
        break;
      }
    }

    return (
      level: currentLevel,
      name: currentName,
      nextThreshold: nextThresh,
      prevThreshold: prevThresh,
      icon: currentIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = calculateLevel(totalKWh);
    final remainingKWh = (info.nextThreshold - totalKWh).clamp(0.0, 99999.0);
    final progressRange = (info.nextThreshold - info.prevThreshold);
    final progress = progressRange > 0
        ? ((totalKWh - info.prevThreshold) / progressRange).clamp(0.0, 1.0)
        : 1.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: CockpitColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: CockpitColors.emerald.withValues(alpha: .22),
          ),
          boxShadow: [
            BoxShadow(
              color: CockpitColors.emerald.withValues(alpha: .04),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: CockpitColors.emerald.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: CockpitColors.emerald.withValues(alpha: .30),
                    ),
                  ),
                  child: Icon(
                    info.icon,
                    size: 20,
                    color: CockpitColors.emerald,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Hành trình năng lượng',
                            style: TextStyle(
                              color: CockpitColors.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: CockpitColors.emerald.withValues(
                                alpha: .15,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Cấp ${info.level}',
                              style: TextStyle(
                                color: CockpitColors.emerald,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Đã tích luỹ ${totalKWh.toStringAsFixed(1)} kWh · Còn ${remainingKWh.toStringAsFixed(1)} kWh để lên cấp',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CockpitColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: CockpitColors.muted,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withValues(alpha: .08),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    CockpitColors.emerald,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
