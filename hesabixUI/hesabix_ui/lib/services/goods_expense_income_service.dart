import '../core/api_client.dart';

/// سرویس کالای هزینه‌شده / کالای درآمدشده
class GoodsExpenseIncomeService {
  final ApiClient _api;
  GoodsExpenseIncomeService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> list({
    required int businessId,
    int page = 1,
    int pageSize = 20,
    String? docKind,
    String? status,
    String? search,
    int? personId,
    String? fromDate,
    String? toDate,
  }) async {
    final body = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
      'take': pageSize,
      if (docKind != null && docKind.isNotEmpty) 'doc_kind': docKind,
      if (status != null && status.isNotEmpty) 'status': status,
      if (search != null && search.isNotEmpty) 'search': search,
      if (personId != null) 'person_id': personId,
      if (fromDate != null && fromDate.isNotEmpty) 'from_date': fromDate,
      if (toDate != null && toDate.isNotEmpty) 'to_date': toDate,
    };
    final res = await _api.post<Map<String, dynamic>>(
      '/businesses/$businessId/goods-expense-income',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> get({
    required int businessId,
    required int documentId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/businesses/$businessId/goods-expense-income/$documentId',
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> getSettings({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/businesses/$businessId/goods-expense-income/settings',
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> create({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/businesses/$businessId/goods-expense-income/create',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> update({
    required int businessId,
    required int documentId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/businesses/$businessId/goods-expense-income/$documentId',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> submit({
    required int businessId,
    required int documentId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/businesses/$businessId/goods-expense-income/$documentId/submit',
      data: const {},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> allocate({
    required int businessId,
    required int documentId,
    Map<String, dynamic>? payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/businesses/$businessId/goods-expense-income/$documentId/allocate',
      data: payload ?? const {},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> post({
    required int businessId,
    required int documentId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/businesses/$businessId/goods-expense-income/$documentId/post',
      data: const {},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> cancel({
    required int businessId,
    required int documentId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/businesses/$businessId/goods-expense-income/$documentId/cancel',
      data: const {},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<bool> delete({
    required int businessId,
    required int documentId,
  }) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/businesses/$businessId/goods-expense-income/$documentId',
    );
    return res.statusCode == 200;
  }

  Future<Map<String, dynamic>> createFromStockCount({
    required int businessId,
    required String stockCountCode,
    required String stockCountDate,
    required List<Map<String, dynamic>> items,
    String? notes,
    String? resultMode,
  }) async {
    final body = <String, dynamic>{
      'stock_count_code': stockCountCode,
      'stock_count_date': stockCountDate,
      'items': items,
      if (notes != null) 'notes': notes,
      if (resultMode != null) 'result_mode': resultMode,
    };
    final res = await _api.post<Map<String, dynamic>>(
      '/businesses/$businessId/goods-expense-income/from-stock-count',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }
}
