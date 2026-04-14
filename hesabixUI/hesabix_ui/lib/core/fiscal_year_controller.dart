import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FiscalYearController extends ChangeNotifier {
  static const String _prefsKey = 'selected_fiscal_year_id';

  int? _fiscalYearId;
  int? get fiscalYearId => _fiscalYearId;

  FiscalYearController._(this._fiscalYearId);

  static Future<FiscalYearController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_prefsKey);
    return FiscalYearController._(id);
  }

  Future<void> setFiscalYearId(int? id) async {
    if (_fiscalYearId == id) return;
    _fiscalYearId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setInt(_prefsKey, id);
    }
  }
}


