import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'add_charge_log_controller.dart';

// ============================================================================
// Widget UI: AddChargeLogModal (Bottom Sheet)
// ============================================================================

class AddChargeLogModal extends ConsumerStatefulWidget {
  final String vehicleId;

  const AddChargeLogModal({
    super.key,
    required this.vehicleId,
  });

  /// Helper method để mở modal từ bất kỳ đâu
  static Future<bool?> show(BuildContext context, String vehicleId) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddChargeLogModal(vehicleId: vehicleId),
    );
  }

  @override
  ConsumerState<AddChargeLogModal> createState() => _AddChargeLogModalState();
}

class _AddChargeLogModalState extends ConsumerState<AddChargeLogModal> {
  final _formKey = GlobalKey<FormState>();
  final _startBatteryController = TextEditingController();
  final _endBatteryController = TextEditingController(text: '100');
  final _odoController = TextEditingController();

  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    // Load thông tin xe khi modal mở
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(addChargeLogProvider.notifier)
          .loadVehicle(widget.vehicleId);
    });
  }

  @override
  void dispose() {
    _startBatteryController.dispose();
    _endBatteryController.dispose();
    _odoController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Date/Time Picker helpers
  // --------------------------------------------------------------------------

  Future<DateTime?> _pickDateTime(BuildContext context, DateTime? initial) async {
    final now = DateTime.now();
    final initialDate = initial ?? now;

    // Chọn ngày
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Chọn ngày',
      cancelText: 'Huỷ',
      confirmText: 'Chọn',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00C853),
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E2C),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (date == null) return null;

    // Chọn giờ
    if (!context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
      helpText: 'Chọn giờ',
      cancelText: 'Huỷ',
      confirmText: 'Chọn',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00C853),
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E2C),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  // --------------------------------------------------------------------------
  // Save handler
  // --------------------------------------------------------------------------

  Future<void> _onSave() async {
    // Validate form fields trước
    if (!_formKey.currentState!.validate()) return;

    final notifier = ref.read(addChargeLogProvider.notifier);
    final success = await notifier.saveChargeLog(
      startBattery: _startBatteryController.text,
      endBattery: _endBatteryController.text,
      odo: _odoController.text,
      vehicleId: widget.vehicleId,
    );

    if (success && mounted) {
      // Hiển thị thông báo thành công
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Đã lưu nhật ký sạc thành công!'),
            ],
          ),
          backgroundColor: const Color(0xFF00C853),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  // --------------------------------------------------------------------------
  // BUILD
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addChargeLogProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    // Listen for error messages from controller-level validation
    ref.listen<AddChargeLogState>(addChargeLogProvider, (prev, next) {
      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(next.errorMessage!)),
              ],
            ),
            backgroundColor: const Color(0xFFE53935),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    });

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            _buildDragHandle(),

            // Header
            _buildHeader(),

            const Divider(color: Color(0xFF2A2A3E), height: 1),

            // Content (scrollable)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- Thông tin xe ---
                      if (state.vehicle != null) _buildVehicleInfoCard(state),

                      const SizedBox(height: 20),

                      // --- Mức pin ---
                      _buildSectionTitle('⚡ Mức pin', 'Battery Level'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _startBatteryController,
                              label: 'Trước sạc (%)',
                              hint: 'VD: 20',
                              icon: Icons.battery_1_bar_rounded,
                              iconColor: const Color(0xFFFF6B6B),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                              validator: (value) => ref
                                  .read(addChargeLogProvider.notifier)
                                  .validateBatteryPercent(
                                      value, 'Mức pin trước sạc'),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: Color(0xFF4A4A6A),
                            ),
                          ),
                          Expanded(
                            child: _buildTextField(
                              controller: _endBatteryController,
                              label: 'Sau sạc (%)',
                              hint: 'VD: 100',
                              icon: Icons.battery_full_rounded,
                              iconColor: const Color(0xFF00C853),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                              validator: (value) => ref
                                  .read(addChargeLogProvider.notifier)
                                  .validateBatteryPercent(
                                      value, 'Mức pin sau sạc'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // --- ODO ---
                      _buildSectionTitle('🛣️ Số ODO', 'Odometer'),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _odoController,
                        label: 'ODO hiện tại (km)',
                        hint: state.vehicle != null
                            ? 'Tối thiểu: ${state.vehicle!.currentOdo} km'
                            : 'VD: 1500',
                        icon: Icons.speed_rounded,
                        iconColor: const Color(0xFF448AFF),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(7),
                        ],
                        validator: (value) => ref
                            .read(addChargeLogProvider.notifier)
                            .validateOdo(value),
                      ),

                      const SizedBox(height: 24),

                      // --- Thời gian sạc ---
                      _buildSectionTitle('🕐 Thời gian sạc', 'Charging Time'),
                      const SizedBox(height: 12),
                      _buildDateTimePicker(
                        label: 'Bắt đầu sạc',
                        icon: Icons.play_circle_outline_rounded,
                        iconColor: const Color(0xFF00C853),
                        value: state.startTime,
                        onTap: () async {
                          final dt = await _pickDateTime(context, state.startTime);
                          if (dt != null) {
                            ref
                                .read(addChargeLogProvider.notifier)
                                .setStartTime(dt);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildDateTimePicker(
                        label: 'Kết thúc sạc',
                        icon: Icons.stop_circle_outlined,
                        iconColor: const Color(0xFFFF6B6B),
                        value: state.endTime,
                        onTap: () async {
                          final dt = await _pickDateTime(context, state.endTime);
                          if (dt != null) {
                            ref
                                .read(addChargeLogProvider.notifier)
                                .setEndTime(dt);
                          }
                        },
                      ),

                      // Duration display
                      if (state.startTime != null && state.endTime != null)
                        _buildDurationCard(state.startTime!, state.endTime!),

                      const SizedBox(height: 32),

                      // --- Nút Lưu ---
                      _buildSaveButton(state),

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Sub-widgets
  // --------------------------------------------------------------------------

  Widget _buildDragHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFF4A4A6A),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00C853), Color(0xFF00E676)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00C853).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.electric_bolt_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nhập nhật ký sạc',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Ghi lại thông tin sau khi sạc xe',
                  style: TextStyle(
                    color: Color(0xFF8888AA),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Color(0xFF8888AA)),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleInfoCard(AddChargeLogState state) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF222240),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E2E4E)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00C853).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.two_wheeler_rounded,
              color: Color(0xFF00C853),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Xe: ${state.vehicle!.vehicleId}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'ODO hiện tại: ${state.vehicle!.currentOdo} km',
                  style: const TextStyle(
                    color: Color(0xFF8888AA),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, String subtitle) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF6A6A8A),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF8888AA), fontSize: 13),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF4A4A6A), fontSize: 13),
        prefixIcon: Icon(icon, color: iconColor, size: 20),
        filled: true,
        fillColor: const Color(0xFF222240),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2E2E4E)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2E2E4E)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF00C853), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE53935)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5),
        ),
        errorStyle: const TextStyle(
          color: Color(0xFFFF6B6B),
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildDateTimePicker({
    required String label,
    required IconData icon,
    required Color iconColor,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF222240),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value != null
                ? const Color(0xFF00C853).withValues(alpha: 0.5)
                : const Color(0xFF2E2E4E),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF8888AA),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value != null
                        ? _dateFormat.format(value)
                        : 'Nhấn để chọn thời gian',
                    style: TextStyle(
                      color: value != null
                          ? Colors.white
                          : const Color(0xFF4A4A6A),
                      fontSize: 14,
                      fontWeight: value != null
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.calendar_month_rounded,
              color: Color(0xFF4A4A6A),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationCard(DateTime start, DateTime end) {
    final duration = end.difference(start);
    final isValid = duration.isNegative == false && duration.inMinutes > 0;

    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final durationText = isValid
        ? '${hours}h ${minutes.toString().padLeft(2, '0')}m'
        : 'Thời gian không hợp lệ';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isValid
              ? const Color(0xFF00C853).withValues(alpha: 0.1)
              : const Color(0xFFE53935).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isValid
                ? const Color(0xFF00C853).withValues(alpha: 0.3)
                : const Color(0xFFE53935).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isValid ? Icons.timer_outlined : Icons.warning_amber_rounded,
              color: isValid
                  ? const Color(0xFF00C853)
                  : const Color(0xFFE53935),
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              isValid ? 'Thời gian sạc: $durationText' : durationText,
              style: TextStyle(
                color: isValid
                    ? const Color(0xFF00C853)
                    : const Color(0xFFE53935),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton(AddChargeLogState state) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: state.isLoading ? null : _onSave,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00C853),
          disabledBackgroundColor: const Color(0xFF2A2A3E),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: state.isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.save_rounded, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Lưu nhật ký sạc',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
