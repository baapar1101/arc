import '../core/api_client.dart';

class CategoryService {
  final ApiClient _api;

  // سازگاری با کدهای قدیمی: positional optional parameter
  CategoryService([ApiClient? apiClient]) : _api = apiClient ?? ApiClient();

  /// دریافت درخت کامل دسته‌بندی‌ها
  Future<List<Map<String, dynamic>>> getCategoriesTree({
    required int businessId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/categories/business/$businessId/tree',
      data: {},
    );
    final data = res.data?['data'];
    final items = (data is Map<String, dynamic>) ? data['items'] : null;
    if (items is List) {
      return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  /// Alias برای سازگاری با کدهای قدیمی
  Future<List<Map<String, dynamic>>> getTree({required int businessId}) {
    return getCategoriesTree(businessId: businessId);
  }

  /// جستجوی دسته‌بندی‌ها با breadcrumb
  Future<List<Map<String, dynamic>>> searchCategories({
    required int businessId,
    required String query,
    int limit = 50,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/categories/business/$businessId/search',
      data: {
        'query': query,
        'limit': limit,
      },
    );
    final data = res.data?['data'];
    final items = (data is Map<String, dynamic>) ? data['items'] : null;
    if (items is List) {
      return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  /// Alias برای سازگاری با کدهای قدیمی
  Future<List<Map<String, dynamic>>> search({
    required int businessId,
    required String query,
    int limit = 50,
  }) {
    return searchCategories(businessId: businessId, query: query, limit: limit);
  }

  /// ایجاد دسته‌بندی جدید
  Future<Map<String, dynamic>> create({
    required int businessId,
    int? parentId,
    String? type,
    required String label,
    String? description,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/categories/business/$businessId',
      data: {
        'parent_id': parentId,
        'label': label,
        if (description != null) 'description': description,
      },
    );
    final data = res.data?['data'];
    return Map<String, dynamic>.from(data?['item'] ?? const {});
  }

  /// به‌روزرسانی دسته‌بندی
  Future<Map<String, dynamic>> update({
    required int businessId,
    required int categoryId,
    String? type,
    String? label,
    String? description,
    int? sortOrder,
    int? parentId,
  }) async {
    final body = <String, dynamic>{
      'category_id': categoryId,
    };
    if (label != null) body['label'] = label;
    if (description != null) body['description'] = description;
    if (sortOrder != null) body['sort_order'] = sortOrder;
    if (parentId != null) body['parent_id'] = parentId;

    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/categories/business/$businessId/update',
      data: body,
    );
    final data = res.data?['data'];
    return Map<String, dynamic>.from(data?['item'] ?? const {});
  }

  /// حذف دسته‌بندی
  Future<bool> delete({
    required int businessId,
    required int categoryId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/categories/business/$businessId/delete',
      data: {
        'category_id': categoryId,
      },
    );
    final data = res.data?['data'];
    return data?['deleted'] == true;
  }
}
