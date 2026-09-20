import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();
  static const _tokenKey = 'cblrep_member_token';
  static const _baseUrl = String.fromEnvironment(
    'CBLREP_API_URL',
    defaultValue: 'http://10.0.2.2:8000/api',
  );

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'Accept': 'application/json'},
  ));

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token != null && token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  Future<void> _setToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    _dio.options.headers.remove('Authorization');
  }

  Future<dynamic> _request(Future<Response<dynamic>> request) async {
    try {
      final response = await request;
      return response.data;
    } on DioException catch (error) {
      final data = error.response?.data;
      final message = data is Map && data['message'] is String
          ? data['message'] as String
          : 'Unable to connect to the CBLRE server.';
      throw ApiException(message, error.response?.statusCode);
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

  Future<Map<String, dynamic>> currentUser() async =>
      Map<String, dynamic>.from(await _request(_dio.get('/user')) as Map);

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

  Future<List<dynamic>> exchanges() async {
    final data = await _request(_dio.get('/exchanges')) as Map;
    return List<dynamic>.from(data['data'] ?? const []);
  }

  Future<Map<String, dynamic>> updateExchange(int id, String status) async =>
      Map<String, dynamic>.from(await _request(
        _dio.patch('/exchanges/$id', data: {'status': status}),
      ) as Map);

  Future<Map<String, dynamic>> timeBankBalance() async =>
      Map<String, dynamic>.from(await _request(_dio.get('/timebank/balance')) as Map);

  Future<List<dynamic>> timeBankTransactions() async {
    final data = await _request(_dio.get('/timebank/transactions')) as Map;
    return List<dynamic>.from(data['transactions'] ?? const []);
  }

  Future<List<dynamic>> messages() async {
    final data = await _request(_dio.get('/messages')) as Map;
    return List<dynamic>.from(data['messages'] ?? const []);
  }

  Future<Map<String, dynamic>> sendMessage(Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await _request(_dio.post('/messages', data: payload)) as Map);

  Future<Map<String, dynamic>> platformStatus() async =>
      Map<String, dynamic>.from(await _request(_dio.get('/platform/status')) as Map);
}
