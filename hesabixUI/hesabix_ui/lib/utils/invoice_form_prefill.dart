import '../models/invoice_line_item.dart';

/// نگاشت ردیف‌های `product_lines` API به [InvoiceLineItem] برای «کپی به فاکتور جدید».
/// `selected_instance_ids` و نسخهٔ یونیک کنار گذاشته می‌شود.
List<InvoiceLineItem> invoiceLineItemsFromProductLinesForCopy(
  List<dynamic> linesRaw,
) {
  num toNum(dynamic v, {num fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? fallback;
  }

  int? toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  final mappedLines = <InvoiceLineItem>[];
  for (final raw in linesRaw) {
    final r = Map<String, dynamic>.from(raw as Map);
    final Map<String, dynamic> info = Map<String, dynamic>.from(r['extra_info'] ?? const {});
    info.remove('selected_instance_ids');

    final num qty = toNum(r['quantity']);
    final num unitPrice = toNum(info['unit_price']);
    final num lineDiscount = toNum(info['line_discount']);
    final num taxAmount = toNum(info['tax_amount']);
    final String discountType =
        (info['discount_type']?.toString() ?? ((info['discount_value'] != null) ? 'amount' : 'amount'));
    final num discountValue = toNum(info['discount_value'], fallback: lineDiscount);

    num taxRate = toNum(info['tax_rate']);
    if (taxRate <= 0) {
      final taxable = (qty * unitPrice) - discountValue;
      if (taxAmount > 0 && taxable > 0) {
        taxRate = (taxAmount / taxable) * 100;
      }
    }

    for (final k in info.keys.toList()) {
      if (k.startsWith('_local_')) info.remove(k);
    }

    mappedLines.add(
      InvoiceLineItem(
        quantity: qty,
        unitPriceSource: 'manual',
        unitPrice: unitPrice,
        discountType: discountType,
        discountValue: discountValue,
        taxRate: taxRate,
        description: r['description']?.toString(),
        trackInventory: false,
        warehouseId: toInt(info['warehouse_id']),
        selectedInstanceIds: null,
        extraInfo: info.isNotEmpty ? info : null,
        productId: toInt(r['product_id']),
        productName: r['product_name']?.toString(),
        selectedUnit: info['unit']?.toString(),
      ),
    );
  }
  return mappedLines;
}

bool installmentPlanPresentInExtra(Map<String, dynamic> extra) {
  final p = extra['installment_plan'];
  if (p is! Map) return false;
  final sch = p['schedule'];
  if (sch is List && sch.isNotEmpty) return true;
  final n = p['num_installments'];
  if (n is int && n > 0) return true;
  if (n is num && n.toInt() > 0) return true;
  return false;
}
