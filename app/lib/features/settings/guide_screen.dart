import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';

/// ========================================================================
/// GuideScreen — Hướng dẫn sử dụng + AI hoạt động
/// Accordion sections với nội dung chi tiết
/// ========================================================================
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.textSecondary, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hướng dẫn sử dụng',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              )),
                          Text('Mọi thứ bạn cần biết',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),
            ),

            // Accordion sections
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _GuideSection(
                    icon: Icons.today_rounded,
                    iconColor: AppColors.primaryGreen,
                    title: 'Luồng sử dụng hàng ngày',
                    content: _dailyFlow,
                    delay: 100,
                  ),
                  _GuideSection(
                    icon: Icons.navigation_rounded,
                    iconColor: AppColors.info,
                    title: 'Tracking chuyến đi & sạc',
                    content: _trackingGuide,
                    delay: 160,
                  ),
                  _GuideSection(
                    icon: Icons.smart_toy_rounded,
                    iconColor: AppColors.warning,
                    title: 'AI hoạt động như nào?',
                    content: _aiExplain,
                    delay: 220,
                  ),
                  _GuideSection(
                    icon: Icons.insights_rounded,
                    iconColor: const Color(0xFFFF9800),
                    title: 'Confidence / SoH / Cảnh báo',
                    content: _metricsExplain,
                    delay: 280,
                  ),
                  _GuideSection(
                    icon: Icons.help_outline_rounded,
                    iconColor: AppColors.error,
                    title: 'FAQ & xử lý lỗi thường gặp',
                    content: _faq,
                    delay: 340,
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Content Constants ──

  static const _dailyFlow = '''
1. **Mở app** → Dashboard hiện SoH + pin hiện tại + bảo dưỡng sắp đến.
2. **Trước khi đi**: nhấn "Bắt đầu đi" ở Dashboard hoặc nút "+" → chọn "Bắt đầu đi".
3. **Khi sạc**: nhấn "Bắt đầu sạc" → chọn mục tiêu sạc (80/90/100%).
4. **Sau khi sạc xong**: nhấn "Ngắt sạc" → app tự ghi nhật ký.
5. **Kiểm tra Thống kê**: xem xu hướng sạc, sức khỏe pin, AI dự đoán.
6. **Bảo dưỡng**: xem tab Bảo dưỡng để thêm/theo dõi mốc bảo dưỡng theo ODO.
''';

  static const _trackingGuide = '''
**Live Tracking (GPS):**
- Nhấn "Bắt đầu đi" → app theo dõi GPS liên tục.
- Hiện quãng đường, pin tiêu thụ, thời gian trực tiếp.
- Khi dừng: nhấn "Kết thúc" → xác nhận → lưu chuyến đi.

**Nhập thủ công:**
- Chọn "Nhập chuyến đi thủ công" hoặc "Nhập sạc".
- Điền ODO bắt đầu/kết thúc, pin bắt đầu/kết thúc.
- App tự tính hiệu suất (km/%) từ dữ liệu bạn nhập.

**Smart Charging:**
- Chọn mục tiêu sạc trước khi bắt đầu.
- ETA tự tính dựa trên tốc độ sạc lịch sử.
- Thông báo khi đạt mục tiêu!
''';

  static const _aiExplain = '''
**AI học từ dữ liệu thực của bạn:**
- Mỗi lần sạc/đi → dữ liệu được ghi vào lịch sử.
- AI phân tích hiệu suất pin theo thời gian (3+ lần sạc là đủ).
- So sánh hiệu suất hiện tại vs thông số gốc VinFast → tính SoH.

**Hybrid AI Engine:**
- Ưu tiên gọi AI API (Flask backend) để tính SoH chính xác.
- Nếu API offline → fallback tính local (on-device).
- Kết quả có confidence level: Cao / Trung bình / Thấp.

**Thời gian học:**
- 3 lần sạc: AI bắt đầu dự đoán (confidence thấp).
- 5-10 lần: confidence trung bình, kết quả ổn định.
- 20+ lần: confidence cao, SoH chính xác nhất.
- Càng nhiều dữ liệu tracking → AI càng thông minh.

**Dung lượng pin AI:**
- Liên kết xe với model VinFast → biết capacity danh nghĩa (Wh, Ah).
- AI tính capacity khả dụng = danh nghĩa × SoH%.
- Hiển thị: Dashboard + Thống kê + Chi tiết xe.
''';

  static const _metricsExplain = '''
**SoH (State of Health):**
- 80-100%: 🟢 Tốt — pin hoạt động bình thường.
- 70-79%: 🟡 Khá — pin bắt đầu chai, theo dõi thêm.
- 60-69%: 🟠 Trung bình — cần chú ý, hiệu suất giảm.
- Dưới 60%: 🔴 Kém — nên thay pin sớm.

**Confidence (Độ tin cậy):**
- Cao: đủ dữ liệu + AI API hoạt động → kết quả rất chính xác.
- Trung bình: dữ liệu đủ nhưng dùng tính toán local.
- Thấp: ít dữ liệu hoặc chưa link model → chỉ mang tính tham khảo.

**Cảnh báo SoH:**
- Bình thường: không có cảnh báo.
- Pin bắt đầu chai: SoH < 80% — theo dõi thêm.
- Cần theo dõi: SoH < 70% — kiểm tra tại đại lý.
- Nên thay pin sớm: SoH < 60% — pin chai nghiêm trọng.
''';

  static const _faq = '''
**Q: App báo "AI API chưa kết nối"?**
A: AI backend (Flask) chưa chạy. App vẫn hoạt động bình thường với tính toán on-device.

**Q: Làm sao link model VinFast?**
A: Cài đặt → Thêm xe mới → chọn Model VinFast từ dropdown. Hoặc app tự auto-match theo tên xe.

**Q: Tại sao SoH khác với dự đoán trước?**
A: SoH tính từ dữ liệu thực nên sẽ thay đổi khi bạn sạc/đi thêm. Đây là điều bình thường.

**Q: GPS không hoạt động khi tracking?**
A: Kiểm tra quyền truy cập vị trí (Cài đặt hệ thống → Ứng dụng → Quyền → Vị trí).

**Q: Dữ liệu có bị mất khi gỡ app?**
A: Dữ liệu lưu trên Firebase Firestore nên sẽ được khôi phục khi cài lại app.

**Q: App có tốn pin không?**
A: Tracking GPS tiêu hao pin nhẹ. Khi không tracking, app gần như không tiêu thụ pin.
''';
}

