import '../core/api_client.dart';

class ProductService {
  final ApiClient _api;

  ProductService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> createProduct({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> getProduct({
    required int businessId,
    required int productId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/$productId',
    );
    return Map<String, dynamic>.from(res.data?['data']?['item'] ?? const {});
  }

  Future<Map<String, dynamic>> updateProduct({
    required int businessId,
    required int productId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/$productId',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<bool> deleteProduct({required int businessId, required int productId}) async {
    final res = await _api.delete('/api/v1/products/business/$businessId/$productId');
    return res.statusCode == 200 && (res.data['data']?['deleted'] == true);
  }

  Future<bool> codeExists({
    required int businessId,
    required String code,
    int? excludeProductId,
  }) async {
    final body = {
      'take': 1,
      'skip': 0,
      'filters': [
        {
          'property': 'code',
          'operator': '=',
          'value': code,
        },
      ],
    };
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/search',
      data: body,
    );
    final data = res.data?['data'];
    final items = (data is Map<String, dynamic>) ? data['items'] : null;
    if (items is List && items.isNotEmpty) {
      final first = Map<String, dynamic>.from(items.first);
      final foundId = first['id'] as int?;
      if (excludeProductId != null && foundId == excludeProductId) {
        return false;
      }
      return true;
    }
    return false;
  }
}


