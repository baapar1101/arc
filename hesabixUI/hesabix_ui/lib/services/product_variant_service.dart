import '../core/api_client.dart';

class ProductVariantService {
  final ApiClient _api;
  ProductVariantService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<List<Map<String, dynamic>>> listDimensions({
    required int businessId,
    required int productId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/$productId/variant-dimensions',
    );
    return _asMapList(res.data?['data']);
  }

  Future<List<Map<String, dynamic>>> replaceDimensions({
    required int businessId,
    required int productId,
    required List<Map<String, dynamic>> dimensions,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/$productId/variant-dimensions',
      data: {'dimensions': dimensions},
    );
    return _asMapList(res.data?['data']);
  }

  Future<List<Map<String, dynamic>>> listVariants({
    required int businessId,
    required int productId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/$productId/variants',
    );
    return _asMapList(res.data?['data']);
  }

  Future<Map<String, dynamic>> createVariant({
    required int businessId,
    required int productId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/$productId/variants',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> updateVariant({
    required int businessId,
    required int productId,
    required int variantId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/$productId/variants/$variantId',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> deactivateVariant({
    required int businessId,
    required int productId,
    required int variantId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/$productId/variants/$variantId/deactivate',
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> enableInventoryVariants({
    required int businessId,
    required int productId,
    required int warehouseId,
    required List<Map<String, dynamic>> splits,
    String? documentDate,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/$productId/enable-inventory-variants',
      data: {
        'warehouse_id': warehouseId,
        'splits': splits,
        if (documentDate != null && documentDate.isNotEmpty) 'document_date': documentDate,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<List<Map<String, dynamic>>> listBalances({
    required int businessId,
    required int productId,
    int? warehouseId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/$productId/variant-balances',
      query: {
        if (warehouseId != null) 'warehouse_id': warehouseId,
      },
    );
    return _asMapList(res.data?['data']);
  }

  Future<Map<String, dynamic>> resolveBarcode({
    required int businessId,
    required String token,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/barcode-resolve',
      query: {'token': token},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  static List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
