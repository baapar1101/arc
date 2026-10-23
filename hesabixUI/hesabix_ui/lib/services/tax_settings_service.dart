import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/tax_settings_model.dart';

class TaxSettingsService {
  final ApiClient _apiClient;

  TaxSettingsService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<TaxSettingsModel> fetchSettings(int businessId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/tax-settings/business/$businessId',
      );
      final data = response.data?['data'];
      if (data is Map<String, dynamic>) {
        return TaxSettingsModel.fromJson(data);
      }
      return TaxSettingsModel(businessId: businessId);
    } on DioException catch (e) {
      throw _extractMessage(e, defaultMessage: 'خطا در دریافت تنظیمات سامانه مودیان');
    }
  }

  Future<TaxSettingsModel> saveSettings({
    required int businessId,
    required TaxSettingsModel settings,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/tax-settings/business/$businessId',
        data: settings.toPayload(),
      );
      final data = response.data?['data'];
      if (data is Map<String, dynamic>) {
        return TaxSettingsModel.fromJson(data);
      }
      return settings;
    } on DioException catch (e) {
      throw _extractMessage(e, defaultMessage: 'خطا در ذخیره تنظیمات سامانه مودیان');
    }
  }

  Future<TaxGeneratedKeys> generateKeys({
    required int businessId,
    required String personType,
    required String nationalId,
    String? nameFa,
    String? nameEn,
    String? email,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/tax-settings/business/$businessId/generate-keys',
        data: {
          'person_type': personType,
          'national_id': nationalId,
          if (nameFa != null && nameFa.trim().isNotEmpty) 'name_fa': nameFa.trim(),
          if (nameEn != null && nameEn.trim().isNotEmpty) 'name_en': nameEn.trim(),
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        },
      );
      final data = response.data?['data'];
      if (data is Map<String, dynamic>) {
        return TaxGeneratedKeys.fromJson(data);
      }
      throw Exception('پاسخ نامعتبر از سرور');
    } on DioException catch (e) {
      throw _extractMessage(e, defaultMessage: 'خطا در تولید کلید سامانه مودیان');
    }
  }

  Future<TaxDataQualityReport> fetchDataQuality(int businessId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/tax-settings/business/$businessId/data-quality',
      );
      final data = response.data?['data'];
      if (data is Map<String, dynamic>) {
        return TaxDataQualityReport.fromJson(data);
      }
      throw Exception('پاسخ نامعتبر از سرور');
    } on DioException catch (e) {
      throw _extractMessage(e, defaultMessage: 'خطا در دریافت گزارش کیفیت داده');
    }
  }

  Future<Map<String, dynamic>> testConnection(
    int businessId, {
    Map<String, dynamic>? formPayload,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/tax-settings/business/$businessId/test-connection',
        data: formPayload ?? const <String, dynamic>{},
      );
      final data = response.data?['data'];
      if (data is Map<String, dynamic>) {
        return data;
      }
      throw Exception('پاسخ نامعتبر از سرور');
    } on DioException catch (e) {
      throw _extractMessage(e, defaultMessage: 'خطا در تست اتصال به سامانه مودیان');
    }
  }

  Future<TaxSettingsModel> selectProvider({
    required int businessId,
    required String providerCode,
    bool consent = false,
    Map<String, dynamic>? enrollment,
    String? economicCode,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/tax-settings/business/$businessId/provider',
        data: {
          'provider_code': providerCode,
          'consent': consent,
          if (enrollment != null) 'enrollment': enrollment,
          if (economicCode != null && economicCode.isNotEmpty) 'economic_code': economicCode,
        },
      );
      final data = response.data?['data'];
      if (data is Map<String, dynamic>) {
        return TaxSettingsModel.fromJson(data);
      }
      throw Exception('پاسخ نامعتبر از سرور');
    } on DioException catch (e) {
      throw _extractMessage(e, defaultMessage: 'تغییر روش ارسال مالیاتی ناموفق بود');
    }
  }

  Future<Map<String, dynamic>> syncFanavaAccount(int businessId) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/tax-settings/business/$businessId/fanava/sync',
      );
      final data = response.data?['data'];
      if (data is Map<String, dynamic>) return data;
      throw Exception('پاسخ نامعتبر از سرور');
    } on DioException catch (e) {
      throw _extractMessage(e, defaultMessage: 'بررسی اتصال فن‌آوا ناموفق بود');
    }
  }

  Future<Map<String, dynamic>> syncMotamedAsaAccount(int businessId) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/tax-settings/business/$businessId/motamed-asa/sync',
      );
      final data = response.data?['data'];
      if (data is Map<String, dynamic>) return data;
      throw Exception('پاسخ نامعتبر از سرور');
    } on DioException catch (e) {
      throw _extractMessage(e, defaultMessage: 'بررسی اتصال معتمد آسا ناموفق بود');
    }
  }

  /// A fresh sign-up link on Motamed ASA, under `motamed_asa_onboarding.url`.
  Future<Map<String, dynamic>> renewMotamedAsaLink(int businessId) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/tax-settings/business/$businessId/motamed-asa/link',
      );
      final data = response.data?['data'];
      if (data is Map<String, dynamic>) return data;
      throw Exception('پاسخ نامعتبر از سرور');
    } on DioException catch (e) {
      throw _extractMessage(e, defaultMessage: 'دریافت لینک ثبت‌نام معتمد آسا ناموفق بود');
    }
  }

  Future<Map<String, dynamic>> saveMotamedAsaCredentials({
    required int businessId,
    required String clientId,
    required String clientSecret,
    String? economicCode,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/tax-settings/business/$businessId/motamed-asa/credentials',
        data: {
          'client_id': clientId,
          'client_secret': clientSecret,
          'consent': true,
          if (economicCode != null && economicCode.isNotEmpty) 'economic_code': economicCode,
        },
      );
      final data = response.data?['data'];
      if (data is Map<String, dynamic>) return data;
      throw Exception('پاسخ نامعتبر از سرور');
    } on DioException catch (e) {
      throw _extractMessage(e, defaultMessage: 'ثبت کلید API معتمد آسا ناموفق بود');
    }
  }

  Exception _extractMessage(DioException exception, {required String defaultMessage}) {
    final data = exception.response?.data;
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message']?.toString();
        if (message != null && message.isNotEmpty) {
          return Exception(message);
        }
      }
      final message = data['message']?.toString();
      if (message != null && message.isNotEmpty) {
        return Exception(message);
      }
    }
    return Exception(defaultMessage);
  }
}

