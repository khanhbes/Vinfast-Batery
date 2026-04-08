import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/animated_battery_gauge.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../core/widgets/stat_card.dart';
import '../../data/models/charge_log_model.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/repositories/charge_log_repository.dart';
import '../charge_log/add_charge_log_modal.dart';
import '../../core/widgets/quick_action_menu.dart';
import '../settings/guide_screen.dart';
import '../settings/ai_functions_screen.dart';

// =============================================================================
// Providers
// =============================================================================

final selectedVehicleIdProvider = StateProvider<String>((ref) => '');

/// Provider khởi tạo: đọc vehicleId đã lưu từ SharedPreferences
final _restoreVehicleIdProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('selected_vehicle_id') ?? '';
});

final vehicleProvider = FutureProvider.family<VehicleModel?, String>((ref, id) {
  if (id.isEmpty) return Future.value(null);
  return ref.watch(chargeLogRepositoryProvider).getVehicle(id);
});

final chargeLogsProvider =
    FutureProvider.family<List<ChargeLogModel>, String>((ref, id) {
  if (id.isEmpty) return Future.value([]);
  return ref.watch(chargeLogRepositoryProvider).getChargeLogs(id);
});

final vehicleStatsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) {
  if (id.isEmpty) {
    return Future.value({
      'totalCharges': 0,
      'avgChargeGain': 0.0,
      'totalEnergyGained': 0,
      'avgChargeDuration': 0.0,
      'avgStartBattery': 0.0,
      'avgEndBattery': 0.0,
    });
  }
  return ref.watch(chargeLogRepositoryProvider).getStats(id);
});

final allVehiclesProvider = FutureProvider<List<VehicleModel>>((ref) async {
  final vehicles = await ref.watch(chargeLogRepositoryProvider).getAllVehicles();
  // Tự động chọn xe đầu tiên nếu chưa có xe nào được chọn
  if (vehicles.isNotEmpty) {
    final currentId = ref.read(selectedVehicleIdProvider);
    if (currentId.isEmpty || !vehicles.any((v) => v.vehicleId == currentId)) {
      // sẽ được cập nhật trong widget
    }
  }
  return vehicles;
});

