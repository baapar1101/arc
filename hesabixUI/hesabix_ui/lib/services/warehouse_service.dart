import '../core/api_client.dart';
import '../models/warehouse_model.dart';

class WarehouseService {
  final ApiClient _api;
  WarehouseService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<List<Warehouse>> listWarehouses({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/warehouses/business/$businessId');
    final data = res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final items = data['items'] as List<dynamic>? ?? const <dynamic>[];
    return items.map((e) => Warehouse.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<Warehouse> createWarehouse({required int businessId, required Map<String, dynamic> payload}) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/warehouses/business/$businessId', data: payload);
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return Warehouse.fromJson(data);
  }

  Future<Warehouse> getWarehouse({required int businessId, required int warehouseId}) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/warehouses/business/$businessId/$warehouseId');
    final data = (res.data?['data']?['item'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return Warehouse.fromJson(data);
  }

  Future<Warehouse> updateWarehouse({required int businessId, required int warehouseId, required Map<String, dynamic> payload}) async {
    final res = await _api.put<Map<String, dynamic>>('/api/v1/warehouses/business/$businessId/$warehouseId', data: payload);
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return Warehouse.fromJson(data);
  }

  Future<bool> deleteWarehouse({required int businessId, required int warehouseId}) async {
    final res = await _api.delete<Map<String, dynamic>>('/api/v1/warehouses/business/$businessId/$warehouseId');
    return res.statusCode == 200 && (res.data?['data']?['deleted'] == true);
  }

  Future<Map<String, dynamic>> createFromInvoice({
    required int businessId,
    required int invoiceId,
    Map<String, dynamic>? body,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/from-invoice/$invoiceId',
      data: body ?? const {},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> searchInvoiceSources({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/sources/invoices/search',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> postDoc({
    required int businessId,
    required int docId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/$docId/post',
      data: const {},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> getDoc({
    required int businessId,
    required int docId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/$docId',
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  /// PDF برگه مرسوله پستی (قالب `warehouse_documents` / `postal_label`).
  Future<List<int>> downloadPostalLabelPdf({
    required int businessId,
    required int docId,
    Map<String, dynamic>? query,
  }) async {
    return _api.downloadPdf(
      '/warehouse-docs/business/$businessId/$docId/postal-label.pdf',
      query: query,
    );
  }

  Future<Map<String, dynamic>> search({
    required int businessId,
    int page = 1,
    int limit = 20,
    Map<String, dynamic>? filters,
  }) async {
    final body = {
      'take': limit,
      'skip': (page - 1) * limit,
      ...?filters,
    };
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/search',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> createManual({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/create',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> updateDoc({
    required int businessId,
    required int docId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/$docId',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> updateLine({
    required int businessId,
    required int docId,
    required int lineId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/$docId/lines/$lineId',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<bool> deleteDoc({
    required int businessId,
    required int docId,
  }) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/$docId',
    );
    return res.statusCode == 200 && (res.data?['data']?['deleted'] == true);
  }

  Future<Map<String, dynamic>> cancelDoc({
    required int businessId,
    required int docId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/$docId/cancel',
      data: const {},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> getStockReport({
    required int businessId,
    Map<String, dynamic>? query,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouses/business/$businessId/stock-report',
      data: query ?? const {},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> bulkDeleteDocs({
    required int businessId,
    required List<int> ids,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/bulk-delete',
      data: {'ids': ids},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> getInvoiceLineQuantities({
    required int businessId,
    required int invoiceId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/invoice/$invoiceId/line-quantities',
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> getAvailableInstances({
    required int businessId,
    required int productId,
    int? warehouseId,
  }) async {
    final queryParams = <String, dynamic>{};
    if (warehouseId != null) {
      queryParams['warehouse_id'] = warehouseId;
    }
    
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/product-instances/business/$businessId/product/$productId/available',
      query: queryParams,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> searchInstanceByCode({
    required int businessId,
    required String code,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/product-instances/business/$businessId/search-by-code',
      query: {'code': code},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> convertProductToUnique({
    required int businessId,
    required int productId,
    bool autoGenerateSerial = true,
    String? serialPrefix,
    bool createForExistingStock = true,
    bool? trackSerial,
    bool? trackBarcode,
  }) async {
    final payload = <String, dynamic>{
      'auto_generate_serial': autoGenerateSerial,
      'create_for_existing_stock': createForExistingStock,
    };
    if (serialPrefix != null) {
      payload['serial_prefix'] = serialPrefix;
    }
    if (trackSerial != null) {
      payload['track_serial'] = trackSerial;
    }
    if (trackBarcode != null) {
      payload['track_barcode'] = trackBarcode;
    }
    
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/product-instances/business/$businessId/product/$productId/convert-to-unique',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> getWarehouseStockReport({
    required int businessId,
    List<int>? productIds,
    List<int>? warehouseIds,
    String? asOfDate,
    bool includeZero = false,
  }) async {
    final query = <String, dynamic>{
      if (productIds != null && productIds.isNotEmpty) 'product_ids': productIds,
      if (warehouseIds != null && warehouseIds.isNotEmpty) 'warehouse_ids': warehouseIds,
      if (asOfDate != null) 'as_of_date': asOfDate,
      'include_zero': includeZero,
    };
    
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/reports/stock',
      data: query,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  // Stock Count Methods
  Future<Map<String, dynamic>> startStockCount({
    required int businessId,
    int? warehouseId,
    List<int>? productIds,
    String? asOfDate,
  }) async {
    final payload = <String, dynamic>{};
    if (warehouseId != null) payload['warehouse_id'] = warehouseId;
    if (productIds != null && productIds.isNotEmpty) payload['product_ids'] = productIds;
    if (asOfDate != null) payload['as_of_date'] = asOfDate;
    
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/stock-count/start',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> calculateStockCountDifferences({
    required int businessId,
    required List<Map<String, dynamic>> items,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/stock-count/calculate',
      data: {'items': items},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> createStockCountAdjustment({
    required int businessId,
    required String stockCountCode,
    required String stockCountDate,
    required List<Map<String, dynamic>> items,
    String? notes,
  }) async {
    final payload = <String, dynamic>{
      'stock_count_code': stockCountCode,
      'stock_count_date': stockCountDate,
      'items': items,
    };
    if (notes != null) payload['notes'] = notes;
    
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/stock-count/create-adjustment',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }
}


