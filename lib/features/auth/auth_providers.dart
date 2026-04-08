import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stream provider theo dõi trạng thái đăng nhập
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Provider lấy UID của user hiện tại (null nếu chưa đăng nhập)
final currentUidProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).whenData((u) => u?.uid).value;
});

/// Provider lấy email user hiện tại
final currentEmailProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).whenData((u) => u?.email).value;
});
