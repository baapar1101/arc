import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class ReferralStore {
  static const String _kRefCode = 'referral_code_cached';
  static const String _kRefSavedAtMs = 'referral_code_saved_at_ms';
  static const String _kUserReferralCode = 'user_referral_code';

  // TTL for referral code: 30 days
  static const Duration _ttl = Duration(days: 30);

  static Future<void> captureFromCurrentUrl() async {
    try {
      String? ref = Uri.base.queryParameters['ref'];
      // اگر در hash بود (مثلاً /login?ref=CODE) از fragment بخوان
      if (ref == null || ref.trim().isEmpty) {
        final frag = Uri.base.fragment; // مثل '/login?ref=CODE'
        if (frag.isNotEmpty) {
          final fragUri = Uri.parse(frag.startsWith('/') ? frag : '/$frag');
          ref = fragUri.queryParameters['ref'];
        }
      }
      if (ref == null || ref.trim().isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRefCode, ref.trim());
      await prefs.setInt(_kRefSavedAtMs, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<String?> getReferrerCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_kRefCode);
      final savedAt = prefs.getInt(_kRefSavedAtMs);
      if (code == null || code.isEmpty || savedAt == null) return null;
      final saved = DateTime.fromMillisecondsSinceEpoch(savedAt);
      if (DateTime.now().difference(saved) > _ttl) {
        // expired
        await clearReferrer();
        return null;
      }
      return code;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearReferrer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kRefCode);
      await prefs.remove(_kRefSavedAtMs);
    } catch (_) {}
  }

  static String buildInviteLink(String referralCode) {
    final origin = Uri.base.origin; // دامنه پویا
    // استفاده از Hash URL Strategy برای سازگاری کامل با Flutter Web
    return '$origin/login?ref=$referralCode';
  }

  static Future<void> saveUserReferralCode(String? code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (code == null || code.isEmpty) {
        await prefs.remove(_kUserReferralCode);
      } else {
        await prefs.setString(_kUserReferralCode, code);
      }
    } catch (_) {}
  }

  static Future<String?> getUserReferralCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_kUserReferralCode);
      if (code == null || code.isEmpty) return null;
      return code;
    } catch (_) {
      return null;
    }
  }
}


