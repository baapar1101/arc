import 'package:dio/dio.dart';
import '../core/api_client.dart';

class CategoryService {
  final ApiClient _apiClient;

  CategoryService(this._apiClient);

  Future<List<Map<String, dynamic>>> getTree({
    required int businessId,
    String? type, // 'product' | 'service'
  }) async {
    try {
      final res = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/categories/business/$businessId/tree',
        data: type != null ? {'type': type} : null,
      );
      final data = res.data?['data'];
      final items = (data is Map<String, dynamic>) ? data['items'] : null;
      if (items is List) {
        return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
      }
      return const <Map<String, dynamic>>[];
    } on DioException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<Map<String, dynamic>> create({
    required int businessId,
    int? parentId,
    required String type, // 'product' | 'service'
    required String label,
  }) async {
    try {
      final res = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/categories/business/$businessId',
        data: {
          'parent_id': parentId,
          'type': type,
          'label': label,
        },
      );
      final data = res.data?['data'];
      final item = (data is Map<String, dynamic>) ? data['item'] : null;
      return Map<String, dynamic>.from(item ?? const {});
    } on DioException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<Map<String, dynamic>> update({
    required int businessId,
    required int categoryId,
    String? type, // optional
    String? label,
  }) async {
    try {
      final body = <String, dynamic>{};
      body['category_id'] = categoryId;
      if (type != null) body['type'] = type;
      if (label != null) body['label'] = label;
      final res = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/categories/business/$businessId/update',
        data: body,
      );
      final data = res.data?['data'];
      final item = (data is Map<String, dynamic>) ? data['item'] : null;
      return Map<String, dynamic>.from(item ?? const {});
    } on DioException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<Map<String, dynamic>> move({
    required int businessId,
    required int categoryId,
    int? newParentId,
  }) async {
    try {
      final res = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/categories/business/$businessId/move',
        data: {
          'category_id': categoryId,
          'new_parent_id': newParentId,
        },
      );
      final data = res.data?['data'];
      final item = (data is Map<String, dynamic>) ? data['item'] : null;
      return Map<String, dynamic>.from(item ?? const {});
    } on DioException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<bool> delete({
    required int businessId,
    required int categoryId,
  }) async {
    try {
      final res = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/categories/business/$businessId/delete',
        data: {
          'category_id': categoryId,
        },
      );
      final data = res.data?['data'];
      if (data is Map<String, dynamic>) {
        return data['deleted'] == true;
      }
      return false;
    } on DioException catch (e) {
      throw Exception(e.message);
    }
  }
}


