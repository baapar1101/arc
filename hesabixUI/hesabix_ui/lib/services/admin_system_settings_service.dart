import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/api_client.dart';

class AdminSystemSettingsService {
  final ApiClient _api;
  AdminSystemSettingsService(this._api);

  Future<Map<String, dynamic>> getNotificationsConfig() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/system-settings/notifications');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> putNotificationsConfig(Map<String, dynamic> data) async {
    final res = await _api.put<Map<String, dynamic>>('/api/v1/admin/system-settings/notifications', data: data);
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> registerTelegramWebhook() async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/admin/system-settings/notifications/telegram/webhook');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> registerBaleWebhook() async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/admin/system-settings/notifications/bale/webhook');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getSystemConfiguration() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/system-settings/configuration');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> updateSystemConfiguration(Map<String, dynamic> data) async {
    final res = await _api.put<Map<String, dynamic>>('/api/v1/admin/system-settings/configuration', data: data);
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getRedisConfiguration() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/system-settings/redis');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> updateRedisConfiguration(Map<String, dynamic> data) async {
    final res = await _api.put<Map<String, dynamic>>('/api/v1/admin/system-settings/redis', data: data);
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> testRedisConnection() async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/admin/system-settings/redis/test');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getNotificationSmsPricing() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/system-settings/notification-sms-pricing');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> setNotificationSmsPricing({
    double? pricePerSms,
    Map<String, double>? eventTypePrices,
  }) async {
    final data = <String, dynamic>{};
    if (pricePerSms != null) {
      data['price_per_sms'] = pricePerSms;
    }
    if (eventTypePrices != null) {
      data['event_type_prices'] = eventTypePrices;
    }
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/system-settings/notification-sms-pricing',
      data: data,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// ایجاد بکاپ دیتابیس و دانلود مستقیم. برگرداندن بایت‌های فایل.
  Future<Uint8List> createDatabaseBackupDownload({bool compress = true}) async {
    final res = await _api.post<List<int>>(
      '/api/v1/admin/system-settings/database-backup',
      data: {},
      query: {'delivery': 'download', 'compress': compress.toString()},
      responseType: ResponseType.bytes,
      options: Options(
        headers: {'Accept': 'application/octet-stream'},
        receiveTimeout: const Duration(minutes: 10),
      ),
    );
    final data = res.data ?? const <int>[];
    return Uint8List.fromList(data);
  }

  /// ارسال بکاپ دیتابیس به ایمیل.
  Future<Map<String, dynamic>> createDatabaseBackupEmail({
    required String email,
    bool compress = true,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/system-settings/database-backup',
      data: {'email': email},
      query: {'delivery': 'email', 'compress': compress.toString()},
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// ارسال بکاپ دیتابیس به FTP.
  Future<Map<String, dynamic>> createDatabaseBackupFtp({
    required String storageConfigId,
    bool compress = true,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/system-settings/database-backup',
      data: {'storage_config_id': storageConfigId},
      query: {'delivery': 'ftp', 'compress': compress.toString()},
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// ریستور دیتابیس از فایل بکاپ. برگرداندن job_id برای پیگیری وضعیت.
  Future<String> startDatabaseRestore({
    required List<int> fileBytes,
    required String filename,
    required String confirmation,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        fileBytes,
        filename: filename,
      ),
    });

    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/system-settings/database-restore',
      data: formData,
      query: {'confirmation': confirmation},
      options: Options(
        headers: {'Content-Type': 'multipart/form-data'},
        receiveTimeout: const Duration(seconds: 10),
      ),
    );

    final data = res.data?['data'] as Map?;
    final jobId = data?['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      throw Exception('job_id دریافت نشد');
    }
    return jobId;
  }

  /// دریافت وضعیت job ریستور دیتابیس.
  Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/jobs/$jobId');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }
}


