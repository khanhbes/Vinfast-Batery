import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/luxe_submit_button.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../core/services/auth_service.dart';
import '../../core/widgets/app_popup.dart';
import '../premium/plan_tag.dart';
import 'delete_account_sheet.dart';
import '../../core/theme/plan_style.dart';

/// Personal Information Screen — PLAN #3
/// Shows user profile from Firestore registration data
/// Allows editing name, phone, and changing password
/// QA 150: what stops a password change, or null.
String? passwordChangeProblem(String current, String next, String repeat) {
  if (current.isEmpty) return 'Nhập mật khẩu hiện tại.';
  if (next.length < 6) return 'Mật khẩu mới tối thiểu 6 ký tự.';
  if (next != repeat) return 'Hai lần nhập mật khẩu mới không khớp.';
  if (next == current) return 'Mật khẩu mới phải khác mật khẩu hiện tại.';
  return null;
}

/// QA 150: what is wrong with an edited name / phone, or null. Same rules as
/// registration; an empty phone stays allowed for accounts created without one.
/// QA 150: the stored birth date as dd/mm/yyyy (the survey saves either
/// that or yyyy-mm-dd); empty when there is none.
String birthDateText(Object? stored) {
  final value = stored is String ? stored.trim() : '';
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
  if (iso != null) return '${iso[3]}/${iso[2]}/${iso[1]}';
  return value;
}

