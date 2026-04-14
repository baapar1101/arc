import '../core/api_client.dart';
import 'document_monetization_service.dart';

class DocumentPolicyException implements Exception {
  final String message;
  final String? code;
  final Map<String, dynamic>? details;

  DocumentPolicyException(this.message, {this.code, this.details});

  @override
  String toString() => message;
}

class DocumentPolicyGuard {
  DocumentPolicyGuard(ApiClient apiClient) : _service = DocumentMonetizationService(apiClient);

  final DocumentMonetizationService _service;

  Future<Map<String, dynamic>> ensureAllowed({
    required int businessId,
    required String documentType,
    required DateTime documentDate,
    required num amount,
  }) async {
    final payload = <String, dynamic>{
      'document_type': documentType,
      'document_date': documentDate.toIso8601String(),
      'amount': amount,
    };

    final result = await _service.validateDocumentSubmission(businessId, payload);
    final allowed = result['allowed'] == true;
    if (allowed) {
      return result;
    }
    final message = (result['message'] as String?) ?? 'مجوز ثبت این سند موجود نیست';
    throw DocumentPolicyException(message, code: result['code'] as String?, details: result);
  }
}

