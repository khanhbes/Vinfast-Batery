import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/onboarding_service.dart';
import '../../core/models/onboarding_draft.dart';
import '../../core/services/api_result.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/cockpit_design_system.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/battery_bot_mascot.dart';
import '../../data/models/vinfast_model_spec.dart';
import '../../data/repositories/vehicle_spec_repository.dart';
import '../../navigation/app_navigation.dart';

/// Màn hình Khảo sát Onboarding Step-by-Step Wizard cao cấp
/// Tối ưu UX/UI với Mascot 2D BatteryBot thông minh, hiệu ứng động,
/// lược bớt chữ rườm rà, tự động bỏ qua dữ liệu đã có và định dạng ngày sinh dd/mm/yyyy chuẩn.
class OnboardingChatScreen extends ConsumerStatefulWidget {
  const OnboardingChatScreen({super.key});

  @override
  ConsumerState<OnboardingChatScreen> createState() =>
      _OnboardingChatScreenState();
}

class _OnboardingChatScreenState extends ConsumerState<OnboardingChatScreen> {
  // 8 Bước chuẩn:
  // 0: Welcome
  // 1: Chọn xe
  // 2: Chi tiết xe
  // 3: Ngày sinh
  // 4: Khảo sát quãng đường
  // 5: Khảo sát mục đích & %Pin cắm sạc
  // 6: Shelly
  // 7: Tổng kết hồ sơ
  int _currentStep = 0;
  final int _totalSteps = 8;
  bool _isLoading = true;
  bool _isSubmitting = false;

  // Dữ liệu người dùng thu thập
  String _userName = '';
  String? _userPhone;
  String? _dateOfBirth; // Định dạng dd/MM/yyyy
  bool _hadExistingDob = false;
  String? _createdVehicleId;
  OnboardingDraft? _draft;

  // Dữ liệu khảo sát cá nhân hóa (Component C)
  double _dailyDistanceKm = 20.0;
  String? _selectedUsagePurpose;
  double _typicalSocWhenCharge = 20.0;

  // Catalog xe
  List<VinFastModelSpec> _catalogSpecs = [];
  VinFastModelSpec? _selectedSpec;

  // Controllers cho thông tin phụ của xe
  final _nicknameCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _odoCtrl = TextEditingController(text: '0');

  // Controller ngày sinh
  final _dobCtrl = TextEditingController();
  final _dobMaskFormatter = MaskTextInputFormatter(
    mask: '##/##/####',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );

  // Shelly status
  String _shellyStatus = 'skipped';

