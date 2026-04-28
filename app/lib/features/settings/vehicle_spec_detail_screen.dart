import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/auth_service.dart';
import '../../core/widgets/app_popup.dart';
import '../../data/models/vinfast_model_spec.dart';
import '../../data/repositories/vehicle_spec_repository.dart';

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
  State<VehicleSpecDetailScreen> createState() => _VehicleSpecDetailScreenState();
}

class _VehicleSpecDetailScreenState extends State<VehicleSpecDetailScreen> {
  bool _isEditing = false;
  bool _isSaving = false;
  VinFastModelSpec? _spec;

  // Editable controllers
  late TextEditingController _modelCtrl;
  late TextEditingController _yearCtrl;
  late TextEditingController _batteryCapCtrl;
  late TextEditingController _sohCtrl;
  late TextEditingController _odoCtrl;
  late TextEditingController _efficiencyCtrl;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicleData;
    _modelCtrl = TextEditingController(text: v['model'] ?? v['vehicleName'] ?? '');
    _yearCtrl = TextEditingController(text: '${v['year'] ?? 2024}');
    _batteryCapCtrl = TextEditingController(text: '${(v['batteryCapacity'] ?? 0).toInt()}');
    _sohCtrl = TextEditingController(text: '${(v['stateOfHealth'] ?? 100).toInt()}');
    _odoCtrl = TextEditingController(text: '${(v['currentOdo'] ?? 0).toInt()}');
    _efficiencyCtrl = TextEditingController(text: '${(v['defaultEfficiency'] ?? 1.2)}');
    _loadSpec();
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    _batteryCapCtrl.dispose();
    _sohCtrl.dispose();
    _odoCtrl.dispose();
    _efficiencyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSpec() async {
    final modelName = widget.vehicleData['model'] ?? widget.vehicleData['vehicleName'] ?? '';
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
          'model': _modelCtrl.text.trim(),
          'vehicleName': _modelCtrl.text.trim(),
          'year': int.tryParse(_yearCtrl.text) ?? 2024,
          'batteryCapacity': double.tryParse(_batteryCapCtrl.text) ?? 0,
          'stateOfHealth': double.tryParse(_sohCtrl.text) ?? 100,
          'currentOdo': double.tryParse(_odoCtrl.text) ?? 0,
          'defaultEfficiency': double.tryParse(_efficiencyCtrl.text) ?? 1.2,
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
        AppPopup.showError('Lỗi: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicleData;
    final modelName = v['model'] ?? v['vehicleName'] ?? 'Xe';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          modelName,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
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
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  )
                : Text(
                    _isEditing ? 'Lưu' : 'Sửa',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Vehicle header card
            _buildHeaderCard(modelName)
                .animate()
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.05),
            const SizedBox(height: 24),

            // Editable Specs
            _buildSpecSection('THÔNG SỐ XE', [
              _SpecRow(label: 'Model', controller: _modelCtrl, isEditing: _isEditing, icon: Icons.electric_moped_rounded),
              _SpecRow(label: 'Năm SX', controller: _yearCtrl, isEditing: _isEditing, icon: Icons.calendar_today, keyboardType: TextInputType.number),
              _SpecRow(label: 'Dung lượng pin (Wh)', controller: _batteryCapCtrl, isEditing: _isEditing, icon: Icons.battery_full_rounded, keyboardType: TextInputType.number),
              _SpecRow(label: 'SoH (%)', controller: _sohCtrl, isEditing: _isEditing, icon: Icons.favorite_outline, keyboardType: TextInputType.number),
              _SpecRow(label: 'ODO (km)', controller: _odoCtrl, isEditing: _isEditing, icon: Icons.speed_rounded, keyboardType: TextInputType.number),
              _SpecRow(label: 'Hiệu suất (km/%)', controller: _efficiencyCtrl, isEditing: _isEditing, icon: Icons.eco_rounded, keyboardType: TextInputType.numberWithOptions(decimal: true)),
            ]).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05),

            // Catalog specs (read-only from VinFast database)
            if (_spec != null) ...[
              const SizedBox(height: 24),
              _buildCatalogSection()
                  .animate()
                  .fadeIn(delay: 200.ms)
                  .slideY(begin: 0.05),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(String modelName) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryContainer,
            AppColors.primaryContainer.withAlpha(120),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withAlpha(51)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(40),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.electric_moped_rounded, color: AppColors.primary, size: 36),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  modelName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _miniChip('${_yearCtrl.text}'),
                    const SizedBox(width: 8),
                    _miniChip('${_batteryCapCtrl.text} Wh'),
                    const SizedBox(width: 8),
                    _miniChip('SoH: ${_sohCtrl.text}%'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildSpecSection(String title, List<_SpecRow> rows) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.settings_outlined, color: AppColors.primary, size: 16),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                if (_isEditing) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.warningBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'ĐANG SỬA',
                      style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...rows.asMap().entries.map((entry) {
            final i = entry.key;
            final row = entry.value;
            return Column(
              children: [
                if (i > 0) Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
                _buildSpecRow(row),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSpecRow(_SpecRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(row.icon, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              row.label,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 3,
            child: row.isEditing
                ? TextField(
                    controller: row.controller,
                    keyboardType: row.keyboardType,
                    style: const TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      filled: true,
                      fillColor: AppColors.surfaceLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.primary.withAlpha(51)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                    ),
                  )
                : Text(
                    row.controller.text,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogSection() {
    if (_spec == null) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 16),
                const SizedBox(width: 8),
                Text(
                  'CATALOG VINFAST',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.infoBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'CHỈ ĐỌC',
                    style: TextStyle(color: AppColors.info, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          _catalogRow('Tên model', _spec!.modelName),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          _catalogRow('Dung lượng (Wh)', '${_spec!.nominalCapacityWh.toInt()}'),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          _catalogRow('Dung lượng (Ah)', '${_spec!.nominalCapacityAh.toStringAsFixed(1)}'),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          _catalogRow('Điện áp (V)', '${_spec!.nominalVoltageV.toInt()}'),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          _catalogRow('Sạc tối đa (W)', '${_spec!.maxChargePowerW.toInt()}'),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          _catalogRow('Motor định mức (W)', '${_spec!.ratedMotorPowerW.toInt()}'),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          _catalogRow('Motor peak (W)', '${_spec!.peakMotorPowerW.toInt()}'),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          _catalogRow('Nguồn dữ liệu', _spec!.source),
        ],
      ),
    );
  }

  Widget _catalogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
          Text(
            value,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
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