String? profileInputProblem(String name, String phone) {
  if (name.trim().length < 2) return 'Vui lòng nhập họ tên (ít nhất 2 ký tự).';
  final value = phone.trim();
  if (value.isEmpty) return null;
  final digits = value.replaceAll(RegExp(r'[\s+().-]'), '');
  if (!RegExp(r'^\d{9,11}$').hasMatch(digits)) {
    return 'Số điện thoại cần 9 đến 11 chữ số.';
  }
  return null;
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  bool _isLoading = true;
  bool _isEditing = false;
  // ignore: unused_field
  bool _isSaving = false;

  // Profile data
  String _name = '';
  String _email = '';
  String _phone = '';
  String _birthDate = '';
  bool _emailUnverified = false;
  bool _sendingVerification = false;
  String _createdAt = '';
  String _source = '';

  // Edit controllers
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);

    try {
      final data = await _authService.getCurrentUserData();
      var user = FirebaseAuth.instance.currentUser;
      // QA 150: the owner may have tapped the link since the last visit.
      try {
        await user?.reload().timeout(const Duration(seconds: 5));
        user = FirebaseAuth.instance.currentUser;
      } on Object {
        // Offline: keep what the phone already knows.
      }

      if (!mounted) return;

      setState(() {
        _name = data?['name'] ?? user?.displayName ?? 'Chưa cập nhật';
        _email = data?['email'] ?? user?.email ?? '';
        _phone = data?['phone'] ?? '';
        _emailUnverified = user != null && !user.emailVerified;
        _birthDate = birthDateText(data?['dateOfBirth']);
        _source = data?['source'] ?? 'flutter_app';

        // Format createdAt
        final ts = data?['createdAt'];
        if (ts is Timestamp) {
          final dt = ts.toDate();
          _createdAt =
              '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        } else if (user?.metadata.creationTime != null) {
          final dt = user!.metadata.creationTime!;
          _createdAt =
              '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        } else {
          _createdAt = 'Không xác định';
        }

        _nameCtrl.text = _name;
        _phoneCtrl.text = _phone;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppPopup.showError('Không tải được thông tin', error: e);
      }
    }
  }

  Future<bool> _saveProfile() async {
    if (_isSaving) return false;
    // QA 150: the same rules as registration; an empty name and "12" as a
    // phone number were saved with "Đã cập nhật thông tin".
    final problem = profileInputProblem(_nameCtrl.text, _phoneCtrl.text);
    if (problem != null) {
      AppPopup.showMessage(problem, kind: AppNoticeKind.warning);
      return false;
    }
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Chưa đăng nhập');

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
            'name': _nameCtrl.text.trim(),
            'phone': _phoneCtrl.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      await user.updateDisplayName(_nameCtrl.text.trim());

      if (!mounted) return true;

      setState(() {
        _name = _nameCtrl.text.trim();
        _phone = _phoneCtrl.text.trim();
        _isSaving = false;
      });
      // The button shows its tick, then the form closes (QA 135).
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _isEditing = false);
      });
      AppPopup.showSuccess('Đã cập nhật thông tin');
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppPopup.showError('Chưa cập nhật được thông tin', error: e);
      }
      return false;
    }
  }

  void _showChangePasswordDialog() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    // QA 150: one typo in a single hidden field locked the owner out.
    final repeatCtrl = TextEditingController();
    bool loading = false;
    bool hidden = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return Theme(
          data: LuxeTheme.of(ctx),
          child: StatefulBuilder(
            builder: (ctx, setDialogState) {
              return Dialog(
                backgroundColor: LuxeColors.sheet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: const BorderSide(color: LuxeColors.hairline),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: LuxeMedallion(
                          icon: Icons.lock_reset_rounded,
                          accent: context.planAccent,
                          size: 52,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Đổi mật khẩu',
                        textAlign: TextAlign.center,
                        style: LuxeText.item,
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        key: const ValueKey('password-current'),
                        controller: currentCtrl,
                        obscureText: hidden,
                        decoration: InputDecoration(
                          labelText: 'Mật khẩu hiện tại',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            key: const ValueKey('password-show'),
                            tooltip: hidden ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                            onPressed: () =>
                                setDialogState(() => hidden = !hidden),
                            icon: Icon(
                              hidden
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('password-new'),
                        controller: newCtrl,
                        obscureText: hidden,
                        decoration: const InputDecoration(
                          labelText: 'Mật khẩu mới',
                          helperText: 'Tối thiểu 6 ký tự',
                          prefixIcon: Icon(Icons.key_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('password-repeat'),
                        controller: repeatCtrl,
                        obscureText: hidden,
                        decoration: const InputDecoration(
                          labelText: 'Nhập lại mật khẩu mới',
                          prefixIcon: Icon(Icons.key_rounded),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (loading)
                        Center(
                          child: SizedBox.square(
                            dimension: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.planAccent,
                            ),
                          ),
                        )
                      else ...[
                        FilledButton(
                          onPressed: () async {
                            final problem = passwordChangeProblem(
                              currentCtrl.text,
                              newCtrl.text,
                              repeatCtrl.text,
                            );
                            if (problem != null) {
                              AppPopup.showMessage(
                                problem,
                                kind: AppNoticeKind.warning,
                              );
                              return;
                            }
                            setDialogState(() => loading = true);
                            final result = await _authService.changePassword(
                              currentPassword: currentCtrl.text,
                              newPassword: newCtrl.text,
                            );
                            setDialogState(() => loading = false);
                            if (result['success'] == true) {
                              if (ctx.mounted) Navigator.pop(ctx);
                              AppPopup.showSuccess('Đổi mật khẩu thành công');
                            } else {
                              AppPopup.showError(
                                result['error'] ?? 'Đổi mật khẩu thất bại',
                              );
                            }
                          },
                          child: const Text('Xác nhận'),
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Hủy'),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _cancelEdit() => setState(() {
    _nameCtrl.text = _name;
    _phoneCtrl.text = _phone;
    _isEditing = false;
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: LuxeTheme.of(context),
      child: Scaffold(
        backgroundColor: LuxeColors.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const LuxeBackdrop(),
            SafeArea(
              child: _isLoading
                  ? Center(
                      child: SizedBox.square(
                        dimension: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.planAccent,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                      children: [
                        LuxePageHeader(
                          title: 'Thông tin cá nhân',
                          eyebrow: 'Tài khoản',
                          trailing: TextButton.icon(
                            onPressed: _isSaving
                                ? null
                                : () {
                                    // QA 150: two Save buttons; the header
                                    // one now leaves edit mode.
                                    if (_isEditing) {
                                      _cancelEdit();
                                    } else {
                                      setState(() => _isEditing = true);
                                    }
                                  },
                            style: TextButton.styleFrom(
                              foregroundColor: context.planAccent,
                            ),
                            icon: Icon(
                              _isEditing
                                  ? Icons.close_rounded
                                  : Icons.edit_rounded,
                              size: 18,
                            ),
                            label: Text(_isEditing ? 'Hủy' : 'Sửa'),
                          ),
                        ),
                        const SizedBox(height: 22),
                        LuxeReveal(child: _buildAvatarSection()),
                        const LuxeSectionLabel('Thông tin cơ bản'),
                        LuxeReveal(index: 1, child: _buildInfoSection()),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 320),
                          curve: LuxeMotion.enter,
                          child: _isEditing
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: _isSaving
                                              ? null
                                              : _cancelEdit,
                                          child: const Text('Hủy'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: LuxeSubmitButton(
                                          key: const ValueKey('profile-save'),
                                          label: 'Lưu thay đổi',
                                          busyLabel: 'Đang lưu…',
                                          onPressed: _saveProfile,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                        const LuxeSectionLabel('Bảo mật'),
                        LuxeReveal(index: 2, child: _buildSecuritySection()),
                        const LuxeSectionLabel('Thông tin tài khoản'),
                        LuxeReveal(index: 3, child: _buildMetaSection()),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    final initials = _name.isNotEmpty
        ? _name
              .split(' ')
              .map((w) => w.isNotEmpty ? w[0] : '')
              .take(2)
              .join()
              .toUpperCase()
        : '?';

    return Column(
      children: [
        Container(
          width: 108,
          height: 108,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                LuxeColors.platinumHi,
                LuxeColors.platinumLow,
                context.planAccent,
                LuxeColors.platinumLow,
                LuxeColors.platinumHi,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: context.planAccent.withValues(alpha: 0.13),
                blurRadius: 28,
              ),
            ],
          ),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A2C30), LuxeColors.shell],
              ),
            ),
            alignment: Alignment.center,
            child: LuxeMetalText(
              initials,
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w300),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: LuxeColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(_email, textAlign: TextAlign.center, style: LuxeText.caption),
        const SizedBox(height: 4),
        const CurrentPlanTag(key: ValueKey('profile-plan-tag'), large: true),
      ],
    );
  }

  Widget _buildInfoSection() => LuxeSettingsGroup(
    children: [
      _buildInfoRow(
        icon: Icons.person_outline_rounded,
        label: 'Họ và tên',
        value: _name,
        isEditing: _isEditing,
        controller: _nameCtrl,
      ),
      _buildInfoRow(
        icon: Icons.alternate_email_rounded,
        label: 'Email',
        value: _email,
        isEditing: false, // Email not editable
      ),
      _buildInfoRow(
        icon: Icons.phone_rounded,
        label: 'Số điện thoại',
        value: _phone.isEmpty ? 'Chưa cập nhật' : _phone,
        isEditing: _isEditing,
        controller: _phoneCtrl,
        keyboardType: TextInputType.phone,
      ),
      // QA 150: the survey asks for it (minimum age); show what is stored.
      if (_birthDate.isNotEmpty)
        _buildInfoRow(
          icon: Icons.cake_rounded,
          label: 'Ngày sinh',
          value: _birthDate,
        ),
    ],
  );

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool isEditing = false,
    TextEditingController? controller,
    TextInputType? keyboardType,
  }) {
    final editing = isEditing && controller != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      child: Row(
        children: [
          LuxeMedallion(
            icon: icon,
            accent: editing ? context.planAccent : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: LuxeText.label.copyWith(fontSize: 11.5)),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: editing
                      ? TextField(
                          key: ValueKey('edit-$label'),
                          controller: controller,
                          keyboardType: keyboardType,
                          style: const TextStyle(
                            color: LuxeColors.text,
                            fontSize: 15.5,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: false,
                            contentPadding: EdgeInsets.symmetric(vertical: 6),
                            border: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: LuxeColors.hairlineStrong,
                              ),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: LuxeColors.hairlineStrong,
                              ),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: context.planAccent,
                                width: 1.6,
                              ),
                            ),
                          ),
                        )
                      : Text(
                          value,
                          key: ValueKey('value-$label'),
                          style: const TextStyle(
                            color: LuxeColors.text,
                            fontSize: 15.5,
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

  Future<void> _sendVerificationEmail() async {
    if (_sendingVerification) return;
    setState(() => _sendingVerification = true);
    try {
      final auth = FirebaseAuth.instance;
      await auth.setLanguageCode('vi');
      await auth.currentUser?.sendEmailVerification();
      AppPopup.showSuccess(
        'Đã gửi email xác minh',
        detail: 'Mở email và bấm vào liên kết. Kiểm tra cả hộp thư rác.',
      );
    } on Object {
      AppPopup.showMessage(
        'Chưa gửi được email xác minh. Thử lại sau ít phút.',
      );
    } finally {
      if (mounted) setState(() => _sendingVerification = false);
    }
  }

  Widget _buildSecuritySection() => LuxeSettingsGroup(
    children: [
      if (_emailUnverified)
        LuxeSettingsRow(
          key: const ValueKey('profile-verify-email'),
          icon: Icons.mark_email_unread_rounded,
          accent: LuxeColors.champagne,
          title: 'Email chưa xác minh',
          subtitle: _sendingVerification
              ? 'Đang gửi email xác minh'
              : 'Chạm để gửi lại email xác minh',
          onTap: _sendVerificationEmail,
        ),
      LuxeSettingsRow(
        icon: Icons.lock_reset_rounded,
        title: 'Đổi mật khẩu',
        subtitle: 'Cần mật khẩu hiện tại để xác nhận',
        onTap: _showChangePasswordDialog,
      ),
      // QA 138: Google Play and App Store want deletion inside the app.
      LuxeSettingsRow(
        key: const ValueKey('profile-delete-account'),
        icon: Icons.delete_forever_rounded,
        accent: LuxeColors.danger,
        title: 'Xóa tài khoản',
        subtitle: 'Xóa vĩnh viễn tài khoản và dữ liệu',
        onTap: () => DeleteAccountSheet.open(context),
      ),
    ],
  );

  Widget _buildMetaSection() => LuxeSettingsGroup(
    children: [
      _buildMetaRow('Ngày tạo', _createdAt),
      _buildMetaRow(
        'Nguồn',
        _source == 'flutter_app' ? 'Ứng dụng mobile' : _source,
      ),
      _buildMetaRow(
        'Mã tài khoản',
        FirebaseAuth.instance.currentUser?.uid ?? '',
      ),
    ],
  );

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Text(label, style: LuxeText.caption),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: LuxeColors.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
