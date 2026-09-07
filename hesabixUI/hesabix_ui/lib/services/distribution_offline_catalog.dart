import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:hesabix_ui/services/distribution_service.dart';

/// کاتالوگ روز برای کار آفلاین واقعی (کالا، مشتری، موجودی ون، برنامه).
class DistributionOfflineCatalog {
  static String _key(int businessId) => 'distribution_offline_pack_$businessId';

  static Future<void> save(int businessId, Map<String, dynamic> pack) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(businessId), jsonEncode(pack));
  }

  static Future<Map<String, dynamic>?> load(int businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(businessId));
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  static Future<Map<String, dynamic>> refresh({
    required int businessId,
    required DistributionService service,
  }) async {
    final pack = await service.getOfflinePack(businessId: businessId);
    await save(businessId, pack);
    return pack;
  }
}