// =============================================================================
// Home Screen
// =============================================================================

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    final vehicleAsync = ref.watch(vehicleProvider(vehicleId));
    final logsAsync = ref.watch(chargeLogsProvider(vehicleId));
    final statsAsync = ref.watch(vehicleStatsProvider(vehicleId));
    final allVehiclesAsync = ref.watch(allVehiclesProvider);
    final restoredId = ref.watch(_restoreVehicleIdProvider);

    // Auto-select: ưu tiên ID đã persist, fallback xe đầu tiên
    allVehiclesAsync.whenData((vehicles) {
      if (vehicles.isNotEmpty && vehicleId.isEmpty) {
        String targetId = vehicles.first.vehicleId;
        restoredId.whenData((savedId) {
          if (savedId.isNotEmpty && vehicles.any((v) => v.vehicleId == savedId)) {
            targetId = savedId;
          }
        });
        Future.microtask(() {
          ref.read(selectedVehicleIdProvider.notifier).state = targetId;
        });
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryGreen,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.invalidate(vehicleProvider(vehicleId));
            ref.invalidate(chargeLogsProvider(vehicleId));
            ref.invalidate(vehicleStatsProvider(vehicleId));
            ref.invalidate(allVehiclesProvider);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // ── Header với Vehicle Switcher ──
              SliverToBoxAdapter(
                child: _HomeHeader(
                  vehicleAsync: vehicleAsync,
                  allVehiclesAsync: allVehiclesAsync,
                  selectedId: vehicleId,
                  onVehicleChanged: (id) async {
                    ref.read(selectedVehicleIdProvider.notifier).state = id;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('selected_vehicle_id', id);
                  },
                ),
              ),

              // ── Battery Gauge lớn ──
              SliverToBoxAdapter(
                child: _buildBatterySection(vehicleAsync, ref),
              ),

              // ── Quick Stats ──
              SliverToBoxAdapter(
                child: _buildQuickStats(statsAsync),
              ),

              // ── Recent Charges Header ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.history_rounded,
                            color: AppColors.info, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Sạc gần đây',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Spacer(),
                      logsAsync.when(
                        data: (logs) => logs.isNotEmpty
                            ? Text(
                                '${logs.length} lần',
                                style: const TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 13,
                                ),
                              )
                            : const SizedBox.shrink(),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Recent Charges List ──
              _buildRecentCharges(logsAsync, ref),

              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
      floatingActionButton: QuickActionFab(
        vehicleId: vehicleId.isEmpty ? null : vehicleId,
        onAction: (action) {
          switch (action) {
            case QuickAction.addCharge:
              AddChargeLogModal.show(context, vehicleId).then((result) {
                if (result == true) {
                  ref.invalidate(vehicleProvider(vehicleId));
                  ref.invalidate(chargeLogsProvider(vehicleId));
                  ref.invalidate(vehicleStatsProvider(vehicleId));
                  ref.invalidate(allVehiclesProvider);
                }
              });
            case QuickAction.aiFunctions:
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiFunctionsScreen()),
              );
            case QuickAction.guide:
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GuideScreen()),
              );
            case QuickAction.startTrip:
            case QuickAction.startCharge:
            case QuickAction.manualTrip:
            case QuickAction.routePrediction:
              // These actions belong to Dashboard — no-op from Home
              break;
          }
        },
      ),
    );
  }

  // ── Battery Gauge Section ──
  Widget _buildBatterySection(AsyncValue<VehicleModel?> vehicleAsync, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: vehicleAsync.when(
        data: (vehicle) {
          if (vehicle == null) return const SizedBox.shrink();
          final percent = vehicle.lastBatteryPercent;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedBatteryGauge(
                      batteryPercent: percent,
                      size: 180,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.speed_rounded,
                            color: AppColors.textTertiary, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'ODO: ${vehicle.currentOdo} km',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(
          child: SizedBox(
            width: 180,
            height: 180,
            child: LoadingSkeleton(layout: SkeletonLayout.gauge),
          ),
        ),
        error: (e, _) => ErrorState.fromError(
          error: e,
          prefix: 'Không tải được dữ liệu xe',
          onRetry: () => ref.invalidate(vehicleProvider(ref.read(selectedVehicleIdProvider))),
        ),
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 600.ms).scale(begin: const Offset(0.9, 0.9));
  }

  // ── Quick Stats Grid ──
  Widget _buildQuickStats(AsyncValue<Map<String, dynamic>> statsAsync) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: statsAsync.when(
        data: (stats) {
          final total = stats['totalCharges'] as int? ?? 0;
          if (total == 0) return const SizedBox.shrink();
          return LayoutBuilder(
            builder: (context, constraints) {
              final ratio = constraints.maxWidth > 380 ? 1.3 : constraints.maxWidth > 300 ? 1.1 : 0.95;
              return GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: ratio,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
            children: [
              StatCard(
                icon: Icons.battery_charging_full_rounded,
                iconColor: AppColors.primaryGreen,
                title: 'Tổng lần sạc',
                value: '$total',
                subtitle: 'lần',
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.3),
              StatCard(
                icon: Icons.trending_up_rounded,
                iconColor: AppColors.info,
                title: 'Sạc trung bình',
                value:
                    '${((stats['avgChargeGain'] as double?) ?? 0.0).toStringAsFixed(0)}%',
                subtitle: 'mỗi lần sạc',
              ).animate().fadeIn(delay: 380.ms).slideY(begin: 0.3),
              StatCard(
                icon: Icons.bolt_rounded,
                iconColor: AppColors.warning,
                title: 'Năng lượng nạp',
                value: '${stats['totalEnergyGained']}%',
                subtitle: 'tổng cộng',
              ).animate().fadeIn(delay: 460.ms).slideY(begin: 0.3),
              StatCard(
                icon: Icons.timer_outlined,
                iconColor: AppColors.error,
                title: 'Thời gian TB',
                value:
                    '${((stats['avgChargeDuration'] as double?) ?? 0.0).toStringAsFixed(1)}h',
                subtitle: 'mỗi lần sạc',
              ).animate().fadeIn(delay: 540.ms).slideY(begin: 0.3),
            ],
          );
            },
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: LoadingSkeleton(layout: SkeletonLayout.stats),
        ),
        error: (e, _) => const SizedBox.shrink(),
      ),
    );
  }

  // ── Recent Charges ──
  Widget _buildRecentCharges(AsyncValue<List<ChargeLogModel>> logsAsync, WidgetRef ref) {
    return logsAsync.when(
      data: (logs) {
        if (logs.isEmpty) {
          return SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.battery_unknown_rounded,
              title: 'Chưa có nhật ký sạc',
              message: 'Nhấn "Nhập sạc" để ghi lại lần sạc đầu tiên',
            ),
          );
        }

        final recent = logs.take(5).toList();
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final log = recent[index];
              return _ChargeLogTile(log: log)
                  .animate()
                  .fadeIn(delay: (700 + index * 80).ms)
                  .slideX(begin: 0.15);
            },
            childCount: recent.length,
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: LoadingSkeleton(layout: SkeletonLayout.list, itemCount: 3),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: ErrorState.fromError(
          error: e,
          prefix: 'Không tải được nhật ký sạc',
          onRetry: () => ref.invalidate(chargeLogsProvider(ref.read(selectedVehicleIdProvider))),
        ),
      ),
    );
  }
}

