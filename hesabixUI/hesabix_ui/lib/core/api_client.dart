import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';
import '../utils/number_normalizer.dart';
import 'auth_store.dart';
import '../services/errors/api_error.dart';
import 'calendar_controller.dart';
import '../main.dart' show navigatorKey;

class ApiClientOptions {
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Map<String, dynamic> defaultHeaders;

  const ApiClientOptions({
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30), // timeout 30 ثانیه
    this.defaultHeaders = const <String, dynamic>{'Content-Type': 'application/json'},
  });
}

class ApiClient {
  final Dio _dio;
  static Locale? _currentLocale;
  static AuthStore? _authStore;
  static CalendarController? _calendarController;
  static ValueNotifier<int?>? _fiscalYearId;

  static void setCurrentLocale(Locale locale) {
    _currentLocale = locale;
  }

  /// همان localeای که روی MaterialApp است (و متن خطا وقتی [BuildContext] در دسترس نیست).
  static Locale? get currentLocale => _currentLocale;

  static void bindAuthStore(AuthStore store) {
    _authStore = store;
  }

  static AuthStore? getAuthStore() {
    return _authStore;
  }

  static void bindCalendarController(CalendarController controller) {
    _calendarController = controller;
  }

  static CalendarController? getCalendarController() {
    return _calendarController;
  }

  // Fiscal Year binding (allows UI to update selected fiscal year globally)
  static void bindFiscalYear(ValueNotifier<int?> fiscalYearId) {
    _fiscalYearId = fiscalYearId;
  }

  ApiClient._(this._dio);

