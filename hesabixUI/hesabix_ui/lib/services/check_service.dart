import 'package:dio/dio.dart';
import '../core/api_client.dart';

class CheckService {
  final ApiClient _client;
  CheckService({ApiClient? client}) : _client = client ?? ApiClient();

  Future<Map<String, dynamic>> list({required int businessId, required Map<String, dynamic> queryInfo}) async {
    try {
      final res = await _client.post<Map<String, dynamic>>(
        '/api/v1/checks/businesses/$businessId/checks',
        data: queryInfo,
      );
      final data = res.data ?? <String, dynamic>{};
      data['items'] ??= <dynamic>[];
      return data;
    } catch (e) {
      return {
        'items': <dynamic>[],
        'pagination': {
          'total': 0,
          'page': 1,
          'per_page': queryInfo['take'] ?? 10,
          'total_pages': 0,
          'has_next': false,
          'has_prev': false,
        },
        'query_info': queryInfo,
      };
    }
  }

  Future<Map<String, dynamic>> getById(int id) async {
    final res = await _client.get<Map<String, dynamic>>('/api/v1/checks/checks/$id');
    return (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  Future<Map<String, dynamic>> getHistory(int checkId) async {
    final res = await _client.get<Map<String, dynamic>>('/api/v1/checks/checks/$checkId/history');
    return (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  Future<Map<String, dynamic>> create({required int businessId, required Map<String, dynamic> payload}) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/v1/checks/businesses/$businessId/checks/create',
      data: payload,
    );
    return (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  Future<Map<String, dynamic>> update({required int id, required Map<String, dynamic> payload}) async {
    final res = await _client.put<Map<String, dynamic>>('/api/v1/checks/checks/$id', data: payload);
    return (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  Future<void> delete(int id) async {
    await _client.delete<Map<String, dynamic>>('/api/v1/checks/checks/$id');
  }

  Future<Response<List<int>>> exportExcel({required int businessId, required Map<String, dynamic> body}) async {
    return await _client.post<List<int>>(
      '/api/v1/checks/businesses/$businessId/checks/export/excel',
      data: body,
      options: Options(responseType: ResponseType.bytes),
    );
  }

  Future<Response<List<int>>> exportPdf({required int businessId, required Map<String, dynamic> body}) async {
    return await _client.post<List<int>>(
      '/api/v1/checks/businesses/$businessId/checks/export/pdf',
      data: body,
      options: Options(responseType: ResponseType.bytes),
    );
  }

  // ===== Actions =====
  Future<Map<String, dynamic>> endorse({required int checkId, required Map<String, dynamic> body}) async {
    final res = await _client.post<Map<String, dynamic>>('/api/v1/checks/checks/$checkId/actions/endorse', data: body);
    return (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  Future<Map<String, dynamic>> clear({required int checkId, required Map<String, dynamic> body}) async {
    final res = await _client.post<Map<String, dynamic>>('/api/v1/checks/checks/$checkId/actions/clear', data: body);
    return (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  Future<Map<String, dynamic>> pay({required int checkId, required Map<String, dynamic> body}) async {
    final res = await _client.post<Map<String, dynamic>>('/api/v1/checks/checks/$checkId/actions/pay', data: body);
    return (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  Future<Map<String, dynamic>> returnCheck({required int checkId, required Map<String, dynamic> body}) async {
    final res = await _client.post<Map<String, dynamic>>('/api/v1/checks/checks/$checkId/actions/return', data: body);
    return (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  Future<Map<String, dynamic>> bounce({required int checkId, required Map<String, dynamic> body}) async {
    final res = await _client.post<Map<String, dynamic>>('/api/v1/checks/checks/$checkId/actions/bounce', data: body);
    return (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  Future<Map<String, dynamic>> deposit({required int checkId, required Map<String, dynamic> body}) async {
    final res = await _client.post<Map<String, dynamic>>('/api/v1/checks/checks/$checkId/actions/deposit', data: body);
    return (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  // ===== Reconciliation =====
  Future<Map<String, dynamic>> calculateReconciliation({required int businessId, required Map<String, dynamic> body}) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/v1/checks/businesses/$businessId/checks/reconciliations/calculate',
      data: body,
    );
    return (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  Future<Map<String, dynamic>> createReconciliation({required int businessId, required Map<String, dynamic> body}) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/v1/checks/businesses/$businessId/checks/reconciliations',
      data: body,
    );
    return (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  Future<Map<String, dynamic>> listReconciliations({required int businessId, required Map<String, dynamic> queryInfo}) async {
    try {
      final res = await _client.post<Map<String, dynamic>>(
        '/api/v1/checks/businesses/$businessId/checks/reconciliations/list',
        data: queryInfo,
      );
      final data = res.data ?? <String, dynamic>{};
      data['items'] ??= <dynamic>[];
      return data;
    } catch (e) {
      return {
        'items': <dynamic>[],
        'pagination': {
          'total': 0,
          'page': 1,
          'per_page': queryInfo['take'] ?? 10,
          'total_pages': 0,
          'has_next': false,
          'has_prev': false,
        },
        'query_info': queryInfo,
      };
    }
  }

  Future<Map<String, dynamic>> getReconciliationById(int id) async {
    final res = await _client.get<Map<String, dynamic>>('/api/v1/checks/reconciliations/$id');
    return (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  Future<void> deleteReconciliation(int id) async {
    await _client.delete<Map<String, dynamic>>('/api/v1/checks/reconciliations/$id');
  }
}