// =============================================================================
// Home Header — Vehicle Selector đẹp
// =============================================================================

class _HomeHeader extends ConsumerWidget {
  final AsyncValue<VehicleModel?> vehicleAsync;
  final AsyncValue<List<VehicleModel>> allVehiclesAsync;
  final String selectedId;
  final void Function(String) onVehicleChanged;

  const _HomeHeader({
    required this.vehicleAsync,
    required this.allVehiclesAsync,
    required this.selectedId,
    required this.onVehicleChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // App Logo
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primaryGreen, AppColors.accentGreen],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGreen.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.electric_bolt_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VinFast Battery',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      'Quản lý pin xe điện',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Notification badge (placeholder)
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.notifications_none_rounded,
                    color: AppColors.textSecondary, size: 20),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Vehicle Switcher Tabs
          allVehiclesAsync.when(
            data: (vehicles) {
              if (vehicles.isEmpty) return const SizedBox.shrink();
              if (vehicles.length == 1) {
                final v = vehicles.first;
                return _SingleVehicleBanner(vehicle: v);
              }
              return _VehicleSwitcherTabs(
                vehicles: vehicles,
                selectedId: selectedId,
                onSelect: onVehicleChanged,
              );
            },
            loading: () => const SizedBox(height: 48),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.05);
  }
}

// ── Single vehicle banner khi chỉ có 1 xe ──
class _SingleVehicleBanner extends StatelessWidget {
  final VehicleModel vehicle;
  const _SingleVehicleBanner({required this.vehicle});

  Color get _avatarColor {
    final hex = vehicle.avatarColor ?? '#00C853';
    try {
      return Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
    } catch (_) {
      return AppColors.primaryGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _avatarColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _avatarColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _avatarColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.electric_moped_rounded,
                color: _avatarColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              vehicle.vehicleName.isNotEmpty
                  ? vehicle.vehicleName
                  : vehicle.vehicleId,
              style: TextStyle(
                color: _avatarColor,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Icon(Icons.electric_bolt_rounded, color: _avatarColor, size: 16),
          const SizedBox(width: 4),
          Text(
            '${vehicle.lastBatteryPercent}%',
            style: TextStyle(
              color: _avatarColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Multi-vehicle tab switcher ──
class _VehicleSwitcherTabs extends StatelessWidget {
  final List<VehicleModel> vehicles;
  final String selectedId;
  final void Function(String) onSelect;

  const _VehicleSwitcherTabs({
    required this.vehicles,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: vehicles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final v = vehicles[i];
          final isSelected = v.vehicleId == selectedId;
          Color avatarColor;
          try {
            final hex = (v.avatarColor ?? '#00C853').replaceFirst('#', 'FF');
            avatarColor = Color(int.parse(hex, radix: 16));
          } catch (_) {
            avatarColor = AppColors.primaryGreen;
          }

          return GestureDetector(
            onTap: () => onSelect(v.vehicleId),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? avatarColor.withValues(alpha: 0.15)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? avatarColor.withValues(alpha: 0.5)
                      : AppColors.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.electric_moped_rounded,
                    color: isSelected ? avatarColor : AppColors.textTertiary,
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    v.vehicleName.isNotEmpty ? v.vehicleName : v.vehicleId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? avatarColor : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: avatarColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${v.lastBatteryPercent}%',
                        style: TextStyle(
                          color: avatarColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Charge Log Tile (compact, premium)
// =============================================================================

class _ChargeLogTile extends StatelessWidget {
  final ChargeLogModel log;
  const _ChargeLogTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM HH:mm');
    final gain = log.chargeGain;
    final gainColor = gain >= 50
        ? AppColors.primaryGreen
        : gain >= 20
            ? AppColors.warning
            : AppColors.info;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Battery level indicator
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  gainColor.withValues(alpha: 0.2),
                  gainColor.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: gainColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bolt_rounded, color: gainColor, size: 15),
                Text(
                  '+$gain%',
                  style: TextStyle(
                    color: gainColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${log.startBatteryPercent}% → ${log.endBatteryPercent}%',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        color: AppColors.textTertiary, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      '${dateFormat.format(log.startTime)} · ${log.durationText}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ODO badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                const Icon(Icons.speed_rounded, color: AppColors.info, size: 11),
                const SizedBox(height: 2),
                Text(
                  '${log.odoAtCharge}',
                  style: const TextStyle(
                    color: AppColors.info,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Text(
                  'km',
                  style: TextStyle(
                    color: AppColors.info,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
