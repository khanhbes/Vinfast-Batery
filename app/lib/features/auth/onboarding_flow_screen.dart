import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/dashboard_preferences_service.dart';
import '../../core/services/guide_registry.dart';
import '../../core/services/onboarding_service.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/coach_mark_overlay.dart';
import '../../data/models/vinfast_model_spec.dart';
import '../../data/repositories/vehicle_spec_repository.dart';
import '../../navigation/app_navigation.dart';

/// Luồng Onboarding 5 bước bắt buộc cho tài khoản đăng ký mới (registrationFlowVersion >= 2)
class OnboardingFlowScreen extends ConsumerStatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  ConsumerState<OnboardingFlowScreen> createState() =>
      _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends ConsumerState<OnboardingFlowScreen> {
  int _currentStep = 0; // 0: Chào mừng, 1: Hồ sơ, 2: Chọn xe, 3: Shelly, 4: Xem lại
  bool _isLoading = false;

  // Step 1: Profile controllers
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  DateTime? _selectedDob;

  // Step 2: Vehicle selection
  List<VinFastModelSpec> _catalogSpecs = [];
  VinFastModelSpec? _selectedSpec;
  final _nicknameCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _odoCtrl = TextEditingController(text: '0');
  bool _loadingSpecs = true;
  String? _createdVehicleId;

  // Step 3: Shelly
  String _shellyStatus = 'skipped'; // 'connected' or 'skipped'

  @override
  void initState() {
    super.initState();
    _loadUserInitialData();
    _loadCatalog();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _dobCtrl.dispose();
    _nicknameCtrl.dispose();
    _plateCtrl.dispose();
    _odoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserInitialData() async {
    final service = ref.read(onboardingServiceProvider);
    var status = await service.fetchOnboardingStatus();
    if (status == null) {
      final user = AuthService().currentUser;
      await service.bootstrapRegistration(
        name: user?.displayName ?? '',
      );
      status = await service.fetchOnboardingStatus();
    }
    if (!mounted || status == null) return;
    final loadedStatus = status;
    if (mounted) {
      setState(() {
        if (loadedStatus.name.isNotEmpty) _nameCtrl.text = loadedStatus.name;
        if (loadedStatus.phone.isNotEmpty) _phoneCtrl.text = loadedStatus.phone;
        if (loadedStatus.dateOfBirth != null) {
          _dobCtrl.text = loadedStatus.dateOfBirth!;
          _selectedDob = DateTime.tryParse(loadedStatus.dateOfBirth!);
        }
        if (loadedStatus.hasVehicle && loadedStatus.vehicles.isNotEmpty) {
          _createdVehicleId = loadedStatus.vehicles.first['vehicleId']?.toString();
        }
      });
    }
  }

  Future<void> _loadCatalog() async {
    setState(() => _loadingSpecs = true);
    try {
      final specs = await VehicleSpecRepository().getAllSpecs();
      if (mounted) {
        setState(() {
          _catalogSpecs = specs.where((s) => s.selectable).toList();
          _loadingSpecs = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingSpecs = false);
    }
  }

  // ── Step Navigation Handlers ──────────────────────────────────────────────

  Future<void> _submitProfileStep() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      AppPopup.showError('Họ tên là bắt buộc để tiếp tục.');
      return;
    }

    final dobErr = OnboardingService.validateDateOfBirth(_dobCtrl.text);
    if (dobErr != null) {
      AppPopup.showError(dobErr);
      return;
    }

    setState(() => _isLoading = true);
    final res = await ref.read(onboardingServiceProvider).updateProfile(
          name: name,
          phone: _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
          dateOfBirth: _dobCtrl.text.trim().isNotEmpty ? _dobCtrl.text.trim() : null,
        );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      setState(() => _currentStep = 2);
    } else {
      AppPopup.showError(res['error']?.toString() ?? 'Không thể lưu hồ sơ.');
    }
  }

  Future<void> _submitVehicleStep() async {
    if (_createdVehicleId != null && _createdVehicleId!.isNotEmpty) {
      // Đã tạo xe trước đó
      setState(() => _currentStep = 3);
      return;
    }

    if (_selectedSpec == null) {
      AppPopup.showError('Vui lòng chọn ít nhất một xe từ danh mục.');
      return;
    }

    final odo = int.tryParse(_odoCtrl.text.trim()) ?? 0;
    if (odo < 0 || odo > 999999) {
      AppPopup.showError('Số ODO ban đầu không hợp lệ.');
      return;
    }

    setState(() => _isLoading = true);
    final res = await AuthService().addVehicle(
      catalogId: _selectedSpec!.modelId,
      nickname: _nicknameCtrl.text.trim().isNotEmpty ? _nicknameCtrl.text.trim() : null,
      licensePlate: _plateCtrl.text.trim().isNotEmpty ? _plateCtrl.text.trim() : null,
      initialOdo: odo,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      _createdVehicleId = res['vehicleId']?.toString();
      setState(() => _currentStep = 3);
    } else {
      AppPopup.showError(res['error']?.toString() ?? 'Không thể tạo xe. Vui lòng thử lại.');
    }
  }

  Future<void> _finishOnboarding() async {
    setState(() => _isLoading = true);
    final res = await ref.read(onboardingServiceProvider).completeOnboarding(
          shellyStatus: _shellyStatus,
        );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      // Điều hướng vào màn chính AppNavigation
      final navigator = Navigator.of(context, rootNavigator: true);
      final preferences = ref.read(dashboardPreferencesProvider);
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppNavigation()),
        (route) => false,
      );

      // Tự động khởi chạy Spotlight tour lần đầu sau khi frame render
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Chỉ chạy nếu chưa từng hoàn thành
        if (!preferences.isTourCompleted(GuideRegistry.overviewTourId)) {
          CoachMarkOverlay.show(
            context: navigator.context,
            steps: GuideRegistry.getOverviewTourSteps(),
            onFinish: () {
              preferences.markTourCompleted(GuideRegistry.overviewTourId);
            },
            onDontShowAgain: (dontShow) {
              if (dontShow) {
                preferences.markTourCompleted(GuideRegistry.overviewTourId);
              }
            },
          );
        }
      });
    } else {
      AppPopup.showError(res['error']?.toString() ?? 'Chưa hoàn tất được onboarding.');
    }
  }

  // ── UI Builders ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C1015), // Deep graphite EV cockpit
      body: SafeArea(
        child: Column(
          children: [
            _buildStepperHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 580),
                    child: _buildCurrentStepContent(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepperHeader() {
    final stepsTitle = ['Chào mừng', 'Hồ sơ', 'Chọn xe', 'Bộ sạc', 'Hoàn tất'];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF131821),
        border: Border(bottom: BorderSide(color: Color(0xFF222B38), width: 1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Thiết lập ban đầu • Bước ${_currentStep + 1}/5',
                style: const TextStyle(
                  color: Color(0xFF10B981),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                stepsTitle[_currentStep],
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: (_currentStep + 1) / 5,
            backgroundColor: Colors.white10,
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildWelcomeStep();
      case 1:
        return _buildProfileStep();
      case 2:
        return _buildVehicleStep();
      case 3:
        return _buildShellyStep();
      case 4:
        return _buildReviewStep();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Step 0: Welcome ───────────────────────────────────────────────────────
  Widget _buildWelcomeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
            ),
            child: const Icon(
              Icons.electric_moped_rounded,
              color: Color(0xFF10B981),
              size: 40,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Center(
          child: Text(
            'Chào mừng đến với EV Battery',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'Ứng dụng thông minh giám sát pin, quản lý sạc và tối ưu hành trình xe máy điện VinFast.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 32),

        // Data usage card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF161D27),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF263345)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Row(
                children: [
                  Icon(Icons.privacy_tip_outlined, color: Color(0xFF10B981), size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Cam kết quyền riêng tư & Dữ liệu',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                '• Dữ liệu pin & hành trình: chỉ dùng huấn luyện AI cá nhân hóa quãng đường của xe bạn.\n'
                '• Mật khẩu & kết nối sạc: lưu an toàn trong Secure Storage và Server Vault mã hóa.\n'
                '• Tuyệt đối không chia sẻ hoặc bán dữ liệu cho bên thứ ba.',
                style: TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 36),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => setState(() => _currentStep = 1),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: const Color(0xFF042F2E),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            child: const Text('Bắt đầu thiết lập'),
          ),
        ),
      ],
    );
  }

  // ── Step 1: Profile ───────────────────────────────────────────────────────
  Widget _buildProfileStep() {
    final age = OnboardingService.calculateAge(_dobCtrl.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hồ sơ của bạn',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Họ tên là bắt buộc. Số điện thoại và ngày sinh là tùy chọn.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
        ),
        const SizedBox(height: 24),

        // Name
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDeco(
            label: 'Họ và tên *',
            icon: Icons.person_rounded,
            hint: 'Ví dụ: Nguyễn Văn A',
          ),
        ),
        const SizedBox(height: 16),

        // Phone
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          style: const TextStyle(color: Colors.white),
          decoration: _inputDeco(
            label: 'Số điện thoại (tùy chọn)',
            icon: Icons.phone_rounded,
            hint: '09xxxxxxxx',
          ),
        ),
        const SizedBox(height: 16),

        // Date of Birth
        TextField(
          controller: _dobCtrl,
          readOnly: true,
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDob ?? DateTime(2000, 1, 1),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            );
            if (picked != null) {
              setState(() {
                _selectedDob = picked;
                _dobCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
              });
            }
          },
          style: const TextStyle(color: Colors.white),
          decoration: _inputDeco(
            label: 'Ngày sinh (YYYY-MM-DD, tùy chọn)',
            icon: Icons.cake_rounded,
            hint: 'Chọn ngày sinh',
            suffix: age != null
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$age tuổi',
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : null,
          ),
        ),

        const SizedBox(height: 36),
        _buildStepActionRow(
          onBack: () => setState(() => _currentStep = 0),
          onNext: _submitProfileStep,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  // ── Step 2: Vehicle Selection ─────────────────────────────────────────────
  Widget _buildVehicleStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Chọn xe ban đầu',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Chọn dòng xe từ Catalog chính thức để áp dụng thông số pin chuẩn.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
        ),
        const SizedBox(height: 20),

        if (_loadingSpecs)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: Color(0xFF10B981)),
            ),
          )
        else ...[
          // Spec selection dropdown / list
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF161D27),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF263345)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<VinFastModelSpec>(
                value: _selectedSpec,
                hint: const Text(
                  'Chọn mẫu xe VinFast *',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
                dropdownColor: const Color(0xFF1A222E),
                isExpanded: true,
                items: _catalogSpecs.map((s) {
                  return DropdownMenuItem<VinFastModelSpec>(
                    value: s,
                    child: Text(
                      '${s.modelName} ${s.variant} (${(s.nominalCapacityWh / 1000).toStringAsFixed(1)} kWh)',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _selectedSpec = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Nickname
          TextField(
            controller: _nicknameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDeco(
              label: 'Tên xe gợi nhớ (Nickname, tùy chọn)',
              icon: Icons.edit_note_rounded,
              hint: 'Ví dụ: Feliz Đi Làm',
            ),
          ),
          const SizedBox(height: 16),

          // License plate
          TextField(
            controller: _plateCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDeco(
              label: 'Biển số xe (tùy chọn)',
              icon: Icons.pin_rounded,
              hint: 'Ví dụ: 29A1-12345',
            ),
          ),
          const SizedBox(height: 16),

          // Initial ODO
          TextField(
            controller: _odoCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDeco(
              label: 'Số công tơ mét ODO ban đầu (km)',
              icon: Icons.speed_rounded,
              hint: '0',
            ),
          ),
        ],

        const SizedBox(height: 36),
        _buildStepActionRow(
          onBack: () => setState(() => _currentStep = 1),
          onNext: _submitVehicleStep,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  // ── Step 3: Shelly Setup ──────────────────────────────────────────────────
  Widget _buildShellyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bộ sạc thông minh Shelly',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Kết nối thiết bị Shelly để tự động bật/ngắt nguồn sạc và bảo vệ pin.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
        ),
        const SizedBox(height: 24),

        // Choice 1: Connect Shelly
        InkWell(
          onTap: () {
            setState(() => _shellyStatus = 'connected');
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF161D27),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _shellyStatus == 'connected'
                    ? const Color(0xFF10B981)
                    : const Color(0xFF263345),
                width: _shellyStatus == 'connected' ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.power_rounded,
                  color: _shellyStatus == 'connected'
                      ? const Color(0xFF10B981)
                      : Colors.white54,
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Tôi có bộ sạc Shelly',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Tự động đồng bộ và kích hoạt relay thông minh.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (_shellyStatus == 'connected')
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 22),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Choice 2: Skip for now
        InkWell(
          onTap: () {
            setState(() => _shellyStatus = 'skipped');
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF161D27),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _shellyStatus == 'skipped'
                    ? const Color(0xFF10B981)
                    : const Color(0xFF263345),
                width: _shellyStatus == 'skipped' ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  color: _shellyStatus == 'skipped'
                      ? const Color(0xFF10B981)
                      : Colors.white54,
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Thiết lập sau (Bỏ qua)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Vẫn sử dụng đầy đủ chức năng theo dõi pin và dự đoán AI.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (_shellyStatus == 'skipped')
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 22),
              ],
            ),
          ),
        ),

        const SizedBox(height: 36),
        _buildStepActionRow(
          onBack: () => setState(() => _currentStep = 2),
          onNext: () => setState(() => _currentStep = 4),
          isLoading: false,
        ),
      ],
    );
  }

  // ── Step 4: Review & Complete ─────────────────────────────────────────────
  Widget _buildReviewStep() {
    final age = OnboardingService.calculateAge(_dobCtrl.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Xem lại thông tin',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Xác nhận thông tin thiết lập để hoàn tất và vào ứng dụng.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
        ),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF161D27),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF263345)),
          ),
          child: Column(
            children: [
              _reviewRow('Họ và tên:', _nameCtrl.text),
              if (_phoneCtrl.text.isNotEmpty)
                _reviewRow('Số điện thoại:', _phoneCtrl.text),
              if (_dobCtrl.text.isNotEmpty)
                _reviewRow('Ngày sinh:', '${_dobCtrl.text}${age != null ? ' ($age tuổi)' : ''}'),
              const Divider(color: Color(0xFF263345), height: 24),
              _reviewRow(
                'Dòng xe:',
                _selectedSpec != null
                    ? '${_selectedSpec!.modelName} ${_selectedSpec!.variant}'
                    : 'Đã liên kết',
              ),
              if (_nicknameCtrl.text.isNotEmpty)
                _reviewRow('Tên gợi nhớ:', _nicknameCtrl.text),
              if (_plateCtrl.text.isNotEmpty)
                _reviewRow('Biển số:', _plateCtrl.text),
              const Divider(color: Color(0xFF263345), height: 24),
              _reviewRow(
                'Bộ sạc Shelly:',
                _shellyStatus == 'connected' ? 'Đã kích hoạt' : 'Thiết lập sau',
              ),
            ],
          ),
        ),

        const SizedBox(height: 36),
        _buildStepActionRow(
          onBack: () => setState(() => _currentStep = 3),
          onNext: _finishOnboarding,
          isLoading: _isLoading,
          nextLabel: 'Hoàn tất & Khám phá',
        ),
      ],
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepActionRow({
    required VoidCallback onBack,
    required VoidCallback onNext,
    required bool isLoading,
    String nextLabel = 'Tiếp tục',
  }) {
    return Row(
      children: [
        OutlinedButton(
          onPressed: onBack,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: const BorderSide(color: Color(0xFF2E3846)),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Quay lại'),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: FilledButton(
            onPressed: isLoading ? null : onNext,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: const Color(0xFF042F2E),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF042F2E)),
                  )
                : Text(nextLabel),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDeco({
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
      prefixIcon: Icon(icon, color: const Color(0xFF10B981), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFF161D27),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF263345)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF263345)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
      ),
    );
  }
}
