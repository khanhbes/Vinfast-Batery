import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/app_providers.dart';
import '../core/services/notification_center_service.dart';
import '../core/theme/app_colors.dart';
import '../data/repositories/notification_repository.dart';
import '../features/ai/ai_models_screen.dart';
import '../features/home/home_screen.dart';
import '../features/maintenance/maintenance_screen.dart';
import '../features/notifications/notification_center_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/trip_planner/trip_planner_wrapper.dart';

/// Unified App Navigation — PLAN1 sync
/// - Unified AppBar với notification bell
/// - Riverpod tab state (thay GlobalKey)
/// - Pull-to-refresh coordinator
class AppNavigation extends ConsumerStatefulWidget {
  const AppNavigation({super.key});

  @override
  ConsumerState<AppNavigation> createState() => _AppNavigationState();

  /// Navigate to specific tab (0: Home, 1: AI, 2: Trip, 3: Service, 4: Settings)
  /// Dùng context để truy cập Riverpod
  static void navigateToTab(BuildContext context, int index) {
    if (index >= 0 && index < 5) {
      // Sử dụng ProviderScope container để update state
      ProviderScope.containerOf(context, listen: false)
          .read(currentTabProvider.notifier)
          .state = index;
    }
  }
}

class _AppNavigationState extends ConsumerState<AppNavigation> {
  final _repository = NotificationRepository();

  // Tab screens — wrap với RefreshIndicator
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      _RefreshableTab(child: const HomeScreen()),           // Tab 0: Home
      _RefreshableTab(child: const AiModelsScreen()),       // Tab 1: AI
      _RefreshableTab(child: const TripPlannerWrapper()),   // Tab 2: Trip
      _RefreshableTab(child: const MaintenanceScreen()),    // Tab 3: Service
      _RefreshableTab(child: const SettingsScreen()),       // Tab 4: Settings
    ];
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(currentTabProvider);

    // Set system UI
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      appBar: _buildUnifiedAppBar(currentIndex),
      body: IndexedStack(
        index: currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.95),
          border: const Border(
            top: BorderSide(color: AppColors.glassBorder, width: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  isSelected: currentIndex == 0,
                  onTap: () => ref.read(currentTabProvider.notifier).state = 0,
                ),
                _NavItem(
                  icon: Icons.psychology_rounded,
                  label: 'AI',
                  isSelected: currentIndex == 1,
                  onTap: () => ref.read(currentTabProvider.notifier).state = 1,
                ),
                _NavItem(
                  icon: Icons.map_rounded,
                  label: 'Trip',
                  isSelected: currentIndex == 2,
                  onTap: () => ref.read(currentTabProvider.notifier).state = 2,
                ),
                _NavItem(
                  icon: Icons.build_rounded,
                  label: 'Service',
                  isSelected: currentIndex == 3,
                  onTap: () => ref.read(currentTabProvider.notifier).state = 3,
                ),
                _NavItem(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  isSelected: currentIndex == 4,
                  onTap: () => ref.read(currentTabProvider.notifier).state = 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Unified AppBar cho tất cả tabs — PLAN1
  PreferredSizeWidget _buildUnifiedAppBar(int currentIndex) {
    final tabTitles = ['VinFast Battery', 'AI Models', 'Trip Planner', 'Service', 'Settings'];
    
    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      title: Text(
        tabTitles[currentIndex],
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        // Notification bell with badge
        StreamBuilder<int>(
          stream: NotificationCenterService().watchUnreadCount(),
          builder: (context, snapshot) {
            final unreadCount = snapshot.data ?? 0;
            return _NotificationBell(
              unreadCount: unreadCount,
              onTap: () => _openNotificationCenter(context),
            );
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  void _openNotificationCenter(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
    );
  }
}

/// Widget wrap tab content với pull-to-refresh — PLAN1
class _RefreshableTab extends ConsumerWidget {
  final Widget child;
  
  const _RefreshableTab({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refreshCoordinator = ref.watch(appRefreshCoordinatorProvider);
    
    return RefreshIndicator(
      onRefresh: () => refreshCoordinator.refreshAll(),
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      displacement: 60,
      child: child,
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryContainer.withValues(alpha: 0.35)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textTertiary,
                size: 22,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textTertiary,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Notification bell icon with unread badge
class _NotificationBell extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;

  const _NotificationBell({
    required this.unreadCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.notifications_outlined,
              color: unreadCount > 0 ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
            if (unreadCount > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.cardBackground,
                      width: 1.5,
                    ),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Center(
                    child: Text(
                      unreadCount > 99 ? '99+' : unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
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
