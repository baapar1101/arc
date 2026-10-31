import '../core/api_client.dart';

class DigipayService {
  static const pluginCode = 'digipay_credit';

  final ApiClient _api;

  DigipayService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Map<String, dynamic> _dataMap(Map<String, dynamic>? body) {
    if (body == null) return const {};
    final d = body['data'];
    if (d is Map) return Map<String, dynamic>.from(d);
    return const {};
  }

  Future<Map<String, dynamic>> getSettings({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/digipay/business/$businessId/settings',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> updateSettings({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/digipay/business/$businessId/settings',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> testConnection({required int businessId}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/digipay/business/$businessId/settings/test',
      data: const <String, dynamic>{},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> createTicket({
    required int businessId,
    required num amount,
    required String cellNumber,
    String source = 'quick_sales',
    List<Map<String, dynamic>>? items,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/digipay/business/$businessId/tickets',
      data: {
        'amount': amount,
        'cell_number': cellNumber,
        'source': source,
        if (items != null) 'items': items,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> recordManualPurchase({
    required int businessId,
    required num amount,
    String? cellNumber,
    String? trackingCode,
    String source = 'manual',
    String channel = 'qr',
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/digipay/business/$businessId/purchases/manual',
      data: {
        'amount': amount,
        if (cellNumber != null && cellNumber.isNotEmpty) 'cell_number': cellNumber,
        if (trackingCode != null && trackingCode.isNotEmpty)
          'tracking_code': trackingCode,
        'source': source,
        'channel': channel,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> getPurchase({
    required int businessId,
    required int purchaseId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/digipay/business/$businessId/purchases/$purchaseId',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> listPurchases({
    required int businessId,
    String? status,
    String? dateFrom,
    String? dateTo,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/digipay/business/$businessId/purchases',
      query: {
        if (status != null && status.isNotEmpty) 'status': status,
        if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
        'limit': limit,
        'offset': offset,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> deliverPurchase({
    required int businessId,
    required int purchaseId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/digipay/business/$businessId/purchases/$purchaseId/deliver',
      data: const <String, dynamic>{},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> refundPurchase({
    required int businessId,
    required int purchaseId,
    num? amount,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/digipay/business/$businessId/purchases/$purchaseId/refund',
      data: {if (amount != null) 'amount': amount},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> previewSettlement({
    required int businessId,
    List<int>? purchaseIds,
    num? commissionPercent,
    num? vatOnCommissionPercent,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/digipay/business/$businessId/settlements/preview',
      data: {
        if (purchaseIds != null) 'purchase_ids': purchaseIds,
        if (commissionPercent != null) 'commission_percent': commissionPercent,
        if (vatOnCommissionPercent != null)
          'vat_on_commission_percent': vatOnCommissionPercent,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> registerSettlement({
    required int businessId,
    required String settlementDate,
    int? bankAccountId,
    List<int>? purchaseIds,
    num? commissionPercent,
    num? vatOnCommissionPercent,
    num? commissionAmount,
    num? vatAmount,
    num? netAmount,
    num? grossAmount,
    String? notes,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/digipay/business/$businessId/settlements',
      data: {
        'settlement_date': settlementDate,
        if (bankAccountId != null) 'bank_account_id': bankAccountId,
        if (purchaseIds != null) 'purchase_ids': purchaseIds,
        if (commissionPercent != null) 'commission_percent': commissionPercent,
        if (vatOnCommissionPercent != null)
          'vat_on_commission_percent': vatOnCommissionPercent,
        if (commissionAmount != null) 'commission_amount': commissionAmount,
        if (vatAmount != null) 'vat_amount': vatAmount,
        if (netAmount != null) 'net_amount': netAmount,
        if (grossAmount != null) 'gross_amount': grossAmount,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> listSettlements({
    required int businessId,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/digipay/business/$businessId/settlements',
      query: {'limit': limit, 'offset': offset},
    );
    return _dataMap(res.data);
  }
}
