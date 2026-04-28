import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/auth_service.dart';
import '../../core/widgets/app_popup.dart';
import '../../data/models/vinfast_model_spec.dart';
import '../../data/repositories/vehicle_spec_repository.dart';
import 'vehicle_spec_detail_screen.dart';

/// Vehicle Garage Screen — PLAN #5
/// - List user vehicles
/// - Add vehicle from VinFast spec catalog
/// - View/edit vehicle specs
class VehicleGarageScreen extends ConsumerStatefulWidget {
  const VehicleGarageScreen({super.key});

  @override
  ConsumerState<VehicleGarageScreen> createState() => _VehicleGarageScreenState();
}

class _VehicleGarageScreenState extends ConsumerState<VehicleGarageScreen> {
  List<Map<String, dynamic>> _vehicles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    setState(() => _isLoading = true);
    try {
      final vehicles = await AuthService().getUserVehicles();
      if (mounted) setState(() { _vehicles = vehicles; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddVehicleSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddVehicleSheet(
        onVehicleAdded: () {
          _loadVehicles();
          ref.invalidate(allVehiclesProvider);
        },
      ),
    );
  }

  Future<void> _deleteVehicle(String vehicleId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Xóa xe', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Bạn có chắc chắn muốn xóa xe này? Thao tác không thể hoàn tác.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final result = await AuthService().deleteVehicle(vehicleId);
      if (result['success'] == true) {
        AppPopup.showSuccess('Đã xóa xe');
        _loadVehicles();
        ref.invalidate(allVehiclesProvider);
      } else {
        AppPopup.showError(result['error'] ?? 'Xóa thất bại');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Garage Xe',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          GestureDetector(
            onTap: _showAddVehicleSheet,
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: AppColors.background, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    'Thêm xe',
                    style: TextStyle(
                      color: AppColors.background,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _vehicles.isEmpty
              ? _buildEmptyState()
              : _buildVehicleList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.directions_car_outlined, color: AppColors.textTertiary, size: 48),
          ),
          const SizedBox(height: 20),
          const Text(
            'Chưa có xe nào',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Thêm xe để bắt đầu theo dõi pin',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showAddVehicleSheet,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Thêm xe mới'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildVehicleList() {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _vehicles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final v = _vehicles[i];
        final isSelected = ref.watch(selectedVehicleIdProvider) == (v['id'] ?? v['vehicleId']);

        return _VehicleCard(
          model: v['model'] ?? v['vehicleName'] ?? 'Xe không tên',
          year: v['year'] ?? 2024,
          battery: (v['batteryCapacity'] ?? 0).toDouble(),
          soh: (v['stateOfHealth'] ?? 100).toDouble(),
          odo: (v['currentOdo'] ?? 0).toDouble(),
          isSelected: isSelected,
          onTap: () {
            final id = v['id'] ?? v['vehicleId'] ?? '';
            ref.read(selectedVehicleIdProvider.notifier).state = id;
          },
          onDelete: () => _deleteVehicle(v['id'] ?? v['vehicleId'] ?? ''),
          onViewSpec: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VehicleSpecDetailScreen(
                  vehicleId: v['id'] ?? v['vehicleId'] ?? '',
                  vehicleData: v,
                ),
              ),
            );
          },
        ).animate().fadeIn(delay: Duration(milliseconds: i * 80)).slideX(begin: 0.05);
      },
    );
  }
}

// ============================================================================
// Vehicle Card
// ============================================================================

class _VehicleCard extends StatelessWidget {
  final String model;
  final int year;
  final double battery;
  final double soh;
  final double odo;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onViewSpec;

