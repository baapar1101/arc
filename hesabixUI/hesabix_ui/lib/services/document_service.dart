import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/document_model.dart';
import 'document_policy_guard.dart';

/// سرویس مدیریت اسناد حسابداری
class DocumentService {
  final ApiClient _apiClient;
  late final DocumentPolicyGuard _policyGuard = DocumentPolicyGuard(_apiClient);

  DocumentService(this._apiClient);

  /// دریافت لیست اسناد با فیلتر و صفحه‌بندی
  /// 
  /// Parameters:
  /// - [businessId]: شناسه کسب‌وکار
  /// - [documentType]: نوع سند (expense, income, receipt, payment, transfer, manual)
  /// - [fiscalYearId]: شناسه سال مالی
  /// - [fromDate]: از تاریخ (ISO format)
  /// - [toDate]: تا تاریخ (ISO format)
  /// - [currencyId]: شناسه ارز
  /// - [isProforma]: پیش‌فاکتور یا قطعی
  /// - [search]: جستجو در کد سند و توضیحات
  /// - [sortBy]: فیلد مرتب‌سازی
  /// - [sortDesc]: ترتیب نزولی
  /// - [page]: شماره صفحه
  /// - [perPage]: تعداد رکورد در هر صفحه
  Future<Map<String, dynamic>> listDocuments({
    required int businessId,
    String? documentType,
    int? fiscalYearId,
    String? fromDate,
    String? toDate,
    int? currencyId,
    bool? isProforma,
    int? projectId,
    int? personId,
    String? search,
    String sortBy = 'document_date',
    bool sortDesc = true,
    int page = 1,
    int perPage = 50,
  }) async {
    try {
      final skip = (page - 1) * perPage;

      final body = {
        'take': perPage,
        'skip': skip,
        'sort_by': sortBy,
        'sort_desc': sortDesc,
        if (documentType != null) 'document_type': documentType,
        if (fiscalYearId != null) 'fiscal_year_id': fiscalYearId,
        if (fromDate != null) 'from_date': fromDate,
        if (toDate != null) 'to_date': toDate,
        if (currencyId != null) 'currency_id': currencyId,
        if (isProforma != null) 'is_proforma': isProforma,
        if (projectId != null) 'project_id': projectId,
        if (personId != null) 'person_id': personId,
        if (search != null && search.isNotEmpty) 'search': search,
      };

      final response = await _apiClient.post(
        '/businesses/$businessId/documents',
        data: body,
      );

      if (response.data['success'] == true) {
        final data = response.data['data'];
        return {
          'items': (data['items'] as List)
              .map((json) => DocumentModel.fromJson(json as Map<String, dynamic>))
              .toList(),
          'pagination': data['pagination'],
        };
      }

      throw Exception(response.data['message'] ?? 'خطا در دریافت لیست اسناد');
    } catch (e) {
      if (e is DioException) {
        throw Exception(e.response?.data['message'] ?? 'خطا در ارتباط با سرور');
      }
      rethrow;
    }
  }

  /// دریافت جزئیات یک سند
  Future<DocumentModel> getDocument(int documentId) async {
    try {
      final response = await _apiClient.get('/documents/$documentId');

      if (response.data['success'] == true) {
        return DocumentModel.fromJson(response.data['data'] as Map<String, dynamic>);
      }

      throw Exception(response.data['message'] ?? 'خطا در دریافت جزئیات سند');
    } catch (e) {
      if (e is DioException) {
        throw Exception(e.response?.data['message'] ?? 'خطا در ارتباط با سرور');
      }
      rethrow;
    }
  }

  /// حذف یک سند (فقط اسناد manual)
  Future<bool> deleteDocument(int documentId) async {
    try {
      final response = await _apiClient.delete('/documents/$documentId');

      if (response.data['success'] == true) {
        return true;
      }

      throw Exception(response.data['message'] ?? 'خطا در حذف سند');
    } catch (e) {
      if (e is DioException) {
        final errorMessage = e.response?.data['message'] ?? 'خطا در ارتباط با سرور';
        throw Exception(errorMessage);
      }
      rethrow;
    }
  }

  /// حذف گروهی اسناد
  Future<Map<String, dynamic>> bulkDeleteDocuments(List<int> documentIds) async {
    try {
      final response = await _apiClient.post(
        '/documents/bulk-delete',
        data: {'document_ids': documentIds},
      );

      if (response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }

      throw Exception(response.data['message'] ?? 'خطا در حذف گروهی اسناد');
    } catch (e) {
      if (e is DioException) {
        throw Exception(e.response?.data['message'] ?? 'خطا در ارتباط با سرور');
      }
      rethrow;
    }
  }

  /// دریافت خلاصه آماری انواع اسناد
  Future<Map<String, int>> getDocumentTypesSummary(int businessId) async {
    try {
      final response = await _apiClient.get(
        '/businesses/$businessId/documents/types-summary',
      );

      if (response.data['success'] == true) {
        final summary = response.data['data']['summary'] as Map<String, dynamic>;
        return summary.map((key, value) => MapEntry(key, value as int));
      }

      throw Exception(response.data['message'] ?? 'خطا در دریافت آمار');
    } catch (e) {
      if (e is DioException) {
        throw Exception(e.response?.data['message'] ?? 'خطا در ارتباط با سرور');
      }
      rethrow;
    }
  }

