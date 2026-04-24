import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../core/widgets/stat_card.dart';
import '../../data/models/charge_log_model.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/repositories/charge_log_repository.dart';

import 'widgets/battery_status_card.dart';
import 'widgets/daily_brief_section.dart';
import 'widgets/ai_insights_section.dart';
import 'widgets/quick_actions_floating.dart';

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

final chargeLogsProvider = FutureProvider.family<List<ChargeLogModel>, String>((
  ref,
  id,
) {
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
  final vehicles = await ref
      .watch(chargeLogRepositoryProvider)
      .getAllVehicles();
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
          if (savedId.isNotEmpty &&
              vehicles.any((v) => v.vehicleId == savedId)) {
            targetId = savedId;
          }
        });
        Future.microtask(() {
          ref.read(selectedVehicleIdProvider.notifier).state = targetId;
        });
      }
    });

    // Daily Brief mock data dựa trên trạng thái xe
    final dailyBriefs = _buildDailyBriefs(vehicleAsync);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.vinfastBlue,
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
              // ── Header V2 ──
              SliverToBoxAdapter(
                child: _HomeHeaderV2(
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

              // ── Battery Status Card V2 ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: vehicleAsync.when(
                    data: (vehicle) {
                      if (vehicle == null) return const SizedBox.shrink();
                      return BatteryStatusCard(vehicle: vehicle);
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
                      onRetry: () => ref.invalidate(
                        vehicleProvider(ref.read(selectedVehicleIdProvider)),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Daily Brief ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: DailyBriefSection(briefs: dailyBriefs),
                ),
              ),

              // ── AI Insights Section ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: const AiInsightsSection(),
                ),
              ),

              // ── Quick Stats ──
              SliverToBoxAdapter(child: _buildQuickStats(statsAsync)),

              // ── Recent Charges Header ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.infoBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.history_rounded,
                          color: AppColors.vinfastBlue,
                          size: 18,
                        ),
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
      floatingActionButton: QuickActionsFloating(
        onHistory: () {
          // Scroll to charges section
        },
      ),
    );
  }

  List<DailyBriefModel> _buildDailyBriefs(AsyncValue<VehicleModel?> vehicleAsync) {
    final vehicle = vehicleAsync.valueOrNull;
    if (vehicle == null) return [];

    final briefs = <DailyBriefModel>[];

    if (vehicle.lastBatteryPercent < 30) {
      briefs.add(DailyBriefModel(
        id: 'low_battery',
        title: 'Pin yếu — Cần sạc ngay',
        content: 'Pin chỉ còn ${vehicle.lastBatteryPercent}%. Hãy sạc lên 80% trước khi di chuyển.',
        type: DailyBriefType.warning,
        actionLabel: 'Tìm trạm sạc',
      ));
    }

    briefs.add(DailyBriefModel(
      id: 'daily_reminder',
      title: 'Nhắc nhở sạc mục tiêu',
      content: 'Bạn có lịch trình đi làm sáng mai. Hãy sạc pin lên 90% trước 11:00 tối nay.',
      type: DailyBriefType.info,
      actionLabel: 'Đặt lịch sạc',
    ));

    briefs.add(DailyBriefModel(
      id: 'maintenance',
      title: 'Bảo dưỡng định kỳ',
      content: 'Còn 500km nữa là đến kỳ bảo dưỡng hệ thống làm mát pin.',
      type: DailyBriefType.alert,
      actionLabel: 'Đặt hẹn',
    ));

    return briefs;
  }

  // ── Quick Stats Grid V2 ──
  Widget _buildQuickStats(AsyncValue<Map<String, dynamic>> statsAsync) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: statsAsync.when(
        data: (stats) {
          final total = stats['totalCharges'] as int? ?? 0;
          if (total == 0) return const SizedBox.shrink();
          return LayoutBuilder(
            builder: (context, constraints) {
              final ratio = constraints.maxWidth > 380
                  ? 1.3
                  : constraints.maxWidth > 300
                  ? 1.1
                  : 0.95;
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
                    iconColor: AppColors.vinfastBlue,
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
  Widget _buildRecentCharges(
    AsyncValue<List<ChargeLogModel>> logsAsync,
    WidgetRef ref,
  ) {
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
          delegate: SliverChildBuilderDelegate((context, index) {
            final log = recent[index];
            return _ChargeLogTile(log: log)
                .animate()
                .fadeIn(delay: (700 + index * 80).ms)
                .slideX(begin: 0.15);
          }, childCount: recent.length),
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
          onRetry: () => ref.invalidate(
            chargeLogsProvider(ref.read(selectedVehicleIdProvider)),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Home Header V2 — VinFast Battery Pro style
// =============================================================================

class _HomeHeaderV2 extends ConsumerWidget {
  final AsyncValue<VehicleModel?> vehicleAsync;
  final AsyncValue<List<VehicleModel>> allVehiclesAsync;
  final String selectedId;
  final void Function(String) onVehicleChanged;

  const _HomeHeaderV2({
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
          // App Header Row
          Row(
            children: [
              // VinFast branding
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VinFast',
                      style: TextStyle(
                        color: AppColors.vinfastBlue,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      'BATTERY PRO',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
              ),
              // Status indicator
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.success.withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Vehicle Switcher
          allVehiclesAsync.when(
            data: (vehicles) {
              if (vehicles.isEmpty) return const SizedBox.shrink();
              if (vehicles.length == 1) {
                final v = vehicles.first;
                return _SingleVehicleBannerV2(vehicle: v);
              }
              return _VehicleSwitcherTabsV2(
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
    ).animate().fadeIn(duration: 400.ms);
  }
}

// ── Single vehicle banner V2 ──
class _SingleVehicleBannerV2 extends StatelessWidget {
  final VehicleModel vehicle;
  const _SingleVehicleBannerV2({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.vinfastBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.vinfastBlue.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.vinfastBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.electric_moped_rounded,
              color: AppColors.vinfastBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              vehicle.vehicleName.isNotEmpty
                  ? vehicle.vehicleName
                  : vehicle.vehicleId,
              style: const TextStyle(
                color: AppColors.vinfastBlue,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.vinfastBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt_rounded,
                    color: AppColors.vinfastBlue, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${vehicle.lastBatteryPercent}%',
                  style: const TextStyle(
                    color: AppColors.vinfastBlue,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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

// ── Multi-vehicle tab switcher V2 ──
class _VehicleSwitcherTabsV2 extends StatelessWidget {
  final List<VehicleModel> vehicles;
  final String selectedId;
  final void Function(String) onSelect;

  const _VehicleSwitcherTabsV2({
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

          return GestureDetector(
            onTap: () => onSelect(v.vehicleId),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.vinfastBlue.withValues(alpha: 0.12)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? AppColors.vinfastBlue.withValues(alpha: 0.4)
                      : AppColors.glassBorder,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.electric_moped_rounded,
                    color: isSelected
                        ? AppColors.vinfastBlue
                        : AppColors.textTertiary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    v.vehicleName.isNotEmpty ? v.vehicleName : v.vehicleId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.vinfastBlue
                          : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.vinfastBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${v.lastBatteryPercent}%',
                        style: const TextStyle(
                          color: AppColors.vinfastBlue,
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
        ? AppColors.vinfastBlue
        : gain >= 20
        ? AppColors.warning
        : AppColors.info;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
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
              border: Border.all(color: gainColor.withValues(alpha: 0.3)),
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
                    const Icon(
                      Icons.access_time_rounded,
                      color: AppColors.textTertiary,
                      size: 12,
                    ),
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
                const Icon(
                  Icons.speed_rounded,
                  color: AppColors.info,
                  size: 11,
                ),
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
                  style: TextStyle(color: AppColors.info, fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
