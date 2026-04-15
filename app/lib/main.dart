import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:ui';

import 'app.dart';
import 'data/services/notification_service.dart';
import 'data/services/background_service_config.dart';
import 'data/services/maintenance_reminder_service.dart';
import 'data/repositories/vehicle_spec_repository.dart';
import 'data/services/vehicle_model_link_service.dart';
import 'core/widgets/app_popup.dart';

/// Provider toàn cục cho trạng thái recovery cần hiển thị dialog
final pendingRecoveryProvider = StateProvider<String?>((ref) => null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppPopup.showError('Đã xảy ra lỗi trong ứng dụng. Vui lòng thử lại.');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled zone error: $error');
    AppPopup.showError('Ứng dụng gặp lỗi ngoài luồng chính.');
    return true;
  };

  await runZonedGuarded(() async {

  // Khởi tạo Firebase
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  // Khởi tạo Notification Service
  try {
    await NotificationService().initialize();
  } catch (e) {
    debugPrint("Notification init error: $e");
  }

  // Khởi tạo Background Service
  try {
    await BackgroundServiceConfig.initialize();
  } catch (e) {
    debugPrint("Background service init error: $e");
  }

  // Kiểm tra session tracking chưa kết thúc (crash recovery)
  String? pendingRecovery;
  try {
    final prefs = await SharedPreferences.getInstance();
    final chargeActive = prefs.getBool('charge_active') ?? false;
    final tripActive = prefs.getBool('trip_active') ?? false;
    if (chargeActive) {
      pendingRecovery = 'charge';
    } else if (tripActive) {
      pendingRecovery = 'trip';
    }
  } catch (e) {
    debugPrint("Recovery check error: $e");
  }

  // Đồng bộ catalog VinFast specs (Firestore → cache → local fallback)
  try {
    final specRepo = VehicleSpecRepository();
    await specRepo.getAllSpecs(); // triggers sync + seed if needed
  } catch (e) {
    debugPrint("VinFast spec sync error: $e");
  }

  // Auto-match vehicle → VinFast model nếu chưa link
  try {
    final prefs = await SharedPreferences.getInstance();
    final selId = prefs.getString('selected_vehicle_id') ?? '';
    if (selId.isNotEmpty) {
      final doc = await FirebaseFirestore.instance
          .collection('Vehicles')
          .doc(selId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        // Chỉ auto-match nếu chưa link
        if (data['vinfastModelId'] == null || (data['vinfastModelId'] as String).isEmpty) {
          final specRepo = VehicleSpecRepository();
          final name = data['vehicleName'] as String? ?? '';
          final match = await specRepo.matchByVehicleName(name);
          if (match != null) {
            final linkService = VehicleModelLinkService();
            await linkService.linkModel(vehicleId: selId, spec: match);
          }
        }
      }
    }
  } catch (e) {
    debugPrint("Auto-match error: $e");
  }

  // Kiểm tra nhắc bảo dưỡng tự động ở app launch
  try {
    final prefs = await SharedPreferences.getInstance();
    final vehicleId = prefs.getString('selected_vehicle_id') ?? '';
    if (vehicleId.isNotEmpty) {
      // Lấy ODO từ Firestore nếu đã có xe
      final doc = await __tryGetVehicleOdo(vehicleId);
      if (doc != null) {
        MaintenanceReminderService().checkAndNotify(
          vehicleId: vehicleId,
          currentOdo: doc,
        );
      }
    }
  } catch (e) {
    debugPrint("Maintenance check error: $e");
  }

  // Lock to portrait mode
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Set system UI style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFF8F9FA),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

    runApp(
      ProviderScope(
        overrides: [
          pendingRecoveryProvider.overrideWith((ref) => pendingRecovery),
        ],
        child: const VinFastBatteryApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('ZonedGuarded error: $error');
    AppPopup.showError('Đã bắt được lỗi không mong muốn.');
  });
}

/// Helper: lấy ODO hiện tại từ Firestore (non-blocking)
Future<int?> __tryGetVehicleOdo(String vehicleId) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('Vehicles')
        .doc(vehicleId)
        .get();
    if (doc.exists) {
      return (doc.data()?['currentOdo'] ?? 0) as int;
    }
  } catch (_) {}
  return null;
}
