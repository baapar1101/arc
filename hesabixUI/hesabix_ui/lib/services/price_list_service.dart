import '../core/api_client.dart';

class PriceListService {
  final ApiClient _api;

  PriceListService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> listPriceLists({
    required int businessId,
    int page = 1,
    int limit = 20,
    String? search,
  }) async {
    final body = {
      'take': limit,
      'skip': (page - 1) * limit,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/price-lists/business/$businessId/search',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<List<Map<String, dynamic>>> listItems({
    required int businessId,
    required int priceListId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/price-lists/business/$businessId/$priceListId/items',
    );
    final data = res.data?['data'];
    final items = (data is Map<String, dynamic>) ? data['items'] : null;
    if (items is List) {
      return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> upsertItem({
    required int businessId,
    required int priceListId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/price-lists/business/$businessId/$priceListId/items',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<bool> deleteItem({
    required int businessId,
    required int itemId,
  }) async {
    final res = await _api.delete(
      '/api/v1/price-lists/business/$businessId/items/$itemId',
    );
    return res.statusCode == 200 && (res.data['data']?['deleted'] == true);
  }
}


