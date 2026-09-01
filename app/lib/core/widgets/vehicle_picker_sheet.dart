import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/session_service.dart';
import '../theme/cockpit_design_system.dart';
import 'app_popup.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/models/vinfast_model_spec.dart';
import '../../data/repositories/vehicle_spec_repository.dart';

class VehiclePickerSheet extends ConsumerStatefulWidget {
  const VehiclePickerSheet({super.key});

  /// Hiển thị bottom sheet chọn xe
  static Future<void> show(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const VehiclePickerSheet(),
    );
  }

  @override
  ConsumerState<VehiclePickerSheet> createState() => _VehiclePickerSheetState();
}

class _VehiclePickerSheetState extends ConsumerState<VehiclePickerSheet> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.1, end: 0.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(allVehiclesProvider);
    final specsAsync = ref.watch(allVinFastSpecsProvider);
    final selectedId = ref.watch(selectedVehicleIdProvider);
    
    final disableAnimations = CockpitMotion.enabled(context) == false;

    return Container(
      decoration: const BoxDecoration(
        color: CockpitColors.shell,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: CockpitColors.dim,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Chọn xe đang kết nối',
                        style: TextStyle(
                          color: CockpitColors.text,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Danh sách xe điện đã ghép nối trong garage',
                        style: TextStyle(
                          color: CockpitColors.muted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: CockpitColors.muted),
                  style: IconButton.styleFrom(
                    backgroundColor: CockpitColors.surfaceSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: CockpitColors.border, height: 1),
          // Content list
          Expanded(
            child: vehiclesAsync.when(
              data: (vehicles) {
                if (vehicles.isEmpty) {
                  return const Center(
                    child: Text(
                      'Chưa có xe nào trong garage',
                      style: TextStyle(color: CockpitColors.muted),
                    ),
                  );
                }
                
                final specs = specsAsync.valueOrNull ?? [];
                
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  itemCount: vehicles.length,
                  itemBuilder: (context, index) {
                    final vehicle = vehicles[index];
                    final spec = specs.cast<VinFastModelSpec?>().firstWhere(
                      (s) => s?.modelId == vehicle.vinfastModelId,
                      orElse: () => null,
                    );
                    
                    return _VehicleCard(
                      vehicle: vehicle,
                      spec: spec,
                      isSelected: vehicle.vehicleId == selectedId,
                      pulseAnimation: disableAnimations ? null : _pulseAnimation,
                      index: index,
                      disableAnimations: disableAnimations,
                      onTap: () async {
                        // Cập nhật selected vehicle
                        AppPopup.clearShownErrors();
                        ref.read(selectedVehicleIdProvider.notifier).state = vehicle.vehicleId;
                        await SessionService().setSelectedVehicleId(vehicle.vehicleId);
                        
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: CockpitColors.emerald),
              ),
              error: (err, _) => Center(
                child: Text('Lỗi tải dữ liệu: $err', style: const TextStyle(color: CockpitColors.danger)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final VehicleModel vehicle;
  final VinFastModelSpec? spec;
  final bool isSelected;
  final Animation<double>? pulseAnimation;
  final int index;
  final bool disableAnimations;
  final VoidCallback onTap;

  const _VehicleCard({
    required this.vehicle,
    this.spec,
    required this.isSelected,
    this.pulseAnimation,
    required this.index,
    required this.disableAnimations,
    required this.onTap,
  });

  String _getBatteryType(String modelName) {
    if (modelName.toUpperCase().contains('NMC')) return 'NMC';
    return 'LFP'; // Default as requested
  }

  @override
  Widget build(BuildContext context) {
    final capacityKWh = (vehicle.batteryCapacityWh / 1000).toStringAsFixed(1);
    final rangeKm = (spec?.rangeKm ?? (vehicle.defaultEfficiency * 100)).toStringAsFixed(0);
    final batteryType = _getBatteryType(vehicle.vinfastModelName ?? '');
    
    // Subtitle default
    final modelLabel = vehicle.vinfastModelName ?? 'VinFast';
    final subtitle = "Biển số: Chưa cập nhật • $modelLabel $batteryType";

    Widget card = GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: isSelected ? CockpitColors.elevated : CockpitColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? CockpitColors.emerald : CockpitColors.borderStrong,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected && !disableAnimations
              ? [
                  BoxShadow(
                    color: CockpitColors.emerald.withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIcon(),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(
                            vehicle.vehicleName,
                            style: const TextStyle(
                              color: CockpitColors.text,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (vehicle.isArchived)
                            const Text(
                              '(Lưu trữ)',
                              style: TextStyle(
                                color: CockpitColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          if (isSelected)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: CockpitColors.emerald.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check, color: CockpitColors.emerald, size: 12),
                                  SizedBox(width: 4),
                                  Text(
                                    'Đang chọn',
                                    style: TextStyle(
                                      color: CockpitColors.emerald,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: CockpitColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: CockpitColors.borderStrong, height: 1),
            const SizedBox(height: 12),
            // Specs layout
            Row(
              children: [
                _buildSpecItem(Icons.battery_charging_full, 'Dung lượng', '$capacityKWh kWh'),
                _buildSpecItem(Icons.speed, 'Quãng đường', '$rangeKm km'),
                _buildSpecItem(Icons.info_outline, 'Loại pin', batteryType),
              ],
            )
          ],
        ),
      ),
    );

    if (disableAnimations) return card;

    // Hiệu ứng trượt lên mượt mà (staggered entry)
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: CockpitMotion.sheet,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value) + (index * 15 * (1 - value))),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: card,
    );
  }

  Widget _buildIcon() {
    Widget iconBase = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isSelected ? CockpitColors.emerald.withValues(alpha: 0.15) : CockpitColors.surfaceSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.electric_bolt,
        color: isSelected ? CockpitColors.emerald : CockpitColors.muted,
        size: 24,
      ),
    );

    if (isSelected && pulseAnimation != null) {
      return AnimatedBuilder(
        animation: pulseAnimation!,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: CockpitColors.emerald.withValues(alpha: pulseAnimation!.value),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              ],
            ),
            child: child,
          );
        },
        child: iconBase,
      );
    }
    
    return iconBase;
  }

  Widget _buildSpecItem(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: CockpitColors.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: CockpitColors.muted, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: CockpitColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
