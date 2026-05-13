import '../core/api_client.dart';

class BasalamIntegrationService {
  final ApiClient _api;

  BasalamIntegrationService({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient();

  Map<String, dynamic> _dataMap(Map<String, dynamic>? body) {
    if (body == null) return const {};
    final d = body['data'];
    if (d is Map) return Map<String, dynamic>.from(d);
    return const {};
  }

  Future<Map<String, dynamic>> getSettings({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/settings',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> getCurrencyReadiness({
    required int businessId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/currency-readiness',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> updateSettings({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/settings',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> manualSyncOrders({
    required int businessId,
    required List<Map<String, dynamic>> orders,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/sync/orders',
      data: <String, dynamic>{'orders': orders},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> manualSyncProducts({
    required int businessId,
    required List<Map<String, dynamic>> products,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/sync/products',
      data: <String, dynamic>{'products': products},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> publishProducts({
    required int businessId,
    required List<Map<String, dynamic>> products,
    int? vendorId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/sync/products/publish',
      data: <String, dynamic>{
        'products': products,
        if (vendorId != null) 'vendor_id': vendorId,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> pullProducts({
    required int businessId,
    int page = 1,
    int perPage = 50,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/sync/products/pull',
      data: <String, dynamic>{'page': page, 'per_page': perPage},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> pushProductsIncremental({
    required int businessId,
    int sinceMinutes = 120,
    int limit = 50,
    int? vendorId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/sync/products/push/incremental',
      data: <String, dynamic>{
        'since_minutes': sinceMinutes,
        'limit': limit,
        if (vendorId != null) 'vendor_id': vendorId,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> retryProductPublishQueue({
    required int businessId,
    int limit = 20,
    int? vendorId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/sync/products/publish/retry',
      data: <String, dynamic>{
        'limit': limit,
        if (vendorId != null) 'vendor_id': vendorId,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> getProductConflicts({
    required int businessId,
    String? conflictType,
    String? direction,
    String? search,
    String sortBy = 'created_at',
    String sortDir = 'desc',
    int limit = 25,
    int offset = 0,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/sync/products/conflicts',
      query: <String, dynamic>{
        if (conflictType != null && conflictType.isNotEmpty) 'conflict_type': conflictType,
        if (direction != null && direction.isNotEmpty) 'direction': direction,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'sort_by': sortBy,
        'sort_dir': sortDir,
        'limit': limit,
        'offset': offset,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> clearProductConflicts({
    required int businessId,
  }) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/sync/products/conflicts',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> resolveProductConflicts({
    required int businessId,
    required String resolution,
    int limit = 20,
    int? vendorId,
    List<String>? conflictIds,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/sync/products/conflicts/resolve',
      data: <String, dynamic>{
        'resolution': resolution,
        'limit': limit,
        if (vendorId != null) 'vendor_id': vendorId,
        if (conflictIds != null && conflictIds.isNotEmpty) 'conflict_ids': conflictIds,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> listSyncDeadLetter({
    required int businessId,
    String? itemType,
    int limit = 25,
    int offset = 0,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/sync/dead-letter',
      query: <String, dynamic>{
        'limit': limit,
        'offset': offset,
        if (itemType != null && itemType.isNotEmpty) 'item_type': itemType,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> clearSyncDeadLetterAll({
    required int businessId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/sync/dead-letter/clear',
      data: <String, dynamic>{'all': true},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> syncUnverifiedPayments({
    required int businessId,
    bool? verifyRemote,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/sync/payments/unverified',
      data: <String, dynamic>{
        if (verifyRemote != null) 'verify_remote': verifyRemote,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> syncInboundChats({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/sync/chats/inbound',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> sendChatReply({
    required int businessId,
    required int conversationId,
    required String body,
    String? chatId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/chats/$conversationId/reply',
      data: <String, dynamic>{
        'body': body,
        if (chatId != null && chatId.trim().isNotEmpty) 'chat_id': chatId.trim(),
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> getReportsOverview({
    required int businessId,
    int chartDays = 90,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/reports/overview',
      query: {'chart_days': chartDays},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> getReportsSyncedInvoices({
    required int businessId,
    String? dateFrom,
    String? dateTo,
    int skip = 0,
    int take = 50,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/reports/synced-invoices',
      query: {
        if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
        'skip': skip,
        'take': take,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> getReportsDeadLetter({
    required int businessId,
    String? itemType,
    int limit = 100,
    int offset = 0,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/reports/dead-letter',
      query: {
        if (itemType != null && itemType.isNotEmpty) 'item_type': itemType,
        'limit': limit,
        'offset': offset,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> getReportsProductConflicts({
    required int businessId,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/basalam/business/$businessId/reports/product-conflicts',
      query: {
        'limit': limit,
        'offset': offset,
      },
    );
    return _dataMap(res.data);
  }
}
