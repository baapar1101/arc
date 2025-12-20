import 'package:shared_preferences/shared_preferences.dart';

class ProductionSettingsService {
  static String _keyInventoryCode(int businessId) => 'prod_inv_code_$businessId';
  static String _keyWipCode(int businessId) => 'prod_wip_code_$businessId';
  static String _keyOverheadCode(int businessId) => 'prod_overhead_code_$businessId';

  Future<(String? inventoryCode, String? wipCode, String? overheadCode)> getDefaultAccounts(int businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final inv = prefs.getString(_keyInventoryCode(businessId));
    final wip = prefs.getString(_keyWipCode(businessId));
    final overhead = prefs.getString(_keyOverheadCode(businessId));
    return (inv, wip, overhead);
  }

  Future<void> saveDefaultAccounts({required int businessId, String? inventoryCode, String? wipCode, String? overheadCode}) async {
    final prefs = await SharedPreferences.getInstance();
    if (inventoryCode == null || inventoryCode.isEmpty) {
      await prefs.remove(_keyInventoryCode(businessId));
    } else {
      await prefs.setString(_keyInventoryCode(businessId), inventoryCode);
    }
    if (wipCode == null || wipCode.isEmpty) {
      await prefs.remove(_keyWipCode(businessId));
    } else {
      await prefs.setString(_keyWipCode(businessId), wipCode);
    }
    if (overheadCode == null || overheadCode.isEmpty) {
      await prefs.remove(_keyOverheadCode(businessId));
    } else {
      await prefs.setString(_keyOverheadCode(businessId), overheadCode);
    }
  }
}


