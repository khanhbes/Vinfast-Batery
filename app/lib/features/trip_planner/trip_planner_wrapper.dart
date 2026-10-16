import 'package:flutter/material.dart';
import '../../core/widgets/vehicle_picker_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../core/widgets/luxe_kit.dart';
import 'trip_planner_screen.dart';

/// Wrapper để TripPlannerScreen hoạt động standalone trong bottom nav
/// Tự lấy vehicle từ selectedVehicleIdProvider
class TripPlannerWrapper extends ConsumerWidget {
  const TripPlannerWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    final vehicleAsync = ref.watch(vehicleProvider(vehicleId));

    return vehicleAsync.when(
      loading: () => const LuxeScaffold(
        title: 'Lập kế hoạch chuyến đi',
        body: Padding(
          padding: EdgeInsets.all(20),
          child: LoadingSkeleton(layout: SkeletonLayout.list, itemCount: 3),
        ),
      ),
      error: (e, _) => LuxeScaffold(
        title: 'Lập kế hoạch chuyến đi',
        body: ErrorState(
          message: 'Không tải được thông tin xe',
          onRetry: () => ref.invalidate(vehicleProvider(vehicleId)),
        ),
      ),
      data: (vehicle) {
        if (vehicle == null) {
          return LuxeScaffold(
            title: 'Lập kế hoạch chuyến đi',
            body: EmptyState(
              icon: Icons.electric_moped_rounded,
              title: 'Chưa chọn xe',
              message: 'Chọn xe để lập kế hoạch chuyến đi.',
              actionLabel: 'Chọn xe ngay',
              onAction: () => VehiclePickerSheet.show(context, ref),
            ),
          );
        }
        return TripPlannerScreen(vehicle: vehicle);
      },
    );
  }
}
