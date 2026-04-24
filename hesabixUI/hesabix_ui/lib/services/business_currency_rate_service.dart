import '../core/api_client.dart';

class BusinessCurrencyRateService {
  final ApiClient _api;

  BusinessCurrencyRateService(ApiClient api) : _api = api;

  Future<Map<String, dynamic>> list({
    required int businessId,
    int skip = 0,
    int take = 50,
    int? currencyId,
  }) async {
    final q = <String, dynamic>{'skip': skip, 'take': take};
    if (currencyId != null) q['currency_id'] = currencyId;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/currency-rates',
      query: q,
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> resolve({
    required int businessId,
    required int currencyId,
    required String asOfIso,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/currency-rates/resolve',
      query: {'currency_id': currencyId, 'as_of': asOfIso},
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> create(
    int businessId,
    Map<String, dynamic> body,
  ) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/currency-rates',
      data: body,
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> update(
    int businessId,
    int rateId,
    Map<String, dynamic> body,
  ) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/currency-rates/$rateId',
      data: body,
    );
    return _data(res.data);
  }

  Future<void> delete(int businessId, int rateId) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/currency-rates/$rateId',
    );
  }

  Map<String, dynamic> _data(dynamic body) {
    if (body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    if (body is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body);
    }
    return <String, dynamic>{};
  }
}