  const _VehicleCard({
    required this.model,
    required this.year,
    required this.battery,
    required this.soh,
    required this.odo,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onViewSpec,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary.withAlpha(102) : AppColors.glassBorder,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.primary.withAlpha(15), blurRadius: 16, spreadRadius: 2)]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primaryContainer : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.electric_moped_rounded,
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Năm $year • ${battery.toInt()} Wh',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.success.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'ĐANG DÙNG',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Stats row
            Row(
              children: [
                _buildMiniStat('SoH', '${soh.toInt()}%', AppColors.success),
                const SizedBox(width: 16),
                _buildMiniStat('ODO', '${odo.toInt()} km', AppColors.primary),
                const Spacer(),
                // Action buttons
                GestureDetector(
                  onTap: onViewSpec,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.info_outline_rounded, color: AppColors.textSecondary, size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 18),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: AppColors.textTertiary, fontSize: 10, fontWeight: FontWeight.w600),
            ),
            Text(
              value,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// Add Vehicle Sheet — PLAN #5
// Select from VinFast spec catalog
// ============================================================================

class _AddVehicleSheet extends StatefulWidget {
  final VoidCallback onVehicleAdded;

  const _AddVehicleSheet({required this.onVehicleAdded});

  @override
  State<_AddVehicleSheet> createState() => _AddVehicleSheetState();
}

class _AddVehicleSheetState extends State<_AddVehicleSheet> {
  List<VinFastModelSpec> _allSpecs = [];
  List<VinFastModelSpec> _filteredSpecs = [];
  bool _isLoading = true;
  bool _isAdding = false;
  final _searchCtrl = TextEditingController();

  // Custom values
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _loadSpecs();
    _searchCtrl.addListener(_filterSpecs);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSpecs() async {
    try {
      final repo = VehicleSpecRepository();
      final specs = await repo.getAllSpecs();
      if (mounted) {
        setState(() {
          _allSpecs = specs;
          _filteredSpecs = specs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterSpecs() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filteredSpecs = query.isEmpty
          ? _allSpecs
          : _allSpecs.where((s) => s.modelName.toLowerCase().contains(query)).toList();
    });
  }

  Future<void> _addVehicle(VinFastModelSpec spec) async {
    setState(() => _isAdding = true);

    final result = await AuthService().addVehicle(
      model: spec.modelName,
      year: _selectedYear,
      batteryCapacity: spec.nominalCapacityWh,
      currentBattery: 100,
      stateOfHealth: 100,
      currentOdo: 0,
      defaultEfficiency: spec.defaultEfficiencyKmPerPercent,
    );

    if (!mounted) return;
    setState(() => _isAdding = false);

    if (result['success'] == true) {
      AppPopup.showSuccess('Đã thêm ${spec.modelName}');
      widget.onVehicleAdded();
      Navigator.pop(context);
    } else {
      AppPopup.showError(result['error'] ?? 'Thêm xe thất bại');
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.85;

    return Container(
      height: h,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Thêm xe mới',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Chọn model từ danh sách VinFast',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                  ),
                ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm model...',
                hintStyle: const TextStyle(color: AppColors.textHint),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
                filled: true,
                fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          // Year picker
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: SizedBox(
              height: 40,
              child: Row(
                children: [
                  Text('Năm sản xuất:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: DateTime.now().year - 2020 + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final year = 2020 + i;
                        final selected = year == _selectedYear;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedYear = year),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected ? AppColors.primary : AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$year',
                              style: TextStyle(
                                color: selected ? AppColors.background : AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _filteredSpecs.isEmpty
                    ? Center(
                        child: Text(
                          'Không tìm thấy model nào',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                        itemCount: _filteredSpecs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) {
                          final spec = _filteredSpecs[i];
                          return _SpecCard(
                            spec: spec,
                            isAdding: _isAdding,
                            onAdd: () => _addVehicle(spec),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SpecCard extends StatelessWidget {
  final VinFastModelSpec spec;
  final bool isAdding;
  final VoidCallback onAdd;

  const _SpecCard({
    required this.spec,
    required this.isAdding,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.electric_moped_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec.modelName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pin: ${spec.nominalCapacityWh.toInt()} Wh • ${spec.nominalVoltageV.toInt()}V',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: isAdding ? null : onAdd,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: isAdding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
                        )
                      : Text(
                          'Thêm',
                          style: TextStyle(
                            color: AppColors.background,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Quick specs
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _specChip('Motor: ${(spec.ratedMotorPowerW / 1000).toStringAsFixed(1)} kW'),
              _specChip('Sạc tối đa: ${spec.maxChargePowerW.toInt()} W'),
              _specChip('~${spec.defaultEfficiencyKmPerPercent.toStringAsFixed(1)} km/%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _specChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }
}
