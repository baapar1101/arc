import 'package:hesabix_ui/core/api_client.dart';

/// نرخ اسنپ‌شات مرکزی برای کسب‌وکار + ثبت سریع تسعیر.
class BusinessFxGlobalRateService {
  BusinessFxGlobalRateService(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> latest({required int businessId}) async {
    final res = await _api.get('/api/v1/businesses/$businessId/fx-global-rates/latest');
    final data = res.data is Map ? res.data['data'] : res.data;
    return Map<String, dynamic>.from(data as Map? ?? {});
  }

  Future<Map<String, dynamic>> applyFromGlobal({
    required int businessId,
    required List<Map<String, dynamic>> items,
    String? note,
  }) async {
    final res = await _api.post(
      '/api/v1/businesses/$businessId/currency-rates/apply-from-global',
      data: {
        'items': items,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    final data = res.data is Map ? res.data['data'] : res.data;
    return Map<String, dynamic>.from(data as Map? ?? {});
  }
}
