/// استخراج خطوط فاکتور برای فرم حواله انبار (با پشتیبانی حواله جزئی).
class InvoiceLineQuantitiesIndex {
  final Map<int, Map<String, double>> byLineId;
  final Map<int, Map<String, double>> byProductId;

  const InvoiceLineQuantitiesIndex({
    required this.byLineId,
    required this.byProductId,
  });

  factory InvoiceLineQuantitiesIndex.fromApiResponse(Map<String, dynamic> data) {
    final lines = data['lines'] as List<dynamic>? ?? const [];
    final byLineId = <int, Map<String, double>>{};
    final byProductId = <int, Map<String, double>>{};
    for (final raw in lines) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final q = <String, double>{
        'required': _toDouble(map['required_quantity']),
        'processed': _toDouble(map['processed_quantity']),
        'remaining': _toDouble(map['remaining_quantity']),
      };
      final lineId = _toInt(map['invoice_item_line_id']);
      if (lineId != null) {
        byLineId[lineId] = q;
      }
      final productId = _toInt(map['product_id']);
      if (productId != null) {
        byProductId[productId] = q;
      }
    }
    return InvoiceLineQuantitiesIndex(
      byLineId: byLineId,
      byProductId: byProductId,
    );
  }

  Map<String, double>? lookup({int? invoiceItemLineId, int? productId}) {
    if (invoiceItemLineId != null) {
      final byLine = byLineId[invoiceItemLineId];
      if (byLine != null) return byLine;
    }
    if (productId != null) {
      return byProductId[productId];
    }
    return null;
  }

  bool get hasAnyRemaining =>
      byLineId.values.any((q) => (q['remaining'] ?? 0) > 0) ||
      byProductId.values.any((q) => (q['remaining'] ?? 0) > 0);
}

List<Map<String, dynamic>> extractWarehouseLinesFromInvoice(
  Map<String, dynamic> invoice,
  String docType, {
  InvoiceLineQuantitiesIndex? quantities,
}) {
  final movementFallback = docType == 'receipt' ? 'in' : 'out';
  final rawLines = List<dynamic>.from(invoice['product_lines'] ?? const []);
  final List<Map<String, dynamic>> result = [];
  for (final raw in rawLines) {
    if (raw is! Map) continue;
    final map = Map<String, dynamic>.from(raw);
    if (map['product_id'] == null) continue;
    final invoiceLineId = _toInt(map['id']);
    final invoiceQty = _toDouble(map['quantity']);
    if (invoiceQty <= 0) continue;

    final extra = Map<String, dynamic>.from(map['extra_info'] ?? const {});
    final warehouseId = _toInt(map['warehouse_id'] ?? extra['warehouse_id']);
    final movement = (extra['movement'] ?? movementFallback).toString();

    double initialQty = invoiceQty;
    if (quantities != null) {
      final q = quantities.lookup(
        invoiceItemLineId: invoiceLineId,
        productId: _toInt(map['product_id']),
      );
      if (q != null) {
        initialQty = q['remaining'] ?? 0;
      }
    }

    result.add({
      'invoice_item_line_id': invoiceLineId,
      'product_id': map['product_id'],
      'product_name': map['product_name'],
      'product_code': map['product_code'],
      'quantity': initialQty,
      'warehouse_id': warehouseId,
      'movement': movement,
      'extra_info': extra,
    });
  }
  return result;
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String && value.isNotEmpty) return int.tryParse(value);
  return null;
}
