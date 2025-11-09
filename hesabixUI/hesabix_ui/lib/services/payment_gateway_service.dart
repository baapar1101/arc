import '../core/api_client.dart';

class PaymentGatewayService {
  final ApiClient _api;
  PaymentGatewayService(this._api);

  // Admin CRUD
  Future<List<Map<String, dynamic>>> listAdmin() async {
    final res = await _api.get<Map<String, dynamic>>('/admin/payment-gateways');
    final body = res.data;
    final items = (body is Map<String, dynamic>) ? body['data'] : body;
    if (items is List) {
      return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> createAdmin({
    required String provider,
    required String displayName,
    required Map<String, dynamic> config,
    bool isActive = true,
    bool isSandbox = true,
  }) async {
    final res = await _api.post<Map<String, dynamic>>('/admin/payment-gateways', data: {
      'provider': provider,
      'display_name': displayName,
      'is_active': isActive,
      'is_sandbox': isSandbox,
      'config': config,
    });
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> updateAdmin({
    required int gatewayId,
    String? provider,
    String? displayName,
    bool? isActive,
    bool? isSandbox,
    Map<String, dynamic>? config,
  }) async {
    final res = await _api.put<Map<String, dynamic>>('/admin/payment-gateways/$gatewayId', data: {
      if (provider != null) 'provider': provider,
      if (displayName != null) 'display_name': displayName,
      if (isActive != null) 'is_active': isActive,
      if (isSandbox != null) 'is_sandbox': isSandbox,
      if (config != null) 'config': config,
    });
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<void> deleteAdmin(int gatewayId) async {
    await _api.delete('/admin/payment-gateways/$gatewayId');
  }

  // Business visible gateways
  Future<List<Map<String, dynamic>>> listBusinessGateways(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/businesses/$businessId/wallet/gateways');
    final body = res.data;
    final items = (body is Map<String, dynamic>) ? body['data'] : body;
    if (items is List) {
      return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }
}