  /// خروجی Excel لیست اسناد
  Future<void> exportToExcel({
    required int businessId,
    String? documentType,
    int? fiscalYearId,
    String? fromDate,
    String? toDate,
    int? currencyId,
    bool? isProforma,
  }) async {
    try {
      final body = {
        if (documentType != null) 'document_type': documentType,
        if (fiscalYearId != null) 'fiscal_year_id': fiscalYearId,
        if (fromDate != null) 'from_date': fromDate,
        if (toDate != null) 'to_date': toDate,
        if (currencyId != null) 'currency_id': currencyId,
        if (isProforma != null) 'is_proforma': isProforma,
      };

      await _apiClient.post(
        '/businesses/$businessId/documents/export/excel',
        data: body,
        options: Options(
          responseType: ResponseType.bytes,
        ),
      );

      // ذخیره فایل
      // TODO: پیاده‌سازی ذخیره فایل
      // می‌توان از file_picker یا path_provider استفاده کرد
      throw UnimplementedError('Export to Excel is not implemented yet');
    } catch (e) {
      if (e is DioException) {
        throw Exception(e.response?.data['message'] ?? 'خطا در دریافت فایل Excel');
      }
      rethrow;
    }
  }

  /// دریافت PDF یک سند
  /// 
  /// Parameters:
  /// - [documentId]: شناسه سند
  /// - [templateId]: شناسه قالب سفارشی (اختیاری)
  /// - [paperSize]: اندازه کاغذ (A4, Letter, ...)
  /// - [orientation]: جهت صفحه (portrait, landscape)
  /// 
  /// Returns: بایت‌های فایل PDF
  Future<Uint8List> downloadPdf({
    required int documentId,
    int? templateId,
    String? paperSize,
    String? orientation,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (templateId != null) queryParams['template_id'] = templateId;
      if (paperSize != null) queryParams['paper_size'] = paperSize;
      if (orientation != null) queryParams['orientation'] = orientation;

      final response = await _apiClient.get(
        '/documents/$documentId/pdf',
        query: queryParams.isNotEmpty ? queryParams : null,
        options: Options(
          responseType: ResponseType.bytes,
        ),
      );

      return response.data as Uint8List;
    } catch (e) {
      if (e is DioException) {
        throw Exception(e.response?.data['message'] ?? 'خطا در دریافت فایل PDF');
      }
      rethrow;
    }
  }

  /// ایجاد سند حسابداری دستی جدید
  Future<DocumentModel> createManualDocument({
    required int businessId,
    required CreateManualDocumentRequest request,
    int? fiscalYearIdOverride,
  }) async {
    try {
      // اعتبارسنجی درخواست
      final validationError = request.validate();
      if (validationError != null) {
        throw Exception(validationError);
      }

      await _policyGuard.ensureAllowed(
        businessId: businessId,
        documentType: 'manual',
        documentDate: request.documentDate,
        amount: _calculateManualAmount(request.lines),
      );

      final response = await _apiClient.post(
        '/businesses/$businessId/documents/manual',
        data: request.toJson(),
        options: fiscalYearIdOverride != null
            ? Options(headers: {'X-Fiscal-Year-ID': fiscalYearIdOverride.toString()})
            : null,
      );

      if (response.data['success'] == true) {
        return DocumentModel.fromJson(response.data['data'] as Map<String, dynamic>);
      }

      throw Exception(response.data['message'] ?? 'خطا در ایجاد سند');
    } catch (e) {
      if (e is DioException) {
        final errorMessage = e.response?.data['message'] ?? 'خطا در ارتباط با سرور';
        throw Exception(errorMessage);
      }
      rethrow;
    }
  }

  /// ویرایش سند حسابداری دستی
  Future<DocumentModel> updateManualDocument({
    required int documentId,
    required UpdateManualDocumentRequest request,
    int? fiscalYearIdOverride,
  }) async {
    try {
      // اعتبارسنجی درخواست
      final validationError = request.validate();
      if (validationError != null) {
        throw Exception(validationError);
      }

      final response = await _apiClient.put(
        '/documents/$documentId',
        data: request.toJson(),
        options: fiscalYearIdOverride != null
            ? Options(headers: {'X-Fiscal-Year-ID': fiscalYearIdOverride.toString()})
            : null,
      );

      if (response.data['success'] == true) {
        return DocumentModel.fromJson(response.data['data'] as Map<String, dynamic>);
      }

      throw Exception(response.data['message'] ?? 'خطا در ویرایش سند');
    } catch (e) {
      if (e is DioException) {
        final errorMessage = e.response?.data['message'] ?? 'خطا در ارتباط با سرور';
        throw Exception(errorMessage);
      }
      rethrow;
    }
  }
}

num _calculateManualAmount(List<DocumentLineCreateRequest> lines) {
  double debit = 0;
  double credit = 0;
  for (final line in lines) {
    debit += line.debit;
    credit += line.credit;
  }
  final amount = debit.abs() > credit.abs() ? debit.abs() : credit.abs();
  return amount;
}

