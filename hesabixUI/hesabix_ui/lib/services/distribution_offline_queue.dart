import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'distribution_service.dart';

/// صف آفلاین عملیات میدانی — فقط اقدامات موفق از صف حذف می‌شوند.
/// کلید ذخیره‌سازی و `client_batch_id` به کاربر گره می‌خورند تا تبلت مشترک
/// اکشن ویزیتور دیگر را به نام کاربر جاری سینک نکند.
class DistributionOfflineQueue {
  static String _key(int businessId, int userId) =>
      'distribution_offline_queue_${businessId}_u$userId';
  static String _batchKey(int businessId, int userId) =>
      'distribution_offline_batch_${businessId}_u$userId';
  static String _legacyKey(int businessId) => 'distribution_offline_queue_$businessId';
  static String _legacyBatchKey(int businessId) => 'distribution_offline_batch_$businessId';

  final DistributionService _api;

  DistributionOfflineQueue({DistributionService? api}) : _api = api ?? DistributionService();

  Future<void> _purgeLegacy(int businessId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyKey(businessId));
    await prefs.remove(_legacyBatchKey(businessId));
  }

  Future<List<Map<String, dynamic>>> peek(int businessId, {required int userId}) async {
    await _purgeLegacy(businessId);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(businessId, userId));
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw);
    if (list is! List) return [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> enqueue(int businessId, Map<String, dynamic> action, {required int userId}) async {
    final items = await peek(businessId, userId: userId);
    final ref = '${action['client_ref'] ?? ''}';
    if (ref.isNotEmpty) {
      items.removeWhere((e) => '${e['client_ref']}' == ref);
    }
    items.add(action);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(businessId, userId), jsonEncode(items));
  }

  Future<void> _save(int businessId, int userId, List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(_key(businessId, userId));
      await prefs.remove(_batchKey(businessId, userId));
    } else {
      await prefs.setString(_key(businessId, userId), jsonEncode(items));
    }
  }

  Future<String> _stableBatchId(int businessId, int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_batchKey(businessId, userId));
    if (existing != null && existing.isNotEmpty) return existing;
    final id = 'dist_${businessId}_u${userId}_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString(_batchKey(businessId, userId), id);
    return id;
  }

  Future<void> clear(int businessId, {required int userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(businessId, userId));
    await prefs.remove(_batchKey(businessId, userId));
    await _purgeLegacy(businessId);
  }

  /// پاک‌سازی صف و کاتالوگ آفلاین این کاربر روی دستگاه (logout).
  static Future<void> clearDeviceDataForUser(int? userId) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList();
    for (final k in keys) {
      final isDist = k.startsWith('distribution_offline_');
      if (!isDist) continue;
      final legacyUnscoped = !k.contains('_u');
      final thisUser = userId != null && k.contains('_u$userId');
      if (legacyUnscoped || thisUser) {
        await prefs.remove(k);
      }
    }
  }

  Future<Map<String, dynamic>> sync(int businessId, {required int userId}) async {
    final items = await peek(businessId, userId: userId);
    if (items.isEmpty) {
      return {'client_batch_id': '', 'results': [], 'remaining': 0, 'ok_count': 0, 'fail_count': 0};
    }
    final batchId = await _stableBatchId(businessId, userId);
    final res = await _api.syncOffline(
      businessId: businessId,
      clientBatchId: batchId,
      actions: items,
    );
    final results = (res['results'] is List) ? res['results'] as List : const [];
    final okRefs = <String>{};
    var okCount = 0;
    var failCount = 0;
    for (final raw in results) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final ref = '${m['client_ref'] ?? ''}';
      if (m['ok'] == true) {
        okCount++;
        if (ref.isNotEmpty) okRefs.add(ref);
      } else {
        failCount++;
      }
    }
    if (results.isEmpty) {
      return {
        ...res,
        'remaining': items.length,
        'ok_count': 0,
        'fail_count': items.length,
      };
    }
    final remaining = <Map<String, dynamic>>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final ref = '${it['client_ref'] ?? i}';
      if (!okRefs.contains(ref)) {
        remaining.add(it);
      }
    }
    await _save(businessId, userId, remaining);
    return {
      ...res,
      'client_batch_id': batchId,
      'remaining': remaining.length,
      'ok_count': okCount,
      'fail_count': failCount,
    };
  }
}
