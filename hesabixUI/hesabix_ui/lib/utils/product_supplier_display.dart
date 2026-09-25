/// کمک‌تابع‌های نمایش تأمین‌کنندهٔ کالا در لیست و دیالوگ جزئیات.

List<Map<String, dynamic>> productSuppliersOf(Map<String, dynamic> product) {
  final raw = product['suppliers'];
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

String productSupplierRowName(Map<String, dynamic> row) {
  final name = row['name']?.toString().trim() ?? '';
  if (name.isNotEmpty) return name;
  final person = row['person_name']?.toString().trim() ?? '';
  return person;
}

Map<String, dynamic>? preferredSupplierRow(List<Map<String, dynamic>> suppliers) {
  if (suppliers.isEmpty) return null;
  for (final row in suppliers) {
    if (row['is_preferred'] == true) return row;
  }
  return suppliers.first;
}

String? preferredSupplierNameOf(Map<String, dynamic> product) {
  final explicit = product['preferred_supplier_name']?.toString().trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final row = preferredSupplierRow(productSuppliersOf(product));
  if (row == null) return null;
  final name = productSupplierRowName(row);
  return name.isEmpty ? null : name;
}

/// برچسب ستون لیست: نام ترجیحی، و در صورت وجود بقیه «+N».
String formatProductSuppliersColumn(dynamic item, {String empty = '-'}) {
  if (item is! Map) return empty;
  final product = Map<String, dynamic>.from(item);
  final suppliers = productSuppliersOf(product);
  if (suppliers.isEmpty) {
    final explicit = preferredSupplierNameOf(product);
    return (explicit == null || explicit.isEmpty) ? empty : explicit;
  }
  final main = preferredSupplierRow(suppliers);
  final mainName = main == null ? '' : productSupplierRowName(main);
  if (mainName.isEmpty) return empty;
  final extra = suppliers.length - 1;
  if (extra <= 0) return mainName;
  return '$mainName  +$extra';
}

String productSuppliersTooltip(dynamic item) {
  if (item is! Map) return '';
  final suppliers = productSuppliersOf(Map<String, dynamic>.from(item));
  if (suppliers.isEmpty) return preferredSupplierNameOf(Map<String, dynamic>.from(item)) ?? '';
  return suppliers.map((row) {
    final name = productSupplierRowName(row);
    if (name.isEmpty) return '';
    return row['is_preferred'] == true ? '$name ★' : name;
  }).where((s) => s.isNotEmpty).join('\n');
}

/// ادغام ردیف لیست با پاسخ GET تا فیلدهایی مثل category_name از لیست نپرند.
Map<String, dynamic> mergeProductDetailMaps(
  Map<String, dynamic> listRow,
  Map<String, dynamic> full,
) {
  final merged = Map<String, dynamic>.from(listRow);
  full.forEach((key, value) {
    if (value != null) {
      merged[key] = value;
    }
  });
  if (full.containsKey('suppliers')) {
    merged['suppliers'] = full['suppliers'] ?? const [];
  }
  if (full.containsKey('preferred_supplier_name')) {
    merged['preferred_supplier_name'] = full['preferred_supplier_name'];
  }
  return merged;
}
