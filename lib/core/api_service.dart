import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'input_sanitizer.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

class ApiService {
  ApiService._() {
    _attachGuards();
  }
  static final ApiService instance = ApiService._();
  static const _tokenKey = 'cblrep_member_token';

  // ── API base URL resolution ──────────────────────────────────────────────
  // The production URL is supplied at BUILD time and never hardcoded:
  //
  //   flutter build apk --release \
  //     --dart-define=CBLREP_API_URL=https://your-api-host.com/api
  //
  // The value is baked into the binary by the Dart compiler, so a shipped APK
  // always talks to exactly the host it was built for.
  //
  // In release builds a missing CBLREP_API_URL is a hard configuration error:
  // the emulator/LAN/localhost candidates are dev-only and are NOT compiled
  // into a release APK, because `baseUrlCandidates` is built from
  // `kReleaseMode` at the top level (see [releaseConfigError]).
  static const _envBaseUrl = String.fromEnvironment('CBLREP_API_URL');

  /// Set for every debug/profile run so the dev helpers below can tell a
  /// release build (production host only) from a local one.
  static const bool _isReleaseBuild = bool.fromEnvironment('dart.vm.product');

  // Dev-only overrides — ignored entirely by release builds.
  static const _envLanIp = String.fromEnvironment('CBLREP_LAN_IP',
      defaultValue: '192.168.1.74');
  static const _envPort = String.fromEnvironment('CBLREP_API_PORT', defaultValue: '8000');

  /// Human-readable reason a release build cannot reach the API, or `null`
  /// when the build is correctly configured.
  static String? get releaseConfigError =>
      (_isReleaseBuild && _normalise(_envBaseUrl).isEmpty)
          ? 'CBLREP_API_URL was not set at build time. Rebuild with '
              '--dart-define=CBLREP_API_URL=https://your-api-host.com/api'
          : null;

