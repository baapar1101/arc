import '../core/api_client.dart';
import '../models/bom_models.dart';

class BomService {
  final ApiClient _api;
  BomService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<List<ProductBOM>> list({required int businessId, int? productId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/boms/business/$businessId',
      query: productId != null ? {'product_id': productId} : null,
    );
    final data = res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final items = data['items'] as List<dynamic>? ?? const <dynamic>[];
    return items.map((e) => ProductBOM.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<ProductBOM> create({required int businessId, required Map<String, dynamic> payload}) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/boms/business/$businessId', data: payload);
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return ProductBOM.fromJson(data);
  }

  Future<ProductBOM> getById({required int businessId, required int bomId}) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/boms/business/$businessId/$bomId');
    final data = (res.data?['data']?['item'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return ProductBOM.fromJson(data);
  }

  Future<ProductBOM> update({required int businessId, required int bomId, required Map<String, dynamic> payload}) async {
    final res = await _api.put<Map<String, dynamic>>('/api/v1/boms/business/$businessId/$bomId', data: payload);
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return ProductBOM.fromJson(data);
  }

  Future<bool> delete({required int businessId, required int bomId}) async {
    final res = await _api.delete<Map<String, dynamic>>('/api/v1/boms/business/$businessId/$bomId');
    return res.statusCode == 200 && (res.data?['data']?['deleted'] == true);
  }

  Future<BomExplosionResult> explode({required int businessId, int? productId, int? bomId, required double quantity}) async {
    final payload = <String, dynamic>{
      if (productId != null) 'product_id': productId,
      if (bomId != null) 'bom_id': bomId,
      'quantity': quantity,
    };
    final res = await _api.post<Map<String, dynamic>>('/api/v1/boms/business/$businessId/explode', data: payload);
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return BomExplosionResult.fromJson(data);
  }

  Future<Map<String, dynamic>> produceDraft({required int businessId, int? productId, int? bomId, required double quantity, int? currencyId, int? fiscalYearId, String? documentDate}) async {
    final payload = <String, dynamic>{
      if (productId != null) 'product_id': productId,
      if (bomId != null) 'bom_id': bomId,
      'quantity': quantity,
      if (currencyId != null) 'currency_id': currencyId,
      if (fiscalYearId != null) 'fiscal_year_id': fiscalYearId,
      if (documentDate != null) 'document_date': documentDate,
    };
    final res = await _api.post<Map<String, dynamic>>('/api/v1/boms/business/$businessId/produce_draft', data: payload);
    return (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
  }
}


