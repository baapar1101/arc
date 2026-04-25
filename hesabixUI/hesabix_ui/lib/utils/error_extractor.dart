import 'dart:convert';

import 'package:dio/dio.dart' as dio;
import 'package:flutter/widgets.dart' show BuildContext, Locale;

import '../core/api_client.dart';
import '../l10n/app_localizations.dart';
import '../services/errors/api_error.dart';

/// استخراج پیام خطای قابل‌نمایش برای کاربر (زبان از [AppLocalizations] یا آخرین locale برنامه).
class ErrorExtractor {
  static AppLocalizations _resolve(AppLocalizations? t) {
    if (t != null) return t;
    final loc = ApiClient.currentLocale;
    if (loc != null) {
      return lookupAppLocalizations(loc);
    }
    return lookupAppLocalizations(const Locale('en'));
  }

  /// پیام خطا برای نمایش به کاربر؛ ترجیحاً [t] را از `AppLocalizations.of(context)` بدهید.
  static String userMessage(Object e, [AppLocalizations? t]) {
    return _userMessage(e, _resolve(t));
  }

  /// راحت‌تر وقتی [BuildContext] در دسترس است (زبان از همان context).
  static String forContext(Object e, BuildContext context) {
    return userMessage(e, AppLocalizations.of(context));
  }

  /// معادل [userMessage] بدون [AppLocalizations] صریح (زبان از [ApiClient.currentLocale]).
  static String extractErrorMessage(Object e) => userMessage(e, null);

  static String? _extractFromResponseData(dynamic data, AppLocalizations t) {
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

  static bool _isLowLevelNetworkNoise(String s) {
    final l = s.toLowerCase();
    if (l.contains('failed to fetch')) return true;
    if (l.contains('xmlhttprequest')) return true;
    if (l.contains('socketexception')) return true;
    if (l.contains('clientexception')) return true;
    if (l.contains('connection errored') || l.contains('connection error')) {
      return l.contains('dio') || l.contains('onerror') || l.contains('callback') || l.contains('network layer');
    }
    if (l.contains('err_internet_disconnected') || l.contains('err_network_changed')) return true;
    return false;
  }

  static String _dioExceptionMessage(dio.DioException e, AppLocalizations t) {
    final inner = e.error;
    if (inner is ApiErrorDetails) {
      final m = inner.message;
      if (m != null && m.isNotEmpty) return m;
    }

    final response = e.response;
    if (response != null && response.data != null) {
      final msg = _extractFromResponseData(response.data, t);
      if (msg != null && msg.isNotEmpty) return msg;
    }

    switch (e.type) {
      case dio.DioExceptionType.connectionTimeout:
        return t.errorConnectionTimeout;
      case dio.DioExceptionType.sendTimeout:
        return t.errorSendTimeout;
      case dio.DioExceptionType.receiveTimeout:
        return t.errorReceiveTimeout;
      case dio.DioExceptionType.connectionError:
        return t.errorConnectionError;
      case dio.DioExceptionType.badCertificate:
        return t.errorConnectionError;
      case dio.DioExceptionType.cancel:
        return t.errorUnknown;
      case dio.DioExceptionType.badResponse:
      case dio.DioExceptionType.unknown:
        break;
    }

    if (e.message != null && e.message!.isNotEmpty) {
      if (_isLowLevelNetworkNoise(e.message!)) {
        return t.errorConnectionError;
      }
      var message = e.message!;
      if (message.contains('400:')) {
        message = message.split('400:').last.trim();
        if (message.startsWith('{')) {
          return t.errorFileUploadFailed;
        }
        return message;
      }
      if (_isLowLevelNetworkNoise(message) || (message.length > 200 && message.contains('DioException'))) {
        return t.errorConnectionError;
      }
      return message;
    }

    if (e.type == dio.DioExceptionType.connectionError) {
      return t.errorConnectionError;
    }
    return t.errorUnknownServer;
  }

  static String _userMessage(Object e, AppLocalizations t) {
    if (e is dio.DioException) {
      return _dioExceptionMessage(e, t);
    }
    final errorMessage = e.toString();
    if (errorMessage == 'Exception') {
      return t.errorDataSaveFailed;
    }
    if (_isLowLevelNetworkNoise(errorMessage)) {
      return t.errorConnectionError;
    }
    if (errorMessage.contains('خطا')) {
      return errorMessage;
    }
    return t.errorDataSaveFailed;
  }
}
