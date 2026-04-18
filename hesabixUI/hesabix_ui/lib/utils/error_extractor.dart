import 'dart:convert';

import 'package:dio/dio.dart' as dio;

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

  /// استخراج پیام خطا از exception
  static String extractErrorMessage(Object e) {
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
            message = 'خطا در آپلود فایل';
          }
        }
        return message;
      }
      
      // نوع خطا
      switch (e.type) {
        case dio.DioExceptionType.connectionTimeout:
          return 'خطا در اتصال به سرور. لطفاً دوباره تلاش کنید.';
        case dio.DioExceptionType.receiveTimeout:
          return 'زمان دریافت پاسخ از سرور به پایان رسید.';
        case dio.DioExceptionType.connectionError:
          return 'خطا در اتصال به سرور. لطفاً اتصال اینترنت خود را بررسی کنید.';
        default:
          return 'خطا در ارتباط با سرور';
      }
    }
    
    // پیام خطای عمومی
    final errorMessage = e.toString();
    if (errorMessage.contains('خطا')) {
      return errorMessage;
    }
    return 'خطا در ذخیره اطلاعات';
  }
}


