import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../services/session_service.dart';
import '../theme/luxe_theme.dart';
import 'luxe_kit.dart';
import 'luxe_settings.dart';
import 'app_popup.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/models/vinfast_model_spec.dart';
import '../../data/repositories/vehicle_spec_repository.dart';

class VehiclePickerSheet extends ConsumerStatefulWidget {
  const VehiclePickerSheet({super.key});
  static Future<void> show(BuildContext context, WidgetRef ref) =>
      showLuxeSheet<void>(
        context,
        isScrollControlled: true,
        clipBehavior: Clip.antiAlias,
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
        AppPopup.showMessage(
          'Không lưu được xe đã chọn. Vui lòng thử lại.',
          kind: AppNoticeKind.error,
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
    return PopScope(
      canPop: !_saving,
      child: Material(
        color: LuxeColors.sheet,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .9,
            child: Column(
              children: [
                const LuxeSheetHandle(),
                // The header scrolls within a cap so large text never starves
                // the vehicle list below it.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .3,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 14),
                    child: LuxeSheetHeader(
                      eyebrow: 'Gara của bạn',
                      title: 'Chọn xe đang kết nối',
                      caption: 'Danh sách xe điện đã ghép nối trong garage',
                      trailing: LuxeCircleButton(
                        icon: Icons.close_rounded,
                        tooltip: 'Đóng',
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                      ),
                    ),
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
                            icon: const Icon(Icons.refresh_rounded),
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
                            if (candidate.modelId ==
                                vehicle.effectiveCatalogId) {
                              spec = candidate;
                              break;
                            }
                          }
                          return LuxeReveal(
                            index: index,
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
    final capacity = vehicle.batteryCapacityWh;
    final configuredRange =
        vehicle.hasEfficiencyData &&
            vehicle.defaultEfficiency.isFinite &&
            vehicle.defaultEfficiency > 0
        ? vehicle.defaultEfficiency * 100
        : null;
    final range = spec?.rangeKm ?? configuredRange;
    final batteryType = vehicle.batteryType?.trim();
    final batteryTypeLabel = batteryType?.isNotEmpty == true
        ? batteryType!
        : 'Chưa có dữ liệu';
    final licensePlate = vehicle.licensePlate?.trim();

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: LuxeGlass(
            selected: selected,
            radius: 22,
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
                            style: LuxeText.item,
                            maxLines: 2,
                            softWrap: true,
                          ),
                          if (selected)
                            const LuxeTag(
                              'Đang chọn',
                              color: LuxeColors.emerald,
                            ),
                        ],
                      ),
                    ),
                    if (selected)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: LuxeColors.emerald,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: LuxeColors.emeraldGlow,
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: Color(0xFF04140D),
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
                        '${licensePlate != null && licensePlate.isNotEmpty ? 'Biển số: $licensePlate' : 'Biển số: Chưa đặt'} · ${spec?.modelName ?? vehicle.vinfastModelName ?? vehicle.vehicleName}',
                        style: LuxeText.caption,
                        maxLines: 2,
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // 3-Column Specifications Grid
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x66000000),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: LuxeColors.hairline),
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
                          LuxeColors.emerald,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: LuxeColors.hairline,
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
                            LuxeColors.text,
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: LuxeColors.hairline,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: _spec(
                            context,
                            'Loại pin',
                            batteryTypeLabel,
                            LuxeColors.emerald,
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

  Widget _spec(
    BuildContext context,
    String label,
    String value,
    Color valueColor,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: LuxeText.label.copyWith(fontSize: 11),
          maxLines: 1,
          softWrap: false,
        ),
      ),
      const SizedBox(height: 3),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          maxLines: 1,
          softWrap: false,
        ),
      ),
    ],
  );
}
