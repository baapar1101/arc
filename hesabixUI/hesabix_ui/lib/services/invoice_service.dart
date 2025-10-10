import '../core/api_client.dart';

class InvoiceService {
  final ApiClient _api;

  InvoiceService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> createInvoice({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/invoices/business/$businessId',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> updateInvoice({
    required int businessId,
    required int invoiceId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/invoices/business/$businessId/$invoiceId',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> getInvoice({
    required int businessId,
    required int invoiceId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/invoices/business/$businessId/$invoiceId',
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> searchInvoices({
    required int businessId,
    int page = 1,
    int limit = 20,
    String? search,
    Map<String, dynamic>? filters,
  }) async {
    final body = {
      'take': limit,
      'skip': (page - 1) * limit,
      if (search != null && search.isNotEmpty) 'search': search,
      if (filters != null) 'filters': filters,
    };
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/invoices/business/$businessId/search',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }
}


