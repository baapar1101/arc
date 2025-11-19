import '../core/api_client.dart';

import 'document_policy_guard.dart';

class InventoryTransferService {
  final ApiClient _api;
  late final DocumentPolicyGuard _policyGuard = DocumentPolicyGuard(_api);

  InventoryTransferService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> create({required int businessId, required Map<String, dynamic> payload}) async {
    final documentDate = _parseDocumentDate(payload['document_date']);
    await _policyGuard.ensureAllowed(
      businessId: businessId,
      documentType: 'inventory_transfer',
      documentDate: documentDate,
      amount: 0,
    );

    final res = await _api.post<Map<String, dynamic>>('/api/v1/inventory-transfers/business/$businessId', data: payload);
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? <String, dynamic>{});
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
}

