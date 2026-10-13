import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/onboarding_service.dart';
import '../../core/models/onboarding_draft.dart';
import '../../core/services/api_result.dart';
import '../../data/services/push_notification_service.dart';
import '../../data/services/shelly_connection_coordinator.dart';
import '../../data/models/shelly_connection_state.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/battery_bot_mascot.dart';
import '../../data/models/vinfast_model_spec.dart';
import '../../data/repositories/vehicle_spec_repository.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';

/// Onboarding keeps the existing draft/validation contract in a calm step UI.
class OnboardingChatScreen extends ConsumerStatefulWidget {
  const OnboardingChatScreen({super.key, this.onCompleted});

  /// Lets the existing AuthGate refresh its profile/draft routing without
  /// pushing a second gate (which would replay the splash).
  final VoidCallback? onCompleted;

  @override
  ConsumerState<OnboardingChatScreen> createState() =>
      _OnboardingChatScreenState();
}

class _OnboardingChatScreenState extends ConsumerState<OnboardingChatScreen> {
  static const Object _unchanged = Object();
  // Khảo sát tuyến tính, các câu hỏi cá nhân và phần cài đặt đều có thể bỏ qua.
  // 0: Welcome
  // 1: Chọn xe
  // 2: Chi tiết xe
  // 3: Ngày sinh
  // 4: Khảo sát quãng đường
  // 5: Khảo sát mục đích & %Pin cắm sạc
  // 6: Shelly
  // 7: Quyền thông báo
  // 8: Tổng kết hồ sơ
  int _currentStep = 0;
  bool _movingForward = true;
  final int _totalSteps = 9;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _initialLoadError;
  int _initialLoadGeneration = 0;

  static const _initialLoadTimeout = Duration(seconds: 15);
  static const _permissionDecisionTimeout = Duration(seconds: 45);
  static const _notificationSetupTimeout = Duration(seconds: 12);

  // Dữ liệu người dùng thu thập
  String _userName = '';
  String? _userPhone;
  String? _dateOfBirth; // Định dạng dd/MM/yyyy
  bool _hadExistingDob = false;
  String? _createdVehicleId;
  OnboardingDraft? _draft;
  Future<void> _pendingDraftWrite = Future<void>.value();

  // Dữ liệu khảo sát cá nhân hóa (Component C)
  double? _dailyDistanceKm;
  String? _selectedUsagePurpose;
  double? _typicalSocWhenCharge;
  bool? _notificationOptIn;
  String? _shellySetupMessage;

  // Catalog xe
  List<VinFastModelSpec> _catalogSpecs = [];
  VinFastModelSpec? _selectedSpec;

  // Controllers cho thông tin phụ của xe
  final _nicknameCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _odoCtrl = TextEditingController();

  // Controller ngày sinh
  final _dobCtrl = TextEditingController();
  final _dobMaskFormatter = MaskTextInputFormatter(
    mask: '##/##/####',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );

  // Shelly status
  String _shellyStatus = 'skipped';

  // BatteryBot Mascot Interactive State
  Timer? _idleTimer;
  final math.Random _random = math.Random();
  BatteryBotMood _botMood = BatteryBotMood.greeting;
  String _botSpeech =
      'Chào bạn! Mình là BatteryBot ⚡. Hãy cùng mình thiết lập chiếc xe VinFast để tối ưu pin nhé!';

