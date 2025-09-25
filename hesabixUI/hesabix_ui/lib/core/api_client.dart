import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import 'auth_store.dart';
import 'calendar_controller.dart';

class ApiClientOptions {
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Map<String, dynamic> defaultHeaders;

  const ApiClientOptions({
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 20),
    this.defaultHeaders = const <String, dynamic>{'Content-Type': 'application/json'},
  });
}

class ApiClient {
  final Dio _dio;
  static Locale? _currentLocale;
  static AuthStore? _authStore;
  static CalendarController? _calendarController;

  static void setCurrentLocale(Locale locale) {
    _currentLocale = locale;
  }

  static void bindAuthStore(AuthStore store) {
    _authStore = store;
  }

  static void bindCalendarController(CalendarController controller) {
    _calendarController = controller;
  }

  ApiClient._(this._dio);

  factory ApiClient({String? baseUrl, ApiClientOptions options = const ApiClientOptions()}) {
    final resolvedBaseUrl = (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(RegExp(r'/+$'), '');
    final dio = Dio(
      BaseOptions(
        baseUrl: resolvedBaseUrl,
        connectTimeout: options.connectTimeout,
        receiveTimeout: options.receiveTimeout,
        headers: options.defaultHeaders,
        responseType: ResponseType.json,
        followRedirects: false,
        validateStatus: (code) => code != null && code >= 200 && code < 400,
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final lang = _currentLocale?.toLanguageTag();
          if (lang != null && lang.isNotEmpty) {
            options.headers['Accept-Language'] = lang;
          }
          final apiKey = _authStore?.apiKey;
          if (apiKey != null && apiKey.isNotEmpty) {
            options.headers['Authorization'] = 'ApiKey $apiKey';
          }
          final deviceId = _authStore?.deviceId;
          if (deviceId != null && deviceId.isNotEmpty) {
            options.headers['X-Device-Id'] = deviceId;
          }
          final calendarType = _calendarController?.calendarType.value;
          if (calendarType != null && calendarType.isNotEmpty) {
            options.headers['X-Calendar-Type'] = calendarType;
          }
          // Inject X-Business-ID header when path targets a specific business
          try {
            final uri = options.uri;
            final path = uri.path;
            // If current business exists, prefer it
            final currentBusinessId = _authStore?.currentBusiness?.id;
            int? resolvedBusinessId = currentBusinessId;
            // Fallback: detect business_id from URL like /api/v1/business/{id}/...
            if (resolvedBusinessId == null) {
              final match = RegExp(r"/api/v1/business/(\d+)/").firstMatch(path);
              if (match != null) {
                final idStr = match.group(1);
                if (idStr != null) {
                  resolvedBusinessId = int.tryParse(idStr);
                }
              }
            }
            if (resolvedBusinessId != null) {
              options.headers['X-Business-ID'] = resolvedBusinessId.toString();
            }
          } catch (_) {
            // ignore header injection failures
          }
          if (kDebugMode) {
            // ignore: avoid_print
            print('[API][REQ] ${options.method} ${options.uri}');
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          if (kDebugMode) {
            // ignore: avoid_print
            print('[API][RES] ${response.statusCode} ${response.requestOptions.uri}');
          }
          handler.next(response);
        },
        onError: (error, handler) {
          if (kDebugMode) {
            // ignore: avoid_print
            print('[API][ERR] ${error.message} ${error.requestOptions.uri}');
          }
          handler.next(error);
        },
      ),
    );

    return ApiClient._(dio);
  }

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? query, Options? options, CancelToken? cancelToken, ResponseType? responseType}) {
    final requestOptions = options ?? Options();
    if (responseType != null) {
      requestOptions.responseType = responseType;
    }
    return _dio.get<T>(path, queryParameters: query, options: requestOptions, cancelToken: cancelToken);
  }

  Future<Response<T>> post<T>(String path, {Object? data, Map<String, dynamic>? query, Options? options, CancelToken? cancelToken, ResponseType? responseType}) {
    final requestOptions = options ?? Options();
    if (responseType != null) {
      requestOptions.responseType = responseType;
    }
    return _dio.post<T>(path, data: data, queryParameters: query, options: requestOptions, cancelToken: cancelToken);
  }

  Future<Response<T>> put<T>(String path, {Object? data, Map<String, dynamic>? query, Options? options, CancelToken? cancelToken}) {
    return _dio.put<T>(path, data: data, queryParameters: query, options: options, cancelToken: cancelToken);
  }

  Future<Response<T>> patch<T>(String path, {Object? data, Map<String, dynamic>? query, Options? options, CancelToken? cancelToken}) {
    return _dio.patch<T>(path, data: data, queryParameters: query, options: options, cancelToken: cancelToken);
  }

  Future<Response<T>> delete<T>(String path, {Object? data, Map<String, dynamic>? query, Options? options, CancelToken? cancelToken}) {
    return _dio.delete<T>(path, data: data, queryParameters: query, options: options, cancelToken: cancelToken);
  }

  // Change Password API
  Future<Response<Map<String, dynamic>>> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) {
    return post<Map<String, dynamic>>(
      '/api/v1/auth/change-password',
      data: {
        'current_password': currentPassword,
        'new_password': newPassword,
        'confirm_password': confirmPassword,
      },
    );
  }
}


