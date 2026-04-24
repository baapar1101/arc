import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// درخواست‌های عمومی لینک اشتراک فایل (بدون ApiKey).
class PublicStorageFileShareService {
  PublicStorageFileShareService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), ''),
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 120),
                headers: const {'Content-Type': 'application/json'},
              ),
            );

  final Dio _dio;

  Future<Map<String, dynamic>> fetchInfo(String token) async {
    final enc = Uri.encodeComponent(token);
    final res = await _dio.get<Map<String, dynamic>>('/api/v1/public/storage/shares/$enc/info');
    final body = res.data;
    if (body == null || body['success'] != true) {
      throw DioException(requestOptions: res.requestOptions, response: res, error: body?['error']);
    }
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> unlock(String token, String password) async {
    final enc = Uri.encodeComponent(token);
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/public/storage/shares/$enc/unlock',
      data: {'password': password},
    );
    final body = res.data;
    if (body == null || body['success'] != true) {
      throw DioException(requestOptions: res.requestOptions, response: res, error: body?['error']);
    }
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  String buildFileUrl(String token, {String? accessToken}) {
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final enc = Uri.encodeComponent(token);
    final qp = <String, dynamic>{};
    if (accessToken != null && accessToken.isNotEmpty) {
      qp['access_token'] = accessToken;
    }
    final uri = Uri.parse('$base/api/v1/public/storage/shares/$enc/file').replace(queryParameters: qp.isEmpty ? null : qp.map((k, v) => MapEntry(k, v.toString())));
    return uri.toString();
  }
}