  @override
  void initState() {
    super.initState();
    _initOnboardingFlow();
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _plateCtrl.dispose();
    _odoCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  /// Khởi tạo dữ liệu từ server & tự động kiểm tra trường đã có
  Future<void> _initOnboardingFlow() async {
    final onboardingService = ref.read(onboardingServiceProvider);

    final currentUser = AuthService().currentUser;
    if (currentUser != null) {
      _draft = await onboardingService.loadDraft(currentUser.uid);
      if (_draft != null) {
        _userName = _draft!.name;
        _userPhone = _draft!.phone;
        _dateOfBirth = _draft!.dateOfBirth;
        _dailyDistanceKm = _draft!.avgDailyDistanceKm ?? _dailyDistanceKm;
        _selectedUsagePurpose = _draft!.usagePurpose;
        _typicalSocWhenCharge = _draft!.typicalSocWhenCharge ?? _typicalSocWhenCharge;
        _nicknameCtrl.text = _draft!.nickname ?? '';
        _plateCtrl.text = _draft!.licensePlate ?? '';
        _odoCtrl.text = _draft!.initialOdo.toString();
        _shellyStatus = _draft!.shellyStatus;
        _dobCtrl.text = _draft!.dateOfBirth ?? '';
        if (_draft!.state == OnboardingDraftState.failedPermanent) {
          AppPopup.showWarning(
            'Cần cập nhật thông tin onboarding',
            detail: _draft!.lastErrorMessage ?? 'Thông tin đã lưu không còn hợp lệ.',
            userInitiated: false,
          );
        }
      }
    }

    // 1. Tải catalog xe song song
    _loadCatalog();

    // 2. Lấy thông tin tài khoản hiện có
    var status = await onboardingService.fetchOnboardingStatus();
    if (status == null) {
      final user = AuthService().currentUser;
      await onboardingService.bootstrapRegistration(
        name: user?.displayName ?? '',
      );
      status = await onboardingService.fetchOnboardingStatus();
    }

    if (status != null) {
      _userName = status.name.trim();
      _userPhone = status.phone.isNotEmpty ? status.phone.trim() : null;

      if (status.dateOfBirth != null && status.dateOfBirth!.isNotEmpty) {
        _dateOfBirth =
            OnboardingService.toDisplayDateFormat(status.dateOfBirth);
        if (_dateOfBirth != null) {
          _dobCtrl.text = _dateOfBirth!;
          _hadExistingDob = true;
        }
      }

      if (status.hasVehicle && status.vehicles.isNotEmpty) {
        _createdVehicleId =
            status.vehicles.first['vehicleId']?.toString() ?? '';
      }
    }

    if (_userName.isEmpty) {
      _userName = currentUser?.displayName ?? 'Bạn';
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  bool _catalogLoadFailed = false;

  Future<void> _loadCatalog() async {
    if (mounted) setState(() => _catalogLoadFailed = false);
    try {
      final specs = await VehicleSpecRepository().getAllSpecs();
      if (mounted) {
        setState(() {
          _catalogSpecs = specs.where((s) => s.selectable).toList();
          _catalogLoadFailed = _catalogSpecs.isEmpty;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _catalogLoadFailed = true);
        AppPopup.showWarning(
          'Không tải được danh sách xe',
          detail: 'Kiểm tra kết nối và thử lại.',
          action: _loadCatalog,
          actionLabel: 'THỬ LẠI',
          userInitiated: false,
        );
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STEP NAVIGATION & ACTIONS
  // ──────────────────────────────────────────────────────────────────────────

  bool _canContinueCurrentStep() {
    switch (_currentStep) {
      case 0:
        return true;
      case 1:
        return _selectedSpec != null;
      case 2:
        return true;
      case 3:
        return true;
      case 4:
        return true;
      case 5:
        return _selectedUsagePurpose != null &&
            _selectedUsagePurpose!.isNotEmpty;
      case 6:
        return true;
      case 7:
        return true;
      default:
        return true;
    }
  }

  void _nextStep() {
    HapticFeedback.lightImpact();
    if (_currentStep == 0) {
      // Từ Welcome sang Chọn xe (nếu đã có xe -> sang ngày sinh)
      if (_createdVehicleId != null && _createdVehicleId!.isNotEmpty) {
        _goToStepOrSkip(_hadExistingDob ? 4 : 3);
      } else {
        _goToStepOrSkip(1);
      }
    } else if (_currentStep == 1) {
      if (_selectedSpec == null) {
        return;
      }
      _goToStepOrSkip(2);
    } else if (_currentStep == 2) {
      _handleCreateVehicle(skipDetails: false);
    } else if (_currentStep == 3) {
      _handleSubmitDob();
    } else if (_currentStep == 4) {
      _handleSubmitDailyDistance();
    } else if (_currentStep == 5) {
      _handleSubmitUsagePurpose();
    } else if (_currentStep == 6) {
      _goToStepOrSkip(7);
    } else if (_currentStep == 7) {
      _finishOnboarding();
    }
  }

  void _handleSubmitDailyDistance() {
    _updateDraftAndPersist(avgDailyDistanceKm: _dailyDistanceKm);
    _goToStepOrSkip(5);
  }

  void _handleSubmitUsagePurpose() {
    if (_selectedUsagePurpose == null) return;
    _updateDraftAndPersist(
      avgDailyDistanceKm: _dailyDistanceKm,
      usagePurpose: _selectedUsagePurpose,
      typicalSocWhenCharge: _typicalSocWhenCharge,
    );
    _goToStepOrSkip(6);
  }

  void _prevStep() {
    if (_currentStep <= 0) return;
    int prev = _currentStep - 1;
    // Bỏ qua các bước đã có dữ liệu khi back
    if (prev == 3 && _hadExistingDob) prev--;
    if ((prev == 2 || prev == 1) &&
        _createdVehicleId != null &&
        _createdVehicleId!.isNotEmpty) {
      prev = 0;
    }
    setState(() => _currentStep = prev.clamp(0, _totalSteps - 1));
  }

  void _goToStepOrSkip(int targetStep) {
    int next = targetStep;
    // Bỏ qua ngày sinh nếu đã có sẵn
    if (next == 3 && _hadExistingDob) {
      next = 4;
    }
    // Bỏ qua chọn xe nếu đã có sẵn
    if ((next == 1 || next == 2) &&
        _createdVehicleId != null &&
        _createdVehicleId!.isNotEmpty) {
      next = _hadExistingDob ? 4 : 3;
    }
    setState(() => _currentStep = next.clamp(0, _totalSteps - 1));
  }

  Future<void> _updateDraftAndPersist({
    String? dateOfBirth,
    double? avgDailyDistanceKm,
    String? usagePurpose,
    double? typicalSocWhenCharge,
  }) async {
    final draft = _draft;
    if (draft == null) return;
    _draft = draft.copyWith(
      revision: draft.revision + 1,
      dateOfBirth: dateOfBirth ?? _dateOfBirth,
      avgDailyDistanceKm: avgDailyDistanceKm ?? _dailyDistanceKm,
      usagePurpose: usagePurpose ?? _selectedUsagePurpose,
      typicalSocWhenCharge: typicalSocWhenCharge ?? _typicalSocWhenCharge,
      updatedAt: DateTime.now().toUtc(),
    );
    await ref.read(onboardingServiceProvider).saveDraft(_draft!);
  }

  Future<ApiResult<Map<String, dynamic>>> _commitDraft() async {
    final draft = _draft;
    if (draft == null) {
      return const ApiResult(success: false, code: 'DRAFT_MISSING', userMessage: 'Chưa có thông tin onboarding.', retryable: false);
    }
    final service = ref.read(onboardingServiceProvider);
    final syncing = draft.copyWith(
      state: OnboardingDraftState.syncing,
      revision: draft.revision + 1,
      attemptCount: draft.attemptCount + 1,
      updatedAt: DateTime.now().toUtc(),
    );
    _draft = syncing;
    await service.saveDraft(syncing);
    final result = await service.commitDraft(syncing);
    if (result.success) {
      _draft = syncing.copyWith(state: OnboardingDraftState.synced, updatedAt: DateTime.now().toUtc());
      await service.clearDraft(syncing.uid);
    } else {
      final nextState = result.retryable
          ? OnboardingDraftState.failedRetryable
          : OnboardingDraftState.failedPermanent;
      _draft = syncing.copyWith(
        state: nextState,
        lastErrorCode: result.code,
        lastErrorMessage: result.userMessage,
        nextAttemptAt: result.retryable
            ? DateTime.now().toUtc().add(const Duration(seconds: 30))
            : null,
        updatedAt: DateTime.now().toUtc(),
      );
      await service.saveDraft(_draft!);
    }
    return result;
  }

  /// Tạo xe cục bộ trước, sau đó đồng bộ server bằng operation idempotent.
  Future<void> _handleCreateVehicle({required bool skipDetails}) async {
    if (_selectedSpec == null) {
      _goToStepOrSkip(_hadExistingDob ? 4 : 3);
      return;
    }

    final nickname = skipDetails ? null : _nicknameCtrl.text.trim();
    final plate = skipDetails ? null : _plateCtrl.text.trim();
    final odoText = skipDetails ? '0' : _odoCtrl.text.trim();
    final odo = int.tryParse(odoText) ?? 0;

    final user = AuthService().currentUser;
    if (user == null) return;
    _draft ??= OnboardingDraft.create(
      uid: user.uid,
      name: _userName,
      phone: _userPhone,
      catalogId: _selectedSpec!.modelId,
      nickname: nickname,
      licensePlate: plate,
      initialOdo: odo,
      shellyStatus: _shellyStatus,
    );
    _draft = _draft!.copyWith(
      name: _userName,
      phone: _userPhone,
      catalogId: _selectedSpec!.modelId,
      nickname: nickname,
      licensePlate: plate,
      initialOdo: odo,
      revision: _draft!.revision + 1,
      state: OnboardingDraftState.localPending,
      updatedAt: DateTime.now().toUtc(),
    );
    setState(() => _isSubmitting = true);
    await ref.read(onboardingServiceProvider).saveDraft(_draft!);
    setState(() => _isSubmitting = false);
    _createdVehicleId = 'pending:${_draft!.operationId}';
    _goToStepOrSkip(3);
  }

  /// Xử lý nộp ngày sinh
  void _handleSubmitDob() {
    final trimmed = _dobCtrl.text.trim();
    if (trimmed.isEmpty) {
      _skipDob();
      return;
    }

    final validationError = OnboardingService.validateDateOfBirth(trimmed);
    if (validationError != null) {
      AppPopup.showError(validationError);
      return;
    }

    _dateOfBirth = trimmed;
    _updateDraftAndPersist(dateOfBirth: _dateOfBirth);

    _goToStepOrSkip(4);
  }

  void _skipDob() {
    _dateOfBirth = null;
    _updateDraftAndPersist(dateOfBirth: null);
    _goToStepOrSkip(4);
  }

  /// Chọn ngày sinh qua DatePicker chuẩn dd/MM/yyyy
  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final initial = DateTime(now.year - 25, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1930),
      lastDate: DateTime(now.year - 16, now.month, now.day),
      builder: (ctx, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: CockpitColors.emeraldStrong,
              onPrimary: Colors.white,
              surface: Color(0xFF1E293B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formatted = DateFormat('dd/MM/yyyy').format(picked);
      setState(() {
        _dobCtrl.text = formatted;
        _dateOfBirth = formatted;
      });
    }
  }

  /// Hoàn tất Onboarding và khởi động Cockpit
  Future<void> _finishOnboarding() async {
    setState(() => _isSubmitting = true);

    if (_draft != null) {
      _draft = _draft!.copyWith(shellyStatus: _shellyStatus, revision: _draft!.revision + 1, updatedAt: DateTime.now().toUtc());
      await ref.read(onboardingServiceProvider).saveDraft(_draft!);
    }
    final result = await _commitDraft();

    setState(() => _isSubmitting = false);
    if (!mounted) return;

    if (result.success) {
      final navigator = Navigator.of(context, rootNavigator: true);
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppNavigation()),
        (route) => false,
      );
    } else if (result.retryable) {
      AppPopup.showWarning(
        'Đang chờ đồng bộ onboarding',
        detail: result.userMessage ?? 'Bạn có thể tiếp tục; app sẽ tự thử lại khi có mạng.',
        action: _finishOnboarding,
        actionLabel: 'THỬ LẠI',
        userInitiated: true,
      );
    } else {
      AppPopup.showError(result.userMessage ?? 'Không thể hoàn tất.');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DYNAMIC MASCOT CONTENT
  // ──────────────────────────────────────────────────────────────────────────

  BatteryBotMood _getMascotMood() {
    switch (_currentStep) {
      case 0:
        return BatteryBotMood.greeting;
      case 1:
        return _selectedSpec != null
            ? BatteryBotMood.happy
            : BatteryBotMood.thinking;
      case 2:
        return BatteryBotMood.listening;
      case 3:
        return BatteryBotMood.idle;
      case 4:
        return BatteryBotMood.happy;
      case 5:
        return _selectedUsagePurpose != null
            ? BatteryBotMood.happy
            : BatteryBotMood.thinking;
      case 6:
        return _shellyStatus == 'connected'
            ? BatteryBotMood.charging
            : BatteryBotMood.idle;
      case 7:
        return BatteryBotMood.happy;
      default:
        return BatteryBotMood.idle;
    }
  }

  String _getMascotSpeech() {
    switch (_currentStep) {
      case 0:
        return 'Chào ${_userName.isNotEmpty ? _userName : 'bạn'}! Mình là BatteryBot. Hãy cùng thiết lập hồ sơ xe để bảo vệ pin tối ưu nhé!';
      case 1:
        return _selectedSpec == null
            ? 'Xe của bạn là dòng nào? Chọn mẫu xe để tải thông số pin chuẩn.'
            : 'Tuyệt vời! ${_selectedSpec!.modelName} có bộ pin ${(_selectedSpec!.nominalCapacityWh / 1000).toStringAsFixed(1)} kWh cực bền bỉ.';
      case 2:
        return 'Đặt tên gợi nhớ hoặc nhập biển số để dễ phân biệt xe nhé! (Có thể bỏ qua)';
      case 3:
        return 'Ngày sinh của bạn là khi nào? BatteryBot sẽ chúc mừng và tối ưu chu kỳ sạc.';
      case 4:
        if (_dailyDistanceKm <= 15) {
          return 'Tuyệt vời! ~${_dailyDistanceKm.toInt()} km/ngày là cự ly nhẹ nhàng giúp pin duy trì tuổi thọ cao nhất.';
        } else if (_dailyDistanceKm <= 40) {
          return '~${_dailyDistanceKm.toInt()} km/ngày là quãng đường lý tưởng cho xe điện đô thị!';
        } else {
          return '~${_dailyDistanceKm.toInt()} km/ngày: Mình sẽ ưu tiên tối ưu chu kỳ sạc sâu cho hành trình dài.';
        }
      case 5:
        if (_selectedUsagePurpose == null) {
          return 'Bạn thường dùng xe vào mục đích gì và thường cắm sạc khi pin còn bao nhiêu %?';
        } else if (_typicalSocWhenCharge <= 15) {
          return 'Mẹo: Bạn nên sạc khi pin còn khoảng 20% thay vì để cạn dưới 15% để kéo dài tuổi thọ cell LFP.';
        } else {
          return 'Thói quen sạc ở mức ${_typicalSocWhenCharge.toInt()}% rất tốt để giữ độ cân bằng cell pin!';
        }
      case 6:
        return 'Bạn có ổ cắm thông minh Shelly không? Tự động ngắt khi đầy 80% chống chai pin.';
      case 7:
        return 'Hồ sơ năng lượng pin đã hoàn tất! Chạm nút dưới để bước vào Cockpit điều khiển.';
      default:
        return '';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BUILD METHOD
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: CockpitColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BatteryBotMascot(
                size: BatteryBotSize.md,
                mood: BatteryBotMood.charging,
              ),
              const SizedBox(height: 20),
              const Text(
                'Đang chuẩn bị hồ sơ năng lượng...',
                style: TextStyle(color: CockpitColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: CockpitColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top Navigation Bar với Progress Pills & Exit
            _buildTopNav(),

            // 2. Mascot Stage với Responsive Keyboard Avatar
            _buildMascotStage(isKeyboardOpen),

            // 3. Step Content chuyển đổi mượt mà
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity < -250) {
                    if (!_isSubmitting && _canContinueCurrentStep() && _currentStep < _totalSteps - 1) {
                      _nextStep();
                    }
                  } else if (velocity > 250) {
                    if (!_isSubmitting && _currentStep > 0) {
                      _prevStep();
                    }
                  }
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.topCenter,
                    children: <Widget>[
                      ...previousChildren,
                      ?currentChild,
                    ],
                  ),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.04, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<int>(_currentStep),
                    child: _buildCurrentStepContent(),
                  ),
                ),
              ),
            ),

            // 4. Bottom Action Bar
            _buildBottomActionBar(),
          ],
        ),
      ),
    );
  }

