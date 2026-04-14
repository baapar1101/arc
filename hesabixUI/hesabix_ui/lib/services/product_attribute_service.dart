import '../core/api_client.dart';

class ProductAttributeService {
  final ApiClient _apiClient;
  ProductAttributeService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> search({
    required int businessId,
    int page = 1,
    int limit = 20,
    String? search,
    String? sortBy,
    bool sortDesc = true,
  }) async {
    final body = <String, dynamic>{
      'take': limit,
      'skip': (page - 1) * limit,
      'sort_desc': sortDesc,
    };
    if (search != null && search.isNotEmpty) body['search'] = search;
    if (sortBy != null && sortBy.isNotEmpty) body['sort_by'] = sortBy;

    final res = await _apiClient.post<Map<String, dynamic>>(
      '/api/v1/product-attributes/business/$businessId/search',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> create({
    required int businessId,
    required String title,
    String? description,
    String? dataType,
    List<String>? options,
  }) async {
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/api/v1/product-attributes/business/$businessId',
      data: {
        'title': title,
        if (description != null) 'description': description,
        if (dataType != null) 'data_type': dataType,
        if (options != null && options.isNotEmpty) 'options': options,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> getOne({
    required int businessId,
    required int id,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/product-attributes/business/$businessId/$id',
    );
    return Map<String, dynamic>.from(res.data?['data']?['item'] ?? const {});
  }

  Future<Map<String, dynamic>> update({
    required int businessId,
    required int id,
    String? title,
    String? description,
    String? dataType,
    List<String>? options,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    if (dataType != null) body['data_type'] = dataType;
    if (options != null) {
      if (options.isEmpty) {
        body['options'] = null;
      } else {
        body['options'] = options;
      }
    }
    final res = await _apiClient.put<Map<String, dynamic>>(
      '/api/v1/product-attributes/business/$businessId/$id',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<bool> delete({
    required int businessId,
    required int id,
  }) async {
    final res = await _apiClient.delete<Map<String, dynamic>>(
      '/api/v1/product-attributes/business/$businessId/$id',
    );
    final data = res.data?['data'];
    if (data is Map<String, dynamic>) return data['deleted'] == true;
    return false;
  }
}


