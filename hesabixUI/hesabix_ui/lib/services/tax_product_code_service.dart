import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;

import '../core/api_client.dart';

class TaxProductCodeService {
  final ApiClient _api;

  TaxProductCodeService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> searchTaxCodes({
    String? query,
    int skip = 0,
    int limit = 20,
  }) async {
    final params = <String, dynamic>{
      'skip': skip,
      'take': limit,
    };
    if (query != null && query.trim().isNotEmpty) {
      params['q'] = query.trim();
    }
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/tax/product-codes',
      query: params,
    );
    final data = res.data?['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return const {'items': <Map<String, dynamic>>[], 'total': 0};
  }

  Future<Map<String, dynamic>?> getTaxCodeByCode(String code) async {
    if (code.trim().isEmpty) return null;
    try {
      final res = await _api.get<Map<String, dynamic>>('/api/v1/tax/product-codes/$code');
      final data = res.data?['data'];
      if (data is Map<String, dynamic>) {
        return data;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<String> importFromXml({
    required String filename,
    required Uint8List bytes,
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = dio.FormData.fromMap({
      'file': dio.MultipartFile.fromBytes(
        bytes,
        filename: filename,
      ),
    });
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/tax/product-codes/import',
      data: formData,
      options: dio.Options(contentType: 'multipart/form-data'),
      onSendProgress: onProgress,
    );
    final data = res.data?['data'];
    if (data is Map<String, dynamic> && data['job_id'] != null) {
      return data['job_id'].toString();
    }
    throw Exception('پاسخ نامعتبر از سرور دریافت شد');
  }

  Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/jobs/$jobId');
    final data = res.data?['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return const {};
  }
}

