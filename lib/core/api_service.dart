import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
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
  // `--dart-define=CBLREP_API_URL=…` always wins when provided. Otherwise the
  // reachable address is picked at runtime from [baseUrlCandidates] because
  // it depends on where the app runs:
  //
  //   Android emulator → http://10.0.2.2:8000/api  (host loopback alias)
  //   iOS simulator    → http://127.0.0.1:8000/api (shares the host network)
  //   Physical device  → http://127.0.0.1:8000/api works after
  //                      `adb reverse tcp:8000 tcp:8000`; otherwise run the
  //                      app with --dart-define=CBLREP_LAN_IP=<pc-ip> so the
  //                      dev machine is reached over the same Wi-Fi network.
  static const _envBaseUrl = String.fromEnvironment('CBLREP_API_URL');
  static const _envLanIp = String.fromEnvironment('CBLREP_LAN_IP');
  static const _envPort = String.fromEnvironment('CBLREP_API_PORT', defaultValue: '8000');

  /// Candidate base URLs in probe order — the first one that answers a
  /// reachability probe wins and is pinned as the active base URL.
  static List<String> get baseUrlCandidates {
    final port = _envPort;
    final lanIp = _envLanIp.isEmpty ? null : 'http://$_envLanIp:$port/api';
    if (_envBaseUrl.isNotEmpty) {
      return [_envBaseUrl, if (lanIp != null && lanIp != _envBaseUrl) lanIp];
    }
    if (Platform.isAndroid) {
      return [
        'http://10.0.2.2:$port/api', // Android emulator → host loopback
        'http://127.0.0.1:$port/api', // physical device + adb reverse
        ?lanIp, // phone + PC on the same Wi-Fi
      ];
    }
    return [
      'http://127.0.0.1:$port/api', // iOS simulator / desktop builds
      'http://localhost:$port/api',
      ?lanIp,
    ];
  }

  static String get _preferredBaseUrl => baseUrlCandidates.first;

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _preferredBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
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

  final _secure = const FlutterSecureStorage();

  Future<void> init() async {
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
    }
  }

  Future<void> _setToken(String token) async {
    try {
      await _secure.write(key: _tokenKey, value: token);
    } catch (_) {
      // Last-resort fallback when the keystore is unavailable.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    }
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<void> clearToken() async {
    try {
      await _secure.delete(key: _tokenKey);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    _dio.options.headers.remove('Authorization');
  }

  void _attachGuards() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // Never log or transmit the raw Authorization header value.
        handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          // Token expired/revoked — drop it so AuthGate returns to login.
          _dio.options.headers.remove('Authorization');
          unawaited(clearToken());
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

    var delay = const Duration(milliseconds: 400);
    for (var attempt = 0; attempt < 2 && canReissue; attempt++) {
      await Future<void>.delayed(delay);
      delay = delay * 2;
      try {
        return await _dio.fetch(original.copyWith());
      } on DioException catch (retryError) {
        if (!_isConnectivityFailure(retryError)) return null;
      }
    }

    final working = await _probeCandidates(skip: _dio.options.baseUrl);
    if (working == null) return null;
    try {
      return await _dio.fetch(original.copyWith(baseUrl: working));
    } on DioException catch (failoverError) {
      if (!_isConnectivityFailure(failoverError)) return null;
      // One more probe cycle before giving up (the winner may have dropped).
      final fallback = await _probeCandidates(skip: working);
      if (fallback == null) return null;
      return await _dio.fetch(original.copyWith(baseUrl: fallback));
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

  static const _connectivityHint =
      "Can't reach the CBLREP server. Start the backend (php artisan serve in backend/) or check your connection, then tap retry.";

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
        return const ApiException(_connectivityHint);
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return const ApiException('The CBLREP server took too long to respond. Please try again.');
      case DioExceptionType.badCertificate:
        return const ApiException('The CBLREP server certificate could not be trusted.');
      default:
        return const ApiException('Unable to connect to the CBLREP server.');
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final data = Map<String, dynamic>.from(await _request(
      _dio.post('/login', data: {'email': email, 'password': password}),
    ) as Map);
    await _setToken(data['access_token'] as String);
    return data;
  }

  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String barangay,
    required String password,
  }) async {
    return Map<String, dynamic>.from(await _request(_dio.post('/register', data: {
      'fullName': fullName,
      'email': email,
      'barangay': barangay,
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
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> payload) async {
    const candidates = ['/user', '/profile', '/me'];
    DioException? last;
    for (final path in candidates) {
      try {
        return Map<String, dynamic>.from(await _request(_dio.patch(path, data: payload)) as Map);
      } on DioException catch (e) {
        last = e;
        if (e.response?.statusCode == 404 || e.response?.statusCode == 405) continue;
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
    required String exchangeType,
    required String condition,
    required String location,
    File? image,
  }) async {
    final payload = <String, dynamic>{
      'title': title,
      'type': type,
      'listingType': type,
      'description': description,
      'category': category,
      'exchangeType': exchangeType,
      'condition': condition,
      'location': location,
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
    required String documentType,
    required File document,
  }) async {
    return Map<String, dynamic>.from(await _request(_dio.post(
      '/verification',
      data: FormData.fromMap({
        'barangay': barangay,
        'document_type': documentType,
        'document': await MultipartFile.fromFile(document.path),
      }),
    )) as Map);
  }

  // ── Exchanges (freecycle / barter / lending) ─────────────────────────
  Future<List<dynamic>> exchanges() async {
    final data = await _request(_dio.get('/exchanges')) as Map;
    final list = data['exchanges'] ?? data['data'] ?? const [];
    return List<dynamic>.from(list as List);
  }

  Future<Map<String, dynamic>> createExchange({
    required int resourceId,
    required String exchangeType,
    String? returnDate,
    double? credits,
  }) async =>
      Map<String, dynamic>.from(await _request(_dio.post('/exchanges', data: {
        'resource_id': resourceId,
        'exchange_type': exchangeType,
        if (returnDate != null) 'return_date': returnDate,
        if (credits != null) 'credits_exchanged': credits,
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

  // ── Notifications (real-time alerts) ─────────────────────────────────
  Future<Map<String, dynamic>> notifications({int perPage = 25}) async =>
      Map<String, dynamic>.from(await _request(
          _dio.get('/notifications', queryParameters: {'per_page': perPage})) as Map);

  Future<Map<String, dynamic>> markNotificationRead(int id) async =>
      Map<String, dynamic>.from(
          await _request(_dio.put('/notifications/$id/read')) as Map);

  // ── Time Bank ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> timeBankBalance() async =>
      Map<String, dynamic>.from(await _request(_dio.get('/timebank/balance')) as Map);

  Future<List<dynamic>> timeBankTransactions() async {
    final data = await _request(_dio.get('/timebank/transactions')) as Map;
    return List<dynamic>.from(data['transactions'] ?? data['data'] ?? const []);
  }

  Future<Map<String, dynamic>> timeBankStats() async {
    try {
      return Map<String, dynamic>.from(await _request(_dio.get('/timebank/stats')) as Map);
    } on ApiException {
      return const {};
    }
  }

  Future<List<dynamic>> timeBankServices() async {
    final data = await _request(_dio.get('/timebank/services')) as Map;
    return List<dynamic>.from(data['services'] ?? const []);
  }

  /// POST /timebank/services — publish a skill/service you can offer to the
  /// community, priced in time-bank hours.
  Future<Map<String, dynamic>> offerTimeBankService({
    required String title,
    String? description,
    String? category,
    double? estimatedHours,
    String? location,
    String? availability,
  }) async =>
      Map<String, dynamic>.from(await _request(_dio.post('/timebank/services', data: {
        'title': title.trim(),
        if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
        if (category != null) 'category': category,
        if (estimatedHours != null) 'estimated_hours': estimatedHours,
        if (location != null && location.trim().isNotEmpty) 'location': location.trim(),
        if (availability != null && availability.trim().isNotEmpty) 'availability': availability.trim(),
      })) as Map);

  /// POST /timebank/transactions — claim a listed service, spending/earning
  /// time-bank credits once the provider completes and the member confirms.
  Future<Map<String, dynamic>> requestTimeBankService({
    required int serviceId,
    double? hours,
  }) async =>
      Map<String, dynamic>.from(await _request(_dio.post('/timebank/transactions', data: {
        'service_id': serviceId,
        if (hours != null) 'requested_hours': hours,
      })) as Map);

  // ── Conversations / secure in-app messaging ──────────────────────────
  Future<List<dynamic>> conversations() async {
    final data = await _request(_dio.get('/conversations')) as Map;
    return List<dynamic>.from(data['conversations'] ?? data['data'] ?? const []);
  }

  Future<Map<String, dynamic>> startConversation(int userId) async =>
      Map<String, dynamic>.from(
          await _request(_dio.post('/conversations', data: {'user_id': userId})) as Map);

  Future<Map<String, dynamic>> conversationMessages(int id) async =>
      Map<String, dynamic>.from(
          await _request(_dio.get('/conversations/$id/messages')) as Map);

  Future<Map<String, dynamic>> sendConversationMessage(int id, String body) async =>
      Map<String, dynamic>.from(await _request(
          _dio.post('/conversations/$id/messages', data: {'body': body})) as Map);

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
