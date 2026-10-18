import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/utils/quick_sales_stock_correction.dart';

void main() {
  test('correction token is independent from shortage row order', () {
    final date = DateTime(2026, 10, 17);
    final first = quickSalesStockCorrectionToken(
      businessId: 4952,
      saleId: 'sale-1',
      documentDate: date,
      shortages: const [
        {'product_id': 2, 'warehouse_id': 1, 'shortage_quantity': 1.0},
        {'product_id': 1, 'warehouse_id': 1, 'shortage_quantity': 2},
      ],
    );
    final second = quickSalesStockCorrectionToken(
      businessId: 4952,
      saleId: 'sale-1',
      documentDate: date,
      shortages: const [
        {'product_id': 1, 'warehouse_id': 1, 'shortage_quantity': 2.0},
        {'product_id': 2, 'warehouse_id': 1, 'shortage_quantity': 1},
      ],
    );

    expect(second, first);
  });

  test('correction token changes for another sale, date, or quantity', () {
    String token(String sale, DateTime date, num quantity) =>
        quickSalesStockCorrectionToken(
          businessId: 4952,
          saleId: sale,
          documentDate: date,
          shortages: [
            {'product_id': 1, 'warehouse_id': 1, 'shortage_quantity': quantity},
          ],
        );

    final base = token('sale-1', DateTime(2026, 10, 17), 1);
    expect(token('sale-2', DateTime(2026, 10, 17), 1), isNot(base));
    expect(token('sale-1', DateTime(2026, 10, 18), 1), isNot(base));
    expect(token('sale-1', DateTime(2026, 10, 17), 2), isNot(base));
  });
}
