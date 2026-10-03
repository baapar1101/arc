import '../core/api_client.dart';
import '../models/product_bundle.dart';

class ProductBundleService {
  final ApiClient _api;

  ProductBundleService({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient();

  Future<List<ProductBundle>> search({
    required int businessId,
    String? query,
    bool? isActive,
    int take = 100,
    int skip = 0,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/product-bundles/business/$businessId/search',
      data: {
        'take': take,
        'skip': skip,
        if (query != null && query.trim().isNotEmpty) 'search': query.trim(),
        if (isActive != null)
          'filters': [
            {'property': 'is_active', 'operator': '=', 'value': isActive},
          ],
      },
    );
    final data = response.data?['data'];
    final items = data is Map ? data['items'] : null;
    if (items is! List) return const <ProductBundle>[];
    return items
        .whereType<Map>()
        .map((item) => ProductBundle.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<ProductBundle> getOne({
    required int businessId,
    required int bundleId,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/api/v1/product-bundles/business/$businessId/$bundleId',
    );
    return ProductBundle.fromJson(
      Map<String, dynamic>.from(response.data?['data'] as Map? ?? const {}),
    );
  }

  Future<ProductBundle> create({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/product-bundles/business/$businessId',
      data: payload,
    );
    return ProductBundle.fromJson(
      Map<String, dynamic>.from(response.data?['data'] as Map? ?? const {}),
    );
  }

  Future<ProductBundle> update({
    required int businessId,
    required int bundleId,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _api.put<Map<String, dynamic>>(
      '/api/v1/product-bundles/business/$businessId/$bundleId',
      data: payload,
    );
    return ProductBundle.fromJson(
      Map<String, dynamic>.from(response.data?['data'] as Map? ?? const {}),
    );
  }

  Future<void> delete({required int businessId, required int bundleId}) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/product-bundles/business/$businessId/$bundleId',
    );
  }

  Future<List<ProductBundleItem>> expand({
    required int businessId,
    required int bundleId,
    required num quantity,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/product-bundles/business/$businessId/$bundleId/expand',
      data: {'quantity': quantity},
    );
    final data = response.data?['data'];
    final items = data is Map ? data['items'] : null;
    if (items is! List) return const <ProductBundleItem>[];
    return items
        .whereType<Map>()
        .map(
          (item) => ProductBundleItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }
}
