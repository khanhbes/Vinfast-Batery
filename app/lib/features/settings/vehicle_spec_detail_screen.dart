import 'package:flutter/material.dart';

import '../../core/theme/luxe_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../data/models/vinfast_model_spec.dart';
import '../../data/repositories/vehicle_spec_repository.dart';
import '../../core/widgets/vehicle_photo.dart';
import '../home/widgets/luxe_vehicle_hero.dart' show LuxeScooterArt;

/// Vehicle Spec Detail Screen — PLAN #5
/// Shows detailed spec sheet and allows editing
class VehicleSpecDetailScreen extends StatefulWidget {
  final String vehicleId;
  final Map<String, dynamic> vehicleData;

  const VehicleSpecDetailScreen({
    super.key,
    required this.vehicleId,
    required this.vehicleData,
  });

  @override
  State<VehicleSpecDetailScreen> createState() =>
      _VehicleSpecDetailScreenState();
}

class _VehicleSpecDetailScreenState extends State<VehicleSpecDetailScreen> {
  /// The same photo as the overview and garage (QA 131).
  late final String? _photo = VehicleImages.forVehicleMap(widget.vehicleData);
  bool _isEditing = false;
  bool _isSaving = false;
  VinFastModelSpec? _spec;

  // Editable controllers
  late TextEditingController _modelCtrl;
  late TextEditingController _yearCtrl;
  late TextEditingController _licensePlateCtrl;
  late TextEditingController _batteryTypeCtrl;
  late TextEditingController _batteryCapCtrl;
  late TextEditingController _sohCtrl;
  late TextEditingController _odoCtrl;
  late TextEditingController _efficiencyCtrl;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicleData;
    _modelCtrl = TextEditingController(text: v['nickname'] ?? '');
    _yearCtrl = TextEditingController(text: '${v['year'] ?? 2024}');
    _licensePlateCtrl = TextEditingController(text: v['licensePlate'] ?? '');
    _batteryTypeCtrl = TextEditingController(
      text: v['batteryType'] ?? v['batteryChemistry'] ?? 'LFP',
    );
    _batteryCapCtrl = TextEditingController(
      text: '${(v['batteryCapacity'] ?? 0).toInt()}',
    );
    _sohCtrl = TextEditingController(
      text: '${(v['stateOfHealth'] ?? 100).toInt()}',
    );
    _odoCtrl = TextEditingController(text: '${(v['currentOdo'] ?? 0).toInt()}');
    _efficiencyCtrl = TextEditingController(
      text: '${(v['defaultEfficiency'] ?? 1.2)}',
    );
    _loadSpec();
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    _licensePlateCtrl.dispose();
    _batteryTypeCtrl.dispose();
    _batteryCapCtrl.dispose();
    _sohCtrl.dispose();
    _odoCtrl.dispose();
    _efficiencyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSpec() async {
    final modelName =
        widget.vehicleData['model'] ?? widget.vehicleData['vehicleName'] ?? '';
    if (modelName.toString().isEmpty) return;

    final repo = VehicleSpecRepository();
    final spec = await repo.matchByVehicleName(modelName);
    if (mounted) setState(() => _spec = spec);
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    try {
      final result = await AuthService().updateVehicle(
        vehicleId: widget.vehicleId,
        updates: {
          'nickname': _modelCtrl.text.trim(),
          'licensePlate': _licensePlateCtrl.text.trim(),
          'stateOfHealth': double.tryParse(_sohCtrl.text) ?? 100,
          'currentOdo': double.tryParse(_odoCtrl.text) ?? 0,
        },
      );

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });

