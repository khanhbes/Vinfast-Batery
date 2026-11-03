import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/entitlement_provider.dart';
import '../../core/services/pinova_api.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/theme/plan_style.dart';
import '../../core/utils/number_text.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../data/models/entitlement.dart';

/// The account's payments (QA 145), newest first, from the server.
final paymentOrdersProvider = FutureProvider.autoDispose<List<PaymentOrder>>(
  (ref) => ref.read(billingRepositoryProvider).orders(),
);

class PaymentHistoryScreen extends ConsumerWidget {
  const PaymentHistoryScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const PaymentHistoryScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(paymentOrdersProvider);
    return LuxeScaffold(
      title: 'Lịch sử thanh toán',
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(paymentOrdersProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: orders.when(
            loading: () => const [
              Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (error, _) => [
              LuxeNotice(
                icon: Icons.cloud_off_rounded,
                color: LuxeColors.danger,
                message: error is PinovaApiException && error.offline
                    ? 'Cần kết nối mạng để xem lịch sử thanh toán.'
                    : 'Chưa tải được lịch sử thanh toán. Kéo xuống để thử lại.',
              ),
            ],
            data: (items) => items.isEmpty
                ? const [
                    SizedBox(height: 40),
                    Center(
                      child: LuxeEmptyArt(icon: Icons.receipt_long_rounded),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Chưa có thanh toán nào.',
                      textAlign: TextAlign.center,
                      style: LuxeText.body,
                    ),
                  ]
                : [
                    for (final order in items) ...[
                      _OrderTile(order: order),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 6),
                    const Text(
                      'Đã bị trừ tiền mà gói chưa bật? Gửi yêu cầu ở Cài đặt → '
                      'Trợ giúp kèm mã đơn.',
                      style: LuxeText.caption,
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});
  final PaymentOrder order;

  @override
  Widget build(BuildContext context) {
    final color = switch (order.status) {
      'paid' => context.planAccent,
      'pending' || 'review' => LuxeColors.champagne,
      'failed' => LuxeColors.danger,
      _ => LuxeColors.steel,
    };
    final when = order.paidAt ?? order.createdAt;
    String two(int v) => v.toString().padLeft(2, '0');
    final date = when == null
        ? ''
        : '${two(when.day)}/${two(when.month)}/${when.year} '
              '${two(when.hour)}:${two(when.minute)}';
    return Semantics(
      container: true,
      child: LuxeGlass(
        radius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Pinova ${order.tier.label} · '
                    '${order.period == PlanPeriod.year ? '1 năm' : '1 tháng'}',
                    style: LuxeText.item,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  order.amount == 0 ? 'Miễn phí' : formatVnd(order.amount),
                  style: LuxeText.item,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                Text(
                  order.statusLabel,
                  style: LuxeText.caption.copyWith(color: color),
                ),
                if (date.isNotEmpty) Text(date, style: LuxeText.caption),
              ],
            ),
            const SizedBox(height: 2),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                Clipboard.setData(ClipboardData(text: order.orderId));
                AppPopup.showMessage('Đã chép mã đơn.');
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Mã đơn ${order.orderId} · chạm để chép',
                    style: LuxeText.caption,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
