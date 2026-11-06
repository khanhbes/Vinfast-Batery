import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/services/guide_registry.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/vehicle_picker_sheet.dart';
import '../ai/controllers/smart_charging_controller.dart';
import '../ai/smart_charge_history_screen.dart';
import '../ai/smart_charging_control_screen.dart';
import '../auth/auth_providers.dart';
import 'charge_section_switcher.dart';

/// Vehicle-scoped Sạc pin tab (QA 140): Sạc AI | Theo giờ | Lịch sử. The
/// switcher sits above the content and stays while a charge runs.
class ChargeScreen extends ConsumerWidget {
  const ChargeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(chargeSectionProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: KeyedSubtree(
            key: GuideRegistry.keyChargeMode,
            child: ChargeSectionSwitcher(
              value: section,
              onChanged: (next) =>
                  ref.read(chargeSectionProvider.notifier).state = next,
            ),
          ),
        ),
        Expanded(
          child: section == ChargeSection.history
              ? const ChargeHistoryView()
              : const _ChargeControl(),
        ),
      ],
    );
  }
}

class _ChargeControl extends ConsumerWidget {
  const _ChargeControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleContext = ref.watch(vehicleContextProvider);
    final vehicleId = vehicleContext.vehicleId;
    if (vehicleId.isEmpty) {
      return EmptyState(
        icon: Icons.electric_bolt_rounded,
        title: 'Chưa chọn phương tiện',
        message:
            'Vui lòng chọn xe VinFast của bạn để sử dụng tính năng sạc thông minh.',
        actionLabel: 'Chọn xe ngay',
        onAction: () => VehiclePickerSheet.show(context, ref),
      );
    }
    // The context owns the identity; the async provider preserves a distinct
    // loading/error state instead of showing an endless spinner on failure.
    final vehicle = ref.watch(vehicleProvider(vehicleId));
    return vehicle.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorState.fromError(
        error: error,
        prefix: 'Chưa tải được thông tin xe',
        onRetry: () => ref.invalidate(vehicleProvider(vehicleId)),
      ),
      data: (value) => value == null
          ? EmptyState(
              icon: Icons.electric_bike_rounded,
              title: 'Chưa có dữ liệu xe',
              message: 'Không tìm thấy dữ liệu cho phương tiện đã chọn.',
              actionLabel: 'Chọn xe khác',
              onAction: () => VehiclePickerSheet.show(context, ref),
            )
          : SmartChargingControlScreen(
              // Task 125: one State per vehicle. Its controller args are
              // fixed in initState, so reusing the State after a vehicle
              // switch could send Start/Stop for the previous vehicle.
              key: ValueKey('charge-control-$vehicleId'),
              vehicleId: vehicleId,
              currentSoc: value.currentBattery.toDouble(),
              embedded: true,
              confirmStartSoc: true,
              startSocSavedAt: value.batteryDataUpdatedAt,
              startSocSource: value.batteryDataSource,
              currentOdoKm: value.currentOdo.toDouble(),
            ),
    );
  }
}

/// Sạc pin → Lịch sử (the History tab before QA 140).
class ChargeHistoryView extends ConsumerWidget {
  const ChargeHistoryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedVehicleIdProvider);
    final pending = ref.watch(pendingSmartChargeTargetProvider);
    final id = pending?.vehicleId ?? selectedId;
    if (id.isEmpty) {
      return EmptyState(
        icon: Icons.history_rounded,
        title: 'Chưa chọn phương tiện',
        message:
            'Vui lòng chọn xe VinFast của bạn để xem toàn bộ lịch sử sạc pin.',
        actionLabel: 'Chọn xe ngay',
        onAction: () => VehiclePickerSheet.show(context, ref),
      );
    }
    final vehicle = ref.watch(vehicleProvider(id));
    return vehicle.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState.fromError(
        error: e,
        prefix: 'Chưa tải được lịch sử',
        onRetry: () => ref.invalidate(vehicleProvider(id)),
      ),
      data: (value) {
        final args = SmartChargingControllerArgs(
          vehicleId: id,
          currentSoc: (value?.currentBattery ?? 0).toDouble(),
        );
        final history = ref.watch(
          smartChargingControllerProvider(args).select((s) => s.history),
        );
        final controller = ref.read(
          smartChargingControllerProvider(args).notifier,
        );
        return SmartChargeHistoryScreen(
          controller: controller,
          ownerUid: ref.watch(currentUidProvider),
          initialItems: history,
          embedded: true,
          initialSessionId: pending?.sessionId,
          onStartCharging: () =>
              ref.read(chargeSectionProvider.notifier).state = ChargeSection.ai,
          onPendingTargetConsumed: pending == null
              ? null
              : () =>
                    ref.read(pendingSmartChargeTargetProvider.notifier).state =
                        null,
        );
      },
    );
  }
}
