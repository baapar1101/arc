import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/frequent_description_item.dart';

class FrequentDescriptionApiService {
  static final ApiClient _api = ApiClient();

  static String _base(int businessId) => '/api/v1/businesses/$businessId/frequent-descriptions';

  static Map<String, dynamic>? _errorBody(Object? e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map<String, dynamic>) return d;
      if (d is Map) return Map<String, dynamic>.from(d);
    }
    return null;
  }

  static Future<List<FrequentDescriptionItem>> list(int businessId, {required String scope}) async {
    try {
      final resp = await _api.get(_base(businessId), query: {'scope': scope});
      if (resp.data['success'] == true) {
        final raw = resp.data['data']?['items'];
        if (raw is! List) return const [];
        return raw
            .map((e) => FrequentDescriptionItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      throw Exception(resp.data['message']?.toString() ?? 'load_error');
    } on DioException catch (e) {
      final m = _errorBody(e);
      throw Exception(m?['message']?.toString() ?? e.message ?? 'load_error');
    }
  }

  static void _throwIfLimitReached(Map<String, dynamic> m) {
    void checkErr(Object? err) {
      if (err is Map && err['code'] == 'LIMIT_REACHED') {
        throw FrequentDescriptionLimitException();
      }
    }

    checkErr(m['error']);
    final detail = m['detail'];
    if (detail is Map) {
      checkErr(detail['error']);
    }
  }

  static Future<FrequentDescriptionItem> create(int businessId, String text, {required String scope}) async {
    try {
      final resp = await _api.post(_base(businessId), data: {'text': text, 'scope': scope});
      if (resp.data['success'] == true) {
        return FrequentDescriptionItem.fromJson(Map<String, dynamic>.from(resp.data['data'] as Map));
      }
      throw Exception(resp.data['message']?.toString() ?? 'Error');
    } on DioException catch (e) {
      final m = _errorBody(e);
      if (m != null) {
        try {
          _throwIfLimitReached(m);
        } on FrequentDescriptionLimitException {
          rethrow;
        }
      }
      rethrow;
    }
  }

  static Future<void> delete(int businessId, int id) async {
    try {
      final resp = await _api.delete('${_base(businessId)}/$id');
      if (resp.data['success'] != true) {
        throw Exception(resp.data['message']?.toString() ?? 'Error');
      }
    } on DioException catch (e) {
      final m = _errorBody(e);
      throw Exception(m?['message']?.toString() ?? e.message ?? 'delete_error');
    }
  }
}

class FrequentDescriptionLimitException implements Exception {}
