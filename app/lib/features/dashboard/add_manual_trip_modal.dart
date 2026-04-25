import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/trip_log_model.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/repositories/trip_log_repository.dart';
import '../home/home_screen.dart';

/// Modal nhập tay chuyến đi (manual trip entry)
class AddManualTripModal extends ConsumerStatefulWidget {
  final VehicleModel vehicle;

  const AddManualTripModal({super.key, required this.vehicle});

  @override
  ConsumerState<AddManualTripModal> createState() => _AddManualTripModalState();
}

class _AddManualTripModalState extends ConsumerState<AddManualTripModal> {
  final _formKey = GlobalKey<FormState>();
  final _startBatteryCtrl = TextEditingController();
  final _endBatteryCtrl = TextEditingController();
  final _startOdoCtrl = TextEditingController();
  final _endOdoCtrl = TextEditingController();

  DateTime _startTime = DateTime.now().subtract(const Duration(hours: 1));
  DateTime _endTime = DateTime.now();
  PayloadType _payload = PayloadType.onePerson;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startOdoCtrl.text = widget.vehicle.currentOdo.toString();
  }

  @override
  void dispose() {
    _startBatteryCtrl.dispose();
    _endBatteryCtrl.dispose();
    _startOdoCtrl.dispose();
    _endOdoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Nhập chuyến đi thủ công',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 4),
              Text('Xe: ${widget.vehicle.vehicleName.isNotEmpty ? widget.vehicle.vehicleName : widget.vehicle.vehicleId}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 20),

              // Payload
              _buildPayloadSelector(),
              const SizedBox(height: 16),

              // Time pickers
              Row(
                children: [
                  Expanded(child: _buildTimePicker('Giờ xuất phát', _startTime, (dt) {
                    setState(() => _startTime = dt);
                  })),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTimePicker('Giờ kết thúc', _endTime, (dt) {
                    setState(() => _endTime = dt);
                  })),
                ],
              ),
              const SizedBox(height: 16),

              // Battery
              Row(
                children: [
                  Expanded(child: _buildTextField(
                    controller: _startBatteryCtrl,
                    label: 'Pin đầu (%)',
                    validator: _validateBattery,
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTextField(
                    controller: _endBatteryCtrl,
                    label: 'Pin cuối (%)',
                    validator: _validateBattery,
                  )),
                ],
              ),
              const SizedBox(height: 16),

              // ODO
              Row(
                children: [
                  Expanded(child: _buildTextField(
                    controller: _startOdoCtrl,
                    label: 'ODO đầu (km)',
                    validator: _validateOdo,
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTextField(
                    controller: _endOdoCtrl,
                    label: 'ODO cuối (km)',
                    validator: _validateOdo,
                  )),
                ],
              ),
              const SizedBox(height: 24),

              // Save
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.info,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Lưu chuyến đi',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPayloadSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.people_alt_rounded, color: AppColors.textSecondary, size: 18),
          const SizedBox(width: 8),
          const Text('Tải trọng:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const Spacer(),
          ...PayloadType.values.map((p) {
            final sel = p == _payload;
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTap: () => setState(() => _payload = p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.info.withValues(alpha: 0.15) : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: sel ? AppColors.info : AppColors.border),
                  ),
                  child: Text(p.label,
                    style: TextStyle(
                      color: sel ? AppColors.info : AppColors.textSecondary,
                      fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTimePicker(String label, DateTime value, ValueChanged<DateTime> onChanged) {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (date == null || !mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value),
        );
        if (time == null) return;
        onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              '${value.day}/${value.month} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      validator: validator,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }

  String? _validateBattery(String? value) {
    final v = int.tryParse(value ?? '');
    if (v == null) return 'Nhập số';
    if (v < 0 || v > 100) return '0-100%';
    return null;
  }

  String? _validateOdo(String? value) {
    final v = int.tryParse(value ?? '');
    if (v == null) return 'Nhập số';
    if (v < 0) return 'Phải ≥ 0';
    return null;
  }

  String? _validateForm() {
    final startBat = int.tryParse(_startBatteryCtrl.text) ?? 0;
    final endBat = int.tryParse(_endBatteryCtrl.text) ?? 0;
    final startOdo = int.tryParse(_startOdoCtrl.text) ?? 0;
    final endOdo = int.tryParse(_endOdoCtrl.text) ?? 0;

    if (startBat <= endBat) return 'Pin đầu phải lớn hơn pin cuối (vì tiêu hao)';
    if (endOdo <= startOdo) return 'ODO cuối phải lớn hơn ODO đầu';
    if (!_endTime.isAfter(_startTime)) return 'Giờ kết thúc phải sau giờ xuất phát';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final formError = _validateForm();
    if (formError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(formError), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _saving = true);

    final startBat = int.parse(_startBatteryCtrl.text);
    final endBat = int.parse(_endBatteryCtrl.text);
    final startOdo = int.parse(_startOdoCtrl.text);
    final endOdo = int.parse(_endOdoCtrl.text);
    final distance = (endOdo - startOdo).toDouble();
    final consumed = startBat - endBat;
    final efficiency = consumed > 0 ? distance / consumed : 0.0;

    final trip = TripLogModel(
      vehicleId: widget.vehicle.vehicleId,
      startTime: _startTime,
      endTime: _endTime,
      distance: double.parse(distance.toStringAsFixed(2)),
      payloadType: _payload,
      startBattery: startBat,
      endBattery: endBat,
      batteryConsumed: consumed,
      efficiency: double.parse(efficiency.toStringAsFixed(3)),
      startOdo: startOdo,
      endOdo: endOdo,
      entryMode: TripEntryMode.manual,
      distanceSource: DistanceSource.odometer,
    );

    try {
      await ref.read(tripLogRepositoryProvider).saveTripAndUpdateVehicle(
        trip: trip,
        vehicleId: widget.vehicle.vehicleId,
      );
      ref.invalidate(vehicleProvider(widget.vehicle.vehicleId));
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã lưu chuyến đi thành công!'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
