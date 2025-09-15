import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../config/app_config.dart';

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

  static void setCurrentLocale(Locale locale) {
    _currentLocale = locale;
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

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? query, Options? options, CancelToken? cancelToken}) {
    return _dio.get<T>(path, queryParameters: query, options: options, cancelToken: cancelToken);
  }

  Future<Response<T>> post<T>(String path, {Object? data, Map<String, dynamic>? query, Options? options, CancelToken? cancelToken}) {
    return _dio.post<T>(path, data: data, queryParameters: query, options: options, cancelToken: cancelToken);
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
}