  /// مدیریت خطاهای نامعتبر بودن سشن یا API key
  static void _handleUnauthorizedError() {
    if (_authStore == null) return;
    
    // حذف API key و اطلاعات ورود
    _authStore!.saveApiKey(null);
    
    // هدایت به صفحه ورود
    final context = navigatorKey.currentContext;
    if (context != null) {
      // استفاده از Future.microtask برای جلوگیری از خطا در حین پردازش خطا
      Future.microtask(() {
        try {
          context.go('/login');
        } catch (e) {
          // اگر هدایت با خطا مواجه شد، از Navigator استفاده می‌کنیم
          if (navigatorKey.currentState != null) {
            navigatorKey.currentState!.pushNamedAndRemoveUntil(
              '/login',
              (route) => false,
            );
          }
        }
      });
    }
  }

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
          // Inject Fiscal Year header if provided
          final fyId = _fiscalYearId?.value;
          if (fyId != null && fyId > 0) {
            options.headers['X-Fiscal-Year-ID'] = fyId.toString();
          }
          // Inject X-Business-ID header when request targets a specific business
          try {
            final uri = options.uri;
            final path = uri.path;
            // If current business exists, prefer it
            final currentBusinessId = _authStore?.currentBusiness?.id;
            int? resolvedBusinessId = currentBusinessId;
            // Fallback: detect business_id from URL like /api/v1/business/{id}/...
            if (resolvedBusinessId == null) {
              // Match any occurrence of /business/{id} in the path
              final match = RegExp(r"/business/(\d+)(/|$)").firstMatch(path);
              if (match != null) {
                final idStr = match.group(1);
                if (idStr != null) {
                  resolvedBusinessId = int.tryParse(idStr);
                }
              }
            }
            // Fallback: query parameter business_id or businessId
            if (resolvedBusinessId == null && uri.queryParameters.isNotEmpty) {
              final qp = uri.queryParameters;
              final idStr = qp['business_id'] ?? qp['businessId'];
              if (idStr != null && idStr.isNotEmpty) {
                resolvedBusinessId = int.tryParse(idStr);
              }
            }
            if (resolvedBusinessId != null) {
              options.headers['X-Business-ID'] = resolvedBusinessId.toString();
            }
            // Inject X-Currency header from authStore selection (code preferred)
            final currencyCode = _authStore?.selectedCurrencyCode;
            if (currencyCode != null && currencyCode.isNotEmpty) {
              options.headers['X-Currency'] = currencyCode;
            }
          } catch (_) {
            // ignore header injection failures
          }
          if (options.data != null) {
            options.data = _normalizeRequestData(options.data);
          }
          if (options.queryParameters.isNotEmpty) {
            options.queryParameters = normalizeQueryParameters(options.queryParameters);
          }
          if (kDebugMode) {
            // ignore: avoid_print
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          if (kDebugMode) {
            // ignore: avoid_print
          }
          handler.next(response);
        },
        onError: (error, handler) {
          final response = error.response;
          if (response != null) {
            try {
              final data = response.data;
              if (data is Map<String, dynamic>) {
                final success = data['success'];
                final errorObj = data['error'];
                if (success == false && errorObj is Map<String, dynamic>) {
                  final errorCode = errorObj['code'] as String?;
                  final apiError = ApiErrorDetails(
                    code: errorCode,
                    message: errorObj['message'] as String?,
                    details: errorObj,
                  );
                  
                  // بررسی خطاهای نامعتبر بودن سشن یا API key
                  final isUnauthorized = response.statusCode == 401 || 
                                       errorCode == 'UNAUTHORIZED' ||
                                       errorCode == 'INVALID_API_KEY' ||
                                       errorCode == 'INVALID_SESSION';
                  
                  if (isUnauthorized && _authStore != null) {
                    // حذف اطلاعات ورود و هدایت به صفحه ورود
                    _handleUnauthorizedError();
                  }
                  
                  handler.reject(DioException(
                    requestOptions: error.requestOptions,
                    error: apiError,
                    response: response,
                    type: error.type,
                  ));
                  return;
                }
              }
            } catch (_) {
              // ignore parsing failures
            }
          }
          
          // بررسی status code 401 حتی اگر ساختار خطا متفاوت باشد
          if (response != null && response.statusCode == 401 && _authStore != null) {
            _handleUnauthorizedError();
          }
          
          if (kDebugMode) {
            // ignore: avoid_print
          }
          handler.next(error);
        },
      ),
    );

    return ApiClient._(dio);
  }

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? query, Options? options, CancelToken? cancelToken, ResponseType? responseType}) {
    path = _resolveApiPath(path);
    final requestOptions = options ?? Options();
    if (responseType != null) {
      requestOptions.responseType = responseType;
    }
    return _dio.get<T>(path, queryParameters: query, options: requestOptions, cancelToken: cancelToken);
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
    ResponseType? responseType,
    ProgressCallback? onSendProgress,
  }) {
    path = _resolveApiPath(path);
    final requestOptions = options ?? Options();
    if (responseType != null) {
      requestOptions.responseType = responseType;
    }
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: query,
      options: requestOptions,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
    );
  }

  Future<Response<T>> put<T>(String path, {Object? data, Map<String, dynamic>? query, Options? options, CancelToken? cancelToken}) {
    path = _resolveApiPath(path);
    return _dio.put<T>(path, data: data, queryParameters: query, options: options, cancelToken: cancelToken);
  }

  Future<Response<T>> patch<T>(String path, {Object? data, Map<String, dynamic>? query, Options? options, CancelToken? cancelToken}) {
    path = _resolveApiPath(path);
    return _dio.patch<T>(path, data: data, queryParameters: query, options: options, cancelToken: cancelToken);
  }

  Future<Response<T>> delete<T>(String path, {Object? data, Map<String, dynamic>? query, Options? options, CancelToken? cancelToken}) {
    path = _resolveApiPath(path);
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

  // Download PDF API
  Future<List<int>> downloadPdf(String path, {Map<String, dynamic>? query, Map<String, dynamic>? data}) async {
    if (data != null) {
      // POST request with data
      final response = await post<List<int>>(
        path,
        data: data,
        query: query,
        responseType: ResponseType.bytes,
        options: Options(
          headers: {
            'Accept': 'application/pdf',
          },
        ),
      );
      return response.data ?? [];
    } else {
      // GET request
      final response = await get<List<int>>(
        path,
        query: query,
        responseType: ResponseType.bytes,
        options: Options(
          headers: {
            'Accept': 'application/pdf',
          },
        ),
      );
      return response.data ?? [];
    }
  }

  // Download Excel API
  Future<List<int>> downloadExcel(String path, {Map<String, dynamic>? params}) async {
    final response = await post<List<int>>(
      path,
      data: params,
      responseType: ResponseType.bytes,
      options: Options(
        headers: {
          'Accept': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        },
      ),
    );
    return response.data ?? [];
  }
}

// Utilities
String _resolveApiPath(String path) {
  // Absolute URL → leave as is
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  // Ensure leading slash
  final p = path.startsWith('/') ? path : '/$path';
  // If already versioned, keep
  if (p.startsWith('/api/')) {
    return p;
  }
  // Auto-prefix with api version
  return '/api/v1$p'.replaceAll(RegExp(r'//+'), '/');
}

dynamic _normalizeRequestData(dynamic data) {
  if (data is FormData) {
    _normalizeFormDataFields(data);
    return data;
  }
  if (data is Map || data is List || data is String) {
    return normalizeDynamic(data);
  }
  return data;
}

void _normalizeFormDataFields(FormData formData) {
  final fields = formData.fields;
  for (var i = 0; i < fields.length; i++) {
    final entry = fields[i];
    final normalized = toEnglishDigits(entry.value);
    if (normalized != entry.value) {
      fields[i] = MapEntry(entry.key, normalized);
    }
  }
}

