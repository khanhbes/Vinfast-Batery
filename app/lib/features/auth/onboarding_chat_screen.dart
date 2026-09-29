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
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/battery_bot_mascot.dart';
import '../../data/models/vinfast_model_spec.dart';
import '../../data/repositories/vehicle_spec_repository.dart';
import 'auth_gate.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';

/// Onboarding keeps the existing draft/validation contract in a calm step UI.
class OnboardingChatScreen extends ConsumerStatefulWidget {
  const OnboardingChatScreen({super.key});

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

    if (mounted) {
      setState(() => _isLoading = false);
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
    setState(() {
      _movingForward = false;
      _currentStep = prev.clamp(0, _totalSteps - 1);
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
    setState(() {
      _movingForward = next >= _currentStep;
      _currentStep = next.clamp(0, _totalSteps - 1);
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
    if (result.success) {
      _draft = syncing.copyWith(
        state: OnboardingDraftState.synced,
        updatedAt: DateTime.now().toUtc(),
      );
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
    final odoText = skipDetails ? '' : _odoCtrl.text.trim();
    final odo = skipDetails || odoText.isEmpty ? null : int.tryParse(odoText);
    if (!skipDetails &&
        odoText.isNotEmpty &&
        (odo == null || odo < 0 || odo > 9999999)) {
      return;
    }

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
      final navigator = Navigator.of(context, rootNavigator: true);
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } else {
      AppPopup.showError(result.userMessage ?? 'Không thể hoàn tất.');
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
    setState(() => _isSubmitting = true);
    var granted = false;
    try {
      granted = await PushNotificationService.instance
          .requestPermissionFromUser();
    } catch (_) {
      granted = false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pushNotifications', granted);
    if (granted) {
      await PushNotificationService.instance.initialize();
      await PushNotificationService.instance.syncCurrentUser();
    }
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _notificationOptIn = granted;
    });
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
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Đang tải thông tin thiết lập',
                style: Theme.of(context).textTheme.bodyMedium,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _plainInfo(
          Icons.electric_scooter_outlined,
          'Chọn mẫu xe',
          'Thông số từ danh mục giúp hiển thị thông tin pin của xe.',
        ),
        const SizedBox(height: 20),
        _plainInfo(
          Icons.tune_rounded,
          'Bổ sung khi thuận tiện',
          'Bạn có thể bỏ qua câu hỏi phụ và thiết lập bộ sạc sau.',
        ),
        const SizedBox(height: 20),
        _plainInfo(
          Icons.fact_check_outlined,
          'Kiểm tra trước khi lưu',
          'Xem lại các lựa chọn ở bước cuối để hoàn tất thiết lập.',
        ),
      ],
    );
  }

  Widget _plainInfo(IconData icon, String title, String description) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(icon, color: theme.colorScheme.primary)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(description, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep1VehiclePicker() {
    if (_catalogIsLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Đang tải danh sách xe',
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
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loadCatalog,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Thử lại'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
        ],
      );
    }
    return Column(
      children: [
        for (final spec in _catalogSpecs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OnboardingVehicleChoice(
              spec: spec,
              selected: _selectedSpec?.modelId == spec.modelId,
              onSelected: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedSpec = spec);
              },
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
        Text(
          _selectedSpec?.modelName ?? 'Thông tin xe',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 20),
        _buildInputField(
          controller: _nicknameCtrl,
          label: 'Tên gợi nhớ',
          hint: 'Ví dụ: Xe đi làm',
          icon: Icons.edit_note_rounded,
        ),
        const SizedBox(height: 16),
        _buildInputField(
          controller: _plateCtrl,
          label: 'Biển số',
          hint: 'Ví dụ: 29-X1 123.45',
          icon: Icons.credit_card_rounded,
        ),
        const SizedBox(height: 16),
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
        const SizedBox(height: 16),
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
        const SizedBox(height: 16),
        _skipButton(_skipDob),
      ],
    );
  }

  Widget _buildStep4DailyDistance() {
    final value = _dailyDistanceKm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          value == null ? 'Chưa chọn quãng đường' : '${value.toInt()} km/ngày',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Chạm một mức gợi ý hoặc kéo thanh để chọn.'),
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
            onChanged: (value) => setState(() => _dailyDistanceKm = value),
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
                onSelected: (_) => setState(() => _dailyDistanceKm = km),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                showCheckmark: true,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Mục đích chính', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final purpose in purposes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              selected: _selectedUsagePurpose == purpose.id,
              inMutuallyExclusiveGroup: true,
              child: ListTile(
                minVerticalPadding: 12,
                leading: Icon(purpose.icon),
                title: Text(purpose.title),
                subtitle: Text(purpose.detail),
                trailing: Icon(
                  _selectedUsagePurpose == purpose.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: _selectedUsagePurpose == purpose.id
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                tileColor: _selectedUsagePurpose == purpose.id
                    ? colors.primaryContainer
                    : colors.surfaceContainerLow,
                onTap: () => setState(() => _selectedUsagePurpose = purpose.id),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Mức pin khi bạn thường bắt đầu sạc',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          _typicalSocWhenCharge == null
              ? 'Chưa chọn mức pin'
              : '${_typicalSocWhenCharge!.toInt()}%',
        ),
        Semantics(
          label: 'Mức pin khi bắt đầu sạc',
          value: _typicalSocWhenCharge == null
              ? 'Chưa chọn'
              : '${_typicalSocWhenCharge!.toInt()}%',
          child: Slider(
            value: _typicalSocWhenCharge ?? 20,
            min: 10,
            max: 60,
            divisions: 10,
            label: _typicalSocWhenCharge == null
                ? 'Chưa chọn'
                : '${_typicalSocWhenCharge!.toInt()}%',
            semanticFormatterCallback: (value) => '${value.toInt()} phần trăm',
            onChanged: (value) => setState(() => _typicalSocWhenCharge = value),
          ),
        ),
        const Text('Bạn có thể trả lời một trong hai câu hỏi hoặc bỏ qua.'),
        const SizedBox(height: 16),
        _skipButton(_skipUsageSurvey),
      ],
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
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _isSubmitting ? null : _openShellySetup,
          icon: const Icon(Icons.settings_input_component_outlined),
          label: const Text('Thiết lập ngay', textAlign: TextAlign.center),
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        if (_shellySetupMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _shellySetupMessage!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 12),
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
        const SizedBox(height: 20),
        _plainInfo(
          Icons.build_outlined,
          'Nhắc nhở bảo dưỡng',
          'Nhận lời nhắc theo thiết lập của bạn.',
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _isSubmitting ? null : () => _chooseNotifications(true),
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('Bật thông báo', textAlign: TextAlign.center),
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        _skipButton(() => _chooseNotifications(false), label: 'Để sau'),
        if (_notificationOptIn != null)
          Text(
            _notificationOptIn!
                ? 'Thông báo đã được cho phép.'
                : 'Thông báo chưa bật. Bạn vẫn có thể tiếp tục và bật lại trong Cài đặt.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
      ],
    );
  }

  Widget _buildStep8Summary() {
    final spec = _selectedSpec;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summaryHeading('Xe'),
        _buildSummaryRow(
          label: 'Mẫu xe',
          value:
              spec?.modelName ??
              (_createdVehicleId != null ? 'Đã lưu trong hồ sơ' : 'Chưa chọn'),
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
        const Divider(height: 32),
        _summaryHeading('Thông tin sử dụng'),
        _buildSummaryRow(label: 'Ngày sinh', value: _provided(_dateOfBirth)),
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
        const Divider(height: 32),
        _summaryHeading('Kết nối và thông báo'),
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
        const SizedBox(height: 16),
        const Text(
          'Chọn Hoàn tất để lưu thông tin. Nếu chưa đồng bộ được, ứng dụng sẽ thông báo trạng thái thực tế.',
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

  Widget _summaryHeading(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _buildSummaryRow({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
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
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
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
  });

  final int step;
  final Widget child;
  final VoidCallback? onContinue;
  final VoidCallback? onBack;
  final bool submitting;
  final bool forward;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = OnboardingStepCopy.steps[step];
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final stepLabel = 'Bước ${step + 1}/${OnboardingStepCopy.steps.length}';
    final duration = AppMotion.durationFor(
      context,
      const Duration(milliseconds: 220),
    );
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          '$stepLabel · ${copy.optional
                              ? 'Tùy chọn'
                              : step == 1
                              ? 'Bắt buộc'
                              : 'Thiết lập'}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ExcludeSemantics(
                        child: LinearProgressIndicator(
                          value: (step + 1) / OnboardingStepCopy.steps.length,
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: AppMotion.enter,
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
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: AnimatedBuilder(
                          animation: animation,
                          child: child,
                          builder: (context, child) => Transform.translate(
                            offset: Offset(
                              (forward ? 8 : -8) * (1 - animation.value),
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
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        child: FocusTraversalGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!keyboardOpen) ...[
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: ExcludeSemantics(
                                    child: TickerMode(
                                      enabled: false,
                                      child: MediaQuery(
                                        data: MediaQuery.of(
                                          context,
                                        ).copyWith(disableAnimations: true),
                                        child: const BatteryBotMascot(
                                          size: BatteryBotSize.avatar,
                                          displayMode:
                                              BatteryBotDisplayMode.avatar,
                                          enableFloating: false,
                                          mood: BatteryBotMood.idle,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              Semantics(
                                header: true,
                                child: Text(
                                  copy.title,
                                  style: theme.textTheme.headlineSmall,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                copy.description,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 24),
                              child,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Row(
                    children: [
                      if (step > 0) ...[
                        IconButton.outlined(
                          onPressed: submitting ? null : onBack,
                          tooltip: 'Quay lại bước trước',
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: FilledButton(
                          onPressed: submitting ? null : onContinue,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          child: submitting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    semanticsLabel: 'Đang lưu thông tin',
                                  ),
                                )
                              : Text(
                                  step == 8
                                      ? 'Hoàn tất'
                                      : step == 0
                                      ? 'Bắt đầu thiết lập'
                                      : 'Tiếp tục',
                                  textAlign: TextAlign.center,
                                ),
                        ),
                      ),
                    ],
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
    final colors = Theme.of(context).colorScheme;
    final image = spec.imageUrl?.trim();
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: selected
            ? colors.primaryContainer
            : colors.surfaceContainerLow,
        leading: SizedBox(
          width: 48,
          height: 48,
          child: image == null || image.isEmpty
              ? const Icon(Icons.electric_scooter_outlined)
              : ExcludeSemantics(
                  child: Image.network(
                    image,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.electric_scooter_outlined),
                  ),
                ),
        ),
        title: Text(spec.modelName),
        subtitle: Text(
          '${(spec.nominalCapacityWh / 1000).toStringAsFixed(1)} kWh · Theo danh mục',
        ),
        trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? colors.primary : colors.onSurfaceVariant,
        ),
        onTap: onSelected,
      ),
    );
  }
}
