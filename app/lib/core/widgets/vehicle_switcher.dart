import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/session_service.dart';
import '../theme/app_ui_colors.dart';
import 'vehicle_picker_sheet.dart';

/// Compact, global vehicle selector used by the V4 shell.
/// Tapping opens the premium VehiclePickerSheet bottom sheet
/// with full vehicle specs (capacity, range, battery type).
class VehicleSwitcher extends ConsumerWidget {
  const VehicleSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedVehicleIdProvider);
    final vehicles = ref.watch(allVehiclesProvider);
    return vehicles.when(
      loading: () => const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        final active = items.where((v) => !v.isArchived).toList();
        if (active.isEmpty) return const SizedBox.shrink();
        final current = active.firstWhere(
          (v) => v.vehicleId == selectedId,
          orElse: () => active.first,
        );
        if (selectedId != current.vehicleId) {
          // Keep the global context and the visible switcher in sync when a
          // new account has no persisted selection (or the old vehicle was
          // archived). Defer mutation until after build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            final notifier = ref.read(selectedVehicleIdProvider.notifier);
            if (notifier.state == current.vehicleId) return;
            notifier.state = current.vehicleId;
            unawaited(SessionService().setSelectedVehicleId(current.vehicleId));
          });
        }
        final displayName = current.nickname?.isNotEmpty == true
            ? current.nickname!
            : (current.vinfastModelName?.isNotEmpty == true
                ? current.vinfastModelName!
                : (current.vehicleName.isNotEmpty ? current.vehicleName : 'Chọn xe'));

        return Semantics(
          button: true,
          label: 'Chọn xe. Đang chọn: $displayName',
          hint: 'Chạm để đổi xe trong gara',
          child: Tooltip(
            message: 'Đổi xe: $displayName',
            child: SizedBox(
              width: switch (MediaQuery.sizeOf(context).width) {
                < 430 => 96,
                < 600 => 128,
                _ => 160,
              },
              child: TextButton.icon(
                onPressed: () => VehiclePickerSheet.show(context, ref),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  backgroundColor: AppUiColors.of(context).elevated,
                ),
                icon: const Icon(Icons.directions_bike_rounded, size: 16),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    displayName,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
