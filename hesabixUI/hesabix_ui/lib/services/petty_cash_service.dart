import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/petty_cash.dart';

class PettyCashService {
  final ApiClient _client;
  PettyCashService({ApiClient? client}) : _client = client ?? ApiClient();

  Future<Map<String, dynamic>> list({required int businessId, required Map<String, dynamic> queryInfo}) async {
    try {
      final res = await _client.post<Map<String, dynamic>>(
        '/api/v1/petty-cash/businesses/$businessId/petty-cash',
        data: queryInfo,
      );
      
      // Null safety checks
      final data = res.data ?? <String, dynamic>{};
      if (data['items'] == null) {
        data['items'] = <dynamic>[];
      }
      
      return data;
    } catch (e) {
      // Return safe fallback data structure
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

  Future<PettyCash> create({required int businessId, required Map<String, dynamic> payload}) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/v1/petty-cash/businesses/$businessId/petty-cash/create',
      data: payload,
    );
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    if (data.isEmpty) {
      throw Exception('No data received from server');
    }
    return PettyCash.fromJson(data);
  }

  Future<PettyCash> getById(int id) async {
    final res = await _client.get<Map<String, dynamic>>('/api/v1/petty-cash/petty-cash/$id');
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return PettyCash.fromJson(data);
  }

  Future<PettyCash> update({required int id, required Map<String, dynamic> payload}) async {
    final res = await _client.put<Map<String, dynamic>>('/api/v1/petty-cash/petty-cash/$id', data: payload);
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return PettyCash.fromJson(data);
  }

  Future<void> delete(int id) async {
    await _client.delete<Map<String, dynamic>>('/api/v1/petty-cash/petty-cash/$id');
  }

  Future<Response<List<int>>> exportExcel({required int businessId, required Map<String, dynamic> body}) async {
    return await _client.post<List<int>>(
      '/api/v1/petty-cash/businesses/$businessId/petty-cash/export/excel',
      data: body,
      options: Options(
        responseType: ResponseType.bytes,
      ),
    );
  }

  Future<Response<List<int>>> exportPdf({required int businessId, required Map<String, dynamic> body}) async {
    return await _client.post<List<int>>(
      '/api/v1/petty-cash/businesses/$businessId/petty-cash/export/pdf',
      data: body,
      options: Options(
        responseType: ResponseType.bytes,
      ),
    );
  }

  Future<Map<String, dynamic>> bulkDelete({required int businessId, required List<int> ids}) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/v1/petty-cash/businesses/$businessId/petty-cash/bulk-delete',
      data: {'ids': ids},
    );
    return (res.data ?? <String, dynamic>{});
  }
}
