import 'package:dio/dio.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/models/expense_income_document.dart';

/// سرویس لیست اسناد هزینه/درآمد
class ExpenseIncomeListService {
  final ApiClient _apiClient;

  ExpenseIncomeListService(this._apiClient);

  /// دریافت لیست اسناد هزینه/درآمد
  Future<PaginatedResponse<ExpenseIncomeDocument>> getList({
    required int businessId,
    int page = 1,
    int pageSize = 20,
    String? documentType,
    DateTime? fromDate,
    DateTime? toDate,
    String? search,
    String? sortBy = 'document_date',
    bool sortDesc = true,
  }) async {
    try {
      final queryInfo = {
        'take': pageSize,
        'skip': (page - 1) * pageSize,
        'sort_by': sortBy,
        'sort_desc': sortDesc,
        'search': search,
        'document_type': documentType,
        if (fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(fromDate),
        if (toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(toDate),
      };

      final response = await _apiClient.post(
        '/businesses/$businessId/expense-income',
        data: queryInfo,
      );

      final data = response.data['data'];
      final items = (data['items'] as List)
          .map((item) => ExpenseIncomeDocument.fromJson(item))
          .toList();

      final pagination = data['pagination'] as Map<String, dynamic>;

      return PaginatedResponse<ExpenseIncomeDocument>(
        items: items,
        total: pagination['total'] as int,
        page: pagination['page'] as int,
        perPage: pagination['per_page'] as int,
        totalPages: pagination['total_pages'] as int,
        hasNext: pagination['has_next'] as bool,
        hasPrev: pagination['has_prev'] as bool,
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// دریافت جزئیات یک سند
  Future<ExpenseIncomeDocument?> getById(int documentId) async {
    try {
      final response = await _apiClient.get('/expense-income/$documentId');
      final data = response.data['data'];
      return ExpenseIncomeDocument.fromJson(data);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 404) {
        return null;
      }
      throw _handleError(e);
    }
  }

  /// حذف یک سند
  Future<bool> delete(int documentId) async {
    try {
      await _apiClient.delete('/expense-income/$documentId');
      return true;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// حذف چندین سند
  Future<bool> deleteMultiple(List<int> documentIds) async {
    try {
      await _apiClient.post('/expense-income/bulk-delete', data: {
        'document_ids': documentIds,
      });
      return true;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// دریافت فایل Excel
  Future<List<int>> exportExcel({
    required int businessId,
    String? documentType,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final params = {
        'business_id': businessId,
        if (documentType != null) 'document_type': documentType,
        if (fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(fromDate),
        if (toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(toDate),
      };

      return await _apiClient.downloadExcel(
        '/businesses/$businessId/expense-income/export/excel',
        params: params,
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// دریافت فایل PDF
  Future<List<int>> exportPdf({
    required int businessId,
    String? documentType,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      // برای PDF از query parameters استفاده می‌کنیم
      final queryParams = <String, dynamic>{
        'business_id': businessId,
        if (documentType != null) 'document_type': documentType,
        if (fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(fromDate),
        if (toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(toDate),
      };

      final response = await _apiClient.get<List<int>>(
        '/businesses/$businessId/expense-income/export/pdf',
        query: queryParams,
        responseType: ResponseType.bytes,
        options: Options(
          headers: {
            'Accept': 'application/pdf',
          },
        ),
      );
      return response.data ?? [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  Exception _handleError(dynamic error) {
    if (error is DioException) {
      final response = error.response;
      if (response != null) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          final message = data['message'] ?? data['detail'] ?? error.message;
          return Exception(message);
        }
      }
      return Exception(error.message ?? 'خطا در ارتباط با سرور');
    }
    return Exception(error.toString());
  }
}

/// پاسخ صفحه‌بندی شده
class PaginatedResponse<T> {
  final List<T> items;
  final int total;
  final int page;
  final int perPage;
  final int totalPages;
  final bool hasNext;
  final bool hasPrev;

  const PaginatedResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrev,
  });
}
