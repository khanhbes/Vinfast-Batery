import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/installed_version.dart';
import '../../core/constants/beta_capabilities.dart';
import '../../core/models/vehicle_context.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/feature_availability_registry.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../core/widgets/vehicle_picker_sheet.dart';
import '../../data/services/shelly_connection_coordinator.dart';
import '../achievements/controllers/achievements_controller.dart';
import '../achievements/models/achievement.dart';
import '../ai/ai_models_screen.dart';
import '../ai/controllers/smart_charging_controller.dart';
import '../auth/auth_gate.dart';
import '../notifications/notification_center_screen.dart';
import '../premium/premium_banner.dart';
import '../support/help_center_screen.dart';
import '../settings/guide_screen.dart';
import '../settings/profile_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/vehicle_garage_screen.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';
import 'widgets/luxe_tile_grid.dart';
import '../settings/assistant_memory_screen.dart';
import '../../core/services/guide_registry.dart';
import '../premium/plan_tag.dart';
import '../../core/theme/plan_style.dart';
import '../settings/privacy_consent.dart';

/// Tab Cài đặt (luxe): profile card ringed by the achievement rank, live
/// tiles for the vehicle and Shelly, and quiet glass lists for system and
/// support. Features live in Tiện ích (QA 140): settings only here. Logout
/// clears session and providers.
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
    _restoreShellyForVehicle(ref.read(selectedVehicleIdProvider));
  }

  void _restoreShellyForVehicle(String vehicleId) {
    if (vehicleId.isNotEmpty) {
      unawaited(
        ShellyConnectionCoordinator.shared.restore(vehicleId: vehicleId),
      );
    }
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
    final confirmed = await showLuxeConfirm(
      context,
      title: 'Đăng xuất',
      // QA 143: signing out sends no OFF; the server keeps managing a
      // running charge and the outlet timer still stops it.
      message:
          'Bạn có chắc chắn muốn đăng xuất khỏi tài khoản trên thiết bị này? '
          'Phiên sạc đang chạy (nếu có) vẫn tiếp tục và tự ngắt theo hẹn giờ; '
          'đăng nhập lại để theo dõi hoặc dừng.',
      confirmLabel: 'Đăng xuất',
    );
    if (confirmed != true || !mounted) return;
    // QA 143: AuthGate rebuilds on sign-out and unmounts this screen before
    // the await returns, so the reset after it never ran: the next account
    // opened on Cài đặt and read the old vehicle (permission-denied).
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context, rootNavigator: true);

    final result = await _authService.signOut();

    if (result['success'] == true) {
      container.read(selectedVehicleIdProvider.notifier).state = '';
      container.read(currentTabProvider.notifier).state = AppTab.overview;
      container.read(chargeSectionProvider.notifier).state = ChargeSection.ai;
      if (!navigator.mounted) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AuthGate()),
        (_) => false,
      );
    } else if (mounted) {
      AppPopup.showError(result['error'] ?? 'Đăng xuất thất bại');
    }
  }

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(selectedVehicleIdProvider, (_, next) {
      _restoreShellyForVehicle(next);
    });
    final vehicleContext = ref.watch(vehicleContextProvider);
    final user = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.currentUser;
    final unreadCount = (user != null && user.uid.isNotEmpty)
        ? ref.watch(unreadCountProvider(user.uid)).valueOrNull ?? 0
        : 0;
    final vehicleId = vehicleContext.vehicleId;
    final vehicle = vehicleContext.vehicle;
    final achievements = ref.watch(achievementsControllerProvider);

    var availability = FeatureAvailabilityRegistry(
      hasVehicleData: vehicleId.isNotEmpty,
    ).smartCharge(ai: true);

    if (BetaCapabilities.advancedAi &&
        vehicleId.isNotEmpty &&
        vehicle != null) {
      final args = SmartChargingControllerArgs(
        vehicleId: vehicleId,
        currentSoc: vehicle.currentBattery.toDouble(),
      );
      // Only the flags this tab shows: watching the whole charging state
      // rebuilt Settings on every 5 s poll (Task 125).
      final flags = ref.watch(
        smartChargingControllerProvider(args).select(
          (charging) => (
            modelLoaded:
                charging.preview?.runtimeHealth == 'loaded' ||
                charging.preview?.aiChargeEligible == true,
            chargerReady: charging.capabilities.readyForControl,
            lanAvailable: charging.capabilities.lanAvailable,
            online: charging.connectionState.internetAvailable,
          ),
        ),
      );
      availability = FeatureAvailabilityRegistry(
        modelLoaded: flags.modelLoaded,
        chargerReady: flags.chargerReady,
        lanAvailable: flags.lanAvailable,
        hasVehicleData: vehicle.batteryCapacityWh > 0 || vehicle.hasModelLink,
        online: flags.online,
      ).smartCharge(ai: true);
    }

    final displayName =
        _userData?['name'] ??
        _userData?['displayName'] ??
        user?.displayName ??
        'Chủ xe VinFast';
    final contactInfo =
        _userData?['phone'] ??
        user?.phoneNumber ??
        user?.email ??
        'Hồ sơ đã kết nối';

    return Theme(
      data: LuxeTheme.of(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const LuxeBackdrop(),
          ListView(
            // QA 143: room under the version footer for the charging pill
            // and the Pinova Bot button, which float above the list.
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 128),
            children: [
              LuxeReveal(
                child: _ProfileCard(
                  displayName: '$displayName',
                  contactInfo: '$contactInfo',
                  loading: _isLoadingUser,
                  vehicle: vehicleContext,
                  rank: achievements.rank,
                  points: achievements.points,
                  rankProgress: achievements.rankProgress,
                  onOpenProfile: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                    _loadUserData();
                  },
                  onSelectVehicle: () => VehiclePickerSheet.show(context, ref),
                ),
              ),
              const SizedBox(height: 14),
              LuxeReveal(
                index: 1,
                key: GuideRegistry.keySettingsPremium,
                child: const PremiumBanner(),
              ),
              const LuxeSectionLabel('PHƯƠNG TIỆN & SẠC'),
              LuxeReveal(
                index: 1,
                child: LuxeTileGrid(
                  tiles: [
                    LuxeTile(
                      icon: Icons.two_wheeler_rounded,
                      title: 'Xe của tôi',
                      value: vehicleContext.hasVehicle
                          ? vehicleContext.displayName
                          : 'Chưa chọn xe',
                      onTap: () => _push(const VehicleGarageScreen()),
                    ),
                    LuxeTile(
                      icon: Icons.power_rounded,
                      title: 'Sạc thông minh Shelly',
                      shelly: true,
                      onTap: () => _push(const SmartChargerSetupHubScreen()),
                    ),
                  ],
                ),
              ),
              LuxeSectionLabel(
                BetaCapabilities.advancedAi
                    ? 'HỆ THỐNG & TRÍ TUỆ AI'
                    : 'HỆ THỐNG',
              ),
              LuxeReveal(
                index: 2,
                child: LuxeSettingsGroup(
                  children: [
                    LuxeSettingsRow(
                      key: const ValueKey('more-assistant-memory'),
                      icon: Icons.auto_awesome_rounded,
                      title: 'Pinova Bot đang nhớ gì',
                      subtitle: 'Xem, xóa hoặc tắt học cá nhân của trợ lý',
                      onTap: () => _push(const AssistantMemoryScreen()),
                    ),
                    if (BetaCapabilities.advancedAi)
                      LuxeSettingsRow(
                        icon: Icons.psychology_rounded,
                        title: 'Trợ lý AI & Dự báo Pin',
                        subtitle: availability.enabled
                            ? 'Thuật toán tối ưu sạc & bảo vệ cell pin'
                            : availability.reason,
                        badge: LuxeTag(
                          availability.enabled ? 'Sẵn sàng' : 'Cần thiết lập',
                          color: availability.enabled
                              ? LuxeColors.emerald
                              : LuxeColors.champagne,
                        ),
                        onTap: () => _push(const AiModelsScreen()),
                      ),
                    LuxeSettingsRow(
                      icon: Icons.tune_rounded,
                      title: 'Cài đặt hệ thống',
                      subtitle: 'Thông báo đẩy, dữ liệu, giao diện',
                      onTap: () => _push(const SettingsScreen()),
                    ),
                  ],
                ),
              ),
              const LuxeSectionLabel('HỖ TRỢ & TÀI KHOẢN'),
              LuxeReveal(
                index: 3,
                child: LuxeSettingsGroup(
                  children: [
                    LuxeSettingsRow(
                      key: GuideRegistry.keySettingsHelp,
                      icon: Icons.support_agent_rounded,
                      title: 'Trợ giúp & khắc phục sự cố',
                      subtitle: 'Tự kiểm tra lỗi, sửa nhanh, hỏi đội Pinova',
                      onTap: () => _push(const HelpCenterScreen()),
                    ),
                    LuxeSettingsRow(
                      key: const ValueKey('more-privacy'),
                      icon: Icons.privacy_tip_rounded,
                      title: 'Chính sách bảo mật',
                      subtitle:
                          'Dữ liệu nào được dùng, ở đâu, và quyền của bạn',
                      onTap: () => unawaited(PrivacyConsent.openPolicy()),
                    ),
                    LuxeSettingsRow(
                      icon: Icons.menu_book_rounded,
                      title: 'Hướng dẫn sử dụng',
                      subtitle: 'Tìm chức năng và làm quen từng bước',
                      onTap: () => _push(const GuideScreen()),
                    ),
                    LuxeSettingsRow(
                      icon: Icons.notifications_none_rounded,
                      title: 'Trung tâm thông báo',
                      subtitle: 'Lịch sử cảnh báo sạc & tin tức',
                      trailing: unreadCount > 0
                          ? _CountBadge(unreadCount)
                          : null,
                      onTap: () => _push(const NotificationCenterScreen()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              LuxeReveal(
                index: 4,
                child: LuxeDangerButton(
                  label: 'Đăng xuất tài khoản',
                  onPressed: _handleSignOut,
                ),
              ),
              const SizedBox(height: 26),
              const _BrandFooter(),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────── Profile card ───────────────────────────────

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.displayName,
    required this.contactInfo,
    required this.loading,
    required this.vehicle,
    required this.rank,
    required this.points,
    required this.rankProgress,
    required this.onOpenProfile,
    required this.onSelectVehicle,
  });

  final String displayName;
  final String contactInfo;
  final bool loading;
  final VehicleContext vehicle;
  final AchievementRank rank;
  final int points;
  final double rankProgress;
  final VoidCallback onOpenProfile;
  final VoidCallback onSelectVehicle;

  @override
  Widget build(BuildContext context) {
    final initial = displayName.trim().isEmpty
        ? 'V'
        : displayName.trim().substring(0, 1).toUpperCase();
    final v = vehicle.vehicle;
    return LuxeGlass(
      radius: 28,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              onTap: () {
                HapticFeedback.selectionClick();
                onOpenProfile();
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 14, 16),
                child: Row(
                  children: [
                    _RankAvatar(
                      initial: initial,
                      rank: rank,
                      progress: rankProgress,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // QA 136: the plan's tag next to the name.
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: Text(
                                  loading ? '…' : displayName,
                                  key: ValueKey(loading),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: LuxeColors.text,
                                    fontSize: 22,
                                    height: 1.2,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const CurrentPlanTag(
                                key: ValueKey('settings-plan-tag'),
                                large: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            maskContact(contactInfo),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LuxeText.caption,
                          ),
                          const SizedBox(height: 6),
                          // QA 141: the achievement rank with its points, not
                          // as a title above the name next to the plan tag.
                          Text(
                            '${rank.name} · $points điểm thành tựu',
                            style: LuxeText.label.copyWith(
                              fontSize: 11.5,
                              color: rank.rarity.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: LuxeColors.dim,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1, indent: 18, endIndent: 18),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(28),
              ),
              onTap: onSelectVehicle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 14, 14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.two_wheeler_rounded,
                        size: 18,
                        color: context.planAccent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          vehicle.hasVehicle
                              ? vehicle.displayName
                              : 'Chọn xe để bắt đầu',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: LuxeColors.text,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      _ShrinkAtLargeText(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (v != null && v.hasBatteryData) ...[
                              _MiniBattery(
                                percent: v.currentBattery.toDouble(),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${v.currentBattery}%',
                                style: const TextStyle(
                                  color: LuxeColors.platinumHi,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            const LuxeTag('Đổi xe'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Initial inside a metal ring whose arc shows progress to the next rank.
class _RankAvatar extends StatelessWidget {
  const _RankAvatar({
    required this.initial,
    required this.rank,
    required this.progress,
  });
  final String initial;
  final AchievementRank rank;
  final double progress;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${rank.name}, ${(progress * 100).round()}% tới hạng kế tiếp',
    excludeSemantics: true,
    child: SizedBox.square(
      dimension: 74,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 1400),
        curve: LuxeMotion.enter,
        builder: (context, t, child) => CustomPaint(
          painter: _RingPainter(metal: rank.rarity.metal, progress: t),
          child: child,
        ),
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A2C30), LuxeColors.surface],
              ),
            ),
            alignment: Alignment.center,
            child: LuxeMetalText(
              initial,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w300),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.metal, required this.progress});
  final List<Color> metal;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 3;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = LuxeColors.hairline,
    );
    if (progress <= 0) return;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: 3 * math.pi / 2,
          colors: [metal[2], metal[1], metal[0], metal[1]],
          stops: const [0.0, 0.4, 0.7, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.metal != metal;
}

class _MiniBattery extends StatelessWidget {
  const _MiniBattery({required this.percent});
  final double percent;

  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 12,
    padding: const EdgeInsets.all(1.5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: LuxeColors.platinumMid),
    ),
    child: Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: (percent / 100).clamp(0.05, 1.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1.5),
            color: percent < 20 ? LuxeColors.danger : context.planAccent,
          ),
        ),
      ),
    ),
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 28),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(99),
      gradient: LinearGradient(
        colors: [context.planAccent, context.planAccentDeep],
      ),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFF04140D),
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _BrandFooter extends StatelessWidget {
  const _BrandFooter();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      FutureBuilder<String?>(
        future: installedVersion,
        builder: (context, snapshot) => Text(
          snapshot.data == null
              ? AppConstants.appName
              : '${AppConstants.appName} · Phiên bản ${snapshot.data}',
          textAlign: TextAlign.center,
          style: LuxeText.label.copyWith(fontSize: 11.5, color: LuxeColors.dim),
        ),
      ),
      const SizedBox(height: 3),
      const Text(
        'Hệ sinh thái quản lý & tối ưu năng lượng xe điện',
        textAlign: TextAlign.center,
        style: TextStyle(color: LuxeColors.dim, fontSize: 11.5),
      ),
    ],
  );
}

/// QA 138 (QA-08): at large text the battery, % and "Đổi xe" shrink with the
/// vehicle name instead of pushing past the card; at normal size they keep
/// their size (and the row its 48 dp).
class _ShrinkAtLargeText extends StatelessWidget {
  const _ShrinkAtLargeText({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1) > 1.3
      ? Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: child,
          ),
        )
      : child;
}

/// QA 141: the profile card is on screen often (and in screenshots), so the
/// phone number and e-mail are partly hidden: "0852 ••• 174".
String maskContact(String value) {
  final text = value.trim();
  final digits = text.replaceAll(RegExp(r'[^0-9+]'), '');
  if (RegExp(r'^\+?[0-9]{9,15}$').hasMatch(digits)) {
    return '${digits.substring(0, 4)} ••• ${digits.substring(digits.length - 3)}';
  }
  final at = text.indexOf('@');
  if (at > 0) {
    final name = text.substring(0, at);
    final keep = name.length <= 2 ? 1 : 2;
    return '${name.substring(0, keep)}•••${text.substring(at)}';
  }
  return text;
}
