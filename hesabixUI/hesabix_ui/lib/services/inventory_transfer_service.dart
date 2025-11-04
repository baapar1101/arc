import '../core/api_client.dart';

class InventoryTransferService {
  final ApiClient _api;
  InventoryTransferService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> create({required int businessId, required Map<String, dynamic> payload}) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/inventory-transfers/business/$businessId', data: payload);
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? <String, dynamic>{});
  }
}


