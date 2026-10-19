import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/widgets/error_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../data/models/vinfast_model_spec.dart';
import '../../data/repositories/vehicle_spec_repository.dart';
import '../home/widgets/luxe_vehicle_hero.dart' show LuxeScooterArt;
import 'vehicle_spec_detail_screen.dart';
import '../../core/widgets/vehicle_photo.dart';

/// Vehicle Garage Screen — LUXE (Task 119)
/// - List user vehicles (active / archived)
/// - Add vehicle from VinFast spec catalog
/// - View/edit vehicle specs
class VehicleGarageScreen extends ConsumerStatefulWidget {
  const VehicleGarageScreen({super.key});

  @override
  ConsumerState<VehicleGarageScreen> createState() =>
      _VehicleGarageScreenState();
}

class _VehicleGarageScreenState extends ConsumerState<VehicleGarageScreen> {
  List<Map<String, dynamic>> _vehicles = [];
  bool _isLoading = true;
  Object? _loadError;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final vehicles = await AuthService().getUserVehicles(
        includeArchived: true,
      );
      if (mounted) {
        setState(() {
          _vehicles = vehicles;
          _isLoading = false;
        });
      }
    } catch (e) {
      // A failed load is not "no vehicles": that invited adding a duplicate
      // (Task 125).
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = e;
        });
      }
    }
  }

  Future<void> _restoreVehicle(String vehicleId) async {
    final result = await AuthService().restoreVehicle(vehicleId);
    if (!mounted) return;
    if (result['success'] == true) {
      AppPopup.showSuccess('Đã khôi phục xe');
      await _loadVehicles();
      ref.invalidate(allVehiclesProvider);
    } else {
      AppPopup.showError(result['error'] ?? 'Khôi phục thất bại');
    }
  }

  void _showAddVehicleSheet() {
    showLuxeSheet<void>(
      context,
      builder: (ctx) => _AddVehicleSheet(
        onVehicleAdded: (newVehicleId) {
          // Auto-select xe vừa thêm (Step 2's listener sẽ tự persist vào
          // SessionService secure storage).
          if (newVehicleId.isNotEmpty) {
            ref.read(selectedVehicleIdProvider.notifier).state = newVehicleId;
          }
          _loadVehicles();
          ref.invalidate(allVehiclesProvider);
        },
      ),
    );
  }

  Future<void> _deleteVehicle(String vehicleId) async {
    final confirmed = await showLuxeConfirm(
      context,
      title: 'Lưu trữ xe',
      message:
          'Xe sẽ được ẩn khỏi danh sách sử dụng. Lịch sử sạc và dữ liệu AI vẫn được giữ lại để khôi phục.',
      confirmLabel: 'Lưu trữ',
    );

    if (confirmed == true) {
      final result = await AuthService().deleteVehicle(vehicleId);
      if (result['success'] == true) {
        AppPopup.showSuccess('Đã lưu trữ xe');
        _loadVehicles();
        ref.invalidate(allVehiclesProvider);
      } else {
        AppPopup.showError(result['error'] ?? 'Lưu trữ thất bại');
      }
    }
  }

  bool _isArchived(Map<String, dynamic> v) =>
      v['isArchived'] == true || v['archivedAt'] != null;

  List<Map<String, dynamic>> get _visibleVehicles => _vehicles
      .where((vehicle) => _isArchived(vehicle) == _showArchived)
      .toList();

  @override
  Widget build(BuildContext context) {
    final activeCount = _vehicles.where((v) => !_isArchived(v)).length;
    final archivedCount = _vehicles.length - activeCount;
    return LuxeScaffold(
      floatingActionButton: _showArchived || _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddVehicleSheet,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Thêm xe mới',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
      appBar: LuxeAppBar(
        actions: [
          LuxeCircleButton(
            tooltip: 'Thêm xe mới',
            icon: Icons.add_rounded,
            color: LuxeColors.emerald,
            onPressed: _showArchived ? null : _showAddVehicleSheet,
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: LuxeReveal(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('GARA', style: LuxeText.eyebrow),
                    const SizedBox(height: 6),
                    const Text('Xe của tôi', style: LuxeText.title),
                    const SizedBox(height: 4),
                    Text(
                      _isLoading
                          ? 'Đang tải danh sách xe…'
                          : '$activeCount xe đang dùng · $archivedCount đã lưu trữ',
                      style: LuxeText.caption,
                    ),
                    const SizedBox(height: 16),
                    LuxeSegmented<bool>(
                      segments: const [
                        (false, 'Đang dùng'),
                        (true, 'Đã lưu trữ'),
                      ],
                      selected: _showArchived,
                      onChanged: (v) => setState(() => _showArchived = v),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: LoadingSkeleton(layout: SkeletonLayout.list),
              ),
            )
          else if (_loadError != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState.fromError(
                error: _loadError!,
                prefix: 'Chưa tải được danh sách xe',
                onRetry: _loadVehicles,
              ),
            )
          else if (_visibleVehicles.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _showArchived
                  ? const EmptyState(
                      icon: Icons.archive_outlined,
                      title: 'Chưa có xe lưu trữ',
                      message:
                          'Xe bạn lưu trữ sẽ nằm ở đây và có thể khôi phục.',
                    )
                  : EmptyState(
                      icon: Icons.electric_moped_rounded,
                      title: 'Chưa có xe nào',
                      message: 'Thêm xe để bắt đầu theo dõi pin',
                      actionLabel: 'Thêm xe mới',
                      onAction: _showAddVehicleSheet,
                    ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
              sliver: SliverList.separated(
                itemCount: _visibleVehicles.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (ctx, i) => LuxeReveal(
                  key: ValueKey('garage-${_showArchived ? 'a' : 'u'}-$i'),
                  index: i,
                  child: _buildVehicleCard(_visibleVehicles[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> v) {
    final archived = _isArchived(v);
    final id = (v['id'] ?? v['vehicleId'] ?? '').toString();
    final isSelected = ref.watch(selectedVehicleIdProvider) == id;
    double? num2(Object? x) => x is num ? x.toDouble() : null;

    return _VehicleCard(
      heroTag: 'vehicle-hero-$id',
      model: (v['model'] ?? v['vehicleName'] ?? 'Xe không tên').toString(),
      photoUrl: VehicleImages.forVehicleMap(v),
      year: v['year'] is num ? (v['year'] as num).toInt() : null,
      battery: num2(v['batteryCapacity']),
      soh: num2(v['stateOfHealth']),
      odo: num2(v['currentOdo']),
      level: num2(v['currentBattery']),
      licensePlate: v['licensePlate'] as String?,
      batteryType: (v['batteryType'] ?? v['batteryChemistry']) as String?,
      isSelected: isSelected,
      isArchived: archived,
      onTap: archived
          ? () {}
          : () {
              HapticFeedback.selectionClick();
              ref.read(selectedVehicleIdProvider.notifier).state = id;
            },
      onDelete: archived ? () => _restoreVehicle(id) : () => _deleteVehicle(id),
      onViewSpec: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                VehicleSpecDetailScreen(vehicleId: id, vehicleData: v),
          ),
        );
      },
    );
  }
}

// ============================================================================
// Vehicle Card
// ============================================================================

class _VehicleCard extends StatelessWidget {
  final String heroTag;
  final String model;
  final int? year;
  final double? battery;
  final double? soh;
  final double? odo;
  final double? level;
  final String? licensePlate;
  final String? batteryType;
  final String? photoUrl;
  final bool isSelected;
  final bool isArchived;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onViewSpec;

  const _VehicleCard({
    required this.heroTag,
    required this.model,
    required this.year,
    required this.battery,
    required this.soh,
    required this.odo,
    required this.level,
    this.licensePlate,
    this.batteryType,
    this.photoUrl,
    required this.isSelected,
    this.isArchived = false,
    required this.onTap,
    required this.onDelete,
    required this.onViewSpec,
  });

  @override
  Widget build(BuildContext context) {
    final plate = licensePlate?.trim() ?? '';
    final meta = [
      if (plate.isNotEmpty) plate,
      year == null ? 'Năm —' : 'Năm $year',
      battery == null || battery! <= 0 ? 'Pin —' : '${battery!.toInt()} Wh',
      ?batteryType,
    ].join(' · ');
    final sohColor = soh == null
        ? LuxeColors.platinumMid
        : soh! < 80
        ? LuxeColors.danger
        : soh! < 90
        ? LuxeColors.champagne
        : LuxeColors.emerald;

    return Semantics(
      button: !isArchived,
      selected: isSelected,
      label: '$model${isSelected ? ', đang dùng' : ''}',
      child: Hero(
        tag: heroTag,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(26),
            child: Opacity(
              opacity: isArchived ? 0.72 : 1,
              child: LuxeGlass(
                selected: isSelected,
                radius: 26,
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                model,
                                style: LuxeText.item.copyWith(fontSize: 17),
                              ),
                              const SizedBox(height: 4),
                              Text(meta, style: LuxeText.caption),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isArchived)
                          const LuxeTag(
                            'Đã lưu trữ',
                            color: LuxeColors.champagne,
                          )
                        else
                          AnimatedSwitcher(
                            duration: luxeDuration(context, 260),
                            child: isSelected
                                ? const LuxeTag(
                                    'Đang dùng',
                                    color: LuxeColors.emerald,
                                  )
                                : const SizedBox.shrink(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 112,
                      child: VehiclePhoto(
                        url: photoUrl,
                        fallback: LuxeScooterArt(
                          level: (level ?? 0).clamp(0.0, 100.0) / 100,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        LuxeRing(
                          value: (soh ?? 0) / 100,
                          size: 46,
                          stroke: 4,
                          color: sohColor,
                          semanticLabel: soh == null
                              ? 'Chưa có SoH'
                              : 'SoH ${soh!.toInt()} phần trăm',
                          child: ExcludeSemantics(
                            child: Text(
                              soh == null ? '—' : '${soh!.toInt()}',
                              style: const TextStyle(
                                color: LuxeColors.text,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SoH · ODO',
                                style: LuxeText.label.copyWith(fontSize: 11),
                              ),
                              Text(
                                odo == null ? '— km' : '${odo!.toInt()} km',
                                style: const TextStyle(
                                  color: LuxeColors.text,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                        LuxeCircleButton(
                          icon: Icons.info_outline_rounded,
                          tooltip: 'Thông số chi tiết',
                          onPressed: onViewSpec,
                        ),
                        const SizedBox(width: 6),
                        LuxeCircleButton(
                          icon: isArchived
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                          tooltip: isArchived ? 'Khôi phục xe' : 'Lưu trữ xe',
                          color: isArchived
                              ? LuxeColors.emerald
                              : LuxeColors.danger,
                          onPressed: onDelete,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Add Vehicle Sheet — select from the verified VinFast spec catalog
// ============================================================================

class _AddVehicleSheet extends StatefulWidget {
  final void Function(String vehicleId) onVehicleAdded;

  const _AddVehicleSheet({required this.onVehicleAdded});

  @override
  State<_AddVehicleSheet> createState() => _AddVehicleSheetState();
}

class _AddVehicleSheetState extends State<_AddVehicleSheet> {
  static const _vehicleTypes = [
    ('all', 'Tất cả'),
    ('scooter', 'Xe máy'),
    ('motorcycle', 'Mô tô'),
    ('car', 'Ô tô'),
    ('suv', 'SUV'),
    ('pickup', 'Bán tải'),
    ('van', 'Van'),
    ('bus', 'Bus'),
    ('truck', 'Tải'),
    ('other', 'Khác'),
  ];

  List<VinFastModelSpec> _allSpecs = [];
  List<VinFastModelSpec> _filteredSpecs = [];
  bool _isLoading = true;
  bool _isAdding = false;
  final _searchCtrl = TextEditingController();
  final _licensePlateCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  String _selectedVehicleType = 'all';
  String _selectedBrand = 'all';
  String _selectedMarket = 'all';
  String _selectedYear = 'all';

  @override
  void initState() {
    super.initState();
    _loadSpecs();
    _searchCtrl.addListener(_filterSpecs);
  }

  @override
  void dispose() {
    _licensePlateCtrl.dispose();
    _nicknameCtrl.dispose();
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
      _filteredSpecs = _allSpecs.where((spec) {
        final haystack = '${spec.brandName} ${spec.modelName} ${spec.variant}'
            .toLowerCase();
        final matchesQuery = query.isEmpty || haystack.contains(query);
        final matchesType =
            _selectedVehicleType == 'all' ||
            spec.vehicleType == _selectedVehicleType;
        final matchesBrand =
            _selectedBrand == 'all' || spec.brandName == _selectedBrand;
        final matchesMarket =
            _selectedMarket == 'all' || spec.market == _selectedMarket;
        final matchesYear =
            _selectedYear == 'all' ||
            spec.releaseYear.toString() == _selectedYear;
        return spec.selectable &&
            matchesQuery &&
            matchesType &&
            matchesBrand &&
            matchesMarket &&
            matchesYear;
      }).toList();
    });
  }

  Future<void> _addVehicle(VinFastModelSpec spec) async {
    setState(() => _isAdding = true);

    final result = await AuthService().addVehicle(
      catalogId: spec.modelId,
      nickname: _nicknameCtrl.text.trim(),
      licensePlate: _licensePlateCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isAdding = false);

    if (result['success'] == true) {
      final newId = (result['vehicleId'] as String?) ?? '';
      // Hiệu ứng xác nhận ngắn rồi đóng sheet
      await _showSuccessOverlay(spec.modelName);
      if (!mounted) return;
      widget.onVehicleAdded(newId);
      Navigator.pop(context);
      AppPopup.showSuccess('Đã thêm ${spec.modelName}');
    } else {
      AppPopup.showError(result['error'] ?? 'Thêm xe thất bại');
    }
  }

  Future<void> _showSuccessOverlay(String modelName) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha(190),
      builder: (_) => _SuccessOverlay(modelName: modelName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.9;
    final brands = _allSpecs.map((spec) => spec.brandName).toSet().toList()
      ..sort();
    final markets = _allSpecs.map((spec) => spec.market).toSet().toList()
      ..sort();
    final years =
        _allSpecs
            .map((spec) => spec.releaseYear)
            .whereType<int>()
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));

    return SizedBox(
      height: h,
      child: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: LuxeSheetHeader(
                  eyebrow: 'Catalog đã xác minh',
                  title: 'Thêm xe mới',
                  caption: 'Chọn cấu hình đã được quản trị viên xác minh',
                  trailing: LuxeCircleButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: LuxeColors.text, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm model...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(99),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(99),
                      borderSide: const BorderSide(color: LuxeColors.hairline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(99),
                      borderSide: const BorderSide(
                        color: LuxeColors.emerald,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  itemCount: _vehicleTypes.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final value = _vehicleTypes[i].$1;
                    return ChoiceChip(
                      label: Text(_vehicleTypes[i].$2),
                      selected: value == _selectedVehicleType,
                      showCheckmark: false,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedVehicleType = value);
                        _filterSpecs();
                      },
                    );
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: _catalogDropdown(
                        label: 'Hãng',
                        value: _selectedBrand,
                        items: brands,
                        onChanged: (value) {
                          setState(() => _selectedBrand = value);
                          _filterSpecs();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _catalogDropdown(
                        label: 'Thị trường',
                        value: _selectedMarket,
                        items: markets,
                        onChanged: (value) {
                          setState(() => _selectedMarket = value);
                          _filterSpecs();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _catalogDropdown(
                        label: 'Năm',
                        value: _selectedYear,
                        items: years.map((year) => year.toString()).toList(),
                        onChanged: (value) {
                          setState(() => _selectedYear = value);
                          _filterSpecs();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Personal values only; catalog technical values are read-only.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                child: Column(
                  children: [
                    TextField(
                      controller: _nicknameCtrl,
                      style: const TextStyle(
                        color: LuxeColors.text,
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Tên gọi riêng (không bắt buộc)',
                        prefixIcon: Icon(
                          Icons.drive_file_rename_outline_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _licensePlateCtrl,
                      style: const TextStyle(
                        color: LuxeColors.text,
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Biển số (không bắt buộc)',
                        prefixIcon: Icon(Icons.pin_outlined, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: LoadingSkeleton(layout: SkeletonLayout.list),
                ),
              )
            else if (_filteredSpecs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Không tìm thấy model nào',
                  message: 'Thử bỏ bớt bộ lọc hoặc đổi từ khóa.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                sliver: SliverList.separated(
                  itemCount: _filteredSpecs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final spec = _filteredSpecs[i];
                    final card = _SpecCard(
                      spec: spec,
                      isAdding: _isAdding,
                      onAdd: () => _addVehicle(spec),
                      onPreview: () => _showSpecPreview(spec),
                    );
                    return i < 8 ? LuxeReveal(index: i, child: card) : card;
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _catalogDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      icon: const Icon(Icons.expand_more_rounded, size: 18),
      dropdownColor: LuxeColors.raised,
      borderRadius: BorderRadius.circular(16),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: const TextStyle(color: LuxeColors.muted, fontSize: 11.5),
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 4, 10),
      ),
      style: const TextStyle(color: LuxeColors.text, fontSize: 12.5),
      items: [
        const DropdownMenuItem(value: 'all', child: Text('Tất cả')),
        ...items.map(
          (item) => DropdownMenuItem(
            value: item,
            child: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }

  void _showSpecPreview(VinFastModelSpec spec) {
    showDialog(
      context: context,
      builder: (_) => _SpecPreviewDialog(
        spec: spec,
        onAdd: () {
          Navigator.pop(context);
          _addVehicle(spec);
        },
      ),
    );
  }
}

class _SpecCard extends StatelessWidget {
  final VinFastModelSpec spec;
  final bool isAdding;
  final VoidCallback onAdd;
  final VoidCallback onPreview;

  const _SpecCard({
    required this.spec,
    required this.isAdding,
    required this.onAdd,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: isAdding ? null : onPreview,
        borderRadius: BorderRadius.circular(22),
        child: LuxeGlass(
          radius: 22,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CatalogVehicleImage(spec: spec),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              spec.modelName,
                              style: LuxeText.item.copyWith(fontSize: 15),
                            ),
                            if (spec.releaseYear != null)
                              LuxeTag('${spec.releaseYear}'),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${spec.brandName} · ${spec.vehicleType.toUpperCase()} · ${spec.market}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LuxeText.eyebrow.copyWith(
                            fontSize: 10,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          spec.tagline ??
                              'Pin: ${spec.nominalCapacityWh.toInt()} Wh • ${spec.nominalVoltageV.toInt()}V',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: LuxeText.caption.copyWith(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  LuxeTag(
                    'Pin ${spec.nominalCapacityWh.toInt()} Wh • ${spec.nominalVoltageV.toInt()}V',
                  ),
                  LuxeTag(
                    'Motor ${(spec.ratedMotorPowerW / 1000).toStringAsFixed(1)} kW',
                  ),
                  if (spec.topSpeedKmh != null)
                    LuxeTag('${spec.topSpeedKmh!.toInt()} km/h'),
                  if (spec.rangeKm != null)
                    LuxeTag(
                      'Tầm ${spec.rangeKm!.toInt()} km',
                      color: LuxeColors.emerald,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: isAdding ? null : onPreview,
                      child: const Text('Xem thông số'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: isAdding ? null : onAdd,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: isAdding
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF0B0C0E),
                              ),
                            )
                          : const Text('Thêm'),
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

class _CatalogVehicleImage extends StatelessWidget {
  const _CatalogVehicleImage({required this.spec});

  final VinFastModelSpec spec;

  @override
  Widget build(BuildContext context) {
    final isCar = {'car', 'suv', 'pickup', 'van'}.contains(spec.vehicleType);
    final fallback = SizedBox(
      width: 72,
      height: 52,
      child: isCar
          ? const Center(
              child: LuxeMedallion(
                icon: Icons.directions_car_filled_rounded,
                size: 46,
              ),
            )
          : const LuxeScooterArt(level: 0),
    );
    final url = VehicleImages.forSpec(spec) ?? '';
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image(
        image: vehicleImageProvider(url),
        width: 72,
        height: 52,
        fit: BoxFit.contain,
        frameBuilder: (context, child, frame, _) => AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: luxeDuration(context, 320),
          child: frame == null
              ? Container(width: 72, height: 52, color: LuxeColors.raised)
              : child,
        ),
        errorBuilder: (_, error, stackTrace) => fallback,
      ),
    );
  }
}

// ============================================================================
// Success overlay — a ring sweeps and a check draws itself once
// ============================================================================

class _SuccessOverlay extends StatefulWidget {
  final String modelName;
  const _SuccessOverlay({required this.modelName});

  @override
  State<_SuccessOverlay> createState() => _SuccessOverlayState();
}

class _SuccessOverlayState extends State<_SuccessOverlay> {
  @override
  void initState() {
    super.initState();
    // Tự đóng sau 1.1s
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) Navigator.of(context, rootNavigator: true).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: LuxeGlass(
          selected: true,
          radius: 26,
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 72,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: luxeDuration(context, 760),
                  curve: LuxeMotion.enter,
                  builder: (context, t, _) =>
                      CustomPaint(painter: _CheckBurstPainter(t)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Đã thêm xe', style: LuxeText.item.copyWith(fontSize: 17)),
              const SizedBox(height: 4),
              Text(widget.modelName, style: LuxeText.caption),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckBurstPainter extends CustomPainter {
  _CheckBurstPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final ringT = (t * 1.6).clamp(0.0, 1.0);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * ringT,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = LuxeColors.emerald,
    );
    canvas.drawCircle(
      rect.center,
      rect.width * 0.38,
      Paint()..color = LuxeColors.emerald.withValues(alpha: 0.10 * ringT),
    );
    final checkT = ((t - 0.4) / 0.6).clamp(0.0, 1.0);
    if (checkT <= 0) return;
    final path = Path()
      ..moveTo(size.width * 0.3, size.height * 0.52)
      ..lineTo(size.width * 0.45, size.height * 0.66)
      ..lineTo(size.width * 0.72, size.height * 0.38);
    for (final m in path.computeMetrics()) {
      canvas.drawPath(
        m.extractPath(0, m.length * checkT),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = LuxeColors.emerald,
      );
    }
  }

  @override
  bool shouldRepaint(_CheckBurstPainter old) => old.t != t;
}

// ============================================================================
// Spec preview dialog — hiển thị thông số chi tiết trước khi confirm thêm
// ============================================================================

class _SpecPreviewDialog extends StatelessWidget {
  final VinFastModelSpec spec;
  final VoidCallback onAdd;

  const _SpecPreviewDialog({required this.spec, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const LuxeMedallion(
            icon: Icons.electric_moped_rounded,
            accent: LuxeColors.emerald,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.modelName,
                  style: LuxeText.item.copyWith(fontSize: 16),
                ),
                if (spec.tagline != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      spec.tagline!,
                      style: LuxeText.caption.copyWith(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _row(
                'Pin',
                '${spec.nominalCapacityWh.toInt()} Wh • ${spec.nominalCapacityAh.toInt()} Ah',
              ),
              _row('Điện áp', '${spec.nominalVoltageV.toInt()} V'),
              _row('Sạc tối đa', '${spec.maxChargePowerW.toInt()} W'),
              _row(
                'Motor (định mức)',
                '${(spec.ratedMotorPowerW / 1000).toStringAsFixed(1)} kW',
              ),
              _row(
                'Motor (đỉnh)',
                '${(spec.peakMotorPowerW / 1000).toStringAsFixed(1)} kW',
              ),
              if (spec.topSpeedKmh != null)
                _row('Tốc độ tối đa', '${spec.topSpeedKmh!.toInt()} km/h'),
              if (spec.rangeKm != null)
                _row('Tầm hoạt động', '~${spec.rangeKm!.toInt()} km'),
              _row(
                'Hiệu suất',
                '~${spec.defaultEfficiencyKmPerPercent.toStringAsFixed(2)} km/%',
              ),
              if (spec.releaseYear != null)
                _row('Năm ra mắt', '${spec.releaseYear}'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Thêm xe này'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: LuxeText.caption.copyWith(fontSize: 12.5),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: LuxeColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