  @override
  void initState() {
    super.initState();
    _updateBotForStep(0);
    _initOnboardingFlow();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _nicknameCtrl.dispose();
    _plateCtrl.dispose();
    _odoCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() {
        _botMood = BatteryBotMood.thinking;
        _botSpeech = _getIdlePromptForStep(_currentStep);
      });
    });
  }

  void _updateBotForStep(int step) {
    _botMood = _getInitialMoodForStep(step);
    _botSpeech = _getInitialPromptForStep(step);
    _resetIdleTimer();
  }

  BatteryBotMood _getInitialMoodForStep(int step) {
    switch (step) {
      case 0:
        return BatteryBotMood.greeting;
      case 1:
        return BatteryBotMood.thinking;
      case 2:
        return BatteryBotMood.listening;
      case 3:
        return BatteryBotMood.thinking;
      case 4:
        return BatteryBotMood.listening;
      case 5:
        return BatteryBotMood.charging;
      case 6:
        return BatteryBotMood.charging;
      case 7:
        return BatteryBotMood.greeting;
      case 8:
        return BatteryBotMood.happy;
      default:
        return BatteryBotMood.idle;
    }
  }

  String _getInitialPromptForStep(int step) {
    const concise = <String>[
      'Mình sẽ giúp bạn thiết lập nhanh. Bắt đầu nhé?',
      'Chọn mẫu xe bạn đang sử dụng.',
      'Bạn có thể thêm biển số và ODO, hoặc bỏ qua.',
      'Ngày sinh là tùy chọn. Bạn có thể bỏ qua.',
      'Ước tính quãng đường mỗi ngày nếu bạn muốn.',
      'Chọn thói quen sạc phù hợp với bạn.',
      'Bạn có thể kết nối Shelly ngay hoặc làm sau trong Cài đặt.',
      'Bật thông báo để nhận nhắc nhở sạc, hoặc chọn Để sau.',
      'Kiểm tra lại thông tin rồi hoàn tất thiết lập.',
    ];
    if (step >= 0 && step < concise.length) return concise[step];
    switch (step) {
      case 0:
        return 'Yo! Mình là BatteryBot ⚡ — Trợ lý pin thông minh nhất vũ trụ! Cùng mình thiết lập chiếc xe VinFast để tối ưu pin nhé! 🚀';
      case 1:
        return 'Woa, xe VinFast à? Khẩu vị sang và chuẩn gu lắm nè! Bạn đang cưỡi chiến mã nào thế? Chọn ngay nha 🛵';
      case 2:
        if (_selectedSpec != null) {
          return 'Tuyệt cú mèo! Chiếc ${_selectedSpec!.modelName} này lái thích mê! Cho mình xin biển số & ODO để AI tính toán pin siêu chuẩn xác nhé! ⚡';
        }
        return 'Cho mình xin thêm biển số & ODO để AI tính toán mức tiêu hao pin chuẩn từng km nhé! ⚡';
      case 3:
        return 'À quên, sinh nhật bạn ngày nào nhỉ? Mình muốn chuẩn bị lời chúc đúng ngày và đảm bảo bạn đủ tuổi lái xe an toàn (≥16 tuổi) nè 🎂';
      case 4:
        return 'Hằng ngày bạn phi bao xa thế? Kéo thanh trượt để mình tính toán tầm hoạt động và gợi ý lịch sạc chuẩn như chuyên gia 📊';
      case 5:
        return 'Đi làm hay đi chơi nhiều hơn? Còn bao nhiêu % pin thì bạn thường cắm sạc? Chia sẻ nhỏ để bảo vệ cell pin LFP nhé! 🔋';
      case 6:
        return 'Sạc thông minh Shelly nè! Tự ngắt khi đạt mức pin mong muốn, tiết kiệm điện và chống chai pin tuyệt đối. Thử xem nào 🔌';
      case 7:
        return 'Cho mình xin phép nhắc bạn khi pin đầy nhé? Hứa là chỉ báo tin quan trọng, không bao giờ spam bạn đâu! 🔔';
      case 8:
        return 'Hoàn hảo không tì vết! Mọi thông số của xế yêu đã sẵn sàng. Bấm Hoàn tất để lên đường thôi bạn ơi! 🎉';
      default:
        return 'Cứ thong thả nhé, mình luôn ở đây sẵn sàng hỗ trợ bạn bất cứ lúc nào! ⚡';
    }
  }

  String _getIdlePromptForStep(int step) {
    const concise = <String>[
      'Khi sẵn sàng, chọn Bắt đầu.',
      'Hãy chọn một mẫu xe để tiếp tục.',
      'Các thông tin chi tiết có thể bổ sung sau.',
      'Bạn có thể bỏ qua ngày sinh.',
      'Kéo thanh chọn để ước tính quãng đường.',
      'Chọn một mục hoặc bỏ qua bước này.',
      'Bạn có thể thiết lập Shelly sau trong Cài đặt.',
      'Chỉ bật thông báo khi bạn muốn nhận nhắc nhở.',
      'Chọn Hoàn tất để vào ứng dụng.',
    ];
    if (step >= 0 && step < concise.length) return concise[step];
    switch (step) {
      case 0:
        return 'Sẵn sàng chưa bạn ơi? Chạm vào "Bắt đầu" để chúng mình cùng khám phá buồng lái nhé! 🚀';
      case 1:
        return 'Chưa thấy xế cưng của bạn? Cứ cuộn xuống tìm hoặc chọn phiên bản tương đương, mình đều xử lý ngon lành! 🛵';
      case 2:
        return 'Nếu không nhớ chính xác số ODO, cứ ước lượng gần đúng nha. AI thông minh sẽ tự học và hiệu chỉnh dần nè! 💡';
      case 3:
        return 'Nhập ngày sinh theo mẫu Ngày/Tháng/Năm (ví dụ 15/08/1998) nha bạn. Mọi dữ liệu đều được bảo mật tuyệt đối! 🛡️';
      case 4:
        return 'Di chuyển quanh phố thường tầm 15-30km. Bạn kéo thanh trượt ước lượng nhé! 🛣️';
      case 5:
        return 'Mẹo vàng từ BatteryBot: Sạc trong khoảng 20% - 80% là bí quyết giúp pin LFP bền bỉ suốt 10 năm đấy! ✨';
      case 6:
        return 'Chưa có sẵn cục sạc Shelly ở đây? Đừng ngại bấm "Bỏ qua", bạn có thể ghép nối bất cứ lúc nào trong Cài đặt! 🔌';
      case 7:
        return 'Bật thông báo sẽ giúp bạn an tâm ngủ ngon giấc mà không phải bận tâm canh giờ rút sạc! 💤';
      case 8:
        return 'Chỉ còn đúng 1 chạm nữa thôi! Bấm "Hoàn tất" để chúng mình đồng hành trên mọi cung đường nào! 🏁';
      default:
        return 'Đang phân vân điều gì hả bạn? Cứ chạm vào mình bất cứ lúc nào để hỏi nhé! 😊';
    }
  }

  void _onBotTapped() {
    HapticFeedback.lightImpact();
    const conciseRemarks = <String>[
      'Mình ở đây nếu bạn cần trợ giúp.',
      'Bạn có thể quay lại bước trước bất cứ lúc nào.',
      'Mình chỉ hướng dẫn, không tự điều khiển thiết bị.',
    ];
    setState(() {
      _botMood = BatteryBotMood.happy;
      _botSpeech = conciseRemarks[_random.nextInt(conciseRemarks.length)];
    });
    _resetIdleTimer();
  }

  /// Khởi tạo dữ liệu từ server & tự động kiểm tra trường đã có
  Future<void> _initOnboardingFlow() async {
    final generation = ++_initialLoadGeneration;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _initialLoadError = null;
      });
    }
    try {
      await _loadOnboardingData().timeout(_initialLoadTimeout);
      if (!mounted || generation != _initialLoadGeneration) return;
      setState(() => _isLoading = false);
    } on TimeoutException {
      if (!mounted || generation != _initialLoadGeneration) return;
      setState(() {
        _isLoading = false;
        _initialLoadError =
            'Việc tải thông tin đang mất nhiều thời gian. Hãy kiểm tra mạng và thử lại.';
      });
    } catch (error) {
      debugPrint('[Onboarding] initial load failed (${error.runtimeType})');
      if (!mounted || generation != _initialLoadGeneration) return;
      setState(() {
        _isLoading = false;
        _initialLoadError =
            'Chưa thể tải thông tin thiết lập. Vui lòng thử lại.';
      });
    }
  }

  Future<void> _loadOnboardingData() async {
    final onboardingService = ref.read(onboardingServiceProvider);

    final currentUser = AuthService().currentUser;
    if (currentUser != null) {
      _draft = await onboardingService.loadDraft(currentUser.uid);
      if (!mounted) return;
      if (_draft != null) {
        _userName = _draft!.name;
        _userPhone = _draft!.phone;
        _dateOfBirth = _draft!.dateOfBirth;
        _dailyDistanceKm = _draft!.avgDailyDistanceKm;
        _selectedUsagePurpose = _draft!.usagePurpose;
        _typicalSocWhenCharge = _draft!.typicalSocWhenCharge;
        _nicknameCtrl.text = _draft!.nickname ?? '';
        _plateCtrl.text = _draft!.licensePlate ?? '';
        _odoCtrl.text = _draft!.initialOdo?.toString() ?? '';
        _shellyStatus = _draft!.shellyStatus;
        _dobCtrl.text = _draft!.dateOfBirth ?? '';
        if (_draft!.state == OnboardingDraftState.failedPermanent) {
          AppPopup.showWarning(
            'Cần cập nhật thông tin thiết lập',
            detail:
                _draft!.lastErrorMessage ??
                'Thông tin đã lưu không còn hợp lệ.',
            userInitiated: false,
          );
        }
      }
    }

    // 1. Tải catalog xe song song
    _loadCatalog();

    // 2. Lấy thông tin tài khoản hiện có
    var status = await onboardingService.fetchOnboardingStatus();
    if (!mounted) return;
    if (status == null) {
      final user = AuthService().currentUser;
      await onboardingService.bootstrapRegistration(
        name: user?.displayName ?? '',
      );
      if (!mounted) return;
      status = await onboardingService.fetchOnboardingStatus();
      if (!mounted) return;
    }

    if (status != null) {
      _userName = status.name.trim();
      _userPhone = status.phone.isNotEmpty ? status.phone.trim() : null;

      if (status.dateOfBirth != null && status.dateOfBirth!.isNotEmpty) {
        _dateOfBirth = OnboardingService.toDisplayDateFormat(
          status.dateOfBirth,
        );
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
  }

  bool _catalogLoadFailed = false;
  bool _catalogIsLoading = true;

  Future<void> _loadCatalog() async {
    if (mounted) {
      setState(() {
        _catalogIsLoading = true;
        _catalogLoadFailed = false;
      });
    }
    try {
      final specs = await VehicleSpecRepository().getAllSpecs();
      if (mounted) {
        setState(() {
          _catalogSpecs = specs.where((s) => s.selectable).toList();
          _catalogIsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _catalogIsLoading = false;
          _catalogLoadFailed = true;
        });
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
        final odoText = _odoCtrl.text.trim();
        return (_nicknameCtrl.text.trim().isNotEmpty ||
                _plateCtrl.text.trim().isNotEmpty ||
                odoText.isNotEmpty) &&
            (odoText.isEmpty ||
                (int.tryParse(odoText) != null &&
                    int.parse(odoText) <= 9999999));
      case 3:
        final dob = _dobCtrl.text.trim();
        return dob.isNotEmpty &&
            OnboardingService.validateDateOfBirth(dob) == null;
      case 4:
        return _dailyDistanceKm != null;
      case 5:
        return _selectedUsagePurpose != null || _typicalSocWhenCharge != null;
      case 6:
        return true;
      case 7:
        return _notificationOptIn != null;
      case 8:
        return true;
      default:
        return true;
    }
  }

  void _nextStep() {
    if (_isSubmitting || !_canContinueCurrentStep()) return;
    FocusManager.instance.primaryFocus?.unfocus();
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
      _goToStepOrSkip(8);
    } else if (_currentStep == 8) {
      _finishOnboarding();
    }
  }

  void _handleSubmitDailyDistance() {
    _updateDraftAndPersist(avgDailyDistanceKm: _dailyDistanceKm);
    _goToStepOrSkip(5);
  }

  void _handleSubmitUsagePurpose() {
    _updateDraftAndPersist(
      avgDailyDistanceKm: _dailyDistanceKm,
      usagePurpose: _selectedUsagePurpose,
      typicalSocWhenCharge: _typicalSocWhenCharge,
    );
    _goToStepOrSkip(6);
  }

  void _skipUsageSurvey() {
    _selectedUsagePurpose = null;
    _typicalSocWhenCharge = null;
    _updateDraftAndPersist(usagePurpose: null, typicalSocWhenCharge: null);
    _goToStepOrSkip(6);
  }

  void _prevStep() {
    if (_currentStep <= 0) return;
    FocusManager.instance.primaryFocus?.unfocus();
    int prev = _currentStep - 1;
    // Bỏ qua các bước đã có dữ liệu khi back
    if (prev == 3 && _hadExistingDob) prev--;
    if ((prev == 2 || prev == 1) &&
        _createdVehicleId != null &&
        _createdVehicleId!.isNotEmpty) {
      prev = 0;
    }
    final clampedPrev = prev.clamp(0, _totalSteps - 1);
    _updateBotForStep(clampedPrev);
    setState(() {
      _movingForward = false;
      _currentStep = clampedPrev;
    });
  }

  void _goToStepOrSkip(int targetStep) {
    if (!mounted) return;
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
    FocusManager.instance.primaryFocus?.unfocus();
    final clampedNext = next.clamp(0, _totalSteps - 1);
    _updateBotForStep(clampedNext);
    setState(() {
      _movingForward = clampedNext >= _currentStep;
      _currentStep = clampedNext;
    });
  }

  Future<void> _updateDraftAndPersist({
    Object? dateOfBirth = _unchanged,
    Object? avgDailyDistanceKm = _unchanged,
    Object? usagePurpose = _unchanged,
    Object? typicalSocWhenCharge = _unchanged,
  }) async {
    final draft = _draft;
    if (draft == null) return;
    _draft = draft.copyWith(
      revision: draft.revision + 1,
      dateOfBirth: identical(dateOfBirth, _unchanged)
          ? _dateOfBirth
          : dateOfBirth as String?,
      avgDailyDistanceKm: identical(avgDailyDistanceKm, _unchanged)
          ? _dailyDistanceKm
          : avgDailyDistanceKm as double?,
      usagePurpose: identical(usagePurpose, _unchanged)
          ? _selectedUsagePurpose
          : usagePurpose as String?,
      typicalSocWhenCharge: identical(typicalSocWhenCharge, _unchanged)
          ? _typicalSocWhenCharge
          : typicalSocWhenCharge as double?,
      updatedAt: DateTime.now().toUtc(),
    );
    final snapshot = _draft!;
    _pendingDraftWrite = _pendingDraftWrite.then((_) async {
      if (AuthService().currentUser?.uid != snapshot.uid) return;
      await ref.read(onboardingServiceProvider).saveDraft(snapshot);
    });
    await _pendingDraftWrite;
  }

  Future<ApiResult<Map<String, dynamic>>> _commitDraft() async {
    final draft = _draft;
    if (draft == null || !draft.isEligibleForCommit) {
      return const ApiResult(
        success: false,
        code: 'DRAFT_MISSING',
        userMessage: 'Chưa có thông tin thiết lập.',
        retryable: false,
      );
    }
    if (AuthService().currentUser?.uid != draft.uid) {
      return const ApiResult(
        success: false,
        code: 'ACCOUNT_CHANGED',
        userMessage: 'Phiên đăng nhập đã thay đổi. Vui lòng thử lại.',
        retryable: false,
      );
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
    if (AuthService().currentUser?.uid != syncing.uid) {
      return const ApiResult(
        success: false,
        code: 'ACCOUNT_CHANGED',
        userMessage: 'Phiên đăng nhập đã thay đổi. Vui lòng thử lại.',
        retryable: false,
      );
    }
    final result = await service.commitDraft(syncing);
    if (AuthService().currentUser?.uid != syncing.uid) return result;
    var confirmedResult = result;
    if (result.success) {
      // A 2xx response is not enough to discard the durable draft. Read the
      // authoritative profile/vehicle state first so a lost response or a
      // partial transaction can be retried without trapping the user in the
      // wizard.
      final confirmation = await service.fetchOnboardingStatus();
      if (confirmation?.isCompleted != true ||
          confirmation?.hasVehicle != true) {
        confirmedResult = const ApiResult(
          success: false,
          code: 'COMMIT_VERIFICATION_PENDING',
          userMessage:
              'Đang xác minh dữ liệu đã lưu. Bạn có thể tiếp tục vào ứng dụng.',
          retryable: true,
        );
      }
    }
    if (confirmedResult.success) {
      _draft = syncing.copyWith(
        state: OnboardingDraftState.synced,
        updatedAt: DateTime.now().toUtc(),
      );
      await service.clearDraft(syncing.uid);
    } else {
      final nextState = confirmedResult.retryable
          ? OnboardingDraftState.failedRetryable
          : OnboardingDraftState.failedPermanent;
      _draft = syncing.copyWith(
        state: nextState,
        lastErrorCode: confirmedResult.code,
        lastErrorMessage: confirmedResult.userMessage,
        nextAttemptAt: confirmedResult.retryable
            ? DateTime.now().toUtc().add(const Duration(seconds: 30))
            : null,
        updatedAt: DateTime.now().toUtc(),
      );
      await service.saveDraft(_draft!);
    }
    return confirmedResult;
  }

  /// Tạo xe cục bộ trước, sau đó đồng bộ server bằng operation idempotent.
  Future<void> _handleCreateVehicle({required bool skipDetails}) async {
    if (_selectedSpec == null) {
      _goToStepOrSkip(_hadExistingDob ? 4 : 3);
      return;
    }

    final nickname = skipDetails ? null : _nicknameCtrl.text.trim();
    final plate = skipDetails ? null : _plateCtrl.text.trim();
    final odoText = skipDetails ? '' : _odoCtrl.text.trim();
    final odo = skipDetails || odoText.isEmpty ? null : int.tryParse(odoText);
    if (!skipDetails &&
        odoText.isNotEmpty &&
        (odo == null || odo < 0 || odo > 9999999)) {
      return;
    }

    final user = AuthService().currentUser;
    final uid = user?.uid ?? (kDebugMode ? 'debug-preview-user' : null);
    if (uid == null) return;
    _draft ??= OnboardingDraft.create(
      uid: uid,
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
    await _pendingDraftWrite;
    await ref.read(onboardingServiceProvider).saveDraft(_draft!);
    if (!mounted) return;
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
      builder: (context, child) =>
          Theme(data: LuxeTheme.of(context), child: child!),
    );

    if (picked != null && mounted) {
      final formatted = DateFormat('dd/MM/yyyy').format(picked);
      setState(() {
        _dobCtrl.text = formatted;
        _dateOfBirth = formatted;
      });
    }
  }

  /// Hoàn tất Onboarding và khởi động Cockpit
  Future<void> _finishOnboarding() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await _pendingDraftWrite;
      if (!mounted) return;

      if (_draft != null) {
        _draft = _draft!.copyWith(
          shellyStatus: _shellyStatus,
          finalizedAt: DateTime.now().toUtc(),
          revision: _draft!.revision + 1,
          updatedAt: DateTime.now().toUtc(),
        );
        await ref.read(onboardingServiceProvider).saveDraft(_draft!);
      }
      final result = await _commitDraft();
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (result.success || result.retryable) {
        // AuthGate is already the root route. Ask that existing gate to reload
        // the durable draft/profile instead of pushing another AuthGate or
        // calling popUntil on a screen that is not itself a Navigator route.
        final onCompleted = widget.onCompleted;
        if (onCompleted != null) {
          onCompleted();
        } else {
          final navigator = Navigator.of(context, rootNavigator: true);
          navigator.popUntil((route) => route.isFirst);
        }
      } else {
        AppPopup.showError(result.userMessage ?? 'Không thể hoàn tất.');
      }
    } catch (error) {
      debugPrint('[Onboarding] completion deferred (${error.runtimeType})');
      if (mounted) {
        AppPopup.showError(
          'Chưa thể lưu thông tin. Vui lòng thử lại; các câu trả lời vẫn được giữ.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _chooseNotifications(bool enable) async {
    if (!enable) {
      _notificationOptIn = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pushNotifications', false);
      if (mounted) setState(() {});
      return;
    }
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    var granted = false;
    try {
      granted = await PushNotificationService.instance
          .requestPermissionFromUser()
          .timeout(_permissionDecisionTimeout);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pushNotifications', granted);
      if (granted) {
        await PushNotificationService.instance.initialize().timeout(
          _notificationSetupTimeout,
        );
      }
    } on TimeoutException {
      // A system permission sheet or token sync must not keep this step
      // loading indefinitely. If permission was granted before token setup
      // timed out, the stored opt-in remains true and sync can retry later.
      debugPrint('[Onboarding] push setup deferred (timeout)');
      if (!granted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('pushNotifications', false);
      }
    } catch (error) {
      debugPrint('[Onboarding] push setup deferred (${error.runtimeType})');
      granted = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pushNotifications', false);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _notificationOptIn = granted;
        });
      }
    }
  }

  Future<void> _openShellySetup() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const SmartChargerSetupHubScreen(),
      ),
    );
    final snapshot = await ShellyConnectionCoordinator.shared.restore();
    if (!mounted) return;
    if (snapshot.state == ShellyConnectionFlowState.connected) {
      setState(() {
        _shellyStatus = 'connected';
        _shellySetupMessage = 'Shelly đã được xác minh an toàn.';
      });
    } else {
      setState(() {
        _shellyStatus = 'skipped';
        _shellySetupMessage =
            'Chưa hoàn tất kết nối. Bạn có thể thiết lập sau.';
      });
    }
  }

  // Presentation is deliberately separate from draft and safety operations.
  @override
  Widget build(BuildContext context) {
    if (_initialLoadError != null || _isLoading) {
      final failed = _initialLoadError != null;
      return Theme(
        data: LuxeTheme.of(context),
        child: Scaffold(
          backgroundColor: LuxeColors.background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              const LuxeBackdrop(accent: 0.5),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (failed)
                            const Icon(
                              Icons.cloud_off_rounded,
                              size: 40,
                              color: LuxeColors.platinumMid,
                            )
                          else
                            const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: LuxeColors.platinum,
                              ),
                            ),
                          const SizedBox(height: 18),
                          Text(
                            failed
                                ? _initialLoadError!
                                : 'Đang tải thông tin thiết lập',
                            textAlign: TextAlign.center,
                            style: LuxeText.body,
                          ),
                          if (failed) ...[
                            const SizedBox(height: 22),
                            FilledButton.icon(
                              onPressed: _initOnboardingFlow,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Thử lại'),
                            ),
                          ],
                        ],
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
    return OnboardingStepFrame(
      step: _currentStep,
      forward: _movingForward,
      submitting: _isSubmitting,
      botMood: _botMood,
      botSpeech: _botSpeech,
      onBotTap: _onBotTapped,
      onBack: _currentStep > 0 && !_isSubmitting ? _prevStep : null,
      onContinue: !_isSubmitting && _canContinueCurrentStep()
          ? _nextStep
          : null,
      child: _buildCurrentStepContent(),
    );
  }

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
        return _buildStep7Notifications();
      case 8:
        return _buildStep8Summary();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep0Welcome() {
    const chapters = [
      (
        '01',
        'Chọn mẫu xe',
        'Thông số từ danh mục giúp hiển thị thông tin pin của xe.',
      ),
      (
        '02',
        'Bổ sung khi thuận tiện',
        'Bạn có thể bỏ qua câu hỏi phụ và thiết lập bộ sạc sau.',
      ),
      (
        '03',
        'Kiểm tra trước khi lưu',
        'Xem lại các lựa chọn ở bước cuối để hoàn tất thiết lập.',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeGlass(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 18,
                color: LuxeColors.emerald,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Khoảng 2 phút · phần lớn câu hỏi có thể bỏ qua',
                  style: LuxeText.caption,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < chapters.length; i++)
          LuxeReveal(
            index: 3 + i,
            child: _chapter(
              chapters[i].$1,
              chapters[i].$2,
              chapters[i].$3,
              last: i == chapters.length - 1,
            ),
          ),
      ],
    );
  }

  Widget _chapter(
    String numeral,
    String title,
    String description, {
    bool last = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: LuxeColors.hairline)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 46,
          child: LuxeMetalText(
            numeral,
            style: const TextStyle(
              fontSize: 24,
              height: 1.0,
              fontWeight: FontWeight.w200,
              letterSpacing: -0.5,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: LuxeText.item),
              const SizedBox(height: 4),
              Text(description, style: LuxeText.caption),
            ],
          ),
        ),
      ],
    ),
  );

  /// Icon medallion + copy on glass, for informational rows.
  Widget _plainInfo(IconData icon, String title, String description) {
    return LuxeGlass(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _medallion(icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: LuxeText.item),
                const SizedBox(height: 4),
                Text(description, style: LuxeText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _medallion(IconData icon, {bool active = false, double size = 44}) =>
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.4),
            colors: active
                ? const [Color(0x4434D399), Color(0x1434D399)]
                : const [Color(0x24FFFFFF), Color(0x08FFFFFF)],
          ),
          border: Border.all(
            color: active
                ? LuxeColors.emerald.withValues(alpha: 0.6)
                : LuxeColors.hairlineStrong,
          ),
        ),
        child: ExcludeSemantics(
          child: Icon(
            icon,
            size: size * 0.48,
            color: active ? LuxeColors.emerald : LuxeColors.platinum,
          ),
        ),
      );

  Widget _buildStep1VehiclePicker() {
    if (_catalogIsLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: LuxeColors.platinum,
              semanticsLabel: 'Đang tải danh sách xe',
            ),
          ),
        ),
      );
    }
    if (_catalogLoadFailed || _catalogSpecs.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _catalogLoadFailed
                ? 'Chưa tải được danh sách xe. Kiểm tra kết nối rồi thử lại.'
                : 'Chưa có mẫu xe để chọn. Thử tải lại danh sách.',
            style: LuxeText.body,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loadCatalog,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Thử lại'),
          ),
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _catalogSpecs.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: LuxeReveal(
              index: 3 + i,
              child: OnboardingVehicleChoice(
                spec: _catalogSpecs[i],
                selected: _selectedSpec?.modelId == _catalogSpecs[i].modelId,
                onSelected: () {
                  final spec = _catalogSpecs[i];
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedSpec = spec;
                    _botMood = BatteryBotMood.happy;
                    _botSpeech =
                        '${spec.modelName}, lựa chọn tuyệt vời. Bấm Tiếp tục nhé.';
                  });
                  _resetIdleTimer();
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStep2VehicleDetails() {
    final odo = _odoCtrl.text.trim();
    final odoInvalid =
        odo.isNotEmpty &&
        (int.tryParse(odo) == null || int.parse(odo) > 9999999);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              color: LuxeColors.glass,
              border: Border.all(color: LuxeColors.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.electric_scooter_outlined,
                  size: 16,
                  color: LuxeColors.emerald,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _selectedSpec?.modelName ?? 'Thông tin xe',
                    style: LuxeText.label.copyWith(color: LuxeColors.text),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildInputField(
          controller: _nicknameCtrl,
          label: 'Tên gợi nhớ',
          hint: 'Ví dụ: Xe đi làm',
          icon: Icons.edit_note_rounded,
        ),
        const SizedBox(height: 14),
        _buildInputField(
          controller: _plateCtrl,
          label: 'Biển số',
          hint: 'Ví dụ: 29-X1 123.45',
          icon: Icons.credit_card_rounded,
        ),
        const SizedBox(height: 14),
        _buildInputField(
          controller: _odoCtrl,
          label: 'Số km đã đi (ODO)',
          hint: 'Nhập số km trên đồng hồ xe',
          icon: Icons.speed_rounded,
          suffixText: 'km',
          errorText: odoInvalid ? 'Nhập số km từ 0 đến 9.999.999.' : null,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 12),
        _skipButton(() => _handleCreateVehicle(skipDetails: true)),
      ],
    );
  }

  Widget _buildStep3Dob() {
    final text = _dobCtrl.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _dobCtrl,
          inputFormatters: [_dobMaskFormatter],
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          scrollPadding: const EdgeInsets.all(24),
          style: const TextStyle(
            color: LuxeColors.text,
            fontSize: 17,
            letterSpacing: 1.2,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            labelText: 'Ngày sinh',
            hintText: 'dd/mm/yyyy',
            helperText: 'Nếu cung cấp, bạn cần đủ 16 tuổi.',
            helperMaxLines: 3,
            errorText: text.isNotEmpty
                ? OnboardingService.validateDateOfBirth(text)
                : null,
            errorMaxLines: 3,
            prefixIcon: const Icon(Icons.cake_outlined),
            suffixIcon: IconButton(
              onPressed: _pickDateOfBirth,
              tooltip: 'Chọn ngày sinh trên lịch',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.calendar_month_rounded),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _skipButton(_skipDob),
      ],
    );
  }

  String _distanceSpeech(double km) => km <= 15
      ? 'Đi lại nhẹ nhàng (${km.toInt()} km/ngày). Pin đủ cho nhiều ngày mới cần sạc.'
      : km <= 40
      ? 'Quãng đường lý tưởng (${km.toInt()} km/ngày). Khoảng 2-3 ngày sạc một lần là đẹp nhất.'
      : 'Di chuyển nhiều (${km.toInt()} km/ngày). Ứng dụng sẽ ưu tiên tầm vận hành cho bạn.';

  BatteryBotMood _distanceMood(double km) => km <= 15
      ? BatteryBotMood.happy
      : km <= 40
      ? BatteryBotMood.listening
      : BatteryBotMood.charging;

  void _setDistance(double km) {
    setState(() {
      _dailyDistanceKm = km;
      _botSpeech = _distanceSpeech(km);
      _botMood = _distanceMood(km);
    });
    _resetIdleTimer();
  }

  /// Large platinum readout that rolls between values.
  Widget _readout({
    required double? value,
    required String unit,
    required String empty,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (value == null)
          const Text(
            '—',
            style: TextStyle(
              color: LuxeColors.dim,
              fontSize: 56,
              height: 1.0,
              fontWeight: FontWeight.w200,
            ),
          )
        else
          TweenAnimationBuilder<double>(
            tween: Tween(end: value),
            duration: AppMotion.durationFor(
              context,
              const Duration(milliseconds: 420),
            ),
            curve: LuxeMotion.enter,
            builder: (context, v, _) => LuxeMetalText(
              '${v.round()}',
              style: const TextStyle(
                fontSize: 56,
                height: 1.0,
                fontWeight: FontWeight.w200,
                letterSpacing: -1.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value == null ? empty : unit,
            style: LuxeText.body.copyWith(
              color: value == null ? LuxeColors.dim : LuxeColors.muted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep4DailyDistance() {
    final value = _dailyDistanceKm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: _readout(
            value: value,
            unit: 'km mỗi ngày',
            empty: 'Chưa chọn quãng đường',
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Chạm một mức gợi ý hoặc kéo thanh để chọn.',
          style: LuxeText.caption,
        ),
        const SizedBox(height: 6),
        Semantics(
          label: 'Quãng đường mỗi ngày',
          value: value == null ? 'Chưa chọn' : '${value.toInt()} km',
          child: Slider(
            value: value ?? 20,
            min: 5,
            max: 100,
            divisions: 19,
            label: value == null ? 'Chưa chọn' : '${value.toInt()} km',
            semanticFormatterCallback: (value) =>
                '${value.toInt()} km mỗi ngày',
            onChanged: (value) {
              if (value != _dailyDistanceKm) HapticFeedback.selectionClick();
              _setDistance(value);
            },
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final km in [5.0, 15.0, 30.0, 50.0, 80.0])
              ChoiceChip(
                label: Text('${km.toInt()} km'),
                selected: value != null && (value - km).abs() < 2.5,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  _setDistance(km);
                },
                materialTapTargetSize: MaterialTapTargetSize.padded,
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _skipButton(() {
          _dailyDistanceKm = null;
          _updateDraftAndPersist(avgDailyDistanceKm: null);
          _goToStepOrSkip(5);
        }),
      ],
    );
  }

  Widget _buildStep5UsagePurpose() {
    const purposes = [
      (
        id: 'commute',
        title: 'Đi làm',
        detail: 'Đi lại hằng ngày',
        icon: Icons.work_outline_rounded,
      ),
      (
        id: 'delivery',
        title: 'Giao hàng / Chạy xe',
        detail: 'Dùng xe cho công việc di chuyển',
        icon: Icons.local_shipping_outlined,
      ),
      (
        id: 'leisure',
        title: 'Đi lại cá nhân',
        detail: 'Mua sắm, gặp gỡ hoặc dạo phố',
        icon: Icons.two_wheeler_rounded,
      ),
    ];
    final soc = _typicalSocWhenCharge;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('MỤC ĐÍCH CHÍNH', style: LuxeText.eyebrow),
        const SizedBox(height: 12),
        for (var i = 0; i < purposes.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: LuxeReveal(
              index: 3 + i,
              child: _purposeCard(
                purposes[i].id,
                purposes[i].title,
                purposes[i].detail,
                purposes[i].icon,
              ),
            ),
          ),
        const SizedBox(height: 18),
        const Text('MỨC PIN KHI BẮT ĐẦU SẠC', style: LuxeText.eyebrow),
        const SizedBox(height: 4),
        const Text(
          'Mức pin khi bạn thường bắt đầu sạc',
          style: LuxeText.caption,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: _readout(
                  value: soc,
                  unit: '%',
                  empty: 'Chưa chọn mức pin',
                ),
              ),
            ),
            ExcludeSemantics(child: _MiniCell(level: (soc ?? 0) / 100)),
          ],
        ),
        Semantics(
          label: 'Mức pin khi bắt đầu sạc',
          value: soc == null ? 'Chưa chọn' : '${soc.toInt()}%',
          child: Slider(
            value: soc ?? 20,
            min: 10,
            max: 60,
            divisions: 10,
            label: soc == null ? 'Chưa chọn' : '${soc.toInt()}%',
            semanticFormatterCallback: (value) => '${value.toInt()} phần trăm',
            onChanged: (value) {
              if (value != _typicalSocWhenCharge) {
                HapticFeedback.selectionClick();
              }
              setState(() {
                _typicalSocWhenCharge = value;
                if (value >= 20 && value <= 30) {
                  _botSpeech =
                      'Khoảng ${value.toInt()}% là mức lý tưởng để bắt đầu sạc, giúp pin bền hơn.';
                  _botMood = BatteryBotMood.happy;
                } else if (value < 20) {
                  _botSpeech =
                      'Còn ${value.toInt()}% mới sạc: nhớ cắm sạc sớm, tránh để pin dưới 10%.';
                  _botMood = BatteryBotMood.listening;
                } else {
                  _botSpeech =
                      'Cắm sạc từ ${value.toInt()}%: xe luôn sẵn sàng cho mọi hành trình.';
                  _botMood = BatteryBotMood.charging;
                }
              });
              _resetIdleTimer();
            },
          ),
        ),
        const Text(
          'Bạn có thể trả lời một trong hai câu hỏi hoặc bỏ qua.',
          style: LuxeText.caption,
        ),
        const SizedBox(height: 12),
        _skipButton(_skipUsageSurvey),
      ],
    );
  }

  Widget _purposeCard(String id, String title, String detail, IconData icon) {
    final selected = _selectedUsagePurpose == id;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          splashColor: const Color(0x1434D399),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _selectedUsagePurpose = id;
              if (id == 'commute') {
                _botSpeech =
                    'Đi làm hằng ngày: lộ trình ổn định giúp ứng dụng hiểu thói quen sạc của bạn.';
                _botMood = BatteryBotMood.happy;
              } else if (id == 'delivery') {
                _botSpeech =
                    'Chạy xe dịch vụ, giao hàng: hẹn giờ sạc giúp xe luôn sẵn sàng lăn bánh.';
                _botMood = BatteryBotMood.charging;
              } else {
                _botSpeech =
                    'Đi lại cá nhân: tận hưởng những chuyến đi êm ái cùng xe điện VinFast.';
                _botMood = BatteryBotMood.greeting;
              }
            });
            _resetIdleTimer();
          },
          child: LuxeGlass(
            selected: selected,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _medallion(icon, active: selected, size: 42),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: LuxeText.item),
                      const SizedBox(height: 2),
                      Text(detail, style: LuxeText.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _LuxeCheck(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep6Shelly() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _plainInfo(
          Icons.power_outlined,
          'Thiết lập bộ sạc',
          'Ứng dụng sẽ hướng dẫn kiểm tra kết nối và an toàn. Chỉ điều khiển sau khi thiết bị được xác minh.',
        ),
        const SizedBox(height: 10),
        _plainInfo(
          Icons.timer_outlined,
          'Tự ngắt bằng bộ đếm phần cứng',
          'Hẹn giờ được nạp vào rơ-le, an toàn kể cả khi điện thoại mất mạng.',
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _isSubmitting ? null : _openShellySetup,
          icon: const Icon(Icons.settings_input_component_outlined, size: 18),
          label: const Text('Thiết lập ngay', textAlign: TextAlign.center),
        ),
        if (_shellySetupMessage != null) ...[
          const SizedBox(height: 12),
          Text(_shellySetupMessage!, style: LuxeText.body),
        ],
        const SizedBox(height: 6),
        _skipButton(() {
          HapticFeedback.selectionClick();
          setState(() => _shellyStatus = 'skipped');
          _nextStep();
        }, label: 'Để sau'),
      ],
    );
  }

  Widget _buildStep7Notifications() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _plainInfo(
          Icons.battery_charging_full_outlined,
          'Theo dõi trạng thái sạc',
          'Nhận thông báo khi có cập nhật từ phiên sạc.',
        ),
        const SizedBox(height: 10),
        _plainInfo(
          Icons.build_outlined,
          'Nhắc nhở bảo dưỡng',
          'Nhận lời nhắc theo thiết lập của bạn.',
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _isSubmitting ? null : () => _chooseNotifications(true),
          icon: const Icon(Icons.notifications_active_outlined, size: 18),
          label: const Text('Bật thông báo', textAlign: TextAlign.center),
        ),
        const SizedBox(height: 6),
        _skipButton(() => _chooseNotifications(false), label: 'Để sau'),
        if (_notificationOptIn != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _notificationOptIn!
                      ? Icons.check_circle_rounded
                      : Icons.info_outline_rounded,
                  size: 18,
                  color: _notificationOptIn!
                      ? LuxeColors.emerald
                      : LuxeColors.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _notificationOptIn!
                        ? 'Thông báo đã được cho phép.'
                        : 'Thông báo chưa bật. Bạn vẫn có thể tiếp tục và bật lại trong Cài đặt.',
                    style: LuxeText.body,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStep8Summary() {
    final spec = _selectedSpec;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeReveal(
          index: 3,
          child: _summaryGroup('Xe', [
            _buildSummaryRow(
              label: 'Mẫu xe',
              value:
                  spec?.modelName ??
                  (_createdVehicleId != null
                      ? 'Đã lưu trong hồ sơ'
                      : 'Chưa chọn'),
            ),
            _buildSummaryRow(
              label: 'Dung lượng theo danh mục',
              value: spec == null
                  ? 'Chưa có dữ liệu'
                  : '${(spec.nominalCapacityWh / 1000).toStringAsFixed(1)} kWh',
            ),
            _buildSummaryRow(
              label: 'Tên gợi nhớ',
              value: _provided(
                _draft != null ? _draft!.nickname : _nicknameCtrl.text,
              ),
            ),
            _buildSummaryRow(
              label: 'Biển số',
              value: _provided(
                _draft != null ? _draft!.licensePlate : _plateCtrl.text,
              ),
            ),
            _buildSummaryRow(
              label: 'Số km đã đi',
              value: _draft?.initialOdo == null
                  ? 'Chưa cung cấp'
                  : '${_draft!.initialOdo} km',
            ),
          ]),
        ),
        const SizedBox(height: 12),
        LuxeReveal(
          index: 4,
          child: _summaryGroup('Thông tin sử dụng', [
            _buildSummaryRow(
              label: 'Ngày sinh',
              value: _provided(_dateOfBirth),
            ),
            _buildSummaryRow(
              label: 'Quãng đường mỗi ngày',
              value: _dailyDistanceKm == null
                  ? 'Chưa cung cấp'
                  : '${_dailyDistanceKm!.toInt()} km/ngày',
            ),
            _buildSummaryRow(
              label: 'Mục đích chính',
              value: _getUsagePurposeName(_selectedUsagePurpose),
            ),
            _buildSummaryRow(
              label: 'Mức pin khi bắt đầu sạc',
              value: _typicalSocWhenCharge == null
                  ? 'Chưa cung cấp'
                  : '${_typicalSocWhenCharge!.toInt()}%',
            ),
          ]),
        ),
        const SizedBox(height: 12),
        LuxeReveal(
          index: 5,
          child: _summaryGroup('Kết nối và thông báo', [
            _buildSummaryRow(
              label: 'Bộ sạc Shelly',
              value: _shellyStatus == 'connected'
                  ? 'Đã xác minh trong thiết lập'
                  : 'Chưa thiết lập',
            ),
            _buildSummaryRow(
              label: 'Thông báo',
              value: _notificationOptIn == true ? 'Đã cho phép' : 'Để sau',
            ),
          ]),
        ),
        const SizedBox(height: 16),
        const Text(
          'Chọn Hoàn tất để lưu thông tin. Nếu chưa đồng bộ được, ứng dụng sẽ thông báo trạng thái thực tế.',
          style: LuxeText.caption,
        ),
      ],
    );
  }

  String _provided(String? text) =>
      text == null || text.trim().isEmpty ? 'Chưa cung cấp' : text.trim();

  String _getUsagePurposeName(String? id) => switch (id) {
    'commute' => 'Đi làm',
    'delivery' => 'Giao hàng / Chạy xe',
    'leisure' => 'Đi lại cá nhân',
    _ => 'Chưa cung cấp',
  };

  Widget _summaryGroup(String title, List<Widget> rows) => LuxeGlass(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title.toUpperCase(), style: LuxeText.eyebrow),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          rows[i],
        ],
      ],
    ),
  );

  Widget _buildSummaryRow({required String label, required String value}) {
    final missing =
        value == 'Chưa cung cấp' ||
        value == 'Chưa thiết lập' ||
        value == 'Chưa chọn' ||
        value == 'Chưa có dữ liệu' ||
        value == 'Để sau';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          Text(label, style: LuxeText.caption),
          Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: missing ? LuxeColors.dim : LuxeColors.text,
              fontSize: 14,
              fontWeight: missing ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? suffixText,
    String? errorText,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
      inputFormatters: inputFormatters,
      onChanged: (_) => setState(() {}),
      scrollPadding: const EdgeInsets.all(24),
      style: const TextStyle(color: LuxeColors.text, fontSize: 15.5),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffixText,
        prefixIcon: Icon(icon),
        errorText: errorText,
        errorMaxLines: 3,
      ),
    );
  }

  Widget _skipButton(VoidCallback action, {String label = 'Bỏ qua bước này'}) {
    return TextButton(
      onPressed: _isSubmitting ? null : action,
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

/// Radio-style check that scales in, matching the vehicle choice.
class _LuxeCheck extends StatelessWidget {
  const _LuxeCheck({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.durationFor(
      context,
      const Duration(milliseconds: 260),
    );
    return AnimatedContainer(
      duration: duration,
      curve: LuxeMotion.enter,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? LuxeColors.emerald : Colors.transparent,
        border: Border.all(
          color: selected ? LuxeColors.emerald : LuxeColors.hairlineStrong,
          width: 1.5,
        ),
      ),
      child: AnimatedScale(
        scale: selected ? 1 : 0,
        duration: duration,
        curve: Curves.easeOutBack,
        child: const Icon(
          Icons.check_rounded,
          size: 14,
          color: Color(0xFF04140D),
        ),
      ),
    );
  }
}

/// Small battery cell that fills to the chosen start-of-charge level.
class _MiniCell extends StatelessWidget {
  const _MiniCell({required this.level});
  final double level;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: level),
    duration: AppMotion.durationFor(context, const Duration(milliseconds: 420)),
    curve: LuxeMotion.enter,
    builder: (context, v, _) =>
        CustomPaint(size: const Size(26, 46), painter: _MiniCellPainter(v)),
  );
}

