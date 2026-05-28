import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'distribution_service.dart';

/// صف آفلاین عملیات میدانی — همگام‌سازی دسته‌ای با API.
class DistributionOfflineQueue {
  static String _key(int businessId) => 'distribution_offline_queue_$businessId';

  final DistributionService _api;

  DistributionOfflineQueue({DistributionService? api}) : _api = api ?? DistributionService();

  Future<List<Map<String, dynamic>>> peek(int businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(businessId));
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw);
    if (list is! List) return [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> enqueue(int businessId, Map<String, dynamic> action) async {
    final items = await peek(businessId);
    items.add(action);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(businessId), jsonEncode(items));
  }

  Future<void> clear(int businessId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(businessId));
  }

  Future<Map<String, dynamic>> sync(int businessId) async {
    final items = await peek(businessId);
    if (items.isEmpty) {
      return {'client_batch_id': '', 'results': []};
    }
    final batchId = DateTime.now().millisecondsSinceEpoch.toString();
    final res = await _api.syncOffline(
      businessId: businessId,
      clientBatchId: batchId,
      actions: items,
    );
    await clear(businessId);
    return res;
  }
}
