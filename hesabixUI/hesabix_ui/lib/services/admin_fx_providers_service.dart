import 'package:hesabix_ui/core/api_client.dart';

/// سرویس ادمین ارائه‌دهندگان نرخ ارز و اسنپ‌شات مرکزی.
class AdminFxProvidersService {
  AdminFxProvidersService(this._api);

  final ApiClient _api;

  Future<List<Map<String, dynamic>>> listProviders() async {
    final res = await _api.get('/api/v1/admin/fx-providers');
    final data = res.data is Map ? res.data['data'] : res.data;
    final items = (data is Map ? data['items'] : null) as List? ?? const [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> upsertProvider({
    required String code,
    required Map<String, dynamic> body,
  }) async {
    final res = await _api.put('/api/v1/admin/fx-providers/$code', data: body);
    final data = res.data is Map ? res.data['data'] : res.data;
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> testProvider(String code) async {
    final res = await _api.post('/api/v1/admin/fx-providers/$code/test');
    final data = res.data is Map ? res.data['data'] : res.data;
    return Map<String, dynamic>.from(data as Map? ?? {});
  }

  Future<Map<String, dynamic>> fetchNow(String code) async {
    final res = await _api.post('/api/v1/admin/fx-providers/$code/fetch-now');
    final data = res.data is Map ? res.data['data'] : res.data;
    return Map<String, dynamic>.from(data as Map? ?? {});
  }

  Future<List<Map<String, dynamic>>> listGlobalRates({
    String? providerCode,
    String? currencyCode,
  }) async {
    final res = await _api.get(
      '/api/v1/admin/fx-providers/global-rates',
      query: {
        if (providerCode != null) 'provider_code': providerCode,
        if (currencyCode != null) 'currency_code': currencyCode,
      },
    );
    final data = res.data is Map ? res.data['data'] : res.data;
    final items = (data is Map ? data['items'] : null) as List? ?? const [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
