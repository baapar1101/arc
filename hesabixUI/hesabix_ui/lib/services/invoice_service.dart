import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../core/api_client.dart';
import 'document_policy_guard.dart';

class InvoiceService {
  final ApiClient _api;
  late final DocumentPolicyGuard _policyGuard = DocumentPolicyGuard(_api);

  InvoiceService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> createInvoice({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final documentDate = _parseDocumentDate(payload['document_date']);
    final documentType = (payload['invoice_type'] as String?) ?? 'invoice_manual';
    final amount = _extractInvoiceAmount(payload);

    await _policyGuard.ensureAllowed(
      businessId: businessId,
      documentType: documentType,
      documentDate: documentDate,
      amount: amount,
    );

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

  Future<Map<String, dynamic>> getInstallmentPlan({
    required int businessId,
    required int invoiceId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/invoices/business/$businessId/$invoiceId/installments',
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
    // Normalize filters: backend expects a list of {property, operator, value}
    List<Map<String, dynamic>>? normalizedFilters;
    if (filters != null && filters.isNotEmpty) {
      normalizedFilters = filters.entries
          .map((e) => <String, dynamic>{
                'property': e.key,
                'operator': '=',
                'value': e.value,
              })
          .toList();
    }

    final body = {
      'take': limit,
      'skip': (page - 1) * limit,
      if (search != null && search.isNotEmpty) 'search': search,
      if (normalizedFilters != null) 'filters': normalizedFilters,
    };
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/invoices/business/$businessId/search',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<bool> deleteInvoice({
    required int businessId,
    required int invoiceId,
  }) async {
    try {
      final response = await _api.delete<Map<String, dynamic>>(
        '/api/v1/invoices/business/$businessId/$invoiceId',
      );

      if (response.data?['success'] == true) {
        return true;
      }

      throw Exception(response.data?['message'] ?? 'خطا در حذف فاکتور');
    } catch (e) {
      if (e is DioException) {
        final errorMessage = e.response?.data?['message'] ?? 'خطا در ارتباط با سرور';
        throw Exception(errorMessage);
      }
      rethrow;
    }
  }

  /// افزودن یک فاکتور به کارپوشه مودیان
  Future<bool> addToTaxWorkspace({
    required int businessId,
    required int invoiceId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/invoices/business/$businessId/$invoiceId/tax-workspace/add',
      data: const <String, dynamic>{},
    );
    return res.data?['success'] == true;
  }

  /// حذف یک فاکتور از کارپوشه مودیان
  Future<bool> removeFromTaxWorkspace({
    required int businessId,
    required int invoiceId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/invoices/business/$businessId/$invoiceId/tax-workspace/remove',
      data: const <String, dynamic>{},
    );
    return res.data?['success'] == true;
  }

  Future<Map<String, dynamic>> searchInstallments({
    required int businessId,
    Map<String, dynamic>? query,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/invoices/business/$businessId/installments/search',
      data: query ?? const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Uint8List> exportInstallmentsCsv({
    required int businessId,
    Map<String, dynamic>? query,
  }) async {
    final res = await _api.post<dynamic>(
      '/api/v1/invoices/business/$businessId/installments/export/excel',
      data: query ?? const <String, dynamic>{},
      options: Options(responseType: ResponseType.bytes),
    );
    final data = res.data;
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    throw Exception('Invalid CSV response');
  }

  num _extractInvoiceAmount(Map<String, dynamic> payload) {
    final extraInfo = payload['extra_info'];
    if (extraInfo is Map<String, dynamic>) {
      final totals = extraInfo['totals'];
      if (totals is Map<String, dynamic>) {
        final gross = _toNum(totals['gross']);
        final discount = _toNum(totals['discount']);
        final tax = _toNum(totals['tax']);
        final net = gross - discount;
        return (net + tax).abs();
      }
    }

    final lines = payload['lines'];
    if (lines is List) {
      num sum = 0;
      for (final line in lines) {
        if (line is Map<String, dynamic>) {
          final lineExtra = line['extra_info'];
          if (lineExtra is Map<String, dynamic>) {
            sum += _toNum(lineExtra['line_total']);
          }
        }
      }
      if (sum != 0) {
        return sum.abs();
      }
    }

    return _toNum(payload['amount']);
  }

  DateTime _parseDocumentDate(dynamic value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  num _toNum(dynamic value) {
    if (value is num) {
      return value;
    }
    if (value is String && value.isNotEmpty) {
      return num.tryParse(value) ?? 0;
    }
    return 0;
  }

}


