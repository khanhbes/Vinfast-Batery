import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../core/providers/connection_status_providers.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/models/vinfast_model_spec.dart';
import '../../data/repositories/charge_log_repository.dart';
import '../../data/repositories/vehicle_spec_repository.dart';
import '../../data/services/vehicle_model_link_service.dart';
import '../../data/services/ai_prediction_service.dart';
import '../../core/widgets/vehicle_detail_sheet.dart';
import '../home/home_screen.dart';
import 'guide_screen.dart';
import 'ai_functions_screen.dart';

// =============================================================================
// Settings Screen - Quản lý xe (Thêm/Xóa) + Cài đặt app
// =============================================================================

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    final allVehicles = ref.watch(allVehiclesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryGreen,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.invalidate(allVehiclesProvider);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
            // ── Header ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cài đặt',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Quản lý xe & tùy chỉnh ứng dụng',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Nút thêm xe
                    GestureDetector(
                      onTap: () => _showAddVehicleDialog(context, ref),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.vinfastBlue,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.vinfastBlue.withValues(alpha: 0.3),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1),
              ),
            ),

            // ── Section: Garage (Danh sách xe) ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                child: _SectionHeader(
                  icon: Icons.garage_rounded,
                  title: 'Garage',
                  subtitle: allVehicles.when(
                    data: (v) => '${v.length} xe',
                    loading: () => '...',
                    error: (_, _) => '',
                  ),
                ),
              ).animate().fadeIn(delay: 150.ms),
            ),

            // ── Vehicle List ──
            allVehicles.when(
              data: (vehicles) {
                if (vehicles.isEmpty) {
                  return SliverToBoxAdapter(
                    child: _EmptyGarage(
                      onAdd: () => _showAddVehicleDialog(context, ref),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, index) {
                        final vehicle = vehicles[index];
                        final isSelected = vehicle.vehicleId == vehicleId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _VehicleCard(
                            vehicle: vehicle,
                            isSelected: isSelected,
                            onTap: () {
                              ref.read(selectedVehicleIdProvider.notifier).state =
                                  vehicle.vehicleId;
                            },
                            onLongPress: () => VehicleDetailSheet.show(
                              ctx,
                              vehicle,
                              onSelect: () {
                                ref.read(selectedVehicleIdProvider.notifier).state =
                                    vehicle.vehicleId;
                              },
                            ),
                            onDelete: vehicles.length > 1
                                ? () => _confirmDeleteVehicle(
                                    context, ref, vehicle, vehicleId)
                                : null,
                          ).animate().fadeIn(delay: (200 + index * 80).ms).slideY(begin: 0.2),
                        );
                      },
                      childCount: vehicles.length,
                    ),
                  ),
                );
              },
              loading: () => SliverToBoxAdapter(
                child: const Padding(
                  padding: EdgeInsets.all(20),
                  child: LoadingSkeleton(layout: SkeletonLayout.list, itemCount: 2),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: ErrorState.fromError(
                  error: e,
                  prefix: 'Không tải được danh sách xe',
                  onRetry: () => ref.invalidate(allVehiclesProvider),
                ),
              ),
            ),

            // ── App Info Section ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                child: _SectionHeader(
                  icon: Icons.widgets_rounded,
                  title: 'Ứng dụng',
                  subtitle: 'Thông tin & trạng thái',
                ),
              ).animate().fadeIn(delay: 350.ms),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _AppInfoTile(
                      icon: Icons.verified_rounded,
                      iconColor: AppColors.info,
                      title: 'Phiên bản',
                      value: AppConstants.appVersion,
                      valueColor: AppColors.info,
                    ).animate().fadeIn(delay: 400.ms),
                    const SizedBox(height: 8),
                    _FirebaseStatusTile(),
                    const SizedBox(height: 8),
                    _AiApiStatusTile(),
                    const SizedBox(height: 8),
                    _AiUrlConfigTile(),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AiFunctionsScreen()),
                      ),
                      child: _AppInfoTile(
                        icon: Icons.hub_rounded,
                        iconColor: const Color(0xFF7C4DFF),
                        title: 'AI Function Center',
                        value: 'Xem chi tiết →',
                        valueColor: const Color(0xFF7C4DFF),
                      ),
                    ).animate().fadeIn(delay: 560.ms),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const GuideScreen()),
                      ),
                      child: _AppInfoTile(
                        icon: Icons.menu_book_rounded,
                        iconColor: AppColors.info,
                        title: 'Hướng dẫn sử dụng',
                        value: 'Mở →',
                        valueColor: AppColors.info,
                      ),
                    ).animate().fadeIn(delay: 600.ms),
                  ],
                ),
              ),
            ),

            // ── About Card ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: _AboutCard(),
              ).animate().fadeIn(delay: 600.ms).scale(begin: const Offset(0.95, 0.95)),
            ),

            // ── Logout Button ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AppColors.surface,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text('Đăng xuất', style: TextStyle(color: AppColors.textPrimary)),
                          content: const Text('Bạn có chắc muốn đăng xuất?', style: TextStyle(color: AppColors.textSecondary)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Đăng xuất', style: TextStyle(color: AppColors.error))),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await FirebaseAuth.instance.signOut();
                      }
                    },
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Đăng xuất'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 700.ms),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
        ),
      ),
    );
  }

  // ─── Add Vehicle Dialog ────────────────────────────────────────────────────
  void _showAddVehicleDialog(BuildContext context, WidgetRef ref) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Add Vehicle',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => _AddVehicleDialog(
        onAdd: (id, name, colorHex, spec) async {
          final repo = ref.read(chargeLogRepositoryProvider);
          await repo.addVehicle(
            vehicleId: id,
            vehicleName: name,
            avatarColor: colorHex,
          );
          // Link VinFast model if selected
          if (spec != null) {
            final linkService = ref.read(vehicleModelLinkServiceProvider);
            await linkService.linkModel(vehicleId: id, spec: spec);
          }
          ref.invalidate(allVehiclesProvider);
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
      transitionBuilder: (_, anim, _, child) {
        return SlideTransition(
          position: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)
              .drive(Tween(begin: const Offset(0, 0.15), end: Offset.zero)),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
    );
  }

  // ─── Confirm Delete Dialog ─────────────────────────────────────────────────
  void _confirmDeleteVehicle(
      BuildContext context, WidgetRef ref, VehicleModel vehicle, String currentId) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.error, size: 32),
              ),
              const SizedBox(height: 16),
              const Text(
                'Xóa xe này?',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Toàn bộ lịch sử sạc của "${vehicle.vehicleName.isNotEmpty ? vehicle.vehicleName : vehicle.vehicleId}" sẽ bị xóa vĩnh viễn.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Hủy'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        final repo = ref.read(chargeLogRepositoryProvider);
                        await repo.deleteVehicle(vehicle.vehicleId);
                        // Nếu xóa xe đang chọn → chuyển sang xe khác
                        if (vehicle.vehicleId == currentId) {
                          final all = await repo.getAllVehicles();
                          if (all.isNotEmpty) {
                            ref.read(selectedVehicleIdProvider.notifier).state =
                                all.first.vehicleId;
                          }
                        }
                        ref.invalidate(allVehiclesProvider);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Xóa', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Vehicle Card
// =============================================================================

class _VehicleCard extends StatelessWidget {
  final VehicleModel vehicle;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;

  const _VehicleCard({
    required this.vehicle,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
    this.onDelete,
  });

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
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryGreen.withValues(alpha: 0.08)
              : AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryGreen.withValues(alpha: 0.4)
                : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            // Avatar xe
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _avatarColor,
                    _avatarColor.withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _avatarColor.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.electric_moped_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          vehicle.vehicleName.isNotEmpty
                              ? vehicle.vehicleName
                              : vehicle.vehicleId,
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.primaryGreen
                                : AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Đang dùng',
                            style: TextStyle(
                              color: AppColors.primaryGreen,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _MiniStat(
                        icon: Icons.speed_rounded,
                        value: '${vehicle.currentOdo} km',
                        color: AppColors.info,
                      ),
                      const SizedBox(width: 10),
                      _MiniStat(
                        icon: Icons.battery_charging_full_rounded,
                        value: '${vehicle.totalCharges} lần',
                        color: AppColors.primaryGreen,
                      ),
                      const SizedBox(width: 10),
                      _MiniStat(
                        icon: Icons.battery_std_rounded,
                        value: '${vehicle.lastBatteryPercent}%',
                        color: vehicle.lastBatteryPercent > 50
                            ? AppColors.primaryGreen
                            : vehicle.lastBatteryPercent > 20
                                ? AppColors.warning
                                : AppColors.error,
                      ),
                    ],
                  ),
                  // Model link badge
                  if (vehicle.hasModelLink) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.link_rounded,
                            color: AppColors.info, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          vehicle.vinfastModelName ?? vehicle.vinfastModelId ?? '',
                          style: const TextStyle(
                            color: AppColors.info,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Delete button
            if (onDelete != null && !isSelected)
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.error, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Add Vehicle Dialog
// =============================================================================

class _AddVehicleDialog extends ConsumerStatefulWidget {
  final Future<void> Function(String id, String name, String colorHex, VinFastModelSpec? spec) onAdd;
  const _AddVehicleDialog({required this.onAdd});

  @override
  ConsumerState<_AddVehicleDialog> createState() => _AddVehicleDialogState();
}

class _AddVehicleDialogState extends ConsumerState<_AddVehicleDialog> {
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  String _selectedColor = '#00C853';
  bool _isLoading = false;
  String? _error;
  VinFastModelSpec? _selectedSpec;
  List<VinFastModelSpec> _specs = [];

  final _colors = [
    '#00C853', // VinFast Green
    '#448AFF', // Blue
    '#FF6B6B', // Red
    '#FFB74D', // Orange
    '#AB47BC', // Purple
    '#26C6DA', // Cyan
    '#FFF176', // Yellow
    '#FF7043', // Deep Orange
  ];

  @override
  void initState() {
    super.initState();
    _loadSpecs();
  }

  Future<void> _loadSpecs() async {
    try {
      final specRepo = ref.read(vehicleSpecRepositoryProvider);
      final specs = await specRepo.getAllSpecs();
      if (mounted) setState(() => _specs = specs);
    } catch (_) {}
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleAdd() async {
    final id = _idController.text.trim();
    final name = _nameController.text.trim();

    if (id.isEmpty) {
      setState(() => _error = 'Vui lòng nhập mã xe');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'Vui lòng nhập tên xe');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await widget.onAdd(id, name, _selectedColor, _selectedSpec);
    } catch (e) {
      setState(() {
        _error = 'Lỗi: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.vinfastBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add_road_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Thêm xe mới',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Nhập thông tin xe của bạn',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: AppColors.textSecondary, size: 18),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Mã xe
              _InputField(
                controller: _idController,
                label: 'Mã xe',
                hint: 'VD: VF-OPES-001',
                icon: Icons.qr_code_rounded,
              ),
              const SizedBox(height: 12),

              // Tên xe
              _InputField(
                controller: _nameController,
                label: 'Tên xe',
                hint: 'VD: VinFast Opes 2024',
                icon: Icons.electric_moped_rounded,
              ),

              const SizedBox(height: 16),

              // Chọn model VinFast
              const Text(
                'Model VinFast (tùy chọn)',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedSpec?.modelId,
                    hint: const Text('Chọn model (để tính dung lượng AI)',
                        style: TextStyle(color: AppColors.textHint, fontSize: 14)),
                    dropdownColor: AppColors.card,
                    icon: const Icon(Icons.expand_more_rounded,
                        color: AppColors.textSecondary),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Không chọn',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                      ),
                      ..._specs.map((s) => DropdownMenuItem(
                            value: s.modelId,
                            child: Text(
                              '${s.modelName} (${s.nominalCapacityWh}Wh)',
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 14),
                            ),
                          )),
                    ],
                    onChanged: (val) {
                      setState(() {
                        if (val == null || val.isEmpty) {
                          _selectedSpec = null;
                        } else {
                          _selectedSpec = _specs.firstWhere((s) => s.modelId == val);
                        }
                      });
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Chọn màu
              const Text(
                'Màu sắc đại diện',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: _colors.map((hex) {
                  final color =
                      Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
                  final isSelected = hex == _selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = hex),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                )
                              ]
                            : [],
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 16)
                          : null,
                    ),
                  );
                }).toList(),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Nút thêm
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleAdd,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Thêm xe',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Helper Widgets
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryGreen, size: 18),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _MiniStat({required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 3),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;

  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textHint),
            prefixIcon: Icon(icon, color: AppColors.textTertiary, size: 18),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyGarage extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyGarage({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.garage_rounded,
                color: AppColors.textTertiary, size: 40),
          ),
          const SizedBox(height: 16),
          const Text(
            'Chưa có xe nào',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Thêm xe đầu tiên để bắt đầu theo dõi pin',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onAdd,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Thêm xe',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _AppInfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final Color valueColor;

  const _AppInfoTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: valueColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Status Tiles — Trạng thái thật Firebase / AI API
// =============================================================================

class _FirebaseStatusTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(firebaseStatusProvider);

    final Color color;
    final IconData icon;
    switch (status) {
      case ConnectionStatus.checking:
        color = AppColors.textTertiary;
        icon = Icons.cloud_sync_rounded;
      case ConnectionStatus.online:
        color = AppColors.primaryGreen;
        icon = Icons.cloud_done_rounded;
      case ConnectionStatus.degraded:
        color = AppColors.warning;
        icon = Icons.cloud_outlined;
      case ConnectionStatus.offline:
        color = AppColors.error;
        icon = Icons.cloud_off_rounded;
    }

    return GestureDetector(
      onTap: () => ref.read(firebaseStatusProvider.notifier).check(),
      child: _AppInfoTile(
        icon: icon,
        iconColor: color,
        title: 'Firebase',
        value: status.label,
        valueColor: color,
      ),
    ).animate().fadeIn(delay: 460.ms);
  }
}