  /// 2. Mascot Stage với Responsive Keyboard Avatar
  Widget _buildMascotStage(bool isKeyboardOpen) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 240),
      crossFadeState: isKeyboardOpen
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
      firstChild: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: BatteryBotMascot(
          size: _currentStep == 0 || _currentStep == (_totalSteps - 1)
              ? BatteryBotSize.lg
              : BatteryBotSize.md,
          mood: _getMascotMood(),
          showSpeechBubble: true,
          speechText: _getMascotSpeech(),
          bubblePosition: BubblePosition.top,
        ),
      ),
      secondChild: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(
          children: [
            BatteryBotMascot(
              size: BatteryBotSize.avatar,
              displayMode: BatteryBotDisplayMode.avatar,
              mood: _getMascotMood(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: CockpitColors.emerald.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Text(
                  _getMascotSpeech(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: CockpitColors.text,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 1. Top Navigation Bar với Progress Pills
  Widget _buildTopNav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Tiêu đề & Logo
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: CockpitColors.emerald,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'EV BATTERY',
                style: CockpitTypography.label(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: CockpitColors.text,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),

          // Progress Pills (8 viên năng lượng)
          Row(
            children: List.generate(_totalSteps, (index) {
              final isCurrent = index == _currentStep;
              final isPassed = index < _currentStep;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: isCurrent ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: isCurrent
                      ? CockpitColors.emerald
                      : isPassed
                          ? CockpitColors.emerald.withValues(alpha: 0.45)
                          : const Color(0xFF334155),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: CockpitColors.emerald.withValues(alpha: 0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              );
            }),
          ),

          // Bước hiện tại
          Text(
            '${_currentStep + 1}/$_totalSteps',
            style: const TextStyle(
              color: CockpitColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// 3. Nội dung theo từng bước
  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep0Welcome();
      case 1:
        return _buildStep1VehiclePicker();
      case 2:
        return _buildStep2VehicleDetails();
      case 3:
        return _buildStep3Dob();
      case 4:
        return _buildStep4DailyDistance();
      case 5:
        return _buildStep5UsagePurpose();
      case 6:
        return _buildStep6Shelly();
      case 7:
        return _buildStep7Summary();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── STEP 0: WELCOME & FEATURE HIGHLIGHTS ──────────────────────────────────
  Widget _buildStep0Welcome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          // Thẻ thông tin tài khoản đã xác thực
          if (_userPhone != null && _userPhone!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: CockpitColors.emerald.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: CockpitColors.emerald.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: CockpitColors.emerald, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Đã liên kết số điện thoại: $_userPhone',
                    style: const TextStyle(
                      color: CockpitColors.emerald,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          // 3 Feature Cards
          _buildFeatureCard(
            badge: '⚡ CELL PROTECTION',
            title: 'Bảo Vệ Cell Pin LFP',
            desc:
                'Theo dõi nội trở, tự động cảnh báo nhiệt độ và ngăn ngừa chai pin.',
            color: CockpitColors.emerald,
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            badge: '🧠 AI PREDICTION',
            title: 'Dự Báo Quãng Đường AI',
            desc:
                'Thuật toán học máy ước tính cự ly di chuyển chính xác theo phong cách lái.',
            color: const Color(0xFF38BDF8),
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            badge: '🔌 SMART CHARGER',
            title: 'Sạc Thông Minh 80%',
            desc:
                'Tự động ngắt khi pin đạt 80% hoặc quá nhiệt qua ổ cắm thông minh Shelly.',
            color: const Color(0xFFA78BFA),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required String badge,
    required String title,
    required String desc,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  // ── STEP 1: VEHICLE PICKER (2-COLUMN GRID) ───────────────────────────────
  Widget _buildStep1VehiclePicker() {
    if (_catalogLoadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, color: CockpitColors.amber, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Không tải được danh sách xe',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Kiểm tra kết nối mạng và thử lại.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadCatalog,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Thử lại'),
                style: FilledButton.styleFrom(
                  backgroundColor: CockpitColors.emerald,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_catalogSpecs.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: CockpitColors.emerald),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.90,
      ),
      itemCount: _catalogSpecs.length,
      itemBuilder: (context, index) {
        final spec = _catalogSpecs[index];
        final isSelected = _selectedSpec?.modelId == spec.modelId;

        return AppTactileBounce(
          pressScale: 0.96,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedSpec = spec);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF064E3B).withValues(alpha: 0.5)
                  : const Color(0xFF131B2B),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected
                    ? CockpitColors.emerald
                    : const Color(0xFF1E293B),
                width: isSelected ? 2.0 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: CockpitColors.emerald.withValues(alpha: 0.25),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Hàng trên: Badge pin + Icon check
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: CockpitColors.emerald.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${(spec.nominalCapacityWh / 1000).toStringAsFixed(1)} kWh',
                        style: const TextStyle(
                          color: CockpitColors.emerald,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle,
                          color: CockpitColors.emerald, size: 18)
                    else
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF475569)),
                        ),
                      ),
                  ],
                ),

                // Ảnh xe điện từ Catalog web admin hoặc biểu tượng fallback
                Center(
                  child: (spec.imageUrl != null &&
                          spec.imageUrl!.trim().isNotEmpty)
                      ? Container(
                          width: 84,
                          height: 54,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A)
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? CockpitColors.emerald
                                      .withValues(alpha: 0.35)
                                  : Colors.transparent,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              spec.imageUrl!.trim(),
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (context, error, stackTrace) =>
                                      _buildVehicleFallbackGraphic(
                                          spec, isSelected),
                              loadingBuilder:
                                  (context, child, progress) {
                                if (progress == null) return child;
                                return const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: CockpitColors.emerald,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        )
                      : _buildVehicleFallbackGraphic(spec, isSelected),
                ),

                // Tên xe & Quãng đường
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec.modelName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      spec.rangeKm != null
                          ? '${spec.rangeKm!.toInt()} km / lần sạc'
                          : 'Pin chuẩn LFP',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVehicleFallbackGraphic(VinFastModelSpec spec, bool isSelected) {
    final line = (spec.modelLine?.isNotEmpty == true)
        ? spec.modelLine!.toUpperCase()
        : (spec.modelName.split(' ').length > 1
            ? spec.modelName.split(' ')[1].toUpperCase()
            : 'EV');

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? CockpitColors.emerald.withValues(alpha: 0.5)
              : const Color(0xFF1E293B),
          width: 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isSelected
              ? [
                  const Color(0xFF064E3B).withValues(alpha: 0.4),
                  const Color(0xFF0F172A),
                ]
              : [
                  const Color(0xFF1E293B).withValues(alpha: 0.3),
                  const Color(0xFF0A0F1D),
                ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background watermark
          Positioned(
            right: 6,
            bottom: 2,
            child: Text(
              line,
              style: TextStyle(
                color: (isSelected ? CockpitColors.emerald : Colors.white)
                    .withValues(alpha: 0.08),
                fontSize: 16,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                letterSpacing: 1.2,
              ),
            ),
          ),
          // Silhouette icon & badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.two_wheeler_rounded,
                size: 26,
                color: isSelected
                    ? CockpitColors.emerald
                    : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? CockpitColors.emerald.withValues(alpha: 0.2)
                      : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: isSelected
                        ? CockpitColors.emerald.withValues(alpha: 0.7)
                        : const Color(0xFF334155),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  line,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: isSelected
                        ? CockpitColors.emerald
                        : const Color(0xFFCBD5E1),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── STEP 2: VEHICLE DETAILS (OPTIONAL) ───────────────────────────────────
  Widget _buildStep2VehicleDetails() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF131B2B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedSpec?.modelName ?? 'Thông tin xe',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Tùy chọn',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tên gợi nhớ
            _buildInputField(
              controller: _nicknameCtrl,
              autofocus: true,
              label: 'Biệt danh cho xe (Tùy chọn)',
              hint: 'VD: Evo của tôi, Xe đi làm...',
              icon: Icons.edit_note_rounded,
            ),
            const SizedBox(height: 14),

            // Biển số xe
            _buildInputField(
              controller: _plateCtrl,
              label: 'Biển kiểm soát (Tùy chọn)',
              hint: 'VD: 29-X1 888.88',
              icon: Icons.credit_card_rounded,
            ),
            const SizedBox(height: 14),

            // ODO ban đầu
            _buildInputField(
              controller: _odoCtrl,
              label: 'Số km đã đi hiện tại (ODO)',
              hint: '0',
              icon: Icons.speed_rounded,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 18),

            // Nút Bỏ qua nhanh
            Center(
              child: TextButton(
                onPressed: () => _handleCreateVehicle(skipDetails: true),
                style: TextButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                ),
                child: const Text(
                  'Bỏ qua & dùng thông tin mặc định',
                  style: TextStyle(color: CockpitColors.muted, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── STEP 3: DATE OF BIRTH (dd/mm/yyyy - OPTIONAL) ─────────────────────────
  Widget _buildStep3Dob() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF131B2B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ngày sinh của bạn',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Định dạng ngày/tháng/năm (dd/mm/yyyy). Giúp hệ thống ghi nhận chu kỳ cá nhân hóa.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
            ),
            const SizedBox(height: 20),

            // Input TextField với mask dd/mm/yyyy & nút chọn lịch
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: CockpitColors.emerald.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  const Icon(Icons.cake_outlined,
                      color: CockpitColors.emerald, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _dobCtrl,
                      autofocus: true,
                      inputFormatters: [_dobMaskFormatter],
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'dd/mm/yyyy',
                        hintStyle: TextStyle(
                          color: Color(0xFF64748B),
                          letterSpacing: 1.2,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _pickDateOfBirth,
                    icon: const Icon(Icons.calendar_month_rounded,
                        color: CockpitColors.emerald),
                    tooltip: 'Chọn lịch',
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Nút Bỏ qua bước này
            Center(
              child: TextButton(
                onPressed: _skipDob,
                style: TextButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                ),
                child: const Text(
                  'Bỏ qua bước này',
                  style: TextStyle(color: CockpitColors.muted, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── STEP 4: DAILY DISTANCE SURVEY ─────────────────────────────────────────
  Widget _buildStep4DailyDistance() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF131B2B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: CockpitColors.emerald.withValues(alpha: 0.25),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: CockpitColors.emerald.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.route_rounded,
                            color: CockpitColors.emerald,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Quãng đường di chuyển',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: CockpitColors.emerald.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '~${_dailyDistanceKm.toInt()} km/ngày',
                        style: const TextStyle(
                          color: CockpitColors.emerald,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${_dailyDistanceKm.toInt()}',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'km / ngày',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: CockpitColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: CockpitColors.emerald,
                    inactiveTrackColor: const Color(0xFF1E293B),
                    thumbColor: Colors.white,
                    overlayColor: CockpitColors.emerald.withValues(alpha: 0.2),
                    trackHeight: 6,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                  ),
                  child: Slider(
                    value: _dailyDistanceKm,
                    min: 5,
                    max: 100,
                    divisions: 19,
                    onChanged: (val) {
                      setState(() => _dailyDistanceKm = val);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [5.0, 15.0, 30.0, 50.0, 80.0].map((km) {
                    final isSelected = (_dailyDistanceKm - km).abs() < 2.5;
                    return GestureDetector(
                      onTap: () => setState(() => _dailyDistanceKm = km),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? CockpitColors.emerald.withValues(alpha: 0.25)
                              : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? CockpitColors.emerald
                                : const Color(0xFF334155),
                          ),
                        ),
                        child: Text(
                          '${km.toInt()} km',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? CockpitColors.emerald
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded,
                    color: CockpitColors.emerald, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _dailyDistanceKm <= 20
                        ? 'Khuyến nghị sạc: Cần sạc khoảng 1-2 lần mỗi tuần.'
                        : _dailyDistanceKm <= 50
                            ? 'Khuyến nghị sạc: Cần sạc khoảng 2-3 lần mỗi tuần.'
                            : 'Khuyến nghị sạc: Nên sạc qua đêm hàng ngày với giới hạn 80%.',
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── STEP 5: USAGE PURPOSE & TYPICAL CHARGE SOC ─────────────────────────────
  Widget _buildStep5UsagePurpose() {
    final purposes = [
      {
        'id': 'commute',
        'title': 'Đi làm hàng ngày',
        'subtitle': 'Lộ trình cố định, tiết kiệm chi phí năng lượng',
        'icon': Icons.work_outline_rounded,
      },
      {
        'id': 'delivery',
        'title': 'Giao hàng / Chạy xe',
        'subtitle': 'Cường độ cao, cần bảo vệ cell pin tối đa',
        'icon': Icons.local_shipping_outlined,
      },
      {
        'id': 'leisure',
        'title': 'Dạo phố & Giải trí',
        'subtitle': 'Đi lại tự do, cắm sạc linh hoạt theo nhu cầu',
        'icon': Icons.sports_motorsports_outlined,
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mục đích sử dụng chính (Chọn 1 để tiếp tục):',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...purposes.map((p) {
            final isSelected = _selectedUsagePurpose == p['id'];
            return GestureDetector(
              onTap: () => setState(() => _selectedUsagePurpose = p['id'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF064E3B).withValues(alpha: 0.5)
                      : const Color(0xFF131B2B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? CockpitColors.emerald
                        : const Color(0xFF1E293B),
                    width: isSelected ? 1.8 : 1.0,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: CockpitColors.emerald.withValues(alpha: 0.2),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? CockpitColors.emerald.withValues(alpha: 0.2)
                            : const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        p['icon'] as IconData,
                        color: isSelected ? CockpitColors.emerald : const Color(0xFF94A3B8),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['title'] as String,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p['subtitle'] as String,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle, color: CockpitColors.emerald, size: 20)
                    else
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF475569)),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF131B2B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Thường cắm sạc khi pin còn:',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: CockpitColors.emerald.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '~${_typicalSocWhenCharge.toInt()}%',
                        style: const TextStyle(
                          color: CockpitColors.emerald,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: CockpitColors.emerald,
                    inactiveTrackColor: const Color(0xFF1E293B),
                    thumbColor: Colors.white,
                    trackHeight: 5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  ),
                  child: Slider(
                    value: _typicalSocWhenCharge,
                    min: 10,
                    max: 60,
                    divisions: 10,
                    onChanged: (val) {
                      setState(() => _typicalSocWhenCharge = val);
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('10% (Sạc sâu)', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                    Text('30% (Khuyến nghị)', style: TextStyle(color: CockpitColors.emerald, fontSize: 11)),
                    Text('60% (Sạc nông)', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── STEP 6: SHELLY SMART SOCKET (OPTIONAL) ────────────────────────────────
  Widget _buildStep6Shelly() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          // Thẻ A: Kết nối Shelly ngay
          AppTactileBounce(
            pressScale: 0.97,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _shellyStatus = 'connected');
              _nextStep();
            },
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF131B2B),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _shellyStatus == 'connected'
                      ? CockpitColors.emerald
                      : const Color(0xFF1E293B),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: CockpitColors.emerald.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.power_rounded,
                        color: CockpitColors.emerald, size: 26),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sử dụng ổ cắm Shelly',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Tự động ngắt sạc an toàn 80% & chống cháy nổ.',
                          style: TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      color: Color(0xFF64748B), size: 16),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Thẻ B: Bỏ qua / Thiết lập sau
          AppTactileBounce(
            pressScale: 0.97,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _shellyStatus = 'skipped');
              _nextStep();
            },
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF131B2B),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.schedule_rounded,
                        color: Color(0xFF94A3B8), size: 26),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tôi sẽ thiết lập sau',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Dùng chế độ sạc thông thường không có ngắt tự động.',
                          style: TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      color: Color(0xFF64748B), size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── STEP 7: SUMMARY CARD ──────────────────────────────────────────────────
  Widget _buildStep7Summary() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF131B2B),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: CockpitColors.emerald.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: CockpitColors.emerald.withValues(alpha: 0.12),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Thẻ tổng kết
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _userPhone ?? 'Tài khoản xe điện',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: CockpitColors.emerald.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          color: CockpitColors.emerald, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'KÍCH HOẠT',
                        style: TextStyle(
                          color: CockpitColors.emerald,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(color: Color(0xFF1E293B), height: 28),

            // Thông tin xe đã chọn
            _buildSummaryRow(
              icon: Icons.electric_scooter_rounded,
              label: 'Mẫu xe',
              value: _selectedSpec?.modelName ?? 'Xe điện chuẩn',
            ),
            const SizedBox(height: 12),
            _buildSummaryRow(
              icon: Icons.battery_charging_full_rounded,
              label: 'Dung lượng pin',
              value: _selectedSpec != null
                  ? '${(_selectedSpec!.nominalCapacityWh / 1000).toStringAsFixed(1)} kWh (LFP)'
                  : '3.5 kWh',
            ),
            if (_plateCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildSummaryRow(
                icon: Icons.credit_card_rounded,
                label: 'Biển kiểm soát',
                value: _plateCtrl.text.trim(),
              ),
            ],
            if (_dateOfBirth != null && _dateOfBirth!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildSummaryRow(
                icon: Icons.cake_outlined,
                label: 'Ngày sinh',
                value: _dateOfBirth!,
              ),
            ],
            const SizedBox(height: 12),
            _buildSummaryRow(
              icon: Icons.route_rounded,
              label: 'Quãng đường / ngày',
              value: '~${_dailyDistanceKm.toInt()} km',
            ),
            if (_selectedUsagePurpose != null) ...[
              const SizedBox(height: 12),
              _buildSummaryRow(
                icon: Icons.work_outline_rounded,
                label: 'Mục đích sử dụng',
                value: _getUsagePurposeName(_selectedUsagePurpose),
              ),
            ],
            const SizedBox(height: 12),
            _buildSummaryRow(
              icon: Icons.battery_saver_rounded,
              label: 'Thói quen cắm sạc',
              value: 'Khi pin còn ~${_typicalSocWhenCharge.toInt()}%',
            ),
            const SizedBox(height: 12),
            _buildSummaryRow(
              icon: Icons.power_rounded,
              label: 'Trạm sạc thông minh',
              value: _shellyStatus == 'connected'
                  ? 'Đã kích hoạt Shelly'
                  : 'Sạc tiêu chuẩn',
            ),
          ],
        ),
      ),
    );
  }

  String _getUsagePurposeName(String? id) {
    switch (id) {
      case 'commute':
        return 'Đi làm hàng ngày';
      case 'delivery':
        return 'Giao hàng / Chạy xe';
      case 'leisure':
        return 'Dạo phố & Giải trí';
      default:
        return 'Cá nhân';
    }
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF94A3B8), size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          ],
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool autofocus = false,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF64748B), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: autofocus,
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle:
                        const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 4. Bottom Action Bar
  Widget _buildBottomActionBar() {
    final isLast = _currentStep == _totalSteps - 1;
    final canContinue = _canContinueCurrentStep();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          // Nút quay lại
          if (_currentStep > 0) ...[
            OutlinedButton(
              onPressed: _isSubmitting ? null : _prevStep,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Color(0xFF334155)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
              child: const Text('Quay lại'),
            ),
            const SizedBox(width: 12),
          ],

          // Nút hành động chính
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: canContinue ? null : const Color(0xFF1E293B),
                gradient: canContinue
                    ? const LinearGradient(
                        colors: [
                          Color(0xFF059669),
                          CockpitColors.emeraldStrong,
                        ],
                      )
                    : null,
                boxShadow: canContinue
                    ? [
                        BoxShadow(
                          color: CockpitColors.emerald.withValues(alpha: 0.35),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: ElevatedButton(
                onPressed: (_isSubmitting || !canContinue) ? null : _nextStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: canContinue ? Colors.white : const Color(0xFF64748B),
                  disabledForegroundColor: const Color(0xFF64748B),
                  disabledBackgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isLast
                                ? 'Khởi động Cockpit ⚡'
                                : _currentStep == 0
                                    ? 'Bắt đầu thiết lập →'
                                    : 'Tiếp tục →',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: canContinue ? Colors.white : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
              ),
            ).appTactile(enabled: canContinue && !_isSubmitting),
          ),
        ],
      ),
    );
  }
}
