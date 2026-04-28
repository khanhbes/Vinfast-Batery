import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../data/services/battery_state_service.dart';
import '../../data/services/charging_feedback_service.dart';
import '../../data/services/notification_service.dart';

/// AI Charging Predictor Screen — PLAN #2 Enhanced
/// - Full fine-tuning workflow
/// - System reminder for unplug
/// - CSV data logging for model fine-tuning
class AiChargingPredictorScreen extends ConsumerStatefulWidget {
  const AiChargingPredictorScreen({super.key});

  @override
  ConsumerState<AiChargingPredictorScreen> createState() => _AiChargingPredictorScreenState();
}

class _AiChargingPredictorScreenState extends ConsumerState<AiChargingPredictorScreen> {
  double _targetSOC = 80;
  double _currentSOC = 20;
  bool _isFastCharging = false;
  bool _isLoading = false;
  String? _prediction;
  String? _completionTime;
  int _predictedMinutes = 0;
  double _actualSOC = 0;
  bool _reminderSet = false;
  bool _feedbackSubmitted = false;
  DateTime? _startTime;
  int _feedbackCount = 0;
  double _avgAccuracy = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrentBatteryState();
    _loadFeedbackStats();
  }

  Future<void> _loadCurrentBatteryState() async {
    final vehicleId = ref.read(selectedVehicleIdProvider);
    if (vehicleId.isEmpty) return;

    try {
      final state = await BatteryStateService.getCurrentBatteryState(vehicleId);
      setState(() {
        _currentSOC = state.percentage;
      });
    } catch (e) {
      // Keep default value
    }
  }

  Future<void> _loadFeedbackStats() async {
    final service = ChargingFeedbackService();
    final count = await service.getFeedbackCount();
    final avg = await service.getAverageAccuracy();
    if (mounted) {
      setState(() {
        _feedbackCount = count;
        _avgAccuracy = avg;
      });
    }
  }

  Future<void> _predictCharging() async {
    setState(() => _isLoading = true);

    final vehicleId = ref.read(selectedVehicleIdProvider);
    if (vehicleId.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final temperature = await _fetchTemperature();

      await BatteryStateService.predictSOC(
        vehicleId: vehicleId,
        currentBattery: _currentSOC,
        temperature: temperature,
        voltage: _isFastCharging ? 400.0 : 220.0,
        current: _isFastCharging ? 100.0 : 32.0,
        odometer: 0,
        timeOfDay: DateTime.now().hour,
        dayOfWeek: DateTime.now().weekday,
        avgSpeed: 0,
        elevationGain: 0,
        weatherCondition: 'sunny',
      );

      // Calculate charging time
      final power = _isFastCharging ? 1000.0 : 400.0; // Watts
      final energyNeeded = (_targetSOC - _currentSOC) / 100 * 72.0; // kWh
      final hours = energyNeeded * 1000 / power;
      final minutes = (hours * 60).round();

      final completionDateTime = DateTime.now().add(Duration(minutes: minutes));
      final formattedTime = '${completionDateTime.hour.toString().padLeft(2, '0')}:${completionDateTime.minute.toString().padLeft(2, '0')}';

      setState(() {
        _prediction = '$minutes phút';
        _predictedMinutes = minutes;
        _completionTime = formattedTime;
        _startTime = DateTime.now();
        _isLoading = false;
        _feedbackSubmitted = false;
        _reminderSet = false;
        _actualSOC = _targetSOC; // Default to target
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi dự đoán: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<double> _fetchTemperature() async {
    return 28.0; // TODO: Call weather API
  }

  Future<void> _setReminder() async {
    if (_predictedMinutes <= 0 || _completionTime == null) return;

    try {
      final completionDateTime = DateTime.now().add(Duration(minutes: _predictedMinutes));

      // Schedule a local notification for when charging completes
      await NotificationService().scheduleChargeReminder(
        completionDateTime,
        _targetSOC.toInt(),
      );

      setState(() => _reminderSet = true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⏰ Đã đặt nhắc nhở lúc $_completionTime'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi đặt nhắc nhở: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _submitFeedback() async {
    final vehicleId = ref.read(selectedVehicleIdProvider);
    if (vehicleId.isEmpty) return;

    try {
      // Calculate actual minutes
      int? actualMinutes;
      if (_startTime != null) {
        actualMinutes = DateTime.now().difference(_startTime!).inMinutes;
      }

      // 1. Submit to Firestore (existing)
      await BatteryStateService.submitChargeFeedback(
        vehicleId: vehicleId,
        predictionId: DateTime.now().millisecondsSinceEpoch.toString(),
        predictedDurationMinutes: _predictedMinutes,
        actualSOC: _actualSOC,
        targetSOC: _targetSOC,
        chargingMode: _isFastCharging ? 'fast' : 'standard',
      );

      // 2. Log to local CSV (PLAN #2 - for fine-tuning)
      await ChargingFeedbackService().logFeedback(
        vehicleId: vehicleId,
        startSOC: _currentSOC,
        targetSOC: _targetSOC,
        actualSOC: _actualSOC,
        predictedMinutes: _predictedMinutes,
        actualMinutes: actualMinutes,
        chargingMode: _isFastCharging ? 'fast' : 'standard',
        temperature: 28.0,
        completionTime: _completionTime,
      );

      if (mounted) {
        setState(() {
          _feedbackSubmitted = true;
        });
        _loadFeedbackStats(); // Refresh stats

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Cảm ơn! Dữ liệu đã lưu vào CSV để cải thiện AI.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi gửi feedback: $e'),
            backgroundColor: AppColors.error,
          ),
        );
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
          'AI Charging Predictor',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Feedback stats banner
            if (_feedbackCount > 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: _buildFeedbackStatsBanner(),
                ),
              ),

            // AI Charging Predictor Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _buildChargingCard(),
              ),
            ),

            // Prediction Result
            if (_prediction != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _buildPredictionResult(),
                ),
              ),

            // Feedback Section
            if (_prediction != null && !_feedbackSubmitted)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _buildFeedbackSection(),
                ),
              ),

            // Success feedback confirmation
            if (_feedbackSubmitted)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _buildFeedbackConfirmation(),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackStatsBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.info.withAlpha(51)),
      ),
      child: Row(
        children: [
          Icon(Icons.analytics_outlined, color: AppColors.info, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dữ liệu fine-tuning',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_feedbackCount mẫu • Accuracy: ${_avgAccuracy.toStringAsFixed(1)}%',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.info.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'CSV',
              style: TextStyle(color: AppColors.info, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildChargingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.bolt, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'AI CHARGING PREDICTOR',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Current SOC
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PIN HIỆN TẠI',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_currentSOC.toInt()}%',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              // Current SOC slider
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Nhập %', style: TextStyle(color: AppColors.textTertiary, fontSize: 10)),
                  SizedBox(
                    width: 120,
                    child: SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: AppColors.warning,
                        inactiveTrackColor: AppColors.surfaceVariant,
                        thumbColor: AppColors.warning,
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      ),
                      child: Slider(
                        value: _currentSOC,
                        min: 0,
                        max: 100,
                        onChanged: (v) => setState(() => _currentSOC = v),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Target SOC
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MỤC TIÊU SẠC',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${_targetSOC.toInt()}%',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Target slider
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.surfaceVariant,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withAlpha(26),
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: _targetSOC,
              min: _currentSOC,
              max: 100,
              onChanged: (v) => setState(() => _targetSOC = v),
            ),
          ),
          const SizedBox(height: 24),

          // Charging Mode
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isFastCharging = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: !_isFastCharging ? AppColors.primary : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Standard (400W)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: !_isFastCharging ? AppColors.background : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isFastCharging = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _isFastCharging ? AppColors.primary : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Fast (1000W)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _isFastCharging ? AppColors.background : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Predict Button
          GestureDetector(
            onTap: _isLoading ? null : _predictCharging,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: AppColors.background,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bolt, color: AppColors.background, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'DỰ ĐOÁN VỚI AI',
                          style: TextStyle(
                            color: AppColors.background,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }

  Widget _buildPredictionResult() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withAlpha(51)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.success.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.check_circle, color: AppColors.success, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thời gian sạc dự đoán',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _prediction!,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_completionTime != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.access_time, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Hoàn thành lúc: ${_completionTime!}',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Reminder toggle — PLAN #2
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _reminderSet ? null : _setReminder,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: _reminderSet ? AppColors.primary.withAlpha(26) : AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _reminderSet ? AppColors.primary : AppColors.glassBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _reminderSet ? Icons.notifications_active : Icons.notifications_outlined,
                    color: _reminderSet ? AppColors.primary : AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _reminderSet
                          ? '✅ Đã đặt nhắc nhở rút sạc lúc $_completionTime'
                          : '🔔 Đặt nhắc nhở rút sạc',
                      style: TextStyle(
                        color: _reminderSet ? AppColors.primary : AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!_reminderSet)
                    Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1);
  }

  Widget _buildFeedbackSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.feedback_outlined, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'PHẢN HỒI DỰ ĐOÁN',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'LƯU CSV',
                  style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sau khi sạc xong, nhập % pin thực tế để cải thiện mô hình AI.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Text(
            'Pin thực tế đạt được:',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: AppColors.surfaceVariant,
                    thumbColor: AppColors.primary,
                    overlayColor: AppColors.primary.withAlpha(26),
                    trackHeight: 6,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                  ),
                  child: Slider(
                    value: _actualSOC,
                    min: 0,
                    max: 100,
                    onChanged: (v) => setState(() => _actualSOC = v),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_actualSOC.toInt()}%',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _submitFeedback,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send, color: AppColors.background, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'GỬI & LƯU CSV',
                    style: TextStyle(
                      color: AppColors.background,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }

  Widget _buildFeedbackConfirmation() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withAlpha(51)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: AppColors.success, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Phản hồi đã ghi nhận!',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Dữ liệu đã lưu vào CSV để fine-tune model.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.95, 0.95));
  }
}
