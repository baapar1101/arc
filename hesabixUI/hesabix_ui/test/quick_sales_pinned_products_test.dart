import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/utils/quick_sales_pinned_products.dart';

void main() {
  test('normalizePinnedProductIds keeps order, drops duplicates and caps length', () {
    expect(
      normalizePinnedProductIds([4, '4', 9, 0, 'x', 9, 2, 7, 8, 1, 11, 12, 13, 14]),
      [4, 9, 2, 7, 8, 1, 11, 12, 13, 14].take(kQuickSalesMaxPinnedProducts).toList(),
    );
  });

  test('recent products hide items that are already pinned', () {
    final visible = recentProductsExcludingPinned(
      recentProducts: [
        {'id': 1, 'name': 'A'},
        {'id': 2, 'name': 'B'},
        {'id': 3, 'name': 'C'},
      ],
      pinnedProducts: [
        {'id': 2, 'name': 'B'},
      ],
    );
    expect(visible.map((e) => e['id']).toList(), [1, 3]);
  });

  test('pinProductId appends until the personal cap', () {
    final first = pinProductId(const [1, 2], 9);
    expect(first.ids, [1, 2, 9]);
    expect(first.changed, isTrue);

    final already = pinProductId(const [1, 9], 9);
    expect(already.changed, isFalse);
    expect(already.ids, [1, 9]);

    final full = pinProductId(List<int>.generate(kQuickSalesMaxPinnedProducts, (i) => i + 1), 99);
    expect(full.changed, isFalse);
    expect(full.atLimit, isTrue);
  });

  test('unpinProductId removes only that product', () {
    expect(unpinProductId(const [4, 8, 2], 8), [4, 2]);
  });
}
