import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local (device) preferences for Android system notifications / keep-alive.
///
/// Stored on all platforms via SharedPreferences but only consumed on Android.
class AndroidNotificationPrefs {
  AndroidNotificationPrefs._();

  static const _kKeepAliveEnabled = 'android_notif_keepalive_enabled';
  static const _kAccentColor = 'android_notif_accent_color';
  static const _kDateStyle = 'android_notif_date_style'; // app | jalali | gregorian | both
  static const _kShowTime = 'android_notif_show_time';
  static const _kShowEventLabel = 'android_notif_show_event_label';
  static const _kShowAppBrand = 'android_notif_show_app_brand';
  static const _kLedEnabled = 'android_notif_led_enabled';
  static const _kVibrate = 'android_notif_vibrate';

  static const int defaultAccentColor = 0xFF1565C0; // blue 800

  static Future<bool> isKeepAliveEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kKeepAliveEnabled) ?? false;
  }

  static Future<void> setKeepAliveEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kKeepAliveEnabled, value);
  }

  static Future<int> getAccentColor() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kAccentColor) ?? defaultAccentColor;
  }

  static Future<void> setAccentColor(int argb) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kAccentColor, argb);
  }

  static Future<Color> getAccentColorValue() async => Color(await getAccentColor());

  /// app | jalali | gregorian | both
  static Future<String> getDateStyle() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kDateStyle) ?? 'both';
  }

  static Future<void> setDateStyle(String style) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDateStyle, style);
  }

  static Future<bool> getShowTime() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kShowTime) ?? true;
  }

  static Future<void> setShowTime(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowTime, value);
  }

  static Future<bool> getShowEventLabel() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kShowEventLabel) ?? true;
  }

  static Future<void> setShowEventLabel(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowEventLabel, value);
  }

  static Future<bool> getShowAppBrand() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kShowAppBrand) ?? true;
  }

  static Future<void> setShowAppBrand(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowAppBrand, value);
  }

  static Future<bool> getLedEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kLedEnabled) ?? true;
  }

  static Future<void> setLedEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kLedEnabled, value);
  }

  static Future<bool> getVibrate() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kVibrate) ?? true;
  }

  static Future<void> setVibrate(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kVibrate, value);
  }

  static Future<Map<String, dynamic>> snapshot() async {
    return <String, dynamic>{
      'keepAliveEnabled': await isKeepAliveEnabled(),
      'accentColor': await getAccentColor(),
      'dateStyle': await getDateStyle(),
      'showTime': await getShowTime(),
      'showEventLabel': await getShowEventLabel(),
      'showAppBrand': await getShowAppBrand(),
      'ledEnabled': await getLedEnabled(),
      'vibrate': await getVibrate(),
    };
  }
}
