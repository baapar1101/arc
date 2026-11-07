import 'package:dio/dio.dart';
import 'package:hesabix_ui/core/api_client.dart';

class PublicPayPageService {
  PublicPayPageService({ApiClient? apiClient})
      : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<Map<String, dynamic>> fetch(String username, {String? token}) async {
    final encoded = Uri.encodeComponent(username);
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/api/v1/public/pay/$encoded',
        query: (token != null && token.trim().isNotEmpty) ? {'token': token.trim()} : null,
      );
      final body = response.data;
      if (body is Map<String, dynamic> && body['success'] == true && body['data'] is Map) {
        return (body['data'] as Map).cast<String, dynamic>();
      }
      throw DioException(
        requestOptions: response.requestOptions,
        error: body?['error'] ?? {'message': 'خطا در دریافت صفحه پرداخت'},
        response: response,
      );
    } on DioException {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> start({
    required String username,
    required double amount,
    String? name,
    String? mobile,
    String? note,
    String? requestToken,
  }) async {
    final encoded = Uri.encodeComponent(username);
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/public/pay/$encoded/start',
      data: {
        'amount': amount,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (mobile != null && mobile.trim().isNotEmpty) 'mobile': mobile.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        if (requestToken != null && requestToken.trim().isNotEmpty) 'request_token': requestToken.trim(),
      },
    );
    final body = response.data;
    if (body is Map<String, dynamic> && body['success'] == true && body['data'] is Map) {
      return (body['data'] as Map).cast<String, dynamic>();
    }
    throw DioException(
      requestOptions: response.requestOptions,
      error: body?['error'] ?? {'message': 'خطا در شروع پرداخت'},
      response: response,
    );
  }
}
