import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// انتخاب سال مالی برای داشبورد و هدر [X-Fiscal-Year-ID].
///
/// - ذخیرهٔ محلی به‌ازای هر [businessId] است (نه یک کلید سراسری).
/// - اگر کاربر سال را دستی عوض نکرده باشد، با سال جاری سرور هم‌تراز می‌شود.
class FiscalYearController extends ChangeNotifier {
  static final Map<int, FiscalYearController> _instances = {};

  static String _idKey(int businessId) => 'selected_fiscal_year_id_$businessId';

  static String _manualKey(int businessId) => 'fiscal_year_manual_select_$businessId';

  /// کلید قدیمی یک‌بار برای جلوگیری از سردرگمی پاک می‌شود.
  static const String _legacyGlobalPrefsKey = 'selected_fiscal_year_id';

  final int businessId;
  int? _fiscalYearId;
  bool _manualSelection;

  int? get fiscalYearId => _fiscalYearId;

  bool get manualSelection => _manualSelection;

  FiscalYearController._(this.businessId, this._fiscalYearId, this._manualSelection);

  /// یک نمونهٔ به‌ازای هر کسب‌وکار؛ بعد از بستن سال یا هم‌ترازی به‌روز می‌ماند.
  static Future<FiscalYearController> load(int businessId) async {
    final existing = _instances[businessId];
    if (existing != null) return existing;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyGlobalPrefsKey);

    final id = prefs.getInt(_idKey(businessId));
    final manual = prefs.getBool(_manualKey(businessId)) ?? false;

    final c = FiscalYearController._(businessId, id, manual);
    _instances[businessId] = c;
    return c;
  }

  /// بعد از بارگذاری لیست سال‌های مالی از API: انتخاب خودکار را با سال جاری هماهنگ کن.
  Future<void> reconcileWithList(List<Map<String, dynamic>> fiscalYears) async {
    if (fiscalYears.isEmpty) return;

    Map<String, dynamic>? currentRow;
    for (final e in fiscalYears) {
      if (e['is_current'] == true) {
        currentRow = e;
        break;
      }
    }
    final int? currentId = currentRow?['id'] as int?;
    if (currentId == null) return;

    if (!_manualSelection) {
      if (_fiscalYearId != currentId) {
        _fiscalYearId = currentId;
        notifyListeners();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_idKey(businessId), currentId);
      }
      return;
    }

    if (_fiscalYearId != null) {
      final stillExists = fiscalYears.any((e) => e['id'] == _fiscalYearId);
      if (!stillExists) {
        _manualSelection = false;
        _fiscalYearId = currentId;
        notifyListeners();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_manualKey(businessId), false);
        await prefs.setInt(_idKey(businessId), currentId);
      }
    }
  }

  /// بعد از بستن سال مالی موفق: انتخاب ثابت به سال جدید و حالت دستی خاموش.
  Future<void> applyAfterYearClosed(int newFiscalYearId) async {
    _manualSelection = false;
    _fiscalYearId = newFiscalYearId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_manualKey(businessId), false);
    await prefs.setInt(_idKey(businessId), newFiscalYearId);
  }

  Future<void> setFiscalYearId(int? id, {bool userInitiated = false}) async {
    if (userInitiated) {
      _manualSelection = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_manualKey(businessId), true);
    }
    if (_fiscalYearId == id) return;
    _fiscalYearId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_idKey(businessId));
    } else {
      await prefs.setInt(_idKey(businessId), id);
    }
  }
}
