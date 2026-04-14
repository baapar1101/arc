import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/receipt_payment_document.dart';

/// پاسخ API برای لیست اسناد
class ReceiptPaymentListResponse {
  final List<ReceiptPaymentDocument> items;
  final int total;
  final int page;
  final int perPage;
  final int totalPages;
  final bool hasNext;
  final bool hasPrev;

  const ReceiptPaymentListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrev,
  });

  factory ReceiptPaymentListResponse.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};
    
    return ReceiptPaymentListResponse(
      items: (json['items'] as List<dynamic>?)
          ?.map((item) => ReceiptPaymentDocument.fromJson(item))
          .toList() ?? [],
      total: pagination['total'] ?? 0,
      page: pagination['page'] ?? 1,
      perPage: pagination['per_page'] ?? 20,
      totalPages: pagination['total_pages'] ?? 0,
      hasNext: pagination['has_next'] ?? false,
      hasPrev: pagination['has_prev'] ?? false,
    );
  }
}

/// سرویس برای مدیریت لیست اسناد دریافت و پرداخت
class ReceiptPaymentListService {
  final ApiClient _apiClient;

  ReceiptPaymentListService(this._apiClient);

  /// دریافت لیست اسناد دریافت و پرداخت
  Future<ReceiptPaymentListResponse> getList({
    required int businessId,
    String? search,
    String? documentType,
    DateTime? fromDate,
    DateTime? toDate,
    String? sortBy,
    bool? sortDesc,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'take': limit,
        'skip': (page - 1) * limit,
        'sort_by': sortBy ?? 'document_date',
        'sort_desc': sortDesc ?? true,
        'search': search,
        'document_type': documentType,
        'from_date': fromDate?.toIso8601String(),
        'to_date': toDate?.toIso8601String(),
      };

      // حذف پارامترهای null
      queryParams.removeWhere((key, value) => value == null);

      final response = await _apiClient.post(
        '/businesses/$businessId/receipts-payments',
        data: queryParams,
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data['data'] as Map<String, dynamic>? ?? {};
        return ReceiptPaymentListResponse.fromJson(data);
      } else {
        throw Exception('خطا در دریافت لیست اسناد: ${response.statusMessage}');
      }
    } catch (e) {
      throw Exception('خطا در دریافت لیست اسناد: $e');
    }
  }

  /// دریافت جزئیات یک سند
  Future<ReceiptPaymentDocument?> getById(int documentId) async {
    try {
      final response = await _apiClient.get('/receipts-payments/$documentId');

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data['data'] as Map<String, dynamic>? ?? {};
        return ReceiptPaymentDocument.fromJson(data);
      } else {
        return null;
      }
    } catch (e) {
      throw Exception('خطا در دریافت جزئیات سند: $e');
    }
  }

  /// حذف یک سند
  Future<bool> delete(int documentId) async {
    try {
      final response = await _apiClient.delete('/receipts-payments/$documentId');

      return response.statusCode == 200;
    } catch (e) {
      throw Exception('خطا در حذف سند: $e');
    }
  }

  /// حذف چندین سند
  Future<bool> deleteMultiple(List<int> documentIds) async {
    try {
      // حذف تک‌تک اسناد
      for (final id in documentIds) {
        await delete(id);
      }
      return true;
    } catch (e) {
      throw Exception('خطا در حذف اسناد: $e');
    }
  }

  /// دریافت آمار کلی
  Future<Map<String, dynamic>> getStats({
    required int businessId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'take': 1, // فقط برای آمار
        'skip': 0,
        'from_date': fromDate?.toIso8601String(),
        'to_date': toDate?.toIso8601String(),
      };

      queryParams.removeWhere((key, value) => value == null);

      // دریافت آمار دریافت‌ها
      final receiptsResponse = await _apiClient.post(
        '/businesses/$businessId/receipts-payments',
        data: {
          ...queryParams,
          'document_type': 'receipt',
        },
      );

      // دریافت آمار پرداخت‌ها
      final paymentsResponse = await _apiClient.post(
        '/businesses/$businessId/receipts-payments',
        data: {
          ...queryParams,
          'document_type': 'payment',
        },
      );

      int receiptsCount = 0;
      int paymentsCount = 0;
      double receiptsTotal = 0.0;
      double paymentsTotal = 0.0;

      if (receiptsResponse.statusCode == 200 && receiptsResponse.data != null) {
        final receiptsData = receiptsResponse.data['data'] as Map<String, dynamic>? ?? {};
        receiptsCount = receiptsData['pagination']?['total'] ?? 0;
        
        final receipts = (receiptsData['items'] as List<dynamic>?)
            ?.map((item) => ReceiptPaymentDocument.fromJson(item))
            .toList() ?? [];
        receiptsTotal = receipts.fold(0.0, (sum, doc) => sum + doc.totalAmount);
      }

      if (paymentsResponse.statusCode == 200 && paymentsResponse.data != null) {
        final paymentsData = paymentsResponse.data['data'] as Map<String, dynamic>? ?? {};
        paymentsCount = paymentsData['pagination']?['total'] ?? 0;
        
        final payments = (paymentsData['items'] as List<dynamic>?)
            ?.map((item) => ReceiptPaymentDocument.fromJson(item))
            .toList() ?? [];
        paymentsTotal = payments.fold(0.0, (sum, doc) => sum + doc.totalAmount);
      }

      return {
        'receipts_count': receiptsCount,
        'payments_count': paymentsCount,
        'receipts_total': receiptsTotal,
        'payments_total': paymentsTotal,
        'total_count': receiptsCount + paymentsCount,
        'net_amount': receiptsTotal - paymentsTotal,
      };
    } catch (e) {
      throw Exception('خطا در دریافت آمار: $e');
    }
  }
}
