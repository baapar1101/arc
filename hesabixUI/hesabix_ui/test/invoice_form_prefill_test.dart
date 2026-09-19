import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/utils/invoice_form_prefill.dart';

void main() {
  test('copy mapping keeps stored unit price as manual', () {
    final lines = invoiceLineItemsFromProductLinesForCopy([
      {
        'product_id': 12,
        'product_code': 'P-12',
        'product_name': 'کالا',
        'quantity': 2,
        'description': 'شرح',
        'extra_info': {
          'unit_price': 150000,
          'line_discount': 1000,
          'tax_amount': 0,
          'discount_type': 'amount',
          'discount_value': 1000,
          'tax_rate': 0,
          'unit': 'عدد',
          'warehouse_id': 3,
          'selected_instance_ids': [9],
        },
      },
    ]);

    expect(lines, hasLength(1));
    final item = lines.first;
    expect(item.productId, 12);
    expect(item.productCode, 'P-12');
    expect(item.quantity, 2);
    expect(item.unitPrice, 150000);
    expect(item.unitPriceSource, 'manual');
    expect(item.discountValue, 1000);
    expect(item.selectedUnit, 'عدد');
    expect(item.warehouseId, 3);
    expect(item.selectedInstanceIds, isNull);
    expect(item.extraInfo?['selected_instance_ids'], isNull);
  });
}
