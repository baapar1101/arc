import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/public_person_share_payload.dart';
import '../models/public_invoice_details.dart';

class PublicPersonShareService {
  final ApiClient _apiClient;

  PublicPersonShareService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<PublicPersonSharePayload> fetchByCode(String code) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/public/person-links/$code',
      );
      final body = response.data;
      if (body is Map<String, dynamic>) {
        final success = body['success'] == true;
        if (!success) {
          final error = body['error'];
          throw DioException(
            requestOptions: response.requestOptions,
            error: error ?? {'message': 'خطا در دریافت اطلاعات'},
            response: response,
          );
        }
        final data = body['data'];
        if (data is Map<String, dynamic>) {
          return PublicPersonSharePayload.fromJson(data);
        }
      }
      throw DioException(
        requestOptions: response.requestOptions,
        error: {'message': 'پاسخ نامعتبر از سرور دریافت شد'},
        response: response,
      );
    } on DioException {
      rethrow;
    } catch (e) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/v1/public/person-links/$code'),
        error: e,
      );
    }
  }

  Future<PublicInvoiceDetails> getInvoiceDetails(String code, int documentId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/public/person-links/$code/invoices/$documentId',
      );
      final body = response.data;
      if (body is Map<String, dynamic>) {
        final success = body['success'] == true;
        if (!success) {
          final error = body['error'];
          throw DioException(
            requestOptions: response.requestOptions,
            error: error ?? {'message': 'خطا در دریافت جزئیات فاکتور'},
            response: response,
          );
        }
        final data = body['data'];
        if (data is Map<String, dynamic>) {
          return PublicInvoiceDetails.fromJson(data);
        }
      }
      throw DioException(
        requestOptions: response.requestOptions,
        error: {'message': 'پاسخ نامعتبر از سرور دریافت شد'},
        response: response,
      );
    } on DioException {
      rethrow;
    } catch (e) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/v1/public/person-links/$code/invoices/$documentId'),
        error: e,
      );
    }
  }
}

