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

  Future<Map<String, dynamic>> testConnection(int businessId) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/tax-settings/business/$businessId/test-connection',
        data: const <String, dynamic>{},
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

