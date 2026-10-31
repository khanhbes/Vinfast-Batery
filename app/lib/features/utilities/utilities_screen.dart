import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/beta_capabilities.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/guide_registry.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../data/models/entitlement.dart';
import '../achievements/achievements_screen.dart';
import '../achievements/controllers/achievements_controller.dart';
import '../achievements/models/achievement.dart';
import '../battery_monitor/battery_health_screen.dart';
import '../maintenance/maintenance_screen.dart';
import '../more/widgets/luxe_tile_grid.dart';
import '../settings/personal_ai_settings_screen.dart';
import '../smart_charging/night_charging_screen.dart';
import '../trip_planner/trip_planner_wrapper.dart';

/// Tab Tiện ích (QA 140): the features that used to sit in Cài đặt. Tiles
/// outside the plan are greyed and only their tag opens Pinova Premium; each
/// screen still checks the plan itself (PremiumRequired).
class UtilitiesScreen extends ConsumerWidget {
  const UtilitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleContext = ref.watch(vehicleContextProvider);
    final achievements = ref.watch(achievementsControllerProvider);

    void push(Widget page) => Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );

    /// The vehicle the feature works on, or a hint to pick one.
    String? vehicleId() {
      final id = ref.read(selectedVehicleIdProvider);
      if (id.isEmpty) {
        AppPopup.showWarning('Hãy chọn xe trước');
        return null;
      }
      return id;
    }

    return Theme(
      data: LuxeTheme.of(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const LuxeBackdrop(),
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
            children: [
              const LuxeSectionLabel('PIN & SẠC'),
              LuxeReveal(
                child: LuxeTileGrid(
                  tiles: [
                    LuxeTile(
                      key: GuideRegistry.keyUtilitiesHealth,
                      icon: Icons.battery_charging_full_rounded,
                      title: 'Sức khỏe pin',
                      value: 'Dung lượng còn lại và dấu hiệu chai',
                      lockedBy: PremiumFeature.batteryHealth,
                      onTap: () {
                        final id = vehicleId();
                        if (id != null) BatteryHealthScreen.open(context, ref, id);
                      },
                    ),
                    LuxeTile(
                      key: GuideRegistry.keyUtilitiesNight,
                      icon: Icons.nights_stay_rounded,
                      title: 'Sạc đêm an toàn',
                      value: 'Đầy 80–90% đúng giờ thức dậy',
                      lockedBy: PremiumFeature.nightCharging,
                      onTap: () => NightChargingScreen.open(
                        context,
                        ref,
                        vehicleId: ref.read(selectedVehicleIdProvider),
                        currentSoc: vehicleContext.vehicle?.currentBattery
                            .toDouble(),
                        currentOdoKm: vehicleContext.vehicle?.currentOdo
                            .toDouble(),
                      ),
                    ),
                    if (BetaCapabilities.tripPlanner)
                      LuxeTile(
                        key: const ValueKey('utilities-trip-planner'),
                        icon: Icons.alt_route_rounded,
                        title: 'Lộ trình',
                        value: 'Chọn điểm đến, ước tính pin cần dùng',
                        lockedBy: PremiumFeature.tripEstimate,
                        onTap: () => push(const TripPlannerWrapper()),
                      ),
                  ],
                ),
              ),
              const LuxeSectionLabel('XE & AI CÁ NHÂN'),
              LuxeReveal(
                index: 1,
                child: LuxeTileGrid(
                  tiles: [
                    // QA 138: open on every plan (the owner's data, its
                    // switch and "delete"); only training is Ultra.
                    LuxeTile(
                      key: const ValueKey('utilities-personal-ai'),
                      icon: Icons.model_training_rounded,
                      title: 'AI cá nhân',
                      value: 'Dữ liệu đã thu thập, quyền học và Huấn luyện',
                      onTap: () {
                        final id = vehicleId();
                        if (id != null) {
                          push(PersonalAiSettingsScreen(vehicleId: id));
                        }
                      },
                    ),
                    LuxeTile(
                      key: const ValueKey('utilities-maintenance'),
                      icon: Icons.build_circle_rounded,
                      title: 'Bảo dưỡng xe',
                      value: 'Lịch theo ODO',
                      onTap: () => push(const MaintenanceScreen()),
                    ),
                    LuxeTile(
                      key: const ValueKey('utilities-achievements'),
                      icon: Icons.workspace_premium_rounded,
                      title: 'Thành tựu',
                      value:
                          '${achievements.unlockedCount}/${achievementCatalog.length} huy hiệu',
                      accent: achievements.rank.rarity.accent,
                      onTap: () => push(const AchievementsScreen()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
