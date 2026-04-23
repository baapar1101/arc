import 'package:dio/dio.dart';
import 'package:hesabix_ui/core/api_client.dart';

class PublicInvoiceShareService {
  final ApiClient _apiClient;

  PublicInvoiceShareService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// بدون احراز هویت — مسیر public API
  Future<Map<String, dynamic>> fetchByCode(String code) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/public/invoice-links/${Uri.encodeComponent(code)}',
      );
      final body = response.data;
      if (body is Map<String, dynamic>) {
        if (body['success'] == true) {
          final data = body['data'];
          if (data is Map<String, dynamic>) {
            return data;
          }
        }
        final error = body['error'];
        throw DioException(
          requestOptions: response.requestOptions,
          error: error ?? {'message': 'خطا در دریافت اطلاعات'},
          response: response,
        );
      }
      throw DioException(
        requestOptions: response.requestOptions,
        error: {'message': 'پاسخ نامعتبر'},
        response: response,
      );
    } on DioException {
      rethrow;
    } catch (e) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/v1/public/invoice-links/$code'),
        error: e,
      );
    }
  }
}
