import '../core/api_client.dart';
import '../models/quick_sales_payment_button.dart';

class QuickSalesService {
  final ApiClient _api;

  QuickSalesService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  /// دریافت تنظیمات فروش سریع
  Future<Map<String, dynamic>> getSettings({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/quick-sales/settings',
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  /// به‌روزرسانی تنظیمات فروش سریع
  Future<Map<String, dynamic>> updateSettings({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/quick-sales/settings',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  /// دریافت یا ایجاد مشتری ناشناس
  Future<Map<String, dynamic>> getAnonymousCustomer({
    required int businessId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/quick-sales/anonymous-customer',
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<List<QuickSalesPaymentButtonModel>> listPaymentButtons({
    required int businessId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/quick-sales/payment-buttons',
    );
    final raw = res.data?['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (e) => QuickSalesPaymentButtonModel.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();
  }

  Future<QuickSalesPaymentButtonModel> createPaymentButton({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/quick-sales/payment-buttons',
      data: payload,
    );
    return QuickSalesPaymentButtonModel.fromJson(
      Map<String, dynamic>.from(res.data?['data'] ?? const {}),
    );
  }

  Future<QuickSalesPaymentButtonModel> updatePaymentButton({
    required int businessId,
    required int buttonId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/quick-sales/payment-buttons/$buttonId',
      data: payload,
    );
    return QuickSalesPaymentButtonModel.fromJson(
      Map<String, dynamic>.from(res.data?['data'] ?? const {}),
    );
  }

  Future<void> deletePaymentButton({
    required int businessId,
    required int buttonId,
  }) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/quick-sales/payment-buttons/$buttonId',
    );
  }

  Future<List<QuickSalesPaymentButtonModel>> reorderPaymentButtons({
    required int businessId,
    required List<int> buttonIds,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/quick-sales/payment-buttons/reorder',
      data: {'button_ids': buttonIds},
    );
    final raw = res.data?['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (row) => QuickSalesPaymentButtonModel.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList();
  }

  Future<Map<String, dynamic>> createStockCorrection({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/quick-sales/stock-corrections',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> listStockDiscrepancies({
    required int businessId,
    String? status,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/quick-sales/stock-discrepancies',
      query: status == null ? null : {'status': status},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> resolveStockDiscrepancy({
    required int businessId,
    required int caseId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/quick-sales/stock-discrepancies/$caseId/resolve',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }
}
