import 'package:hesabix_ui/core/api_client.dart';

/// زمان‌بندی خودکار ثبت نرخ تسعیر از اسنپ‌شات مرکزی + آفست.
class BusinessFxAutoSyncService {
  BusinessFxAutoSyncService(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> getSettings({required int businessId}) async {
    final res = await _api.get('/api/v1/businesses/$businessId/fx-auto-sync');
    final data = res.data is Map ? res.data['data'] : res.data;
    return Map<String, dynamic>.from(data as Map? ?? {});
  }

  Future<Map<String, dynamic>> saveSettings({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put(
      '/api/v1/businesses/$businessId/fx-auto-sync',
      data: payload,
    );
    final data = res.data is Map ? res.data['data'] : res.data;
    return Map<String, dynamic>.from(data as Map? ?? {});
  }

  Future<Map<String, dynamic>> preview({
    required int businessId,
    Map<String, dynamic>? draft,
  }) async {
    if (draft != null) {
      final res = await _api.post(
        '/api/v1/businesses/$businessId/fx-auto-sync/preview',
        data: draft,
      );
      final data = res.data is Map ? res.data['data'] : res.data;
      return Map<String, dynamic>.from(data as Map? ?? {});
    }
    final res = await _api.get('/api/v1/businesses/$businessId/fx-auto-sync/preview');
    final data = res.data is Map ? res.data['data'] : res.data;
    return Map<String, dynamic>.from(data as Map? ?? {});
  }

  Future<Map<String, dynamic>> runNow({required int businessId}) async {
    final res = await _api.post('/api/v1/businesses/$businessId/fx-auto-sync/run-now');
    final data = res.data is Map ? res.data['data'] : res.data;
    return Map<String, dynamic>.from(data as Map? ?? {});
  }
}
