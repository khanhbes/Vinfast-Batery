import 'package:flutter/material.dart';

import '../../../core/services/connection_coordinator.dart';

class ChargingConnectionBanner extends StatelessWidget {
  const ChargingConnectionBanner({
    super.key,
    required this.state,
    required this.onRetry,
  });

  final ChargingConnectionState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.fullyConnected) return const SizedBox.shrink();
    final internetOnly = !state.internetAvailable && state.shellyReachable;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.tertiaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              internetOnly ? Icons.cloud_off_rounded : Icons.wifi_off_rounded,
              color: colors.onTertiaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    internetOnly ? 'Mất Internet' : 'Mất kết nối',
                    style: TextStyle(
                      color: colors.onTertiaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    internetOnly
                        ? 'Sạc vẫn được bảo vệ'
                        : 'Đang thử kết nối lại',
                    style: TextStyle(color: colors.onTertiaryContainer),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}
