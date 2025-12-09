import 'package:dio/dio.dart' as dio;

/// کلاس کمکی برای استخراج پیام خطا از exception
class ErrorExtractor {
  /// استخراج پیام خطا از exception
  static String extractErrorMessage(Object e) {
    if (e is dio.DioException) {
      final response = e.response;
      if (response != null && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final error = data['error'];
        
        // بررسی خطای STORAGE_LIMIT_EXCEEDED
        if (error is Map && error['code'] == 'STORAGE_LIMIT_EXCEEDED') {
          return error['message'] as String? ?? 'حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند';
        }
        
        // استخراج پیام خطا از error object
        if (error is Map && error['message'] is String) {
          final message = error['message'] as String;
          if (message.isNotEmpty) {
            return message;
          }
        }
        
        // استخراج پیام خطا از data
        if (data['message'] is String) {
          final message = data['message'] as String;
          if (message.isNotEmpty) {
            return message;
          }
        }
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


