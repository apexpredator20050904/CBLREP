import 'package:flutter/foundation.dart';
import '../core/api_service.dart';
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
    } on ApiException {
      await api.clearToken();
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
}
