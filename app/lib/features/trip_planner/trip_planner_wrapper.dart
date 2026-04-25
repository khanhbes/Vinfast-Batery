import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/widgets/loading_skeleton.dart';
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
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: LoadingSkeleton(layout: SkeletonLayout.list, itemCount: 3),
        ),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text(
                'Không tải được thông tin xe',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
      data: (vehicle) {
        if (vehicle == null) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.electric_moped_rounded,
                      color: AppColors.textTertiary, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'Trip Planner / Lộ trình',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Vui lòng thêm xe để sử dụng tính năng này',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }
        return TripPlannerScreen(vehicle: vehicle);
      },
    );
  }
}
