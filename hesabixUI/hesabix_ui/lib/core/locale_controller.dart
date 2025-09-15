import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleController extends ChangeNotifier {
  static const String _prefsKey = 'app_locale_code';

  Locale _locale;
  Locale get locale => _locale;

  LocaleController._(this._locale);

  static const Locale faIR = Locale('fa', 'IR');
  static const Locale enUS = Locale('en', 'US');
  static const List<Locale> supportedLocales = <Locale>[faIR, enUS];

  static Future<LocaleController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    Locale initial = faIR;
    if (code != null) {
      final parts = code.split('-');
      if (parts.isNotEmpty) {
        initial = Locale(parts[0], parts.length > 1 ? parts[1] : null);
      }
    }
    return LocaleController._(initial);
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final String code = locale.countryCode != null && locale.countryCode!.isNotEmpty
        ? '${locale.languageCode}-${locale.countryCode}'
        : locale.languageCode;
    await prefs.setString(_prefsKey, code);
  }
}


