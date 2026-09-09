import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../services/session_service.dart';
import '../theme/app_ui_colors.dart';
import '../theme/app_motion.dart';
import 'app_popup.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/models/vinfast_model_spec.dart';
import '../../data/repositories/vehicle_spec_repository.dart';

class VehiclePickerSheet extends ConsumerStatefulWidget {
  const VehiclePickerSheet({super.key});
  static Future<void> show(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const VehiclePickerSheet(),
      );
  @override
  ConsumerState<VehiclePickerSheet> createState() => _VehiclePickerSheetState();
}

class _VehiclePickerSheetState extends ConsumerState<VehiclePickerSheet> {
  bool _saving = false;
  Future<void> _select(VehicleModel vehicle) async {
    if (_saving || vehicle.isArchived) return;
    setState(() => _saving = true);
    try {
      await SessionService().setSelectedVehicleId(vehicle.vehicleId);
      if (!mounted) return;
      AppPopup.clearShownErrors();
      ref.read(selectedVehicleIdProvider.notifier).state = vehicle.vehicleId;
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không lưu được xe đã chọn. Vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicles = ref.watch(allVehiclesProvider);
    final specs =
        ref.watch(allVinFastSpecsProvider).valueOrNull ?? <VinFastModelSpec>[];
    final selected = ref.watch(selectedVehicleIdProvider);
    final ui = AppUiColors.of(context);
    return PopScope(
      canPop: !_saving,
      child: Material(
        color: ui.surface,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .85,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chọn xe đang kết nối',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Danh sách xe điện đã ghép nối trong garage',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: ui.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Đóng',
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                if (_saving) const LinearProgressIndicator(),
                const Divider(height: 1),
                Expanded(
                  child: vehicles.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Không tải được danh sách xe.'),
                          TextButton.icon(
                            onPressed: () =>
                                ref.invalidate(allVehiclesProvider),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    ),
                    data: (items) {
                      final active = items.where((v) => !v.isArchived).toList();
                      if (active.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'Chưa có xe đang sử dụng.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: active.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final vehicle = active[index];
                          VinFastModelSpec? spec;
                          for (final candidate in specs) {
                            if (candidate.modelId == vehicle.vinfastModelId) {
                              spec = candidate;
                              break;
                            }
                          }
                          return AppReveal(
                            child: _VehicleCard(
                              vehicle: vehicle,
                              spec: spec,
                              selected: vehicle.vehicleId == selected,
                              onTap: _saving ? null : () => _select(vehicle),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    this.spec,
    required this.selected,
    this.onTap,
  });
  final VehicleModel vehicle;
  final VinFastModelSpec? spec;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ui = AppUiColors.of(context);
    final capacity = vehicle.batteryCapacityWh;
    final configuredRange =
        vehicle.hasEfficiencyData &&
            vehicle.defaultEfficiency.isFinite &&
            vehicle.defaultEfficiency > 0
        ? vehicle.defaultEfficiency * 100
        : null;
    final range = spec?.rangeKm ?? configuredRange;
    final batteryType = vehicle.batteryType ?? 'LFP';
    final licensePlate = vehicle.licensePlate?.trim();

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? ui.primary.withAlpha(25)
            : ui.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? ui.primary : ui.borderStrong,
            width: selected ? 1.8 : 1.0,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Title + Status badge + Checkmark
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            vehicle.vehicleName.isEmpty
                                ? 'Xe chưa đặt tên'
                                : vehicle.vehicleName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (selected)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: ui.primary.withAlpha(35),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: ui.primary.withAlpha(80),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                'Đang chọn',
                                style: TextStyle(
                                  color: ui.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (selected)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: ui.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: Colors.black,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                // Subtitle Row: License plate & model & battery
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${licensePlate != null && licensePlate.isNotEmpty ? 'Biển số: $licensePlate' : 'Biển số: Chưa đặt'} · ${vehicle.vinfastModelName ?? vehicle.vehicleName} · Pin $batteryType',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ui.muted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // 3-Column Specifications Grid
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: ui.surface.withAlpha(120),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: ui.border.withAlpha(40),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _spec(
                          context,
                          'Dung lượng',
                          capacity.isFinite && capacity > 0
                              ? '${(capacity >= 1000 ? (capacity / 1000).toStringAsFixed(1) : capacity.round())} ${capacity >= 1000 ? 'kWh' : 'Wh'}'
                              : '—',
                          ui.primary,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: ui.border.withAlpha(40),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _spec(
                            context,
                            'Quãng đường',
                            range != null && range.isFinite && range > 0
                                ? '${range.round()} km'
                                : '—',
                            ui.text,
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: ui.border.withAlpha(40),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: _spec(
                            context,
                            'Loại pin',
                            batteryType,
                            ui.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _spec(BuildContext context, String label, String value, Color valueColor) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 11,
          color: AppUiColors.of(context).muted,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: valueColor,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );
}
