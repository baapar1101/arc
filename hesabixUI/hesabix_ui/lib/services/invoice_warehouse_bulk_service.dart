import '../core/api_client.dart';

/// عملیات گروهی حواله انبار برای فاکتورهای انتخاب‌شده (هر فاکتور در بک‌اند مستقل پردازش می‌شود).
class InvoiceWarehouseBulkService {
  final ApiClient _api;

  InvoiceWarehouseBulkService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  /// [operation]: `create_draft` | `remove_linked` | `post_drafts`
  /// برای `post_drafts`: [existingPostedPolicy] یکی از
  /// `skip` | `post_drafts_only` | `remove_all_then_create_and_post`
  Future<Map<String, dynamic>> bulkWarehouseOperations({
    required int businessId,
    required String operation,
    required List<int> invoiceIds,
    String? existingPostedPolicy,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/invoices/bulk-warehouse-operations',
      data: <String, dynamic>{
        'operation': operation,
        'invoice_ids': invoiceIds,
        if (existingPostedPolicy != null &&
            existingPostedPolicy.isNotEmpty &&
            operation == 'post_drafts')
          'existing_posted_policy': existingPostedPolicy,
      },
    );
    final data = res.data?['data'];
    if (data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{};
  }
}
