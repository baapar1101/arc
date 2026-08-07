import '../../models/business_dashboard_models.dart';
import '../../services/business_dashboard_service.dart';

class _CacheEntry {
  final BusinessStatistics stats;
  final DateTime fetchedAt;

  _CacheEntry(this.stats, this.fetchedAt);

  bool get isExpired => DateTime.now().difference(fetchedAt) > const Duration(minutes: 5);
}

/// کش سبک آمار داشبورد برای پیش‌نمایش hover.
class BusinessHubStatsCache {
  static final Map<int, _CacheEntry> _cache = {};

  static void invalidate(int businessId) => _cache.remove(businessId);

  static void clear() => _cache.clear();

  static Future<BusinessStatistics?> load(
    int businessId,
    BusinessDashboardService service,
  ) async {
    final cached = _cache[businessId];
    if (cached != null && !cached.isExpired) return cached.stats;

    try {
      final dash = await service.getDashboard(businessId);
      _cache[businessId] = _CacheEntry(dash.statistics, DateTime.now());
      return dash.statistics;
    } catch (_) {
      return null;
    }
  }
}