  /// Strips trailing slashes and a trailing `/api` so the value can be used
  /// as a clean origin regardless of how it was supplied.
  static String _normalise(String raw) {
    var value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith('/api')) {
      value = value.substring(0, value.length - 4);
    }
    return value;
  }

  /// Candidate base URLs in probe order — the first one that answers a
  /// reachability probe wins and is pinned as the active base URL.
  ///
  /// Release: the single production host baked in at build time.
  /// Debug/profile: production host (if given), else whichever of the LAN /
  /// emulator / loopback addresses matches where the app is running:
  ///
  ///   Physical device  → http://<LAN-IP>:8000/api (phone + PC on same Wi-Fi)
  ///   Android emulator → http://10.0.2.2:8000/api     (host loopback alias)
  ///   iOS simulator    → http://127.0.0.1:8000/api    (shares the host network)
  ///   adb reverse      → http://127.0.0.1:8000/api    (after `adb reverse`)
  static List<String> get baseUrlCandidates {
    final production = _normalise(_envBaseUrl);
    if (production.isNotEmpty) {
      if (_isReleaseBuild) return ['$production/api'];
      final lanIp = _devLanCandidate();
      return ['$production/api', if (lanIp != null) lanIp, ..._devFallbacks()];
    }

    if (_isReleaseBuild) {
      // Nothing configured: keep the list valid so Dio has a base URL, but it
      // is unreachable by design. [releaseConfigError] explains why.
      return ['https://api.invalid/api'];
    }
    return [?_devLanCandidate(), ..._devFallbacks()];
  }

  static String? _devLanCandidate() =>
      _envLanIp.isEmpty ? null : 'http://$_envLanIp:$_envPort/api';

  static List<String> _devFallbacks() => Platform.isAndroid
      ? [
          // Android emulator → host loopback alias.
          'http://10.0.2.2:$_envPort/api',
          // Physical device over `adb reverse tcp:8000 tcp:8000`.
          'http://127.0.0.1:$_envPort/api',
        ]
      : [
          // iOS simulator / desktop share the host network.
          'http://127.0.0.1:$_envPort/api',
          'http://localhost:$_envPort/api',
        ];

  static String get _preferredBaseUrl => baseUrlCandidates.first;

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _preferredBaseUrl,
    // Tuned for a LAN-hosted backend: a reachable local host answers in
    // milliseconds, so a long connect timeout only delays the error the member
    // needs to see. Retries below still cover a briefly busy server.
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 15),
    headers: {'Accept': 'application/json'},
  ));

  /// Reachability probe client: short timeouts and `validateStatus: true` so
  /// any HTTP answer (even a 404) proves the server is reachable.
  final Dio _probeDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 2),
    receiveTimeout: const Duration(seconds: 4),
    validateStatus: (_) => true,
  ));

  /// Base URL requests currently go out to; switches automatically when the
  /// preferred candidate is unreachable (emulator vs device vs LAN).
  String _activeBaseUrl = _preferredBaseUrl;
  String get baseUrl => _activeBaseUrl;

  /// Host:port of the active base URL — shown in network error messages so a
  /// member knows exactly which server the app is trying to reach.
  String get baseUrlHost {
    final uri = Uri.tryParse(_activeBaseUrl);
    if (uri == null || uri.host.isEmpty) return _activeBaseUrl;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.host}$port';
  }

  /// Fires once when the server rejects the stored token (401). [AuthProvider]
  /// listens so an expired session bounces the member to Login instead of
  /// leaving the dashboard on screen with every request doomed to fail.
  final _sessionExpired = StreamController<void>.broadcast();

  /// Emits when a 401 invalidates the session — never closed by the API layer.
  Stream<void> get sessionExpired => _sessionExpired.stream;

  final _secure = const FlutterSecureStorage();

  /// Restores the persisted session (if any) from device storage.
  ///
  /// Returns true when a stored token was found and applied to the client —
  /// i.e. the member had signed in with "Remember me". Returns false when
  /// nothing was persisted (an unremembered sign-in keeps its token in
  /// memory only, so an app restart starts from a clean login screen), which
  /// lets the launch gate skip the `GET /user` round-trip and its
  /// "session ended" banner entirely.
  Future<bool> init() async {
    // A release build shipped without CBLREP_API_URL can never reach the
    // backend. Say so loudly once at startup instead of letting every screen
    // show a generic network error.
    final configError = releaseConfigError;
    if (configError != null) {
      debugPrint('[CBLREP] $configError');
    }

    // Prefer the encrypted store; fall back to legacy SharedPreferences
    // token once, then migrate it into secure storage.
    String? token;
    try {
      token = await _secure.read(key: _tokenKey);
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_tokenKey);
      if (legacy != null && legacy.isNotEmpty) {
        token = legacy;
        try {
          await _secure.write(key: _tokenKey, value: legacy);
        } catch (_) {}
        await prefs.remove(_tokenKey);
      }
    }
    if (token != null && token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
      return true;
    }
    return false;
  }

  /// Applies the token for the current sign-in.
  ///
  /// `persist: true` (Remember Me) writes it to encrypted storage so the next
  /// launch can restore the session; `persist: false` keeps the token in the
  /// Dio header only — memory — and wipes any previously stored copy, so
  /// killing the app always ends an unremembered session.
  Future<void> _setToken(String token, {required bool persist}) async {
    if (persist) {
      try {
        await _secure.write(key: _tokenKey, value: token);
      } catch (_) {
        // Last-resort fallback when the keystore is unavailable.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, token);
      }
    } else {
      await _wipeStoredToken();
    }
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// Removes every persisted copy of the token (secure store + legacy prefs).
  Future<void> _wipeStoredToken() async {
    try {
      await _secure.delete(key: _tokenKey);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  /// Drops the session entirely: revokes local persistence and the header.
  Future<void> clearToken() async {
    await _wipeStoredToken();
    _dio.options.headers.remove('Authorization');
  }

  void _attachGuards() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // Never log or transmit the raw Authorization header value.
        handler.next(options);
      },
      onError: (error, handler) {
        final status = error.response?.statusCode;
        // A login/register attempt answers 401 for bad credentials — that must
        // surface on the login form, not trigger a global session-expiry.
        final path = error.requestOptions.path;
        final isAuthAttempt = path.endsWith('/login') || path.endsWith('/register');
        if (status == 401 && !isAuthAttempt) {
          // Token expired/revoked — drop it so AuthGate returns to login and
          // tell the app layer, otherwise the member is left staring at a
          // dashboard whose every request is about to fail.
          _dio.options.headers.remove('Authorization');
          unawaited(clearToken());
          if (!_sessionExpired.isClosed) _sessionExpired.add(null);
        }
        handler.next(error);
      },
    ));
  }

  Future<dynamic> _request(Future<Response<dynamic>> request) async {
    try {
      final response = await request;
      return response.data;
    } on DioException catch (error) {
      final recovered = await _recover(error);
      if (recovered != null) return recovered.data;
      throw _toApiException(error);
    }
  }

  /// True when the request never reached the server — the only case that
  /// retrying or failing over to another base URL can fix. Anything with an
  /// HTTP status is a real server answer and is surfaced as-is.
  bool _isConnectivityFailure(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.unknown:
        return error.error is SocketException || error.error is HttpException;
      default:
        return false;
    }
  }

  /// Retries a request that died before getting an HTTP response:
  /// 1. two quick back-off retries on the same base URL (transient dropouts);
  /// 2. fail-over across [baseUrlCandidates] (wrong host for this device).
  ///
  /// Multipart bodies ([FormData]) are stream-once and can never be re-sent,
  /// so those requests fail over immediately without retrying.
  Future<Response<dynamic>?> _recover(DioException error) async {
    if (!_isConnectivityFailure(error)) return null;
    final original = error.requestOptions;
    final canReissue = original.data is! FormData;

    // Hard ceiling on recovery work. Without it, a device that cannot reach
    // the LAN host burns 6s connect + retries + probes on EVERY request, which
    // reads to the member as a frozen app rather than a network error.
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    bool timeLeft() => DateTime.now().isBefore(deadline);

    var delay = const Duration(milliseconds: 400);
    for (var attempt = 0; attempt < 2 && canReissue && timeLeft(); attempt++) {
      await Future<void>.delayed(delay);
      delay = delay * 2;
      try {
        return await _dio.fetch(original.copyWith());
      } on DioException catch (retryError) {
        if (!_isConnectivityFailure(retryError)) return null;
      }
    }

    final working = await _probeCandidates(skip: _dio.options.baseUrl);
    if (working == null || !timeLeft()) return null;
    try {
      return await _dio.fetch(original.copyWith(baseUrl: working));
    } on DioException catch (failoverError) {
      if (!_isConnectivityFailure(failoverError)) return null;
      // One more probe cycle before giving up (the winner may have dropped).
      final fallback = await _probeCandidates(skip: working);
      if (fallback == null || !timeLeft()) return null;
      // Guarded: an unguarded fetch here leaked a raw DioException past
      // _request(), and every caller only catches ApiException — so one bad
      // failover turned into an unhandled async error instead of a message.
      try {
        return await _dio.fetch(original.copyWith(baseUrl: fallback));
      } on DioException {
        return null;
      }
    }
  }

  Future<bool> _isReachable(String baseUrl) async {
    try {
      await _probeDio.getUri<dynamic>(Uri.parse('$baseUrl/platform/status'));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Tries every candidate base URL and pins the first reachable one as the
  /// active base URL. Returns null when none of them answer.
  Future<String?> _probeCandidates({String? skip}) async {
    for (final candidate in baseUrlCandidates) {
      if (candidate == skip || candidate == _activeBaseUrl) continue;
      if (await _isReachable(candidate)) {
        _activeBaseUrl = candidate;
        _dio.options.baseUrl = candidate;
        return candidate;
      }
    }
    return null;
  }

  /// Public reachability check for retry flows: keeps the current base URL
  /// when it answers, otherwise hunts for another candidate that does.
  Future<bool> probeConnectivity() async {
    if (await _isReachable(_activeBaseUrl)) return true;
    return await _probeCandidates() != null;
  }

  /// Names the host the app actually tried, so "can't reach the server" is
  /// actionable instead of vague: the member sees whether they are pointed at
  /// 192.168.1.81 (PC on the same Wi-Fi) or a deployed API.
  String _connectivityHint() {
    final host = baseUrlHost;
    return "Unable to connect to the CBLREP server at $host. "
        'Check that your phone is on the same Wi-Fi as that server and that the '
        'backend is running, then retry.';
  }

  ApiException _toApiException(DioException error) {
    final data = error.response?.data;
    String? serverMessage;
    if (data is Map) {
      final raw = data['message'];
      if (raw is String && raw.trim().isNotEmpty) serverMessage = raw.trim();
      // Laravel validation payloads carry field errors; show the first one.
      if (serverMessage == null && data['errors'] is Map) {
        for (final messages in (data['errors'] as Map).values) {
          if (messages is List && messages.isNotEmpty) {
            serverMessage = messages.first.toString();
            break;
          }
        }
      }
    }
    if (serverMessage != null) return ApiException(serverMessage, error.response?.statusCode);

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
        return ApiException(_connectivityHint());
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return ApiException('The CBLREP server at ${baseUrlHost} took too long to respond. Please retry.');
      case DioExceptionType.badCertificate:
        return const ApiException('The CBLREP server certificate could not be trusted.');
      case DioExceptionType.cancel:
        return const ApiException('The request was cancelled.');
      default:
        return ApiException('Unable to connect to the CBLREP server at $baseUrlHost.');
    }
  }

  /// POST /login — authenticates and applies the session token.
  ///
  /// With [rememberMe] the token is persisted (long-lived, chosen by the
  /// backend) and survives an app restart; without it the token lives only in
  /// memory for this run of the app.
  Future<Map<String, dynamic>> login(String email, String password,
      {bool rememberMe = false}) async {
    final data = Map<String, dynamic>.from(await _request(
      _dio.post('/login', data: {
        'email': email,
        'password': password,
        'remember_me': rememberMe,
      }),
    ) as Map);
    await _setToken(data['access_token'] as String, persist: rememberMe);
    return data;
  }

  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String barangay,
    required String purokSitio,
    required String password,
  }) async {
    return Map<String, dynamic>.from(await _request(_dio.post('/register', data: {
      'fullName': fullName,
      'email': email,
      'barangay': barangay,
      'purok_sitio': purokSitio,
      'password': password,
    })) as Map);
  }

  /// POST /forgot-password — e-mails a single-use reset code.
  ///
  /// The backend answers identically whether or not the address exists, so a
  /// membership cannot be probed from here. In local debug builds it also
  /// returns `dev_code`, which the UI surfaces so the flow is testable while
  /// MAIL_MAILER=log.
  Future<Map<String, dynamic>> requestPasswordReset(String email) async =>
      Map<String, dynamic>.from(await _request(_dio.post('/forgot-password', data: {
        'email': InputSanitizer.email(email),
      })) as Map);

  /// POST /reset-password — redeems the mailed code and stores the new hash.
  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String password,
    required String passwordConfirmation,
  }) async =>
      Map<String, dynamic>.from(await _request(_dio.post('/reset-password', data: {
        'email': InputSanitizer.email(email),
        'code': code.trim(),
        'password': password,
        'password_confirmation': passwordConfirmation,
      })) as Map);

  Future<Map<String, dynamic>> currentUser() async =>
      Map<String, dynamic>.from(await _request(_dio.get('/user')) as Map);

  /// PATCH /user — update profile fields (name, barangay).
  /// Falls back gracefully when the backend has no such route yet.
  /// PATCH /user — persist profile edits for the signed-in member.
  ///
  /// Falls back across `/user`, `/profile` and `/me` for older backends.
  /// The catch is on [ApiException], not DioException: [_request] converts
  /// every transport failure into an ApiException, so an `on DioException`
  /// clause here was unreachable and the fallback never advanced past a 404.
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> payload) async {
    const candidates = ['/user', '/profile', '/me'];
    ApiException? last;
    for (final path in candidates) {
      try {
        return Map<String, dynamic>.from(await _request(_dio.patch(path, data: payload)) as Map);
      } on ApiException catch (e) {
        last = e;
        if (e.statusCode == 404 || e.statusCode == 405) continue;
        rethrow;
      }
    }
    throw last ?? const ApiException('Profile update is not available yet.');
  }

  Future<Map<String, dynamic>> verificationStatus() async {
    try {
      return Map<String, dynamic>.from(await _request(_dio.get('/user/verification-status')) as Map);
    } on ApiException {
      return const {};
    }
  }

  Future<void> logout() async {
    try {
      await _request(_dio.post('/logout'));
    } finally {
      await clearToken();
    }
  }

  Future<List<dynamic>> listings({String? query, String? barangay}) async {
    final data = await _request(_dio.get('/listings', queryParameters: {
      if (query != null && query.isNotEmpty) 'q': query,
      if (barangay != null && barangay.isNotEmpty) 'barangay': barangay,
    })) as Map;
    return List<dynamic>.from(data['listings'] ?? data['data'] ?? const []);
  }

  Future<Map<String, dynamic>> createListing({
    required String title,
    required String type,
    required String description,
    required String category,
    required String condition,
    required String location,
    required String barangay,
    required String purokSitio,
    String compensationType = 'barter',
    double? price,
    File? image,
  }) async {
    final payload = <String, dynamic>{
      'title': title,
      'type': type,
      'listingType': type,
      'description': description,
      'category': category,
      'condition': condition,
      'location': location,
      'barangay': barangay,
      'purok_sitio': purokSitio,
      // free | barter | paid — the flexible compensation model.
      'compensation_type': compensationType,
      // Only sent for a priced sale; free/barter never carry a figure.
      if (compensationType == 'paid' && price != null) 'price': price,
    };
    if (image != null) {
      payload['image'] = await MultipartFile.fromFile(
        image.path,
        filename: image.path.split(Platform.pathSeparator).last,
      );
    }
    return Map<String, dynamic>.from(await _request(
      _dio.post('/listings', data: FormData.fromMap(payload)),
    ) as Map);
  }

  /// Update a listing owned by the signed-in member.
  Future<Map<String, dynamic>> updateListing(
    int id,
    Map<String, dynamic> payload,
  ) async =>
      Map<String, dynamic>.from(
        await _request(_dio.patch('/listings/$id', data: payload)) as Map,
      );

  /// Close (soft-delete) a listing owned by the signed-in member.
  Future<Map<String, dynamic>> deleteListing(int id) async =>
      Map<String, dynamic>.from(
        await _request(_dio.delete('/listings/$id')) as Map,
      );

  Future<Map<String, dynamic>> dashboardStats() async =>
      Map<String, dynamic>.from(await _request(_dio.get('/dashboard/stats')) as Map);

  Future<Map<String, dynamic>> submitVerification({
    required String barangay,
    required String purokSitio,
    required String documentType,
    required File document,
  }) async {
    return Map<String, dynamic>.from(await _request(_dio.post(
      '/verification',
      data: FormData.fromMap({
        'barangay': barangay,
        'purok_sitio': purokSitio,
        'document_type': documentType,
        'document': await MultipartFile.fromFile(document.path),
      }),
    )) as Map);
  }

  // ── Exchanges (direct bartering only) ────────────────────────────────
  Future<List<dynamic>> exchanges() async {
    final data = await _request(_dio.get('/exchanges')) as Map;
    final list = data['exchanges'] ?? data['data'] ?? const [];
    return List<dynamic>.from(list as List);
  }

  /// POST /api/exchanges — propose a direct barter.
  ///
  /// `offeredItem` is the proposer's side of the trade and is what keeps every
  /// proposal two-sided. `offeredResourceId` optionally names one
  /// of the proposer's own listings instead of free text (skill-for-skill
  /// trades just use the free-text field).
  Future<Map<String, dynamic>> createExchange({
    required int resourceId,
    String? offeredItem,
    int? offeredResourceId,
    required String barangay,
    required String purokSitio,
  }) async =>
      Map<String, dynamic>.from(await _request(_dio.post('/exchanges', data: {
        'resource_id': resourceId,
        if (offeredItem != null && offeredItem.trim().isNotEmpty) 'offered_item': offeredItem.trim(),
        if (offeredResourceId != null) 'offered_resource_id': offeredResourceId,
        'barangay': barangay,
        'purok_sitio': purokSitio,
      })) as Map);

  Future<Map<String, dynamic>> updateExchange(int id, String status) async {
    try {
      return Map<String, dynamic>.from(
          await _request(_dio.patch('/exchanges/$id', data: {'status': status})) as Map);
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        return Map<String, dynamic>.from(
            await _request(_dio.put('/exchanges/$id/status', data: {'status': status})) as Map);
      }
      rethrow;
    }
  }

  /// POST /api/exchanges/{id}/confirm-completion — dual-confirmation.
  ///
  /// Records the caller's half of the completion (proposer OR owner).
  /// The server promotes the exchange to `completed` only once BOTH
  /// parties have confirmed; otherwise it returns the partial state with
  /// "Waiting for other party's confirmation".
  Future<Map<String, dynamic>> confirmExchangeCompletion(int id) async =>
      Map<String, dynamic>.from(
          await _request(_dio.post('/exchanges/$id/confirm-completion')) as Map);

  // ── Notifications (real-time alerts) ─────────────────────────────────
  Future<Map<String, dynamic>> notifications({int perPage = 25}) async =>
      Map<String, dynamic>.from(await _request(
          _dio.get('/notifications', queryParameters: {'per_page': perPage})) as Map);

  Future<Map<String, dynamic>> markNotificationRead(int id) async =>
      Map<String, dynamic>.from(
          await _request(_dio.put('/notifications/$id/read')) as Map);

  // ── Conversations / secure in-app messaging ──────────────────────────
  Future<List<dynamic>> conversations() async {
    final data = await _request(_dio.get('/conversations')) as Map;
    return List<dynamic>.from(data['conversations'] ?? data['data'] ?? const []);
  }

  /// POST /conversations — open the direct-inquiry thread about a listing.
  ///
  /// Passing [listingId] scopes the conversation to the post (buyer + seller +
  /// listing), so each listing gets its own thread. Omit it for a plain
  /// person-to-person chat with [userId].
  Future<Map<String, dynamic>> startConversation(int userId, {int? listingId}) async =>
      Map<String, dynamic>.from(await _request(_dio.post('/conversations', data: {
        'user_id': userId,
        if (listingId != null) 'listing_id': listingId,
      })) as Map);

  Future<Map<String, dynamic>> conversationMessages(int id) async =>
      Map<String, dynamic>.from(
          await _request(_dio.get('/conversations/$id/messages')) as Map);

  Future<Map<String, dynamic>> sendConversationMessage(int id, String body,
      {File? file, void Function(int sent, int total)? onProgress}) async {
    if (file == null) {
      return Map<String, dynamic>.from(await _request(
          _dio.post('/conversations/$id/messages', data: {'body': body})) as Map);
    }
    final fileName = file.path.split(Platform.pathSeparator).last;
    final form = FormData.fromMap({
      'body': body,
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
    });
    return Map<String, dynamic>.from(await _request(_dio.post(
      '/conversations/$id/messages',
      data: form,
      onSendProgress: onProgress,
    )) as Map);
  }

  /// POST /messages (multipart) — direct send with optional photo/document.
  /// Used by the chat attachment flow; body may be an empty caption.
  Future<Map<String, dynamic>> sendMessageWithFile({
    required int conversationId,
    required String body,
    required File file,
    void Function(int sent, int total)? onProgress,
  }) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final form = FormData.fromMap({
      'conversation_id': conversationId,
      'body': body,
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
    });
    final data = Map<String, dynamic>.from(await _request(_dio.post(
      '/messages',
      data: form,
      onSendProgress: onProgress,
    )) as Map);
    return Map<String, dynamic>.from(data['message'] as Map);
  }

  // ── Per-message actions (edit / delete) ─────────────────────────────────
  //
  // These are keyed on the message, not the conversation: the backend
  // re-resolves the thread from the message so a non-participant gets a 404
  // rather than a 403 that would confirm the id exists.

  /// PUT /messages/{id} — edit a message you sent. Returns the stored copy,
  /// including the `edited_at` marker the backend stamps.
  Future<Map<String, dynamic>> editMessage(int messageId, String body) async {
    final data = Map<String, dynamic>.from(await _request(
      _dio.put('/messages/$messageId', data: {'body': body}),
    ) as Map);
    return Map<String, dynamic>.from(data['message'] as Map);
  }

  /// DELETE /messages/{id} — remove a message you sent.
  Future<void> deleteMessage(int messageId) async {
    await _request(_dio.delete('/messages/$messageId'));
  }

  Future<List<dynamic>> messages() async {
    try {
      final data = await _request(_dio.get('/messages')) as Map;
      return List<dynamic>.from(data['messages'] ?? const []);
    } on ApiException {
      return const [];
    }
  }

  Future<Map<String, dynamic>> sendMessage(Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _request(_dio.post('/messages', data: payload)) as Map);

  Future<Map<String, dynamic>> platformStatus() async =>
      Map<String, dynamic>.from(await _request(_dio.get('/platform/status')) as Map);
}
