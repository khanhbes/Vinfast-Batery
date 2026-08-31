import '../models/feature_availability.dart';

/// Centralizes runtime availability decisions; remote feature flags remain
/// separate from device/account readiness.
class FeatureAvailabilityRegistry {
  const FeatureAvailabilityRegistry({
    this.modelLoaded = false,
    this.chargerReady = false,
    this.hasVehicleData = true,
    this.online = true,
    this.lanAvailable = false,
  });

  final bool modelLoaded;
  final bool chargerReady;
  final bool hasVehicleData;
  final bool online;
  final bool lanAvailable;

  FeatureAvailability smartCharge({bool ai = false}) {
    // Vehicle identity/data is required for every charging action, including
    // a LAN-only timed charge. Do not let offline availability bypass this
    // safety gate.
    if (!hasVehicleData) {
      return const FeatureAvailability(
        state: FeatureAvailabilityState.needsData,
        reason: 'Cần thêm dữ liệu xe',
      );
    }
    if (!online) {
      // A reachable Shelly on LAN can still execute a device timer and safe
      // manual ON/OFF. Only server-backed AI preview needs the Internet.
      if (!ai && chargerReady && lanAvailable) {
        return const FeatureAvailability(
          state: FeatureAvailabilityState.ready,
          reason: 'Điều khiển qua LAN; AI tạm dừng khi mất Internet',
        );
      }
      return const FeatureAvailability(
        state: FeatureAvailabilityState.offline,
        reason: 'Mất kết nối mạng',
      );
    }
    if (!chargerReady) {
      return const FeatureAvailability(
        state: FeatureAvailabilityState.needsSetup,
        reason: 'Cần kết nối Shelly',
      );
    }
    if (ai && !modelLoaded) {
      return const FeatureAvailability(
        state: FeatureAvailabilityState.disabled,
        reason: 'Model AI chưa sẵn sàng',
      );
    }
    return const FeatureAvailability(
      state: FeatureAvailabilityState.ready,
      reason: 'Sẵn sàng',
    );
  }
}
