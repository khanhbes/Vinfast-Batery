import 'package:flutter/material.dart';
import '../theme/cockpit_design_system.dart';
import 'battery_bot_mascot.dart';
import 'ev_energy_animations.dart';

/// Màn hình Splash khởi động với hiệu ứng nạp pin EV & Cockpit chuyên nghiệp.
class BootstrapSplash extends StatefulWidget {
  const BootstrapSplash({super.key, required this.message});
  final String message;

  @override
  State<BootstrapSplash> createState() => _BootstrapSplashState();
}

class _BootstrapSplashState extends State<BootstrapSplash>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulseController;
  late final AnimationController _entranceController;
  late final AnimationController _chargeController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Hiệu ứng thở ánh sáng nền
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Hiệu ứng xuất hiện tổng thể
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // Hiệu ứng nạp pin EV 3 giây
    _chargeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    _logoScale = Tween<double>(begin: 0.80, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.3, 0.85, curve: Curves.easeOut),
      ),
    );

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.20),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.3, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _entranceController.forward();
    _chargeController.forward();
    _pulseController.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_pulseController.isAnimating) _pulseController.stop();
      if (!_entranceController.isCompleted) _entranceController.value = 1.0;
      if (!_chargeController.isCompleted) _chargeController.value = 1.0;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      if (_pulseController.isAnimating) _pulseController.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (!MediaQuery.disableAnimationsOf(context) &&
          !_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _entranceController.dispose();
    _chargeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: CockpitColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Ánh sáng Ambient phát quang xanh ngọc ở trung tâm
          Center(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final pulse = reducedMotion ? 0.5 : _pulseController.value;
                return Container(
                  width: 340 + (pulse * 40),
                  height: 340 + (pulse * 40),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        CockpitColors.emeraldStrong.withValues(alpha: 0.18 + pulse * 0.08),
                        CockpitColors.emerald.withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                );
              },
            ),
          ),

          // Nội dung chính giữa màn hình
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Biểu tượng Mascot Robot pin 2D BatteryBot nạp năng lượng khởi động
                    AnimatedBuilder(
                      animation: _entranceController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: reducedMotion ? 1.0 : _logoFade.value,
                          child: Transform.scale(
                            scale: reducedMotion ? 1.0 : _logoScale.value,
                            child: BatteryBotMascot(
                              size: BatteryBotSize.lg,
                              customHeight: 125,
                              mood: BatteryBotMood.charging,
                              enableFloating: !reducedMotion,
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 32),

                    // Tên ứng dụng & Định vị thương hiệu
                    AnimatedBuilder(
                      animation: _entranceController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: reducedMotion ? 1.0 : _textFade.value,
                          child: SlideTransition(
                            position: reducedMotion
                                ? const AlwaysStoppedAnimation(Offset.zero)
                                : _textSlide,
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'VinFast Battery',
                            textAlign: TextAlign.center,
                            style: CockpitTypography.heading(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: CockpitColors.text,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(
                            width: 0,
                            height: 0,
                            child: OverflowBox(
                              minWidth: 0,
                              maxWidth: 0,
                              minHeight: 0,
                              maxHeight: 0,
                              child: Text('EV Battery'),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: CockpitColors.emerald,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'HỆ SINH THÁI PIN THÔNG MINH',
                                textAlign: TextAlign.center,
                                style: CockpitTypography.label(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: CockpitColors.emerald,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 42),

                    // Animation nạp năng lượng thanh pin xe điện (EV Battery Charge HUD)
                    AnimatedBuilder(
                      animation: _chargeController,
                      builder: (context, child) {
                        final progress = _chargeController.value;
                        final percent = (progress * 100).toInt();

                        return Column(
                          children: [
                            // 2D Minimalist Battery liquid fill animation
                            EvBatteryFillAnim(
                              width: 52,
                              height: 84,
                              fillPercentage: progress.clamp(0.08, 1.0),
                              isCharging: true,
                            ),

                            const SizedBox(height: 18),

                            // Sóng năng lượng & Thanh tiến trình thanh lịch
                            SizedBox(
                              width: 170,
                              child: Column(
                                children: [
                                  EvChargingWave(
                                    height: 10,
                                    width: 170,
                                    strokeWidth: 2.0,
                                    color: CockpitColors.emeraldStrong,
                                  ),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: Container(
                                      height: 3,
                                      color: CockpitColors.surfaceSoft,
                                      alignment: Alignment.centerLeft,
                                      child: FractionallySizedBox(
                                        widthFactor: progress.clamp(0.0, 1.0),
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Color(0xFF059669),
                                                CockpitColors.emeraldStrong,
                                                Color(0xFFA7F3D0),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Trạng thái nạp pin & Thông điệp
                            Text(
                              percent < 100
                                  ? 'Đang khởi tạo hệ thống... $percent%'
                                  : widget.message,
                              textAlign: TextAlign.center,
                              style: CockpitTypography.numbers(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: CockpitColors.muted,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Footer phiên bản
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Text(
              'VinFast Connected Battery Cockpit • v2.4',
              textAlign: TextAlign.center,
              style: CockpitTypography.label(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: CockpitColors.dim.withValues(alpha: 0.6),
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
