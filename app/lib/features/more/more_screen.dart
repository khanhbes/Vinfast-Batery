import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/providers/app_providers.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/feature_availability_registry.dart';
import '../../core/services/notification_center_service.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/cockpit_design_system.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/vehicle_picker_sheet.dart';
import '../ai/ai_models_screen.dart';
import '../ai/controllers/smart_charging_controller.dart';
import '../auth/auth_gate.dart';
import '../maintenance/maintenance_screen.dart';
import '../notifications/notification_center_screen.dart';
import '../settings/guide_screen.dart';
import '../settings/profile_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/vehicle_garage_screen.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';
import '../trip_planner/trip_planner_wrapper.dart';

/// Driver Profile Hub (Tab 3 — Quản lý & Cài đặt).
///
/// Thiết kế theo chuẩn Premium Automotive Dark UI:
/// - Hero Driver Card: Hồ sơ chủ xe, mã định danh, huy hiệu trạng thái & phương tiện.
/// - Inset Grouped Cards: Phân loại khoa học (Phương tiện & Sạc, AI & Hệ thống, Hỗ trợ & Tài khoản).
/// - Central Feature Availability: Đánh giá tính sẵn sàng của Smart Charge / AI.
/// - Logout an toàn: Xóa session, reset provider và quay về AuthGate.
class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  final _authService = AuthService();
  Map<String, dynamic>? _userData;
  bool _isLoadingUser = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    if (Firebase.apps.isEmpty) {
      if (mounted) setState(() => _isLoadingUser = false);
      return;
    }
    setState(() => _isLoadingUser = true);
    try {
      final data = await _authService.getCurrentUserData();
      if (mounted) {
        setState(() {
          _userData = data;
          _isLoadingUser = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingUser = false);
      }
    }
  }

  Future<void> _handleSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12161F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF1E293B), width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 22),
            SizedBox(width: 10),
            Text(
              'Đăng xuất',
              style: TextStyle(
                color: Color(0xFFF8FAFC),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: const Text(
          'Bạn có chắc chắn muốn đăng xuất khỏi tài khoản trên thiết bị này?',
          style: TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Hủy',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text(
              'Đăng xuất',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = await _authService.signOut();
    if (!mounted) return;

    if (result['success'] == true) {
      ref.read(selectedVehicleIdProvider.notifier).state = '';
      ref.read(currentTabProvider.notifier).state = 0;

      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AuthGate()),
        (_) => false,
      );
    } else {
      AppPopup.showError(result['error'] ?? 'Đăng xuất thất bại');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicleContext = ref.watch(vehicleContextProvider);
    final vehicleId = vehicleContext.vehicleId;
    final vehicle = vehicleContext.vehicle;

    var availability = FeatureAvailabilityRegistry(
      hasVehicleData: vehicleId.isNotEmpty,
    ).smartCharge(ai: true);

    if (vehicleId.isNotEmpty && vehicle != null) {
      final args = SmartChargingControllerArgs(
        vehicleId: vehicleId,
        currentSoc: vehicle.currentBattery.toDouble(),
      );
      final charging = ref.watch(smartChargingControllerProvider(args));
      availability = FeatureAvailabilityRegistry(
        modelLoaded:
            charging.preview?.runtimeHealth == 'loaded' ||
            charging.preview?.aiChargeEligible == true,
        chargerReady: charging.capabilities.readyForControl,
        lanAvailable: charging.capabilities.lanAvailable,
        hasVehicleData: vehicle.batteryCapacityWh > 0 || vehicle.hasModelLink,
        online: charging.connectionState.internetAvailable,
      ).smartCharge(ai: true);
    }

    final currentUser = Firebase.apps.isNotEmpty
        ? FirebaseAuth.instance.currentUser
        : null;
    final displayName = _userData?['name'] ??
        _userData?['displayName'] ??
        currentUser?.displayName ??
        'Chủ xe VinFast';
    final contactInfo = _userData?['phone'] ??
        currentUser?.phoneNumber ??
        currentUser?.email ??
        'Hồ sơ đã kết nối';

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // 1. DRIVER PROFILE HERO CARD
        _DriverProfileHeroCard(
          displayName: displayName,
          contactInfo: contactInfo,
          vehicle: vehicle,
          isLoading: _isLoadingUser,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );
            _loadUserData();
          },
          onSelectVehicle: () => VehiclePickerSheet.show(context, ref),
        ).appFadeSlideIn(index: 0),

        const SizedBox(height: 20),

        // 2. SECTION: PHƯƠNG TIỆN & SẠC
        const _SectionHeader(title: 'PHƯƠNG TIỆN & SẠC').appFadeSlideIn(index: 1),
        const SizedBox(height: 8),
        _GroupCard(
          children: [
            _ActionTile(
              icon: Icons.garage_rounded,
              iconColor: CockpitColors.emerald,
              title: 'Garage xe của tôi',
              subtitle: 'Quản lý xe sở hữu & thông số pin',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VehicleGarageScreen()),
              ),
            ),
            const _CardDivider(),
            _ActionTile(
              icon: Icons.power_rounded,
              iconColor: CockpitColors.info,
              title: 'Sạc thông minh Shelly',
              subtitle: 'Kết nối ổ cắm WiFi & quản lý tự ngắt 80%',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SmartChargerSetupHubScreen(),
                ),
              ),
            ),
            const _CardDivider(),
            _ActionTile(
              icon: Icons.alt_route_rounded,
              iconColor: CockpitColors.amber,
              title: 'Lộ trình sạc',
              subtitle: 'Lập kế hoạch di chuyển theo trạm sạc',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TripPlannerWrapper()),
              ),
            ),
          ],
        ).appFadeSlideIn(index: 2),

        const SizedBox(height: 20),

        // 3. SECTION: HỆ THỐNG & TRÍ TUỆ AI
        const _SectionHeader(title: 'HỆ THỐNG & TRÍ TUỆ AI').appFadeSlideIn(index: 3),
        const SizedBox(height: 8),
        _GroupCard(
          children: [
            _ActionTile(
              icon: Icons.psychology_rounded,
              iconColor: const Color(0xFFA855F7),
              title: 'Trợ lý AI & Dự báo Pin',
              subtitle: availability.enabled
                  ? 'Thuật toán tối ưu sạc & bảo vệ cell pin'
                  : availability.reason,
              badge: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: availability.enabled
                      ? CockpitColors.emerald.withValues(alpha: 0.15)
                      : CockpitColors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: availability.enabled
                        ? CockpitColors.emerald.withValues(alpha: 0.4)
                        : CockpitColors.amber.withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  availability.enabled ? 'Sẵn sàng' : 'Cần thiết lập',
                  style: TextStyle(
                    color: availability.enabled
                        ? CockpitColors.emerald
                        : CockpitColors.amber,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiModelsScreen()),
              ),
            ),
            const _CardDivider(),
            _ActionTile(
              icon: Icons.build_circle_rounded,
              iconColor: const Color(0xFFF97316),
              title: 'Bảo dưỡng xe',
              subtitle: 'Theo dõi chu kỳ bảo dưỡng, lốp & ắc quy',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MaintenanceScreen()),
              ),
            ),
            const _CardDivider(),
            _ActionTile(
              icon: Icons.tune_rounded,
              iconColor: const Color(0xFF38BDF8),
              title: 'Cài đặt hệ thống',
              subtitle: 'Giao diện, bảo mật & cấu hình đồng bộ',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ).appFadeSlideIn(index: 4),

        const SizedBox(height: 20),

        // 4. SECTION: HỖ TRỢ & TÀI KHOẢN
        const _SectionHeader(title: 'HỖ TRỢ & TÀI KHOẢN').appFadeSlideIn(index: 5),
        const SizedBox(height: 8),
        _GroupCard(
          children: [
            _ActionTile(
              icon: Icons.support_agent_rounded,
              iconColor: const Color(0xFF34D399),
              title: 'Cẩm nang & Cứu hộ 24/7',
              subtitle: 'Hướng dẫn sử dụng & hotline cứu hộ khẩn cấp',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GuideScreen()),
              ),
            ),
            const _CardDivider(),
            _ActionTile(
              icon: Icons.notifications_outlined,
              iconColor: const Color(0xFFFBBF24),
              title: 'Trung tâm thông báo',
              subtitle: 'Lịch sử cảnh báo sạc & tin tức',
              trailing: StreamBuilder<int>(
                stream: Firebase.apps.isNotEmpty
                    ? NotificationCenterService().watchUnreadCount()
                    : const Stream<int>.empty(),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  if (count > 0) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: CockpitColors.emerald,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    );
                  }
                  return const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF64748B),
                    size: 20,
                  );
                },
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationCenterScreen(),
                ),
              ),
            ),
          ],
        ).appFadeSlideIn(index: 6),

        const SizedBox(height: 24),

        // 5. SIGN OUT BUTTON
        _SignOutButton(onTap: _handleSignOut).appFadeSlideIn(index: 7),

        const SizedBox(height: 24),

        // 6. BRANDING FOOTER
        const _AppBrandingFooter().appFadeSlideIn(index: 8),

        const SizedBox(height: 32),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12161F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF1E293B),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: children,
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: const Color(0xFF1E293B).withValues(alpha: 0.6),
      indent: 68,
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? badge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: CockpitColors.emerald.withValues(alpha: 0.08),
        highlightColor: Colors.white.withValues(alpha: 0.03),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: iconColor.withValues(alpha: 0.28),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: iconColor, size: 19),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Color(0xFFF8FAFC),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          badge!,
                        ],
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF64748B),
                    size: 20,
                  ),
            ],
          ),
        ),
      ),
    ).appTactile(pressScale: 0.985);
  }
}

