const int kQuickSalesMaxPinnedProducts = 12;

int? quickSalesProductIntId(Map<String, dynamic> product) {
  final value = product['id'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

num quickSalesProductPrice(Map<String, dynamic> product) {
  final raw = product['base_sales_price'] ?? product['sales_price'];
  if (raw is num) return raw;
  return num.tryParse(raw?.toString() ?? '') ?? 0;
}

List<int> normalizePinnedProductIds(
  Iterable<dynamic> raw, {
  int max = kQuickSalesMaxPinnedProducts,
}) {
  final seen = <int>{};
  final ids = <int>[];
  for (final value in raw) {
    final parsed = value is int
        ? value
        : value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed <= 0 || seen.contains(parsed)) continue;
    seen.add(parsed);
    ids.add(parsed);
    if (ids.length >= max) break;
  }
  return ids;
}

Set<int> pinnedProductIdSet(Iterable<Map<String, dynamic>> pinnedProducts) {
  return pinnedProducts
      .map(quickSalesProductIntId)
      .whereType<int>()
      .toSet();
}

List<Map<String, dynamic>> recentProductsExcludingPinned({
  required Iterable<Map<String, dynamic>> recentProducts,
  required Iterable<Map<String, dynamic>> pinnedProducts,
}) {
  final pinnedIds = pinnedProductIdSet(pinnedProducts);
  if (pinnedIds.isEmpty) return List<Map<String, dynamic>>.from(recentProducts);
  return recentProducts
      .where((product) {
        final id = quickSalesProductIntId(product);
        return id == null || !pinnedIds.contains(id);
      })
      .toList();
}

class PinProductIdsResult {
  final List<int> ids;
  final bool changed;
  final bool atLimit;

  const PinProductIdsResult({
    required this.ids,
    required this.changed,
    required this.atLimit,
  });
}

PinProductIdsResult pinProductId(
  Iterable<int> current,
  int productId, {
  int max = kQuickSalesMaxPinnedProducts,
}) {
  final ids = normalizePinnedProductIds(current, max: max);
  if (ids.contains(productId)) {
    return PinProductIdsResult(ids: ids, changed: false, atLimit: false);
  }
  if (ids.length >= max) {
    return PinProductIdsResult(ids: ids, changed: false, atLimit: true);
  }
  return PinProductIdsResult(
    ids: [...ids, productId],
    changed: true,
    atLimit: false,
  );
}

List<int> unpinProductId(Iterable<int> current, int productId) {
  return normalizePinnedProductIds(
    current.where((id) => id != productId),
  );
}