// =============================================================================
// Accordion Section Widget
// =============================================================================

class _GuideSection extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String content;
  final int delay;

  const _GuideSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.content,
    required this.delay,
  });

  @override
  State<_GuideSection> createState() => _GuideSectionState();
}

class _GuideSectionState extends State<_GuideSection>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _expanded
                ? widget.iconColor.withValues(alpha: 0.3)
                : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            // Header
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: widget.iconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(widget.icon,
                          color: widget.iconColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(widget.title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.expand_more_rounded,
                          color: AppColors.textSecondary, size: 22),
                    ),
                  ],
                ),
              ),
            ),
            // Content
            AnimatedCrossFade(
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _buildRichContent(widget.content),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: widget.delay.ms).slideY(begin: 0.1);
  }

  Widget _buildRichContent(String text) {
    // Simple markdown-ish bold rendering
    final spans = <InlineSpan>[];
    final parts = text.split('**');
    for (int i = 0; i < parts.length; i++) {
      if (i % 2 == 1) {
        spans.add(TextSpan(
          text: parts[i],
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            height: 1.6,
          ),
        ));
      } else {
        spans.add(TextSpan(
          text: parts[i],
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.6,
          ),
        ));
      }
    }
    return RichText(text: TextSpan(children: spans));
  }
}
