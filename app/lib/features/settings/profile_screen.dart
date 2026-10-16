import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../core/services/auth_service.dart';
import '../../core/widgets/app_popup.dart';

/// Personal Information Screen — PLAN #3
/// Shows user profile from Firestore registration data
/// Allows editing name, phone, and changing password
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
      final user = FirebaseAuth.instance.currentUser;

      if (!mounted) return;

      setState(() {
        _name = data?['name'] ?? user?.displayName ?? 'Chưa cập nhật';
        _email = data?['email'] ?? user?.email ?? '';
        _phone = data?['phone'] ?? '';
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
        AppPopup.showError('Không tải được thông tin: $e');
      }
    }
  }

  Future<void> _saveProfile() async {
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

      if (!mounted) return;

      setState(() {
        _name = _nameCtrl.text.trim();
        _phone = _phoneCtrl.text.trim();
        _isEditing = false;
        _isSaving = false;
      });

      AppPopup.showSuccess('Đã cập nhật thông tin');
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppPopup.showError('Lỗi cập nhật: $e');
      }
    }
  }

  void _showChangePasswordDialog() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return Theme(
          data: LuxeTheme.of(ctx),
          child: StatefulBuilder(
            builder: (ctx, setDialogState) {
              return Dialog(
                backgroundColor: const Color(0xFF121315),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: const BorderSide(color: LuxeColors.hairline),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(
                        child: LuxeMedallion(
                          icon: Icons.lock_reset_rounded,
                          accent: LuxeColors.emerald,
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
                        controller: currentCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Mật khẩu hiện tại',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: newCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Mật khẩu mới (tối thiểu 6 ký tự)',
                          prefixIcon: Icon(Icons.key_rounded),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (loading)
                        const Center(
                          child: SizedBox.square(
                            dimension: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: LuxeColors.emerald,
                            ),
                          ),
                        )
                      else ...[
                        FilledButton(
                          onPressed: () async {
                            if (currentCtrl.text.isEmpty ||
                                newCtrl.text.length < 6) {
                              AppPopup.showError(
                                'Mật khẩu mới tối thiểu 6 ký tự',
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
                  ? const Center(
                      child: SizedBox.square(
                        dimension: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: LuxeColors.emerald,
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
                            onPressed: () {
                              if (_isEditing) {
                                _saveProfile();
                              } else {
                                setState(() => _isEditing = true);
                              }
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: LuxeColors.emerald,
                            ),
                            icon: Icon(
                              _isEditing
                                  ? Icons.check_rounded
                                  : Icons.edit_outlined,
                              size: 18,
                            ),
                            label: Text(_isEditing ? 'Lưu' : 'Sửa'),
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
                                          onPressed: _cancelEdit,
                                          child: const Text('Hủy'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton(
                                          onPressed: _saveProfile,
                                          child: const Text('Lưu thay đổi'),
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
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                LuxeColors.platinumHi,
                LuxeColors.platinumLow,
                LuxeColors.emerald,
                LuxeColors.platinumLow,
                LuxeColors.platinumHi,
              ],
            ),
            boxShadow: [BoxShadow(color: Color(0x2234D399), blurRadius: 28)],
          ),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A2C30), Color(0xFF0B0C0E)],
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
        icon: Icons.phone_outlined,
        label: 'Số điện thoại',
        value: _phone.isEmpty ? 'Chưa cập nhật' : _phone,
        isEditing: _isEditing,
        controller: _phoneCtrl,
        keyboardType: TextInputType.phone,
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
            accent: editing ? LuxeColors.emerald : null,
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
                          decoration: const InputDecoration(
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
                                color: LuxeColors.emerald,
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

  Widget _buildSecuritySection() => LuxeSettingsGroup(
    children: [
      LuxeSettingsRow(
        icon: Icons.lock_reset_rounded,
        title: 'Đổi mật khẩu',
        subtitle: 'Cần mật khẩu hiện tại để xác nhận',
        onTap: _showChangePasswordDialog,
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
      _buildMetaRow('UID', FirebaseAuth.instance.currentUser?.uid ?? ''),
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
              style: const TextStyle(color: LuxeColors.text, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}
