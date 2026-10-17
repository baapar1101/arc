String _canonicalStockQuantity(Object? value) {
  final number = value is num ? value : num.tryParse(value?.toString() ?? '');
  if (number == null) return value?.toString().trim() ?? '';
  if (number == number.truncateToDouble()) return number.toInt().toString();
  return number
      .toStringAsFixed(6)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// شناسه‌ای پایدار برای اینکه تکرار درخواست اصلاح یک فروش، سند تازه نسازد.
String quickSalesStockCorrectionToken({
  required int businessId,
  required String saleId,
  required DateTime documentDate,
  required List<Map<String, dynamic>> shortages,
}) {
  final rows =
      shortages
          .map(
            (row) =>
                '${row['product_id']}:${row['warehouse_id']}:'
                '${_canonicalStockQuantity(row['shortage_quantity'])}',
          )
          .toList()
        ..sort();
  final date = documentDate.toIso8601String().split('T').first;
  final input = '$businessId|$saleId|$date|${rows.join(';')}';

  var hash = 0x811c9dc5;
  for (final byte in input.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  final digest = hash.toRadixString(16).padLeft(8, '0');
  return 'qs-stock-$businessId-$saleId-$digest';
}
