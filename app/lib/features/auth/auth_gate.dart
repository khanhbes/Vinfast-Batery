import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/services/app_update_service.dart';
import '../../core/services/notification_center_service.dart';
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
          return _AuthenticatedRoot(key: ValueKey(snapshot.data!.uid));
        }
        return const LoginScreen();
      },
    );
  }
}

class _AuthenticatedRoot extends StatefulWidget {
  const _AuthenticatedRoot({super.key});

  @override
  State<_AuthenticatedRoot> createState() => _AuthenticatedRootState();
}

class _AuthenticatedRootState extends State<_AuthenticatedRoot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Check app updates
      await AppUpdateService().initialize(context: context);
      
      // Initialize notification center and sync models
      await NotificationCenterService().initialize();
      await NotificationCenterService().syncModels();
    });
  }

  @override
  Widget build(BuildContext context) => const AppNavigation();
}
