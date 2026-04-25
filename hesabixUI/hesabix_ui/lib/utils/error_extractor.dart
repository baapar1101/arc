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

  /// قطع/تایم‌اوت اتصال یا خطای سطح سوکت (بدون اتکا به صرفاً [DioException.message] که متن فنی انگلیسی است).
  static bool _isNetworkConnectivityFailure(dio.DioException e) {
    final type = e.type;
    if (type == dio.DioExceptionType.connectionTimeout ||
        type == dio.DioExceptionType.receiveTimeout ||
        type == dio.DioExceptionType.sendTimeout ||
        type == dio.DioExceptionType.connectionError ||
        type == dio.DioExceptionType.badCertificate) {
      return true;
    }
    if (type == dio.DioExceptionType.badResponse || type == dio.DioExceptionType.cancel) {
      return false;
    }
    if (type == dio.DioExceptionType.unknown) {
      final m = (e.message ?? '').toLowerCase();
      final errStr = (e.error?.toString() ?? '').toLowerCase();
      if (m.contains('dioexception') &&
          (m.contains('connection timeout') ||
              m.contains('connection error') ||
              m.contains('receive timeout') ||
              m.contains('send timeout') ||
              m.contains('aborted') ||
              m.contains('took longer') ||
              m.contains('larger than') ||
              m.contains('requestoptions'))) {
        return true;
      }
      if (m.contains('socketexception') || errStr.contains('socketexception')) {
        return true;
      }
      if (m.contains('failed host lookup') ||
          m.contains('network is unreachable') ||
          m.contains('errno = 7') ||
          m.contains('errno = 101') ||
          m.contains('no address associated with hostname')) {
        return true;
      }
    }
    return false;
  }

  static String _dioTypeMessage(dio.DioExceptionType type, AppLocalizations t) {
    if (type == dio.DioExceptionType.connectionTimeout ||
        type == dio.DioExceptionType.receiveTimeout ||
        type == dio.DioExceptionType.sendTimeout ||
        type == dio.DioExceptionType.connectionError ||
        type == dio.DioExceptionType.badCertificate) {
      return t.errorInternetUnavailablePleaseRetry;
    }
    if (type == dio.DioExceptionType.cancel) {
      return t.errorUnknownServer;
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

      // قبل از نمایش message خام Dio (متن فنی/انگلیسی) — خطای شبکه/اینترنت
      if (_isNetworkConnectivityFailure(e)) {
        return t.errorInternetUnavailablePleaseRetry;
      }

      // پیام خطای دیو (مثلاً بدنهٔ خطای آپلود)
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
