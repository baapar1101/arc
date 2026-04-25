import 'dart:convert';

import 'package:dio/dio.dart' as dio;
import 'package:flutter/widgets.dart';

import '../core/api_client.dart';
import '../l10n/app_localizations.dart';
import '../services/errors/api_error.dart';

/// کلاس کمکی برای استخراج پیام خطا از exception
class ErrorExtractor {
  /// استخراج پیام خطا از response.data (پشتیبانی از Map و bytes)
  static String? _extractFromResponseData(dynamic data) {
    Map<String, dynamic>? dataMap;
    if (data is Map) {
      dataMap = Map<String, dynamic>.from(data);
    } else if (data is List<int> || data is Iterable<int>) {
      try {
        final decoded = utf8.decode(data is List<int> ? data : data.toList());
        dataMap = jsonDecode(decoded) as Map<String, dynamic>?;
      } catch (_) {
        return null;
      }
    }
    if (dataMap == null) return null;
    final error = dataMap['error'];
    if (error is Map && error['code'] == 'STORAGE_LIMIT_EXCEEDED') {
      return error['message'] as String? ?? 'حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند';
    }
    if (error is Map && error['message'] is String) {
      final message = error['message'] as String;
      if (message.isNotEmpty) return message;
    }
    if (dataMap['message'] is String) {
      final message = dataMap['message'] as String;
      if (message.isNotEmpty) return message;
    }
    return null;
  }

  static AppLocalizations _effectiveL10n([AppLocalizations? explicit]) {
    if (explicit != null) return explicit;
    final bound = ApiClient.currentLocale;
    if (bound != null) {
      return lookupAppLocalizations(bound);
    }
    return lookupAppLocalizations(const Locale('fa'));
  }

  static String _dioTypeMessage(dio.DioExceptionType type, AppLocalizations t) {
    if (type == dio.DioExceptionType.connectionTimeout) {
      return t.errorConnectionTimeout;
    }
    if (type == dio.DioExceptionType.receiveTimeout) {
      return t.errorReceiveTimeout;
    }
    if (type == dio.DioExceptionType.sendTimeout) {
      return t.errorSendTimeout;
    }
    if (type == dio.DioExceptionType.connectionError) {
      return t.errorConnectionError;
    }
    return t.errorUnknownServer;
  }

  /// [l10n] اگر از ویجت با [BuildContext] صدا زده می‌شود پاس بدهید؛ در غیر این صورت
  /// از [ApiClient.currentLocale] (هم‌تراز با زبان اپ) استفاده می‌شود.
  static String extractErrorMessage(Object e, [AppLocalizations? l10n]) {
    final t = _effectiveL10n(l10n);
    if (e is dio.DioException) {
      // خطای ساختاریافتهٔ API (پس از interceptor در ApiClient)
      final inner = e.error;
      if (inner is ApiErrorDetails) {
        final m = inner.message;
        if (m != null && m.isNotEmpty) return m;
      }

      final response = e.response;
      if (response != null && response.data != null) {
        final msg = _extractFromResponseData(response.data);
        if (msg != null) return msg;
      }

      // پیام خطای دیو
      if (e.message != null && e.message!.isNotEmpty) {
        // حذف قسمت‌های تکنیکی از پیام خطا
        String message = e.message!;
        if (message.contains('400:')) {
          message = message.split('400:').last.trim();
          // حذف JSON object از پیام
          if (message.startsWith('{')) {
            message = t.errorExtractorFileUpload;
          }
        }
        return message;
      }

      return _dioTypeMessage(e.type, t);
    }

    // پیام خطای عمومی
    final errorMessage = e.toString();
    if (errorMessage.contains('خطا')) {
      return errorMessage;
    }
    return t.errorExtractorSaveData;
  }
}
