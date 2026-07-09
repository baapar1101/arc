import '../core/api_client.dart';

class CatalogSpecFieldService {
  final ApiClient _apiClient;
  CatalogSpecFieldService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<List<Map<String, dynamic>>> list({
    required int businessId,
    bool activeOnly = true,
    int take = 100,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/catalog-spec-fields/business/$businessId',
      query: {
        'active_only': activeOnly,
        'take': take,
        'skip': 0,
      },
    );
    final data = Map<String, dynamic>.from(res.data?['data'] ?? const {});
    final items = data['items'];
    if (items is List) {
      return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> create({
    required int businessId,
    required String title,
    String? description,
    String dataType = 'text',
    List<String>? options,
    int sortOrder = 0,
    bool isRequired = false,
  }) async {
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/api/v1/catalog-spec-fields/business/$businessId',
      data: {
        'title': title,
        if (description != null && description.isNotEmpty) 'description': description,
        'data_type': dataType,
        if (options != null && options.isNotEmpty) 'options': options,
        'sort_order': sortOrder,
        'is_required': isRequired,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<void> delete({
    required int businessId,
    required int fieldId,
  }) async {
    await _apiClient.delete<Map<String, dynamic>>(
      '/api/v1/catalog-spec-fields/business/$businessId/$fieldId',
    );
  }

  Future<Map<String, dynamic>> update({
    required int businessId,
    required int fieldId,
    String? title,
    String? description,
    String? dataType,
    List<String>? options,
    int? sortOrder,
    bool? isRequired,
    bool? isActive,
  }) async {
    final res = await _apiClient.put<Map<String, dynamic>>(
      '/api/v1/catalog-spec-fields/business/$businessId/$fieldId',
      data: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (dataType != null) 'data_type': dataType,
        if (options != null) 'options': options,
        if (sortOrder != null) 'sort_order': sortOrder,
        if (isRequired != null) 'is_required': isRequired,
        if (isActive != null) 'is_active': isActive,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }
}
