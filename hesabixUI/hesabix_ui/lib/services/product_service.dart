import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;
import '../core/api_client.dart';

class ProductService {
  final ApiClient _api;

  ProductService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> createProduct({
    required int businessId,
    required Map<String, dynamic> payload,
    List<int>? imageBytes,
    String? imageFilename,
  }) async {
    if (imageBytes != null && imageFilename != null) {
      // استفاده از multipart/form-data برای آپلود فایل
      // تبدیل attribute_ids به JSON string برای ارسال صحیح
      final payloadForForm = Map<String, dynamic>.from(payload);
      if (payloadForForm.containsKey('attribute_ids') && payloadForForm['attribute_ids'] is List) {
        payloadForForm['attribute_ids'] = jsonEncode(payloadForForm['attribute_ids']);
      }
      
      final formData = dio.FormData.fromMap({
        ...payloadForForm.map((key, value) => MapEntry(key, value?.toString() ?? '')),
        if (imageBytes.isNotEmpty && imageFilename.isNotEmpty)
          'file': dio.MultipartFile.fromBytes(
            imageBytes,
            filename: imageFilename,
          ),
      });
      
      final res = await _api.post<Map<String, dynamic>>(
        '/api/v1/products/business/$businessId',
        data: formData,
        options: dio.Options(contentType: 'multipart/form-data'),
      );
      return Map<String, dynamic>.from(res.data?['data'] ?? const {});
    } else {
      // استفاده از JSON معمولی
      final res = await _api.post<Map<String, dynamic>>(
        '/api/v1/products/business/$businessId',
        data: payload,
      );
      return Map<String, dynamic>.from(res.data?['data'] ?? const {});
    }
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
    List<int>? imageBytes,
    String? imageFilename,
  }) async {
    if (imageBytes != null && imageFilename != null) {
      // استفاده از multipart/form-data برای آپلود فایل
      // تبدیل attribute_ids به JSON string برای ارسال صحیح
      final payloadForForm = Map<String, dynamic>.from(payload);
      if (payloadForForm.containsKey('attribute_ids') && payloadForForm['attribute_ids'] is List) {
        payloadForForm['attribute_ids'] = jsonEncode(payloadForForm['attribute_ids']);
      }
      
      final formData = dio.FormData.fromMap({
        ...payloadForForm.map((key, value) => MapEntry(key, value?.toString() ?? '')),
        if (imageBytes.isNotEmpty && imageFilename.isNotEmpty)
          'file': dio.MultipartFile.fromBytes(
            imageBytes,
            filename: imageFilename,
          ),
      });
      
      final res = await _api.put<Map<String, dynamic>>(
        '/api/v1/products/business/$businessId/$productId',
        data: formData,
        options: dio.Options(contentType: 'multipart/form-data'),
      );
      return Map<String, dynamic>.from(res.data?['data'] ?? const {});
    } else {
      // استفاده از JSON معمولی
      final res = await _api.put<Map<String, dynamic>>(
        '/api/v1/products/business/$businessId/$productId',
        data: payload,
      );
      return Map<String, dynamic>.from(res.data?['data'] ?? const {});
    }
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
      'take': 5, // fetch a few matches to reliably detect duplicates beyond the current record
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
      for (final it in items) {
        final m = Map<String, dynamic>.from(it as Map);
        final foundId = m['id'] as int?;
        if (excludeProductId == null || foundId != excludeProductId) {
          return true;
        }
      }
      // only the same product found
      return false;
    }
    return false;
  }

  Future<List<Map<String, dynamic>>> searchProducts({
    required int businessId,
    String? searchQuery,
    int limit = 20,
    int skip = 0,
    List<Map<String, dynamic>>? filters,
    List<String>? searchFields,
    List<int>? categoryIds,
  }) async {
    final data = await searchProductsRaw(
      businessId: businessId,
      searchQuery: searchQuery,
      limit: limit,
      skip: skip,
      filters: filters,
      searchFields: searchFields,
      categoryIds: categoryIds,
    );
    final items = data['items'];
    if (items is List) {
      return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  /// پاسخ خام جستجوی محصولات (شامل total_count).
  Future<Map<String, dynamic>> searchProductsRaw({
    required int businessId,
    String? searchQuery,
    int limit = 20,
    int skip = 0,
    List<Map<String, dynamic>>? filters,
    List<String>? searchFields,
    List<int>? categoryIds,
  }) async {
    final body = <String, dynamic>{
      'take': limit,
      'skip': skip,
      if (searchQuery != null && searchQuery.trim().isNotEmpty) 'search': searchQuery.trim(),
      if (filters != null && filters.isNotEmpty) 'filters': filters,
      if (searchFields != null && searchFields.isNotEmpty) 'searchFields': searchFields,
      if (categoryIds != null && categoryIds.isNotEmpty) 'category_ids': categoryIds,
    };
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/search',
      data: body,
    );
    final data = res.data?['data'];
    if (data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(data);
    }
    return const <String, dynamic>{};
  }

  /// اعمال دسته‌ای قیمت پایه از نمای ویرایش گسترده.
  Future<Map<String, dynamic>> applyBulkProductPriceSheet({
    required int businessId,
    required List<Map<String, dynamic>> items,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/bulk-prices-sheet/apply',
      data: {'items': items},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  /// ردیف‌های قیمت لیست برای کالاهای همین صفحه (ورق ویرایش).
  Future<List<Map<String, dynamic>>> fetchBulkPriceSheetItems({
    required int businessId,
    required List<int> productIds,
    required List<int> priceListIds,
  }) async {
    if (productIds.isEmpty || priceListIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/bulk-prices-sheet/price-items',
      data: {
        'product_ids': productIds,
        'price_list_ids': priceListIds,
      },
    );
    final data = res.data?['data'];
    final items = (data is Map<String, dynamic>) ? data['items'] : null;
    if (items is List) {
      return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  /// خروجی اکسل تمام کالاهای مطابق جستجو و لیست‌های قیمت انتخاب‌شده (ورق ویرایش گسترده).
  Future<List<int>> exportBulkPriceSheetExcel({
    required int businessId,
    String? search,
    List<String>? searchFields,
    List<int> priceListIds = const [],
  }) async {
    final res = await _api.post<List<int>>(
      '/api/v1/products/business/$businessId/bulk-prices-sheet/export/excel',
      data: {
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (searchFields != null && searchFields.isNotEmpty) 'search_fields': searchFields,
        'price_list_ids': priceListIds,
      },
      responseType: dio.ResponseType.bytes,
      options: dio.Options(
        receiveTimeout: const Duration(minutes: 5),
        headers: {
          'Accept': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        },
      ),
    );
    final raw = res.data;
    if (raw == null) return const <int>[];
    if (raw is Uint8List) return raw.toList();
    return List<int>.from(raw as List<dynamic>);
  }

  /// ایمپورت اکسل خروجی همین ورق؛ به‌روزرسانی قیمت پایه و ستون‌های pi_*.
  Future<Map<String, dynamic>> importBulkPriceSheetExcel({
    required int businessId,
    required List<int> fileBytes,
    required String filename,
  }) async {
    final formData = dio.FormData.fromMap({
      'file': dio.MultipartFile.fromBytes(
        fileBytes,
        filename: filename.endsWith('.xlsx') ? filename : '$filename.xlsx',
      ),
    });
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/bulk-prices-sheet/import/excel',
      data: formData,
      options: dio.Options(
        contentType: 'multipart/form-data',
        receiveTimeout: const Duration(minutes: 5),
      ),
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }
}