class _DriverProfileHeroCard extends StatelessWidget {
  const _DriverProfileHeroCard({
    required this.displayName,
    required this.contactInfo,
    required this.vehicle,
    required this.isLoading,
    required this.onTap,
    required this.onSelectVehicle,
  });

  final String displayName;
  final String contactInfo;
  final dynamic vehicle;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback onSelectVehicle;

  @override
  Widget build(BuildContext context) {
    final initial = displayName.isNotEmpty
        ? displayName.trim().substring(0, 1).toUpperCase()
        : 'V';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111722),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF1E293B),
          width: 1,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF131B28),
            Color(0xFF0D121B),
          ],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: CockpitColors.emerald.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar với emerald ring
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF0B101B),
                            border: Border.all(
                              color: CockpitColors.emerald.withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: CockpitColors.emerald,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: CockpitColors.emerald,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF0D121B),
                              width: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    // Tên & liên hệ
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  displayName,
                                  style: const TextStyle(
                                    color: Color(0xFFF8FAFC),
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: CockpitColors.emerald
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: CockpitColors.emerald
                                        .withValues(alpha: 0.3),
                                    width: 0.8,
                                  ),
                                ),
                                child: const Text(
                                  'PIONEER',
                                  style: TextStyle(
                                    color: CockpitColors.emerald,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            contactInfo,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Nút mở hồ sơ
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF334155),
                          width: 0.8,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Hồ sơ',
                            style: TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 3),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 14,
                            color: Color(0xFF94A3B8),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                Container(
                  height: 1,
                  color: const Color(0xFF1E293B).withValues(alpha: 0.7),
                ),
                const SizedBox(height: 10),

                // Thanh thông tin xe đang kích hoạt
                if (vehicle != null)
                  Row(
                    children: [
                      const Icon(
                        Icons.two_wheeler_rounded,
                        size: 16,
                        color: CockpitColors.emerald,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          vehicle.modelName,
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: CockpitColors.emerald,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${vehicle.currentBattery}% PIN',
                        style: const TextStyle(
                          color: CockpitColors.emerald,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (vehicle.currentOdo > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '· ${vehicle.currentOdo} km',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  )
                else
                  Row(
                    children: [
                      const Icon(
                        Icons.add_circle_outline_rounded,
                        size: 16,
                        color: CockpitColors.amber,
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Chưa chọn xe hoạt động',
                          style: TextStyle(
                            color: CockpitColors.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onSelectVehicle,
                        child: const Text(
                          'Chọn xe ngay →',
                          style: TextStyle(
                            color: CockpitColors.emerald,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ).appTactile(pressScale: 0.98);
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161214),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: const Color(0xFFEF4444).withValues(alpha: 0.12),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.logout_rounded,
                  color: Color(0xFFEF4444),
                  size: 19,
                ),
                SizedBox(width: 10),
                Text(
                  'Đăng xuất tài khoản',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).appTactile(pressScale: 0.97);
  }
}

class _AppBrandingFooter extends StatelessWidget {
  const _AppBrandingFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'VinFast Battery · Phiên bản 1.1.3 (Build 4)',
          style: TextStyle(
            color: const Color(0xFF64748B).withValues(alpha: 0.8),
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Hệ sinh thái quản lý & tối ưu năng lượng xe điện',
          style: TextStyle(
            color: Color(0xFF475569),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
