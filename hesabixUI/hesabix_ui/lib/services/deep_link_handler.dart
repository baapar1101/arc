import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// سرویس مدیریت Deep Links
/// برای مدیریت لینک‌های بازگشت از درگاه پرداخت
class DeepLinkHandler {
  static const platform = MethodChannel('hesabix.ir/deeplink');
  
  /// Callback برای مدیریت deep link های دریافتی
  static Function(Uri)? _onDeepLink;

  /// ثبت listener برای deep links
  static void init(Function(Uri) onDeepLink) {
    _onDeepLink = onDeepLink;
    
    // گوش دادن به deep links
    _listenToDeepLinks();
  }

  /// گوش دادن به deep links
  static void _listenToDeepLinks() async {
    try {
      // چک کردن اولیه برای لینکی که باعث باز شدن اپ شده
      final initialLink = await _getInitialLink();
      if (initialLink != null) {
        _handleDeepLink(initialLink);
      }
    } catch (e) {
      debugPrint('خطا در دریافت initial link: $e');
    }
  }

  /// دریافت لینک اولیه (اگر اپ از طریق deep link باز شده)
  static Future<Uri?> _getInitialLink() async {
    try {
      final String? link = await platform.invokeMethod('getInitialLink');
      if (link != null && link.isNotEmpty) {
        return Uri.parse(link);
      }
    } catch (e) {
      debugPrint('خطا در parse کردن initial link: $e');
    }
    return null;
  }

  /// مدیریت deep link دریافتی
  static void _handleDeepLink(Uri uri) {
    if (_onDeepLink != null) {
      _onDeepLink!(uri);
    }
  }

  /// پردازش payment callback
  static Map<String, dynamic>? parsePaymentCallback(Uri uri) {
    if (uri.scheme == 'hesabix' && uri.host == 'payment' && uri.path.contains('callback')) {
      final params = uri.queryParameters;
      return {
        'tx_id': int.tryParse(params['tx_id'] ?? '0'),
        'status': params['status'],
        'amount': double.tryParse(params['amount'] ?? '0'),
        'ref': params['ref'],
      };
    }
    return null;
  }

  /// پردازش لینک‌های مختلف
  static String? getRouteFromDeepLink(Uri uri) {
    if (uri.scheme != 'hesabix') return null;

    switch (uri.host) {
      case 'payment':
        if (uri.path.contains('callback')) {
          return '/payment-result';
        }
        break;
      case 'dashboard':
        return '/dashboard';
      case 'wallet':
        if (uri.path.contains('topup')) {
          return '/wallet-topup';
        }
        return '/wallet';
      case 'support':
        return '/support';
    }
    
    return null;
  }
}


