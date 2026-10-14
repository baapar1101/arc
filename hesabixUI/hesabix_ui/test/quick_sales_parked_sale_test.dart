import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/customer_model.dart';
import 'package:hesabix_ui/models/invoice_line_item.dart';
import 'package:hesabix_ui/models/quick_sales_parked_sale.dart';
import 'package:hesabix_ui/models/quick_sales_change_resolution.dart';

void main() {
  test('parked sale round-trips cart, customer and totals', () {
    final sale = QuickSalesParkedSale(
      id: 'sale-1',
      createdAt: DateTime.utc(2026, 8, 15, 8),
      updatedAt: DateTime.utc(2026, 8, 15, 9),
      customer: const Customer(id: 42, name: 'علی رضایی', phone: '09120000000'),
      cartItems: [
        InvoiceLineItem(
          lineKey: 'line-1',
          productId: 7,
          productCode: 'P-7',
          productName: 'چیپس',
          quantity: 2,
          unitPrice: 15000,
          taxRate: 10,
          warehouseId: 3,
          extraInfo: const {'unit_price_source': 'base'},
        ),
      ],
      warehouseId: 3,
      cashRegisterId: '9',
      documentDate: DateTime.utc(2026, 8, 15),
      documentDescription: 'فروش صندوق',
      globalDiscountType: 'percent',
      globalDiscountValue: '5',
      itemCount: 1,
      totalAmount: 33000,
    );

    final parsed = QuickSalesParkedSale.fromJson(sale.toJson());
    expect(parsed.id, 'sale-1');
    expect(parsed.customer?.id, 42);
    expect(parsed.customer?.phone, '09120000000');
    expect(parsed.cartItems, hasLength(1));
    expect(parsed.cartItems.first.productId, 7);
    expect(parsed.cartItems.first.quantity, 2);
    expect(parsed.cartItems.first.warehouseId, 3);
    expect(parsed.cartItems.first.extraInfo?['unit_price_source'], 'base');
    expect(parsed.globalDiscountValue, '5');
    expect(parsed.totalAmount, 33000);
    expect(parsed.isBlank(anonymousCustomerId: 1), isFalse);
  });

  test('blank sale is detected for anonymous customer without items', () {
    final sale = QuickSalesParkedSale(
      id: 'blank',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      customer: const Customer(id: 1, name: 'ناشناس'),
      documentDate: DateTime.now(),
    );
    expect(sale.isBlank(anonymousCustomerId: 1), isTrue);
    expect(sale.isBlank(anonymousCustomerId: 99), isFalse);
  });

  test('bundle parse rejects wrong version and keeps active id', () {
    expect(
      QuickSalesParkedSalesBundle.tryParse({'version': 2, 'sales': []}),
      isNull,
    );
    final sale = QuickSalesParkedSale(
      id: 'a',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      documentDate: DateTime.now(),
    );
    final bundle = QuickSalesParkedSalesBundle(activeId: 'a', sales: [sale]);
    final parsed = QuickSalesParkedSalesBundle.tryParse(bundle.toJson());
    expect(parsed?.activeId, 'a');
    expect(parsed?.sales, hasLength(1));
  });

  test('parked sale preserves split change resolution', () {
    final sale = QuickSalesParkedSale(
      id: 'change-sale',
      createdAt: DateTime.utc(2026, 10, 14, 8),
      updatedAt: DateTime.utc(2026, 10, 14, 9),
      documentDate: DateTime.utc(2026, 10, 14),
      changeResolution: const QuickSalesChangeResolution(
        overpaymentAmount: 1000000,
        creditAmount: 300000,
        allocations: [
          QuickSalesChangeAllocation(
            id: 'cash-1',
            sourceType: QuickSalesChangeSourceType.cashRegister,
            sourceId: 3,
            sourceName: 'صندوق اصلی',
            amount: 400000,
          ),
          QuickSalesChangeAllocation(
            id: 'bank-1',
            sourceType: QuickSalesChangeSourceType.bank,
            sourceId: 7,
            sourceName: 'بانک سامان',
            amount: 300000,
            commission: 20000,
          ),
        ],
      ),
    );

    final parsed = QuickSalesParkedSale.fromJson(sale.toJson());
    final resolution = parsed.changeResolution;
    expect(resolution, isNotNull);
    expect(resolution!.returnedAmount, 700000);
    expect(resolution.creditAmount, 300000);
    expect(resolution.bankCommission, 20000);
    expect(resolution.isValidFor(1000000, 0.5), isTrue);
  });
}
