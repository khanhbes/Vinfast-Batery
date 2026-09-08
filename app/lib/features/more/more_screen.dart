import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/vehicle_context_provider.dart';
import '../../core/services/feature_availability_registry.dart';
import '../../core/widgets/feature_availability_tile.dart';
import '../ai/ai_models_screen.dart';
import '../maintenance/maintenance_screen.dart';
import '../settings/settings_screen.dart';
import '../trip_planner/trip_planner_wrapper.dart';
import '../ai/controllers/smart_charging_controller.dart';

/// V4 secondary feature hub. Features remain reachable without becoming
/// primary navigation tabs, and availability is evaluated centrally.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleContext = ref.watch(vehicleContextProvider);
    final vehicleId = vehicleContext.vehicleId;
    // An empty context is a missing-data state, not a Shelly connectivity
    // error. Keep the secondary hub honest before a vehicle is selected.
    var availability = FeatureAvailabilityRegistry(
      hasVehicleData: vehicleId.isNotEmpty,
    ).smartCharge(ai: true);
    if (vehicleId.isNotEmpty) {
      final vehicle = vehicleContext.vehicle;
      if (vehicle != null) {
        final args = SmartChargingControllerArgs(
          vehicleId: vehicleId,
          currentSoc: vehicle.currentBattery.toDouble(),
        );
        final charging = ref.watch(smartChargingControllerProvider(args));
        availability = FeatureAvailabilityRegistry(
          modelLoaded:
              charging.preview?.runtimeHealth == 'loaded' ||
              charging.preview?.aiChargeEligible == true,
          chargerReady: charging.capabilities.readyForControl,
          lanAvailable: charging.capabilities.lanAvailable,
          hasVehicleData: vehicle.batteryCapacityWh > 0 || vehicle.hasModelLink,
          online: charging.connectionState.internetAvailable,
        ).smartCharge(ai: true);
      }
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FeatureAvailabilityTile(
          icon: Icons.psychology_rounded,
          title: 'AI & Tính năng',
          subtitle: 'Khám phá các công cụ AI cho xe đã chọn',
          availability: availability,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AiModelsScreen()),
          ),
        ).appFadeSlideIn(),
        ListTile(
          leading: const Icon(Icons.map_rounded),
          title: const Text('Trip Planner'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TripPlannerWrapper()),
          ),
        ).appFadeSlideIn(index: 1),
        ListTile(
          leading: const Icon(Icons.build_rounded),
          title: const Text('Bảo dưỡng'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MaintenanceScreen()),
          ),
        ).appFadeSlideIn(index: 2),
        ListTile(
          leading: const Icon(Icons.settings_rounded),
          title: const Text('Cài đặt'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ).appFadeSlideIn(index: 3),
      ],
    );
  }
}
