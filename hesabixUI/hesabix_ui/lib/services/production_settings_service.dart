import 'package:shared_preferences/shared_preferences.dart';

class ProductionSettingsService {
  static String _keyInventoryCode(int businessId) => 'prod_inv_code_$businessId';
  static String _keyWipCode(int businessId) => 'prod_wip_code_$businessId';

  Future<(String? inventoryCode, String? wipCode)> getDefaultAccounts(int businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final inv = prefs.getString(_keyInventoryCode(businessId));
    final wip = prefs.getString(_keyWipCode(businessId));
    return (inv, wip);
  }

  Future<void> saveDefaultAccounts({required int businessId, String? inventoryCode, String? wipCode}) async {
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
  }
}