class _MiniCellPainter extends CustomPainter {
  _MiniCellPainter(this.level);
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromLTRBR(
      0,
      5,
      size.width,
      size.height,
      const Radius.circular(6),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
        size.width * 0.32,
        0,
        size.width * 0.68,
        5,
        const Radius.circular(2),
      ),
      Paint()..color = LuxeColors.platinumMid,
    );
    final inner = body.deflate(3);
    final h = inner.height * level.clamp(0.0, 1.0);
    if (h > 0) {
      final low = level < 0.2;
      canvas.drawRRect(
        RRect.fromLTRBR(
          inner.left,
          inner.bottom - h,
          inner.right,
          inner.bottom,
          const Radius.circular(3),
        ),
        Paint()..color = low ? const Color(0xFFFBBF24) : LuxeColors.emerald,
      );
    }
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = LuxeColors.platinum,
    );
  }

  @override
  bool shouldRepaint(_MiniCellPainter old) => old.level != level;
}

/// Content metadata only: validation and persistence stay in the screen state.
class OnboardingStepCopy {
  final String title;
  final String description;
  final bool optional;
  const OnboardingStepCopy(
    this.title,
    this.description, {
    this.optional = false,
  });

  static const steps = [
    OnboardingStepCopy(
      'Thiết lập xe của bạn',
      'Chọn xe để theo dõi pin và sạc. Các câu hỏi phụ có thể để sau.',
    ),
    OnboardingStepCopy(
      'Bạn đang dùng mẫu xe nào?',
      'Chọn đúng mẫu xe trong danh mục. Đây là thông tin bắt buộc.',
    ),
    OnboardingStepCopy(
      'Phân biệt xe của bạn',
      'Các thông tin dưới đây đều tùy chọn. Nhập ít nhất một mục để tiếp tục, hoặc bỏ qua.',
      optional: true,
    ),
    OnboardingStepCopy(
      'Ngày sinh của bạn',
      'Bổ sung ngày sinh vào hồ sơ nếu bạn muốn.',
      optional: true,
    ),
    OnboardingStepCopy(
      'Mỗi ngày bạn thường đi bao xa?',
      'Chọn quãng đường gần với thói quen của bạn.',
      optional: true,
    ),
    OnboardingStepCopy(
      'Bạn thường sử dụng xe thế nào?',
      'Thông tin giúp ghi nhận thói quen sử dụng của bạn.',
      optional: true,
    ),
    OnboardingStepCopy(
      'Kết nối bộ sạc Shelly',
      'Bạn có thể thiết lập ngay hoặc mở lại từ Cài đặt.',
      optional: true,
    ),
    OnboardingStepCopy(
      'Bạn muốn nhận thông báo?',
      'Chỉ hỏi quyền hệ thống khi bạn chọn Bật thông báo.',
      optional: true,
    ),
    OnboardingStepCopy(
      'Kiểm tra trước khi hoàn tất',
      'Thông tin bỏ qua được ghi là Chưa cung cấp, không thay bằng câu trả lời mặc định.',
    ),
  ];
}

