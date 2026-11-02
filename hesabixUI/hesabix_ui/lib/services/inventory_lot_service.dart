import '../core/api_client.dart';

class InventoryLotService {
  InventoryLotService({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<List<Map<String, dynamic>>> listLots({
    required int businessId,
    required int productId,
    int? warehouseId,
    int? variantId,
    bool sellableOnly = false,
  }) async {
    final qp = <String, dynamic>{
      if (warehouseId != null) 'warehouse_id': warehouseId,
      if (variantId != null) 'variant_id': variantId,
      'sellable_only': sellableOnly,
    };
    final res = await _api.get(
      '/api/v1/inventory-lots/business/$businessId/products/$productId',
      query: qp,
    );
    final data = res.data is Map ? res.data['data'] : res.data;
    final items = (data is Map ? data['items'] : null) as List? ?? const [];
    return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> previewDates({
    required int businessId,
    required int productId,
    String? manufacturingDate,
    String? expiryDate,
  }) async {
    final res = await _api.get(
      '/api/v1/inventory-lots/business/$businessId/products/$productId/preview-dates',
      query: {
        if (manufacturingDate != null && manufacturingDate.isNotEmpty) 'manufacturing_date': manufacturingDate,
        if (expiryDate != null && expiryDate.isNotEmpty) 'expiry_date': expiryDate,
      },
    );
    final data = res.data is Map ? res.data['data'] : res.data;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