class _AiApiStatusTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(aiApiStatusProvider);

    final Color color;
    final IconData icon;
    final String label;
    switch (status) {
      case ConnectionStatus.checking:
        color = AppColors.textTertiary;
        icon = Icons.smart_toy_outlined;
        label = status.label;
      case ConnectionStatus.online:
        color = AppColors.primaryGreen;
        icon = Icons.smart_toy_rounded;
        label = 'Hoạt động';
      case ConnectionStatus.offline:
        color = AppColors.error;
        icon = Icons.smart_toy_outlined;
        label = 'Ngoại tuyến (On-device fallback)';
      case ConnectionStatus.degraded:
        color = AppColors.warning;
        icon = Icons.smart_toy_outlined;
        label = 'Không ổn định';
    }

    return GestureDetector(
      onTap: () => ref.read(aiApiStatusProvider.notifier).check(),
      child: _AppInfoTile(
        icon: icon,
        iconColor: color,
        title: 'AI Dự đoán chai pin',
        value: label,
        valueColor: color,
      ),
    ).animate().fadeIn(delay: 520.ms);
  }
}

class _AiUrlConfigTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiService = ref.read(aiPredictionServiceProvider);

    return GestureDetector(
      onTap: () => _showUrlDialog(context, ref, aiService),
      child: _AppInfoTile(
        icon: Icons.link_rounded,
        iconColor: AppColors.info,
        title: 'AI Server URL',
        value: aiService.baseUrl,
        valueColor: AppColors.textSecondary,
      ),
    ).animate().fadeIn(delay: 535.ms);
  }

  void _showUrlDialog(BuildContext context, WidgetRef ref, AiPredictionService aiService) {
    final controller = TextEditingController(text: aiService.baseUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cấu hình AI Server URL',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhập URL Flask AI (LAN/Cloud). Ví dụ:\n• Emulator: http://10.0.2.2:5001\n• LAN: http://192.168.1.x:5001',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.card,
                hintText: kAiBaseUrlDefault,
                hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.info),
                ),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.text = kAiBaseUrlDefault;
            },
            child: const Text('Mặc định', style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isEmpty) return;
              await aiService.setBaseUrl(url);
              // Re-check AI status với URL mới
              ref.read(aiApiStatusProvider.notifier).check();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Lưu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryGreen.withValues(alpha: 0.06),
            AppColors.card,
            AppColors.info.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.vinfastBlue,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.vinfastBlue.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child:
                const Icon(Icons.electric_bolt_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 14),
          const Text(
            'VinFast Battery',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Quản lý pin xe máy điện thông minh',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 1,
            color: AppColors.border,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.copyright_rounded,
                  color: AppColors.textTertiary, size: 14),
              const SizedBox(width: 4),
              const Text(
                '2026 VinFast Battery Team',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
