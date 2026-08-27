import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/api_service.dart';
import '../../core/services/notification_center_service.dart';
import '../../data/services/battery_state_service.dart';
import '../../data/services/charging_feedback_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/models/smart_charger_status.dart';
import '../../data/models/smart_charging_session.dart';
import '../../data/services/smart_charger_service.dart';
import 'widgets/smart_charger_card.dart';

/// AI Charging Predictor Screen — PLAN #2 Enhanced
/// - Full fine-tuning workflow
/// - System reminder for unplug
/// - CSV data logging for model fine-tuning
class AiChargingPredictorScreen extends ConsumerStatefulWidget {
  const AiChargingPredictorScreen({super.key});

  @override
  ConsumerState<AiChargingPredictorScreen> createState() =>
      _AiChargingPredictorScreenState();
}

class _AiChargingPredictorScreenState
    extends ConsumerState<AiChargingPredictorScreen> {
  double _targetSOC = 80;
  double _currentSOC = 20;
  bool _isFastCharging = false;
  bool _isLoading = false;
  String? _prediction;
  String? _completionTime;
  int _predictedMinutes = 0;
  double _actualSOC = 0;
  bool _reminderSet = false;
  DateTime? _reminderTime;
  bool _feedbackSubmitted = false;
  DateTime? _startTime;
  int _feedbackCount = 0;
  double _avgAccuracy = 0;
  final SmartChargerService _smartChargerService = SmartChargerService();
  SmartChargerStatus? _smartChargerStatus;
  String? _smartChargerError;
  bool _smartChargerLoading = false;
  bool _smartChargerCommandBusy = false;
  bool _smartChargerRefreshInFlight = false;
  Timer? _smartChargerPollTimer;
  DateTime? _smartChargerLastUpdated;
  DateTime? _predictedFullAt;
  String? _predictionSource;
  double? _predictionConfidence;
  String? _monitorSessionId;
  String? _monitorSessionError;

  @override
  void initState() {
    super.initState();
    _loadCurrentBatteryState();
    _loadFeedbackStats();
    _startSmartChargerPolling();
  }

  @override
  void dispose() {
    _smartChargerPollTimer?.cancel();
    super.dispose();
  }

  void _startSmartChargerPolling() {
    _refreshSmartChargerStatus();
    if (!_smartChargerService.isConfigured) return;
    _smartChargerPollTimer?.cancel();
    _smartChargerPollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshSmartChargerStatus(silent: true),
    );
  }

  Future<void> _refreshSmartChargerStatus({bool silent = false}) async {
    if (_smartChargerRefreshInFlight || _smartChargerCommandBusy || !mounted) {
      return;
    }
    _smartChargerRefreshInFlight = true;
    if (!silent) {
      setState(() => _smartChargerLoading = true);
    }
    try {
      final status = await _smartChargerService.getStatus();
      if (!mounted) return;
      setState(() {
        _smartChargerStatus = status;
        _smartChargerError = status.online
            ? null
            : 'Không thể kết nối bộ điều khiển sạc trong mạng Wi-Fi.';
        _smartChargerLastUpdated = DateTime.now();
      });
    } on SmartChargerException catch (error) {
      if (!mounted) return;
      setState(() => _smartChargerError = error.message);
    } catch (error) {
      debugPrint('[SmartCharger] status error: $error');
      if (!mounted) return;
      setState(() {
        _smartChargerError =
            'Không thể kết nối bộ điều khiển sạc trong mạng Wi-Fi.';
      });
    } finally {
      _smartChargerRefreshInFlight = false;
      if (mounted && _smartChargerLoading) {
        setState(() => _smartChargerLoading = false);
      }
    }
  }

  Future<void> _loadCurrentBatteryState() async {
    final vehicleId = ref.read(selectedVehicleIdProvider);
    if (vehicleId.isEmpty) return;

    try {
      final state = await BatteryStateService.getCurrentBatteryState(vehicleId);
      if (!mounted) return;
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
    if (_reminderSet) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Hãy hủy nhắc hẹn hiện tại trước khi dự đoán lại.',
          ),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    if (_targetSOC <= _currentSOC) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mức pin mục tiêu phải lớn hơn mức pin hiện tại.'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final vehicleId = ref.read(selectedVehicleIdProvider);
    if (vehicleId.isEmpty) {
      return;
    }

    final predictionStartedAt = DateTime.now();
    setState(() => _isLoading = true);

    try {
      // Gọi API predict-charging-time (AI model + heuristic fallback)
      final response = await ApiService().predictChargingTime(
        vehicleId: vehicleId,
        currentBattery: _currentSOC.toInt(),
        targetBattery: _targetSOC.toInt(),
        ambientTempC: await _fetchTemperature(),
      );

      if (response['success'] == true) {
        final data = response['data'] as Map<String, dynamic>? ?? {};
        final durationMin =
            (data['predictedDurationMin'] ?? data['estimatedMinutes'] ?? 0)
                .toDouble();
        final minutes = durationMin.round();
        final formatted =
            data['formattedDuration'] ??
            data['formattedTime'] ??
            '$minutes phút';
        final predictedFullAt = predictionStartedAt.add(
          Duration(minutes: minutes),
        );
        final formattedTime =
            '${predictedFullAt.hour.toString().padLeft(2, '0')}:${predictedFullAt.minute.toString().padLeft(2, '0')}';
        final modelSource = data['modelSource']?.toString();
        final confidenceValue = data['confidence'];
        final confidence = confidenceValue is num
            ? confidenceValue.toDouble()
            : double.tryParse(confidenceValue?.toString() ?? '');

        if (!mounted) return;
        setState(() {
          _prediction = formatted.toString();
          _predictedMinutes = minutes;
          _completionTime = formattedTime;
          _startTime = predictionStartedAt;
          _predictedFullAt = predictedFullAt;
          _predictionSource = modelSource;
          _predictionConfidence = confidence;
          _isLoading = false;
          _feedbackSubmitted = false;
          _reminderSet = false;
          _reminderTime = null;
          _actualSOC = _targetSOC; // Default to target
        });
        await _syncPredictionToSmartCharger(vehicleId: vehicleId);
      } else {
        await _applyLocalFallback(
          vehicleId: vehicleId,
          predictionStartedAt: predictionStartedAt,
        );
      }
    } catch (e) {
      debugPrint('[AiCharging] cloud prediction error, using fallback: $e');
      await _applyLocalFallback(
        vehicleId: vehicleId,
        predictionStartedAt: predictionStartedAt,
      );
    }
  }

  Future<void> _applyLocalFallback({
    required String vehicleId,
    required DateTime predictionStartedAt,
  }) async {
    const batteryCapacityWh = AppConstants.defaultBatteryCapacityWh;
    final chargerPowerW = _isFastCharging ? 1000.0 : 400.0;
    final energyNeededWh =
        (_targetSOC - _currentSOC) / 100.0 * batteryCapacityWh;
    final minutes = ((energyNeededWh / chargerPowerW) * 60).round();
    final predictedFullAt = predictionStartedAt.add(Duration(minutes: minutes));
    final formattedTime =
        '${predictedFullAt.hour.toString().padLeft(2, '0')}:${predictedFullAt.minute.toString().padLeft(2, '0')}';
    if (!mounted) return;
    setState(() {
      _prediction = '$minutes phút';
      _predictedMinutes = minutes;
      _completionTime = formattedTime;
      _startTime = predictionStartedAt;
      _predictedFullAt = predictedFullAt;
      _predictionSource = 'local_fallback';
      _predictionConfidence = null;
      _isLoading = false;
      _feedbackSubmitted = false;
      _reminderSet = false;
      _reminderTime = null;
      _actualSOC = _targetSOC;
    });
    await _syncPredictionToSmartCharger(vehicleId: vehicleId);
  }

  Future<void> _syncPredictionToSmartCharger({
    required String vehicleId,
  }) async {
    if (!_smartChargerService.isConfigured ||
        _predictedMinutes <= 0 ||
        _startTime == null ||
        _predictedFullAt == null) {
      return;
    }
    try {
      final response = await _smartChargerService.startMonitoringSession(
        SmartChargingSessionRequest(
          vehicleId: vehicleId,
          startSoc: _currentSOC,
          targetSoc: _targetSOC,
          predictedMinutes: _predictedMinutes,
          startedAt: _startTime!,
          predictedFullAt: _predictedFullAt!,
          chargingMode: _isFastCharging ? 'fast' : 'standard',
          predictionSource: _predictionSource,
          predictionConfidence: _predictionConfidence,
        ),
      );
      if (!mounted) return;
      setState(() {
        _monitorSessionId = response.sessionId;
        _monitorSessionError = null;
      });
    } catch (error) {
      debugPrint('[SmartCharger] monitor session sync error: $error');
      if (!mounted) return;
      setState(() {
        _monitorSessionId = null;
        _monitorSessionError =
            'Dự đoán vẫn hợp lệ, nhưng chưa đồng bộ được với Smart Charger.';
      });
    }
  }

  Future<void> _turnSmartChargerOn() async {
    if (_smartChargerStatus == null || _smartChargerError != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bật nguồn sạc?'),
        content: const Text(
          'Hãy đảm bảo bộ sạc và xe đã được kết nối đúng cách.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('HỦY'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('BẬT NGUỒN'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runSmartChargerCommand(turnOn: true);
  }

  Future<void> _turnSmartChargerOff() => _runSmartChargerCommand(turnOn: false);

  Future<void> _runSmartChargerCommand({required bool turnOn}) async {
    if (_smartChargerCommandBusy || !mounted) return;
    setState(() => _smartChargerCommandBusy = true);
    try {
      if (turnOn) {
        await _smartChargerService.turnOn();
      } else {
        await _smartChargerService.turnOff();
      }
      final confirmedStatus = await _smartChargerService.getStatus();
      if (confirmedStatus.relay != turnOn) {
        throw SmartChargerException(
          turnOn
              ? 'Không thể xác nhận nguồn sạc đã bật.'
              : 'Không thể xác nhận nguồn sạc đã ngắt.',
        );
      }
      if (!mounted) return;
      setState(() {
        _smartChargerStatus = confirmedStatus;
        _smartChargerError = null;
        _smartChargerLastUpdated = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(turnOn ? 'Đã bật nguồn sạc.' : 'Đã ngắt nguồn sạc.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      debugPrint('[SmartCharger] command error: $error');
      if (!mounted) return;
      setState(() {
        _smartChargerError = turnOn
            ? 'Không thể bật nguồn sạc.'
            : 'Không thể ngắt nguồn sạc.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            turnOn ? 'Không thể bật nguồn sạc.' : 'Không thể ngắt nguồn sạc.',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _smartChargerCommandBusy = false);
      }
    }
  }

  Future<double> _fetchTemperature() async {
    return 28.0; // TODO: Call weather API
  }

  Future<void> _setReminder() async {
    // Validate trước khi gọi service
    if (_predictedMinutes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Thời gian dự đoán không hợp lệ. Hãy chạy DỰ ĐOÁN trước.',
          ),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final completionDateTime = _predictedFullAt;
    if (_completionTime == null || completionDateTime == null) return;
    // Nếu thời điểm đã qua (edge case: dự đoán < 1 phút)
    if (completionDateTime.isBefore(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thời gian nhắc nhở đã qua. Hãy dự đoán lại.'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      // scheduleChargeReminder tự gọi initialize() bên trong
      final isExact = await NotificationService().scheduleChargeReminder(
        completionDateTime,
        _targetSOC.toInt(),
      );

      setState(() {
        _reminderSet = true;
        _reminderTime = completionDateTime;
      });

      await NotificationCenterService().notifyChargeReminderScheduled(
        targetPercent: _targetSOC.toInt(),
        scheduledAt: completionDateTime,
        exact: isExact,
      );

      if (mounted) {
        final msg = isExact
            ? '⏰ Đã đặt nhắc nhở lúc $_completionTime'
            : '⏰ Đã đặt nhắc nhở lúc $_completionTime (gần đúng)';
        final color = isExact ? AppColors.success : AppColors.warning;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: color,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi đặt nhắc nhở: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _cancelReminder() async {
    final scheduledAt = _reminderTime;
    try {
      await NotificationService().cancelChargeReminder();
      await NotificationCenterService().notifyChargeReminderCancelled(
        scheduledAt: scheduledAt,
      );

      if (!mounted) return;
      setState(() {
        _reminderSet = false;
        _reminderTime = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Đã hủy nhắc hẹn rút sạc.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi hủy nhắc hẹn: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _submitFeedback() async {
    final vehicleId = ref.read(selectedVehicleIdProvider);
    if (vehicleId.isEmpty) return;

    int? actualMinutes;
    if (_startTime != null) {
      actualMinutes = DateTime.now().difference(_startTime!).inMinutes;
    }

    // ── Step 1: LUÔN lưu CSV local trước ───────────────────────────
    bool csvSaved = false;
    try {
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
      csvSaved = true;
    } catch (e) {
      debugPrint('[AiCharging] CSV save error: $e');
    }

    // ── Step 2: Thử gửi server (non-blocking, không nuốt CSV) ────────
    bool serverOk = false;
    String? serverErr;
    try {
      await BatteryStateService.submitChargeFeedback(
        vehicleId: vehicleId,
        predictionId: DateTime.now().millisecondsSinceEpoch.toString(),
        predictedDurationMinutes: _predictedMinutes,
        actualSOC: _actualSOC,
        targetSOC: _targetSOC,
        chargingMode: _isFastCharging ? 'fast' : 'standard',
      );
      serverOk = true;
    } catch (e) {
      debugPrint('[AiCharging] Server feedback error: $e');
      serverErr = e.toString();
    }

    if (mounted) {
      setState(() {
        _feedbackSubmitted = true;
      });
      _loadFeedbackStats();

      // Thông báo rõ ràng: CSV luôn giữ, server có thể fail
      if (csvSaved && serverOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Đã lưu CSV và gửi server thành công'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      } else if (csvSaved && !serverOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '⚠️ Đã lưu CSV local. Gửi server thất bại — sẽ tự đồng bộ sau.',
            ),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ Không lưu được dữ liệu: ${serverErr ?? "Lỗi CSV"}',
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
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
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'AI Charging Predictor',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
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

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: SmartChargerCard(
                  status: _smartChargerStatus,
                  error: _smartChargerError,
                  loading: _smartChargerLoading,
                  commandBusy: _smartChargerCommandBusy,
                  lastUpdated: _smartChargerLastUpdated,
                  onRefresh: _refreshSmartChargerStatus,
                  onTurnOn: _turnSmartChargerOn,
                  onTurnOff: _turnSmartChargerOff,
                  monitorSessionId: _monitorSessionId,
                  monitorSessionError: _monitorSessionError,
                ),
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
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_feedbackCount mẫu • Accuracy: ${_avgAccuracy.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
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
              style: TextStyle(
                color: AppColors.info,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
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
                  Text(
                    'Nhập %',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: AppColors.warning,
                        inactiveTrackColor: AppColors.surfaceVariant,
                        thumbColor: AppColors.warning,
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
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
                      color: !_isFastCharging
                          ? AppColors.primary
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Standard (400W)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: !_isFastCharging
                            ? AppColors.background
                            : AppColors.textSecondary,
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
                      color: _isFastCharging
                          ? AppColors.primary
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Fast (1000W)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _isFastCharging
                            ? AppColors.background
                            : AppColors.textSecondary,
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
                child: Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thời gian sạc dự đoán',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
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
            onTap: _reminderSet ? _cancelReminder : _setReminder,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: _reminderSet ? AppColors.warningBg : AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _reminderSet
                      ? AppColors.warning
                      : AppColors.glassBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _reminderSet
                        ? Icons.notifications_off_rounded
                        : Icons.notifications_outlined,
                    color: _reminderSet
                        ? AppColors.warning
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _reminderSet
                          ? 'Hủy nhắc hẹn rút sạc lúc $_completionTime'
                          : '🔔 Đặt nhắc nhở rút sạc',
                      style: TextStyle(
                        color: _reminderSet
                            ? AppColors.warning
                            : AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _reminderSet ? Icons.close_rounded : Icons.chevron_right,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
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
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
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
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 10,
                    ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                color: AppColors.success,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phản hồi đã ghi nhận!',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Dữ liệu đã lưu vào CSV để fine-tune model.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _shareCsv,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.share_rounded, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Chia sẻ CSV',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Future<void> _shareCsv() async {
    final ok = await ChargingFeedbackService().shareCsv();
    if (mounted && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể chia sẻ CSV. Vui lòng kiểm tra quyền.'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
