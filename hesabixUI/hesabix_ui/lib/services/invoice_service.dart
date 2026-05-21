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
    bool isInstallmentSale = false,
    String? sortBy,
    bool sortDesc = true,
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

    final body = <String, dynamic>{
      'take': limit,
      'skip': (page - 1) * limit,
      if (search != null && search.isNotEmpty) 'search': search,
      if (normalizedFilters != null) 'filters': normalizedFilters,
      if (isInstallmentSale) 'is_installment_sale': true,
      if (sortBy != null && sortBy.isNotEmpty) 'sort_by': sortBy,
      'sort_desc': sortDesc,
    };
    // Backend also reads person_id and currency_id from flat body keys
    if (filters != null) {
      if (filters['person_id'] != null) body['person_id'] = filters['person_id'];
      if (filters['currency_id'] != null) body['currency_id'] = filters['currency_id'];
    }
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/invoices/business/$businessId/search',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  /// جستجوی فاکتورهای اقساطی برای انتخاب در سند دریافت (تخصیص به اقساط)
  /// شامل: فیلتر شخص، ارز، جستجو، مرتب‌سازی بر اساس مانده، صفحه‌بندی
  Future<Map<String, dynamic>> searchInstallmentInvoices({
    required int businessId,
    int? personId,
    int? currencyId,
    int page = 1,
    int limit = 20,
    String? search,
    String sortBy = 'remaining_amount',
    bool sortDesc = true,
  }) async {
    final filters = <String, dynamic>{};
    if (personId != null) filters['person_id'] = personId;
    if (currencyId != null) filters['currency_id'] = currencyId;

    return searchInvoices(
      businessId: businessId,
      page: page,
      limit: limit,
      search: search?.trim().isEmpty ?? true ? null : search,
      filters: filters.isEmpty ? null : filters,
      isInstallmentSale: true,
      sortBy: sortBy,
      sortDesc: sortDesc,
    );
  }

  /// محاسبه مانده چند فاکتور در یک درخواست
  Future<Map<String, dynamic>> calculateInvoicesRemaining({
    required int businessId,
    required List<int> invoiceIds,
  }) async {
    final body = {
      'invoice_ids': invoiceIds,
    };
    
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/invoices/business/$businessId/invoices/calculate-remaining',
      data: body,
    );
    
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  /// دریافت اطلاعات مرتبط با فاکتور برای نمایش در هشدار حذف
  Future<Map<String, dynamic>> getInvoiceDeleteInfo({
    required int businessId,
    required int invoiceId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/invoices/business/$businessId/$invoiceId/delete-info',
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

  /// حذف گروهی فاکتورها. نتیجه شامل deleted (لیست idهای حذف‌شده) و skipped (لیست {id, code, reason}) است.
  Future<Map<String, dynamic>> deleteMultiple({
    required int businessId,
    required List<int> invoiceIds,
  }) async {
    if (invoiceIds.isEmpty) {
      return {'deleted': <int>[], 'skipped': <Map<String, dynamic>>[]};
    }
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/invoices/business/$businessId/bulk-delete',
      data: {'invoice_ids': invoiceIds},
    );
    final data = res.data?['data'];
    if (data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(data);
    }
    return {'deleted': <int>[], 'skipped': <Map<String, dynamic>>[]};
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

  Future<List<int>> downloadInvoicePdf({
    required int businessId,
    required int invoiceId,
    Map<String, dynamic>? query,
  }) async {
    return _api.downloadPdf(
      '/invoices/business/$businessId/$invoiceId/pdf',
      query: query,
    );
  }

  Future<Map<String, dynamic>?> getInvoiceShareLink({
    required int businessId,
    required int invoiceId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/invoices/business/$businessId/$invoiceId/share-link',
    );
    final data = res.data?['data'];
    if (data is Map<String, dynamic>) {
      final link = data['link'];
      if (link is Map<String, dynamic>) {
        return Map<String, dynamic>.from(link);
      }
      if (link == null) {
        return null;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> createInvoiceShareLink({
    required int businessId,
    required int invoiceId,
    int? expiresInHours,
    int? maxViewCount,
    bool replaceExisting = true,
    bool? onlinePaymentEnabled,
    int? onlinePaymentGatewayId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/invoices/business/$businessId/$invoiceId/share-link',
      data: {
        if (expiresInHours != null) 'expires_in_hours': expiresInHours,
        if (maxViewCount != null) 'max_view_count': maxViewCount,
        'replace_existing': replaceExisting,
        if (onlinePaymentEnabled != null) 'online_payment_enabled': onlinePaymentEnabled,
        if (onlinePaymentGatewayId != null) 'online_payment_gateway_id': onlinePaymentGatewayId,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> patchInvoiceShareLinkPayment({
    required int businessId,
    required int invoiceId,
    required Map<String, dynamic> patch,
  }) async {
    final res = await _api.patch<Map<String, dynamic>>(
      '/api/v1/invoices/business/$businessId/$invoiceId/share-link/payment',
      data: patch,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<void> revokeInvoiceShareLink({
    required int businessId,
    required int invoiceId,
  }) async {
    await _api.delete(
      '/api/v1/invoices/business/$businessId/$invoiceId/share-link',
    );
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

  /// دانلود تمپلیت Excel برای ایمپورت فاکتورها
  Future<Uint8List> downloadImportTemplate({
    required int businessId,
  }) async {
    final res = await _api.post<dynamic>(
      '/api/v1/invoices/business/$businessId/import/template',
      options: Options(responseType: ResponseType.bytes),
    );
    final data = res.data;
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    throw Exception('Invalid template response');
  }

  /// ایمپورت فاکتورها از فایل Excel
  Future<Map<String, dynamic>> importInvoicesFromExcel({
    required int businessId,
    required List<int> fileBytes,
    required String filename,
    required bool dryRun,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(fileBytes, filename: filename),
      'dry_run': dryRun.toString(),
    });
    
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/invoices/business/$businessId/import/excel',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

}


