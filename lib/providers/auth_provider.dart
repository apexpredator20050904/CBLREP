import 'package:flutter/foundation.dart';
import '../core/api_service.dart';
import '../core/input_sanitizer.dart';
import '../models/models.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService api;
  UserModel? user;
  bool loading = true;
  String? error;

  AuthProvider(this.api);

  bool get isAuthenticated => user != null;

  Future<void> restore() async {
    loading = true;
    notifyListeners();
    try {
      await api.init();
      user = UserModel.fromJson(await api.currentUser());
    } on ApiException catch (exception) {
      // Only definitive rejections prove the token is dead — a transient
      // network failure must keep the saved session for the next attempt.
      if (exception.statusCode == 401 || exception.statusCode == 403) {
        await api.clearToken();
      }
      user = null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    error = null;
    loading = true;
    notifyListeners();
    try {
      final data = await api.login(email.trim(), password);
      user = UserModel.fromJson(Map<String, dynamic>.from(data['user'] as Map));
    } on ApiException catch (exception) {
      error = exception.message;
      rethrow;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String barangay,
    required String password,
  }) async {
    error = null;
    try {
      await api.register(fullName: name, email: email, barangay: barangay, password: password);
      await login(email, password);
    } on ApiException catch (exception) {
      error = exception.message;
      rethrow;
    }
  }

  Future<void> logout() async {
    await api.logout();
    user = null;
    notifyListeners();
  }

  /// PATCH /user — persist profile edits for the signed-in member.
  ///
  /// Only name/barangay are ever sent; role, verification and time credits
  /// remain administrator-controlled on the server.
  Future<void> updateProfile({String? name, String? barangay}) async {
    final payload = <String, dynamic>{
      if (name != null && name.trim().isNotEmpty) 'name': InputSanitizer.name(name),
      if (barangay != null && barangay.trim().isNotEmpty) 'barangay': InputSanitizer.name(barangay),
    };
    if (payload.isEmpty) return;

    final data = await api.updateProfile(payload);
    final fresh = data['user'];
    user = fresh is Map
        ? UserModel.fromJson(Map<String, dynamic>.from(fresh))
        : UserModel.fromJson(await api.currentUser());
    notifyListeners();
  }

  /// PATCH /user with current_password — rotates the member's own password and
  /// invalidates their other device sessions (the server keeps this one).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await api.updateProfile({
      'current_password': currentPassword,
      'password': newPassword,
    });
  }
}
