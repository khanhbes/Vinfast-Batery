import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/smart_charger_status.dart';

class SmartChargerCard extends StatelessWidget {
  const SmartChargerCard({
    super.key,
    required this.status,
    required this.error,
    required this.loading,
    required this.commandBusy,
    required this.lastUpdated,
    required this.onRefresh,
    required this.onTurnOn,
    required this.onTurnOff,
    this.monitorSessionId,
    this.monitorSessionError,
  });

  final SmartChargerStatus? status;
  final String? error;
  final bool loading;
  final bool commandBusy;
  final DateTime? lastUpdated;
  final VoidCallback onRefresh;
  final VoidCallback onTurnOn;
  final VoidCallback onTurnOff;
  final String? monitorSessionId;
  final String? monitorSessionError;

  bool get _notConfigured =>
      status == null && error?.contains('chưa được cấu hình') == true;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
              Icon(
                Icons.ev_station_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'SMART CHARGER',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (status != null && error == null)
                IconButton(
                  tooltip: 'Làm mới',
                  onPressed: loading ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  color: AppColors.textSecondary,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_notConfigured)
            _buildNotConfigured()
          else if (loading && status == null)
            _buildLoading()
          else if (error != null)
            _buildOffline()
          else if (status != null)
            _buildOnline(context, status!),
          if (!_notConfigured &&
              (monitorSessionId != null || monitorSessionError != null)) ...[
            const SizedBox(height: 14),
            Divider(color: AppColors.glassBorder, height: 1),
            const SizedBox(height: 12),
            _buildMonitorStatus(),
          ],
        ],
      ),
    );
  }

  Widget _buildNotConfigured() => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '⚪ Chưa cấu hình gateway',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      SizedBox(height: 8),
      Text(
        'Thiết lập SMART_CHARGER_API_BASE_URL để kết nối.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    ],
  );

  Widget _buildLoading() => const Row(
    children: [
      SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      SizedBox(width: 12),
      Text('Đang kết nối...', style: TextStyle(color: AppColors.textSecondary)),
    ],
  );

  Widget _buildOffline() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '🔴 Không kết nối gateway',
        style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Text(
        error!,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      if (lastUpdated != null) ...[
        const SizedBox(height: 4),
        Text(
          'Dữ liệu gần nhất: ${DateFormat.Hms().format(lastUpdated!)}',
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
        ),
      ],
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: loading ? null : onRefresh,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('THỬ LẠI'),
      ),
    ],
  );

  Widget _buildOnline(BuildContext context, SmartChargerStatus value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🟢 Gateway online',
          style: TextStyle(
            color: AppColors.success,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value.relay ? '🟢 Đang cấp nguồn' : '⚪ Đã ngắt nguồn',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metric(Icons.bolt_rounded, '${value.powerW.toStringAsFixed(1)} W'),
            _metric(
              Icons.electrical_services_rounded,
              '${value.currentA.toStringAsFixed(3)} A',
            ),
            _metric(
              Icons.show_chart_rounded,
              '${value.voltageV.toStringAsFixed(1)} V',
            ),
            _metric(
              Icons.waves_rounded,
              '${value.frequencyHz.toStringAsFixed(1)} Hz',
            ),
            _metric(
              Icons.device_thermostat_rounded,
              value.temperatureC == null
                  ? '-- °C'
                  : '${value.temperatureC!.toStringAsFixed(1)} °C',
            ),
            _metric(
              Icons.battery_charging_full_rounded,
              'Energy ${value.energyWh.toStringAsFixed(0)} Wh',
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: ValueKey(
              value.relay ? 'smart-charger-off' : 'smart-charger-on',
            ),
            onPressed: commandBusy
                ? null
                : value.relay
                ? onTurnOff
                : onTurnOn,
            style: FilledButton.styleFrom(
              backgroundColor: value.relay
                  ? AppColors.error
                  : AppColors.primary,
              foregroundColor: AppColors.background,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            icon: commandBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(value.relay ? Icons.power_settings_new : Icons.power),
            label: Text(value.relay ? 'NGẮT NGUỒN' : 'BẬT NGUỒN SẠC'),
          ),
        ),
      ],
    );
  }

  Widget _metric(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 16),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _buildMonitorStatus() {
    if (monitorSessionId != null) {
      final shortId = monitorSessionId!.length > 8
          ? monitorSessionId!.substring(0, 8)
          : monitorSessionId!;
      return Text(
        'AI monitor: Đã đồng bộ · Session: $shortId',
        style: const TextStyle(color: AppColors.success, fontSize: 11),
      );
    }
    return const Text(
      'AI monitor: Chưa đồng bộ gateway',
      style: TextStyle(color: AppColors.warning, fontSize: 11),
    );
  }
}
