import 'package:dio/dio.dart';
import 'package:hesabix_ui/core/api_client.dart';

class PublicPayPageService {
  PublicPayPageService({ApiClient? apiClient})
      : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<Map<String, dynamic>> fetch(String username) async {
    final encoded = Uri.encodeComponent(username);
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/api/v1/public/pay/$encoded',
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
  }) async {
    final encoded = Uri.encodeComponent(username);
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/public/pay/$encoded/start',
      data: {
        'amount': amount,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (mobile != null && mobile.trim().isNotEmpty) 'mobile': mobile.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
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
