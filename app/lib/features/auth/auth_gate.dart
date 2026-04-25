import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/theme/app_colors.dart';
import 'login_screen.dart';
import '../../navigation/app_navigation.dart';

/// AuthGate: hiển thị LoginScreen nếu chưa đăng nhập,
/// AppNavigation nếu đã đăng nhập.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
              ),
            ),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const AppNavigation();
        }
        return const LoginScreen();
      },
    );
  }
}
