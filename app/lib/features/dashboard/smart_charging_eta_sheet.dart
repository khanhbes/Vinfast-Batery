import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/api_service.dart';
import '../../data/services/charge_tracking_service.dart';

/// Smart Charging ETA (Beta) Bottom Sheet
/// 
/// Flow:
/// 1. User enters current battery % (prefilled from vehicle)
/// 2. User enters target battery %
/// 3. App calls AI prediction endpoint
/// 4. Show prediction with "Rút lúc HH:mm" and Beta badge
/// 5. User confirms to start charging with reminder
class SmartChargingEtaSheet extends ConsumerStatefulWidget {
  final String vehicleId;
  final int initialBattery;
  final int currentOdo;
  final ChargeTrackingService chargeService;

  const SmartChargingEtaSheet({
    super.key,
    required this.vehicleId,
    required this.initialBattery,
    required this.currentOdo,
    required this.chargeService,
  });

  @override
  ConsumerState<SmartChargingEtaSheet> createState() =>
      _SmartChargingEtaSheetState();
}

class _SmartChargingEtaSheetState extends ConsumerState<SmartChargingEtaSheet> {
  late final TextEditingController _currentBatteryCtrl;
  late final TextEditingController _targetBatteryCtrl;
  
  bool _reminderEnabled = true;
  bool _isLoading = false;
  bool _showResult = false;
  
  // AI Prediction result
  double? _predictedDurationSec;
  double? _predictedDurationMin;
  String? _formattedDuration;
  DateTime? _predictedStopAt;
  String? _modelSource;
  String? _modelVersion;
  double? _confidence;
  List<String> _warnings = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentBatteryCtrl = TextEditingController(text: '${widget.initialBattery}');
    _targetBatteryCtrl = TextEditingController(text: '80'); // Default target
  }

  @override
  void dispose() {
    _currentBatteryCtrl.dispose();
    _targetBatteryCtrl.dispose();
    super.dispose();
  }

  Future<void> _getPrediction() async {
    final current = int.tryParse(_currentBatteryCtrl.text) ?? widget.initialBattery;
    final target = int.tryParse(_targetBatteryCtrl.text) ?? 80;

    // Validation
    if (current < 0 || current > 100 || target < 0 || target > 100) {
      setState(() => _error = 'Pin % phải từ 0 đến 100');
      return;
    }
    if (target <= current) {
      setState(() => _error = 'Mục tiêu phải lớn hơn pin hiện tại');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _showResult = false;
    });

    try {
      final result = await ApiService().predictChargingTime(
        vehicleId: widget.vehicleId,
        currentBattery: current,
        targetBattery: target,
      );

      if (result['success'] == true) {
        final data = result['data'] as Map<String, dynamic>;
        setState(() {
          _predictedDurationSec = data['predictedDurationSec']?.toDouble();
          _predictedDurationMin = data['predictedDurationMin']?.toDouble();
          _formattedDuration = data['formattedDuration'] as String?;
          _modelSource = data['modelSource'] as String?;
          _modelVersion = data['modelVersion'] as String?;
          _confidence = data['confidence']?.toDouble();
          _warnings = (data['warnings'] as List<dynamic>?)?.cast<String>() ?? [];
          
          // Calculate predicted stop time
          if (_predictedDurationSec != null) {
            _predictedStopAt = DateTime.now().add(
              Duration(seconds: _predictedDurationSec!.toInt()),
            );
          }
          
          _showResult = true;
        });
      } else {
        setState(() => _error = result['error'] ?? 'Không thể lấy dự đoán');
      }
    } catch (e) {
      setState(() => _error = 'Lỗi: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startCharging() async {
    final current = int.tryParse(_currentBatteryCtrl.text) ?? widget.initialBattery;
    final target = int.tryParse(_targetBatteryCtrl.text) ?? 80;

    await widget.chargeService.startCharging(
      vehicleId: widget.vehicleId,
      currentBattery: current,
      currentOdo: widget.currentOdo,
      targetBatteryPercent: target,
      predictedDurationSec: _predictedDurationSec,
      predictedStopAt: _predictedStopAt,
      modelSource: _modelSource ?? 'heuristic_fallback',
      modelVersion: _modelVersion ?? 'heuristic-v1',
      reminderEnabled: _reminderEnabled,
    );

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  String get _predictedStopTimeText {
    if (_predictedStopAt == null) return '--:--';
    final h = _predictedStopAt!.hour.toString().padLeft(2, '0');
    final m = _predictedStopAt!.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20,
        right: 20,
        top: 16,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title with Beta badge
          Row(
            children: [
              Expanded(
                child: Text(
                  'Smart Charging ETA',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primaryGreen.withOpacity(0.3),
                  ),
                ),
                child: Text(
                  'Beta',
                  style: TextStyle(
                    color: AppColors.primaryGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Dự đoán thời gian sạc bằng AI',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 24),

          // Input fields
          Row(
            children: [
              Expanded(
                child: _buildInputField(
                  label: 'Pin hiện tại (%)',
                  controller: _currentBatteryCtrl,
                  hint: '30',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildInputField(
                  label: 'Mục tiêu (%)',
                  controller: _targetBatteryCtrl,
                  hint: '80',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Reminder toggle
          Row(
            children: [
              Checkbox(
                value: _reminderEnabled,
                onChanged: (v) => setState(() => _reminderEnabled = v ?? true),
                activeColor: AppColors.primaryGreen,
              ),
              Expanded(
                child: Text(
                  'Nhắc tôi khi nên rút sạc',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Error message
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Prediction result
          if (_showResult && _predictedDurationSec != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primaryGreen.withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: AppColors.primaryGreen,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Kết quả dự đoán',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formattedDuration ?? '--',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Rút lúc $_predictedStopTimeText',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Model source and confidence
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _modelSource?.contains('ai') == true
                              ? 'AI Model'
                              : 'Heuristic',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_confidence != null)
                        Text(
                          'Độ tin: ${_confidence!.toInt()}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                    ],
                  ),
                  // Warnings
                  if (_warnings.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ..._warnings.map((w) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: Colors.orange.withOpacity(0.7),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              w,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.withOpacity(0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
                  ],
                ],
              ),
            ).animate().fadeIn(duration: 300.ms).slideY(
              begin: 0.2,
              end: 0,
              duration: 300.ms,
            ),
            const SizedBox(height: 20),
          ],

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : (_showResult
                          ? _startCharging
                          : _getPrediction),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_showResult ? 'Bắt đầu sạc' : 'Dự đoán'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}
