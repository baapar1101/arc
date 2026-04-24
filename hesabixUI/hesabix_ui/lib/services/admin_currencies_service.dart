import '../core/api_client.dart';

class AdminCurrenciesService {
  final ApiClient _api;
  AdminCurrenciesService(this._api);

  Future<List<Map<String, dynamic>>> list() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/currencies');
    final raw = res.data;
    final items = (raw is Map<String, dynamic>) ? raw['data'] : raw;
    if (items is List) {
      return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/admin/currencies', data: body);
    final raw = res.data;
    final data = (raw is Map<String, dynamic>) ? raw['data'] : null;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw Exception('پاسخ نامعتبر از سرور');
  }

  Future<Map<String, dynamic>> update(int id, Map<String, dynamic> body) async {
    final res = await _api.patch<Map<String, dynamic>>('/api/v1/admin/currencies/$id', data: body);
    final raw = res.data;
    final data = (raw is Map<String, dynamic>) ? raw['data'] : null;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw Exception('پاسخ نامعتبر از سرور');
  }

  Future<void> delete(int id) async {
    await _api.delete<Map<String, dynamic>>('/api/v1/admin/currencies/$id');
  }

  Future<Map<String, dynamic>> deleteCheck(int id) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/currencies/$id/delete-check');
    final raw = res.data;
    final data = (raw is Map<String, dynamic>) ? raw['data'] : null;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return const <String, dynamic>{};
  }
}