      if (result['success'] == true) {
        AppPopup.showSuccess('Đã cập nhật thông số');
      } else {
        AppPopup.showError(result['error'] ?? 'Cập nhật thất bại');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppPopup.showError('Cập nhật thất bại', error: e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicleData;
    final modelName = (v['model'] ?? v['vehicleName'] ?? 'Xe').toString();
    final soh = double.tryParse(_sohCtrl.text);

    return LuxeScaffold(
      appBar: LuxeAppBar(
        actions: [
          if (_isEditing && !_isSaving)
            TextButton(
              onPressed: () => setState(() => _isEditing = false),
              child: const Text('Hủy'),
            ),
          TextButton(
            onPressed: _isSaving
                ? null
                : () {
                    if (_isEditing) {
                      _saveChanges();
                    } else {
                      setState(() => _isEditing = true);
                    }
                  },
            style: TextButton.styleFrom(foregroundColor: LuxeColors.emerald),
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _isEditing ? 'Lưu' : 'Sửa',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Hero(
              tag: 'vehicle-hero-${widget.vehicleId}',
              child: Material(
                type: MaterialType.transparency,
                child: _buildHeaderCard(modelName, soh),
              ),
            ),
            if (_photo != null) ...[
              const SizedBox(height: 14),
              LuxeReveal(
                index: 1,
                child: LuxeGlass(
                  radius: 26,
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
                  child: AspectRatio(
                    aspectRatio: 1.5,
                    child: VehiclePhoto(
                      url: _photo,
                      reflection: true,
                      semanticLabel: 'Ảnh xe $modelName',
                      fallback: const LuxeScooterArt(level: 0.6),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const LuxeReveal(
              index: 1,
              child: LuxeNotice(
                icon: Icons.verified_user_outlined,
                message:
                    'Thông số hãng được quản lý bởi catalog chung. Bạn chỉ có thể sửa tên gọi riêng, biển số, ODO và tình trạng pin thực tế.',
              ),
            ),
            LuxeReveal(
              index: 2,
              child: _buildSpecSection('Thông số xe', [
                _SpecRow(
                  label: 'Tên gọi riêng',
                  controller: _modelCtrl,
                  isEditing: _isEditing,
                  icon: Icons.electric_moped_rounded,
                ),
                _SpecRow(
                  label: 'Biển số xe',
                  controller: _licensePlateCtrl,
                  isEditing: _isEditing,
                  icon: Icons.pin_outlined,
                ),
                _SpecRow(
                  label: 'Loại pin (LFP / NMC)',
                  controller: _batteryTypeCtrl,
                  isEditing: false,
                  icon: Icons.electric_bolt_rounded,
                ),
                _SpecRow(
                  label: 'Năm SX',
                  controller: _yearCtrl,
                  isEditing: false,
                  icon: Icons.calendar_today_rounded,
                  keyboardType: TextInputType.number,
                ),
                _SpecRow(
                  label: 'Dung lượng pin (Wh)',
                  controller: _batteryCapCtrl,
                  isEditing: false,
                  icon: Icons.battery_full_rounded,
                  keyboardType: TextInputType.number,
                ),
                _SpecRow(
                  label: 'SoH (%)',
                  controller: _sohCtrl,
                  isEditing: _isEditing,
                  icon: Icons.favorite_outline_rounded,
                  keyboardType: TextInputType.number,
                ),
                _SpecRow(
                  label: 'ODO (km)',
                  controller: _odoCtrl,
                  isEditing: _isEditing,
                  icon: Icons.speed_rounded,
                  keyboardType: TextInputType.number,
                ),
                _SpecRow(
                  label: 'Hiệu suất (km/%)',
                  controller: _efficiencyCtrl,
                  isEditing: false,
                  icon: Icons.eco_rounded,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ]),
            ),
            if (_spec != null)
              LuxeReveal(index: 3, child: _buildCatalogSection()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(String modelName, double? soh) {
    return LuxeGlass(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('XE CỦA BẠN', style: LuxeText.eyebrow),
                const SizedBox(height: 8),
                LuxeMetalText(
                  modelName,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -0.6,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    LuxeTag(_yearCtrl.text),
                    LuxeTag('${_batteryCapCtrl.text} Wh'),
                    LuxeTag(_batteryTypeCtrl.text, color: LuxeColors.steel),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          LuxeRing(
            value: (soh ?? 0) / 100,
            size: 92,
            stroke: 7,
            color: (soh ?? 0) < 80
                ? LuxeColors.danger
                : (soh ?? 0) < 90
                ? LuxeColors.champagne
                : LuxeColors.emerald,
            semanticLabel: 'Sức khỏe pin ${_sohCtrl.text} phần trăm',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: FittedBox(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_sohCtrl.text}%',
                        style: const TextStyle(
                          color: LuxeColors.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      Text(
                        'SoH',
                        style: LuxeText.label.copyWith(fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecSection(String title, List<_SpecRow> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeSectionLabel(
          title,
          trailing: AnimatedSwitcher(
            duration: luxeDuration(context, 220),
            child: _isEditing
                ? const LuxeTag('Đang sửa', color: LuxeColors.champagne)
                : const SizedBox.shrink(),
          ),
        ),
        LuxeSettingsGroup(
          children: [for (final row in rows) _buildSpecRow(row)],
        ),
      ],
    );
  }

  Widget _buildSpecRow(_SpecRow row) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Row(
          children: [
            LuxeMedallion(
              icon: row.icon,
              size: 36,
              accent: row.isEditing ? LuxeColors.emerald : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 5,
              child: Text(
                row.label,
                style: const TextStyle(
                  color: LuxeColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: AnimatedSwitcher(
                duration: luxeDuration(context, 240),
                child: row.isEditing
                    ? TextField(
                        key: const ValueKey('edit'),
                        controller: row.controller,
                        keyboardType: row.keyboardType,
                        style: const TextStyle(
                          color: LuxeColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 10,
                          ),
                        ),
                      )
                    : Align(
                        key: const ValueKey('view'),
                        alignment: Alignment.centerRight,
                        child: Text(
                          row.controller.text.isEmpty
                              ? '—'
                              : row.controller.text,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: LuxeColors.muted,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogSection() {
    final spec = _spec;
    if (spec == null) return const SizedBox();
    final rows = <(String, String)>[
      ('Tên model', spec.modelName),
      ('Dung lượng (Wh)', '${spec.nominalCapacityWh.toInt()}'),
      ('Dung lượng (Ah)', spec.nominalCapacityAh.toStringAsFixed(1)),
      ('Điện áp (V)', '${spec.nominalVoltageV.toInt()}'),
      ('Sạc tối đa (W)', '${spec.maxChargePowerW.toInt()}'),
      ('Motor định mức (W)', '${spec.ratedMotorPowerW.toInt()}'),
      ('Motor peak (W)', '${spec.peakMotorPowerW.toInt()}'),
      ('Nguồn dữ liệu', spec.source),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LuxeSectionLabel(
          'Catalog xe điện',
          trailing: LuxeTag('Chỉ đọc', color: LuxeColors.steel),
        ),
        LuxeSettingsGroup(
          children: [
            for (final (label, value) in rows) _catalogRow(label, value),
          ],
        ),
      ],
    );
  }

  Widget _catalogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: LuxeText.caption.copyWith(fontSize: 13.5),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: LuxeColors.text,
                fontSize: 13.5,
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

class _SpecRow {
  final String label;
  final TextEditingController controller;
  final bool isEditing;
  final IconData icon;
  final TextInputType keyboardType;

  const _SpecRow({
    required this.label,
    required this.controller,
    required this.isEditing,
    required this.icon,
    this.keyboardType = TextInputType.text,
  });
}
