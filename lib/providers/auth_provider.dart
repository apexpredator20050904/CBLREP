import 'dart:async';

import 'package:flutter/foundation.dart';
import '../core/api_service.dart';
import '../core/input_sanitizer.dart';
import '../models/models.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService api;
  UserModel? user;
  bool loading = true;
  String? error;

  /// Set when the launch-time session check could not reach the server, so
  /// the launch gate can offer a retry instead of silently dumping the member
  /// on the login form as if they had been signed out.
  String? restoreError;

  /// True once a 401 proved the stored token is dead.
  bool sessionExpired = false;

  StreamSubscription<void>? _expiryWatch;

  AuthProvider(this.api) {
    // A token can be revoked (or expire) long after launch — every subsequent
    // request then 401s. Watching the API layer is what turns that from a
    // frozen dashboard into a prompt redirect to Login.
    _expiryWatch = api.sessionExpired.listen((_) {
      if (user == null) return;
      user = null;
      sessionExpired = true;
      error = 'Your session expired. Please sign in again.';
      notifyListeners();
    });
  }

  bool get isAuthenticated => user != null;

  Future<void> restore() async {
    loading = true;
    restoreError = null;
    error = null;
    notifyListeners();
    try {
      await api.init();
      user = UserModel.fromJson(await api.currentUser());
    } on ApiException catch (exception) {
      final status = exception.statusCode;
      if (status == 401 || status == 403) {
        // Definitive rejection — the token is dead, drop it.
        await api.clearToken();
        user = null;
        sessionExpired = true;
      } else {
        // Network/API failure: the session may still be perfectly valid, so
        // keep the stored token and report the failure for a retry rather than
        // pretending the member was signed out.
        restoreError = exception.message;
        user = null;
      }
    } catch (unexpected) {
      // Anything that is not an ApiException (a storage plugin failure, a
      // malformed payload, …) used to escape restore() as an unhandled async
      // error, leaving the launch gate spinning forever.
      restoreError = 'Could not start the app properly. Please retry.';
      debugPrint('[CBLREP] session restore failed: $unexpected');
      user = null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Retry the launch-time session check after a connectivity failure.
  Future<void> retryRestore() => restore();

  /// Clears a launch-time connectivity failure so the gate stops showing the
  /// error card (the member chose to go to the login screen instead).
  void dismissRestoreError() {
    restoreError = null;
    notifyListeners();
  }

  /// Hides the "your session ended" banner once the member starts signing in.
  void clearSessionExpiredNotice() {
    if (!sessionExpired) return;
    sessionExpired = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _expiryWatch?.cancel();
    super.dispose();
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
    required String purokSitio,
    required String password,
  }) async {
    error = null;
    try {
      await api.register(fullName: name, email: email, barangay: barangay, purokSitio: purokSitio, password: password);
      await login(email, password);
    } on ApiException catch (exception) {
      error = exception.message;
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } catch (_) {
      // A failed server call must never trap the member in a dead session.
      // api.logout() clears the stored token in its finally block regardless,
      // so the local session is dropped either way.
    }
    user = null;
    notifyListeners();
  }

  /// Re-fetch the member's residency verification state — called after a
  /// document submission and when the profile screen regains focus, so the
  /// badge reflects a change immediately without a re-login.
  Future<void> refreshVerification() async {
    try {
      final data = await api.verificationStatus();
      final current = user;
      if (current == null) return;
      user = current.copyWith(
        verified: data['is_verified'] == true,
        verificationStatus:
            UserModel.labelForStatus(data['status'] ?? data['status_label']),
        verificationNote: data['note'] as String?,
      );
      notifyListeners();
    } on ApiException {
      // Best-effort refresh — keep the last known status on failure.
    }
  }

  /// PATCH /user — persist profile edits for the signed-in member.
  ///
  /// Only name/barangay are ever sent; role, verification
  /// remain administrator-controlled on the server.
  Future<void> updateProfile({String? name, String? barangay, String? purokSitio}) async {
    final payload = <String, dynamic>{
      if (name != null && name.trim().isNotEmpty) 'name': InputSanitizer.name(name),
      if (barangay != null && barangay.trim().isNotEmpty) 'barangay': InputSanitizer.name(barangay),
      if (purokSitio != null && purokSitio.trim().isNotEmpty) 'purok_sitio': InputSanitizer.name(purokSitio),
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
