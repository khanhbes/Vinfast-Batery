import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/session_service.dart';
import '../theme/cockpit_design_system.dart';

/// Compact, global vehicle selector used by the V4 shell.
/// Changing it only changes context; it never deletes or mutates a vehicle.
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
        return PopupMenuButton<String>(
          tooltip: 'Đổi xe',
          onSelected: (id) {
            ref.read(selectedVehicleIdProvider.notifier).state = id;
            // Persist context immediately so the same vehicle is restored on
            // the next foreground/login without touching charging sessions.
            unawaited(SessionService().setSelectedVehicleId(id));
          },
          itemBuilder: (_) => [
            for (final vehicle in active)
              PopupMenuItem<String>(
                value: vehicle.vehicleId,
                child: Semantics(
                  selected: vehicle.vehicleId == current.vehicleId,
                  label: 'Chọn ${vehicle.vehicleName}',
                  child: Row(
                    children: [
                      Icon(
                        vehicle.vehicleId == current.vehicleId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          vehicle.vehicleName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          child: Semantics(
            button: true,
            label: 'Xe đang chọn: ${current.vehicleName}. Nhấn để đổi xe',
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: CockpitColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: CockpitColors.emerald.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: CockpitColors.emerald.withValues(alpha: .25),
                      ),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      size: 15,
                      color: CockpitColors.emerald,
                    ),
                  ),
                  const SizedBox(width: 7),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      current.vehicleName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: CockpitColors.muted,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
