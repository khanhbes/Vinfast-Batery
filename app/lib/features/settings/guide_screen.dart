import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/dashboard_preferences_service.dart';
import '../../core/services/guide_registry.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/coach_mark_overlay.dart';
import '../../navigation/app_navigation.dart';

/// Thư viện Hướng dẫn sử dụng & Trợ giúp toàn diện
/// - Tìm kiếm nhanh theo từ khóa
/// - Lọc theo danh mục: Bắt đầu, Xe, Sạc, Chuyến đi, AI, Tài khoản, Xử lý lỗi
/// - Hiển thị Điều kiện cần, Các bước thực hiện, Kết quả mong đợi
/// - Nút hành động: "Mở màn hình này" & "Chạy lại hướng dẫn tương tác"
/// - Không chứa Developer Mode dành cho người dùng thông thường
class GuideScreen extends ConsumerStatefulWidget {
  const GuideScreen({super.key});

  @override
  ConsumerState<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends ConsumerState<GuideScreen> {
  final _searchCtrl = TextEditingController();
  GuideCategory? _selectedCategory;
  String _searchQuery = '';
  final Set<String> _expandedItemIds = <String>{'guide_getting_started'};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _runTour(String tourId) {
    if (tourId == GuideRegistry.overviewTourId) {
      Navigator.of(context).pop(); // Quay về màn trước (hoặc Tổng quan)
      AppNavigation.navigateToTab(context, 0);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pref = ref.read(dashboardPreferencesProvider);
        CoachMarkOverlay.show(
          context: context,
          steps: GuideRegistry.getOverviewTourSteps(),
          onFinish: () {
            pref.markTourCompleted(GuideRegistry.overviewTourId);
          },
          onDontShowAgain: (val) {
            if (val) pref.markTourCompleted(GuideRegistry.overviewTourId);
          },
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final langCode = isEn ? 'en' : 'vi';

    // Lọc theo search và category
    var filtered = GuideRegistry.search(_searchQuery, langCode);
    if (_selectedCategory != null) {
      filtered = filtered.where((item) => item.category == _selectedCategory).toList();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEn ? 'Help & Guides' : 'Thư viện hướng dẫn',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          Text(
                            isEn
                                ? 'Search and learn how to use every feature'
                                : 'Tìm kiếm và khám phá mọi tính năng trong app',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Search Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (val) {
                      setState(() => _searchQuery = val);
                    },
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: isEn ? 'Search guides...' : 'Tìm kiếm bài hướng dẫn...',
                      hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ),
            ),

            // Category Filter Chips
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _buildCategoryChip(
                      label: isEn ? 'All' : 'Tất cả',
                      isSelected: _selectedCategory == null,
                      onTap: () => setState(() => _selectedCategory = null),
                    ),
                    ...GuideCategory.values.map((cat) {
                      return _buildCategoryChip(
                        label: isEn ? cat.nameEn : cat.nameVi,
                        icon: cat.icon,
                        isSelected: _selectedCategory == cat,
                        onTap: () => setState(() => _selectedCategory = cat),
                      );
                    }),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // Empty state if no items found
            if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_off_rounded, size: 48, color: AppColors.textTertiary),
                        const SizedBox(height: 12),
                        Text(
                          isEn ? 'No guides found' : 'Không tìm thấy bài viết nào',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = filtered[index];
                      final isExpanded = _expandedItemIds.contains(item.id);
                      return _buildGuideCard(item, isExpanded, langCode, isEn);
                    },
                    childCount: filtered.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip({
    required String label,
    IconData? icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected ? const Color(0xFF042F2E) : const Color(0xFF10B981),
              ),
              const SizedBox(width: 6),
            ],
            Text(label),
          ],
        ),
        selected: isSelected,
        onSelected: (_) => onTap(),
        selectedColor: const Color(0xFF10B981),
        backgroundColor: AppColors.card,
        labelStyle: TextStyle(
          color: isSelected ? const Color(0xFF042F2E) : AppColors.textSecondary,
          fontSize: 12.5,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected ? const Color(0xFF10B981) : AppColors.border,
          ),
        ),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
    );
  }

  Widget _buildGuideCard(GuideItem item, bool isExpanded, String langCode, bool isEn) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded ? const Color(0xFF10B981).withValues(alpha: 0.4) : AppColors.border,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey(item.id),
          initiallyExpanded: isExpanded,
          onExpansionChanged: (val) {
            setState(() {
              if (val) {
                _expandedItemIds.add(item.id);
              } else {
                _expandedItemIds.remove(item.id);
              }
            });
          },
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.category.icon, color: const Color(0xFF10B981), size: 22),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isEn ? item.category.nameEn : item.category.nameVi,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              item.title(langCode),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: AppColors.border, height: 16),
                  Text(
                    item.summary(langCode),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Prerequisites
                  if (item.prerequisites(langCode).isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF10B981)),
                        const SizedBox(width: 6),
                        Text(
                          isEn ? 'Prerequisites:' : 'Điều kiện cần:',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...item.prerequisites(langCode).map((pre) => Padding(
                          padding: const EdgeInsets.only(left: 22, bottom: 3),
                          child: Text(
                            '• $pre',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                          ),
                        )),
                    const SizedBox(height: 12),
                  ],

                  // Steps
                  Row(
                    children: [
                      const Icon(Icons.format_list_numbered_rounded, size: 16, color: Color(0xFF10B981)),
                      const SizedBox(width: 6),
                      Text(
                        isEn ? 'Steps:' : 'Các bước thực hiện:',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...item.steps(langCode).asMap().entries.map((entry) => Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${entry.key + 1}. ',
                              style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                entry.value,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 12),

                  // Expected result
                  Row(
                    children: [
                      const Icon(Icons.verified_outlined, size: 16, color: Color(0xFF10B981)),
                      const SizedBox(width: 6),
                      Text(
                        isEn ? 'Expected Result:' : 'Kết quả mong đợi:',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 22),
                    child: Text(
                      item.expectedResult(langCode),
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (item.tourId != null) ...[
                        OutlinedButton.icon(
                          onPressed: () => _runTour(item.tourId!),
                          icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
                          label: Text(isEn ? 'Start Tour' : 'Chạy lại tour'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF10B981),
                            side: const BorderSide(color: Color(0xFF10B981)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (item.targetTab != null) ...[
                        FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            AppNavigation.navigateToTab(context, item.targetTab!);
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 15),
                          label: Text(isEn ? 'Open Screen' : 'Mở màn hình này'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.18),
                            foregroundColor: const Color(0xFF10B981),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