/// Stateless layout used by the real wizard and widget tests, without Firebase.
class OnboardingStepFrame extends StatelessWidget {
  const OnboardingStepFrame({
    super.key,
    required this.step,
    required this.child,
    required this.onContinue,
    this.onBack,
    this.submitting = false,
    this.forward = true,
    this.botMood,
    this.botSpeech,
    this.onBotTap,
  });

  final int step;
  final Widget child;
  final VoidCallback? onContinue;
  final VoidCallback? onBack;
  final bool submitting;
  final bool forward;
  final BatteryBotMood? botMood;
  final String? botSpeech;
  final VoidCallback? onBotTap;

  static final _emoji = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]',
    unicode: true,
  );

  /// The assistant speaks in a calm voice here: no emoji, single spaces.
  static String cleanSpeech(String text) =>
      text.replaceAll(_emoji, '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

  @override
  Widget build(BuildContext context) {
    final copy = OnboardingStepCopy.steps[step];
    final total = OnboardingStepCopy.steps.length;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = AppMotion.durationFor(
      context,
      const Duration(milliseconds: 220),
    );
    final kind = copy.optional
        ? 'Tùy chọn'
        : step == 1
        ? 'Bắt buộc'
        : 'Thiết lập';
    final progress = (step + 1) / total;

    return Theme(
      data: LuxeTheme.of(context),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: LuxeColors.background,
        ),
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: LuxeColors.background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              LuxeBackdrop(accent: 0.5 + 0.5 * progress),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      children: [
                        // ── Header: step label + continuous energy line ──
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                liveRegion: true,
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Bước ${step + 1}',
                                        style: const TextStyle(
                                          color: LuxeColors.text,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      TextSpan(text: '/$total'),
                                      const TextSpan(text: ' · '),
                                      TextSpan(
                                        text: kind,
                                        style: TextStyle(
                                          color: copy.optional
                                              ? LuxeColors.muted
                                              : LuxeColors.emerald,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  style: LuxeText.label,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ExcludeSemantics(
                                child: _EnergyLine(
                                  progress: progress,
                                  steps: total,
                                  animate: !reduced,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!keyboardOpen) _buildBotDock(context),
                        // ── Step content: one shared-axis transition ──
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: duration,
                            switchInCurve: LuxeMotion.enter,
                            switchOutCurve: AppMotion.exit,
                            layoutBuilder: (current, previous) => Stack(
                              alignment: Alignment.topCenter,
                              children: [
                                for (final child in previous)
                                  IgnorePointer(
                                    child: ExcludeSemantics(child: child),
                                  ),
                                ?current,
                              ],
                            ),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: AnimatedBuilder(
                                    animation: animation,
                                    child: child,
                                    builder: (context, child) =>
                                        Transform.translate(
                                          offset: Offset(
                                            (forward ? 28 : -28) *
                                                (1 - animation.value),
                                            0,
                                          ),
                                          child: child,
                                        ),
                                  ),
                                ),
                            child: SingleChildScrollView(
                              key: ValueKey('onboarding-step-$step'),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                              child: FocusTraversalGroup(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    LuxeReveal(
                                      child: Semantics(
                                        header: true,
                                        child: Text(
                                          copy.title,
                                          style: LuxeText.title,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    LuxeReveal(
                                      index: 1,
                                      child: Text(
                                        copy.description,
                                        style: LuxeText.body,
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                    LuxeReveal(index: 2, child: child),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // ── Actions ──
                        DecoratedBox(
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Color(0x0FFFFFFF)),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                            child: Row(
                              children: [
                                if (step > 0) ...[
                                  IconButton.outlined(
                                    onPressed: submitting ? null : onBack,
                                    tooltip: 'Quay lại bước trước',
                                    constraints: const BoxConstraints(
                                      minWidth: 52,
                                      minHeight: 52,
                                    ),
                                    style: IconButton.styleFrom(
                                      side: const BorderSide(
                                        color: LuxeColors.hairlineStrong,
                                      ),
                                      backgroundColor: LuxeColors.glass,
                                    ),
                                    icon: const Icon(
                                      Icons.arrow_back_rounded,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: FilledButton(
                                    onPressed: submitting ? null : onContinue,
                                    child: submitting
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: LuxeColors.platinum,
                                              semanticsLabel:
                                                  'Đang lưu thông tin',
                                            ),
                                          )
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  step == 8
                                                      ? 'Hoàn tất'
                                                      : step == 0
                                                      ? 'Bắt đầu thiết lập'
                                                      : 'Tiếp tục',
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Icon(
                                                step == 8
                                                    ? Icons.check_rounded
                                                    : Icons
                                                          .arrow_forward_rounded,
                                                size: 18,
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBotDock(BuildContext context) {
    final raw = botSpeech?.trim();
    final speech = cleanSpeech(
      raw == null || raw.isEmpty ? 'Mình sẽ hướng dẫn từng bước.' : raw,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Semantics(
        container: true,
        label: 'BatteryBot: $speech',
        button: onBotTap != null,
        child: GestureDetector(
          onTap: onBotTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                colors: [Color(0x14FFFFFF), Color(0x06FFFFFF)],
              ),
              border: Border.all(color: LuxeColors.hairline),
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: BatteryBotMascot(
                    size: BatteryBotSize.avatar,
                    displayMode: BatteryBotDisplayMode.avatar,
                    enableFloating: true,
                    mood: botMood ?? BatteryBotMood.idle,
                    onTap: onBotTap,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ExcludeSemantics(
                    // New lines fade in; no second AnimatedSwitcher here.
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(speech),
                      tween: Tween(begin: 0, end: 1),
                      duration: AppMotion.durationFor(
                        context,
                        const Duration(milliseconds: 320),
                      ),
                      curve: Curves.easeOut,
                      builder: (context, t, child) => Opacity(
                        opacity: t,
                        child: Transform.translate(
                          offset: Offset(6 * (1 - t), 0),
                          child: child,
                        ),
                      ),
                      child: Text(
                        speech,
                        maxLines: 2,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(
                          color: LuxeColors.platinum,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Continuous progress: a hairline track with an emerald → platinum fill,
/// a glowing head and faint step ticks.
class _EnergyLine extends StatelessWidget {
  const _EnergyLine({
    required this.progress,
    required this.steps,
    required this.animate,
  });

  final double progress;
  final int steps;
  final bool animate;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: progress),
    duration: animate ? const Duration(milliseconds: 700) : Duration.zero,
    curve: LuxeMotion.enter,
    builder: (context, value, _) => SizedBox(
      height: 8,
      width: double.infinity,
      child: CustomPaint(
        painter: _EnergyLinePainter(value: value, steps: steps),
      ),
    ),
  );
}

class _EnergyLinePainter extends CustomPainter {
  _EnergyLinePainter({required this.value, required this.steps});
  final double value;
  final int steps;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final track = RRect.fromLTRBR(
      0,
      y - 1.5,
      size.width,
      y + 1.5,
      const Radius.circular(2),
    );
    canvas.drawRRect(track, Paint()..color = const Color(0x1AFFFFFF));
    for (var i = 1; i < steps; i++) {
      final x = size.width * i / steps;
      canvas.drawCircle(
        Offset(x, y),
        1.2,
        Paint()..color = const Color(0x33FFFFFF),
      );
    }
    final w = size.width * value.clamp(0.0, 1.0);
    if (w <= 0) return;
    final fill = RRect.fromLTRBR(
      0,
      y - 1.5,
      w,
      y + 1.5,
      const Radius.circular(2),
    );
    canvas.drawRRect(
      fill,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            LuxeColors.emeraldDeep,
            LuxeColors.emerald,
            LuxeColors.platinumHi,
          ],
          stops: [0.0, 0.85, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, size.height)),
    );
    canvas.drawCircle(
      Offset(w, y),
      5,
      Paint()
        ..color = LuxeColors.emerald.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      Offset(w, y),
      2.4,
      Paint()..color = LuxeColors.platinumHi,
    );
  }

  @override
  bool shouldRepaint(_EnergyLinePainter old) =>
      old.value != value || old.steps != steps;
}

class OnboardingVehicleChoice extends StatelessWidget {
  const OnboardingVehicleChoice({
    super.key,
    required this.spec,
    required this.selected,
    required this.onSelected,
  });
  final VinFastModelSpec spec;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final image = spec.imageUrl?.trim();
    final duration = AppMotion.durationFor(
      context,
      const Duration(milliseconds: 260),
    );
    final fallback = Icon(
      Icons.electric_scooter_outlined,
      color: selected ? LuxeColors.emerald : LuxeColors.platinumMid,
      size: 28,
    );

    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          splashColor: const Color(0x1434D399),
          highlightColor: const Color(0x0AFFFFFF),
          onTap: () {
            HapticFeedback.selectionClick();
            onSelected();
          },
          child: LuxeGlass(
            selected: selected,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const RadialGradient(
                      center: Alignment(0, -0.3),
                      colors: [Color(0x1FFFFFFF), Color(0x05FFFFFF)],
                    ),
                    border: Border.all(color: LuxeColors.hairline),
                  ),
                  child: image == null || image.isEmpty
                      ? fallback
                      : ExcludeSemantics(
                          child: Image.network(
                            image,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => fallback,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(spec.modelName, style: LuxeText.item),
                      const SizedBox(height: 4),
                      AnimatedDefaultTextStyle(
                        duration: duration,
                        style: LuxeText.caption.copyWith(
                          color: selected
                              ? LuxeColors.emerald
                              : LuxeColors.muted,
                        ),
                        child: Text(
                          '${(spec.nominalCapacityWh / 1000).toStringAsFixed(1)} kWh · Theo danh mục',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: duration,
                  curve: LuxeMotion.enter,
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? LuxeColors.emerald : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? LuxeColors.emerald
                          : LuxeColors.hairlineStrong,
                      width: 1.5,
                    ),
                    boxShadow: selected
                        ? const [
                            BoxShadow(
                              color: LuxeColors.emeraldGlow,
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  child: AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: duration,
                    curve: Curves.easeOutBack,
                    child: const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Color(0xFF04140D),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
