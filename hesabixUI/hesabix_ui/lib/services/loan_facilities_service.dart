import '../core/api_client.dart';

/// تسهیلات دریافتی — API هم‌سو با `hesabixAPI/adapters/api/v1/received_loan_facilities.py`
class LoanFacilitiesService {
  final ApiClient _api;

  LoanFacilitiesService([ApiClient? api]) : _api = api ?? ApiClient();

  static Map<String, dynamic> unwrapDataEnvelope(dynamic raw) {
    try {
      if (raw == null || raw is! Map) return <String, dynamic>{};
      final outer = Map<String, dynamic>.from(raw);
      final data = outer['data'];
      if (data == null || data is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(data);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<Map<String, dynamic>> query({
    required int businessId,
    int take = 50,
    int skip = 0,
    String search = '',
    bool sortDesc = true,
  }) async {
    final res = await _api.post(
      '/loan-facilities/businesses/$businessId/query',
      data: <String, dynamic>{
        'take': take,
        'skip': skip,
        if (search.isNotEmpty) 'search': search,
        'sort_desc': sortDesc,
      },
    );
    final inner = unwrapDataEnvelope(res.data);
    final itemsRaw = inner['items'];
    final items = itemsRaw is List ? itemsRaw : <dynamic>[];
    final pag = inner['pagination'];
    final pagination = pag is Map ? Map<String, dynamic>.from(pag) : <String, dynamic>{};
    return <String, dynamic>{'items': items, 'pagination': pagination};
  }

  Future<Map<String, dynamic>> createDraft({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post(
      '/loan-facilities/businesses/$businessId/create',
      data: payload,
    );
    return unwrapDataEnvelope(res.data);
  }

  Future<Map<String, dynamic>> getDetail({
    required int facilityId,
  }) async {
    final res = await _api.get('/loan-facilities/$facilityId');
    return unwrapDataEnvelope(res.data);
  }

  Future<Map<String, dynamic>> regenerateSchedule({
    required int facilityId,
    Map<String, dynamic>? body,
  }) async {
    final res = await _api.post(
      '/loan-facilities/$facilityId/schedule',
      data: body ?? <String, dynamic>{},
    );
    return unwrapDataEnvelope(res.data);
  }

  Future<Map<String, dynamic>> recordInstallmentPayment({
    required int businessId,
    required int facilityId,
    required int installmentId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _api.post(
      '/loan-facilities/businesses/$businessId/facilities/$facilityId/installments/$installmentId/payments',
      data: body,
    );
    return unwrapDataEnvelope(res.data);
  }

  Future<Map<String, dynamic>> deleteInstallmentPayment({
    required int businessId,
    required int facilityId,
    required int installmentId,
    required int paymentId,
  }) async {
    final res = await _api.delete(
      '/loan-facilities/businesses/$businessId/facilities/$facilityId/installments/$installmentId/payments/$paymentId',
    );
    return unwrapDataEnvelope(res.data);
  }
}
