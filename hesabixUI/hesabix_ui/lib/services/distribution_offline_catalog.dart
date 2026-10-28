import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:hesabix_ui/services/distribution_service.dart';

/// کاتالوگ روز برای کار آفلاین واقعی (کالا، مشتری، موجودی ون، برنامه).
class DistributionOfflineCatalog {
  static String _key(int businessId, int userId) =>
      'distribution_offline_pack_${businessId}_u$userId';
  static String _legacyKey(int businessId) => 'distribution_offline_pack_$businessId';

  static Future<void> save(int businessId, Map<String, dynamic> pack, {required int userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyKey(businessId));
    await prefs.setString(_key(businessId, userId), jsonEncode(pack));
  }

  static Future<Map<String, dynamic>?> load(int businessId, {required int userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyKey(businessId));
    final raw = prefs.getString(_key(businessId, userId));
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  static Future<Map<String, dynamic>> refresh({
    required int businessId,
    required int userId,
    required DistributionService service,
  }) async {
    final pack = await service.getOfflinePack(businessId: businessId);
    await save(businessId, pack, userId: userId);
    return pack;
  }
}
