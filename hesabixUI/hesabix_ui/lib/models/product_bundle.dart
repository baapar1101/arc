class ProductBundleItem {
  final int? id;
  final int productId;
  final num quantity;
  final int lineOrder;
  final Map<String, dynamic> product;

  const ProductBundleItem({
    this.id,
    required this.productId,
    required this.quantity,
    required this.lineOrder,
    required this.product,
  });

  factory ProductBundleItem.fromJson(Map<String, dynamic> json) {
    return ProductBundleItem(
      id: _asInt(json['id']),
      productId: _asInt(json['product_id']) ?? 0,
      quantity: _asNum(json['quantity']) ?? 0,
      lineOrder: _asInt(json['line_order']) ?? 0,
      product: json['product'] is Map
          ? Map<String, dynamic>.from(json['product'] as Map)
          : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toRequestJson() => {
    'product_id': productId,
    'quantity': quantity,
  };
}

class ProductBundle {
  final int id;
  final int businessId;
  final String name;
  final String? description;
  final bool isActive;
  final int itemsCount;
  final List<ProductBundleItem> items;
  final String? updatedAtDisplay;

  const ProductBundle({
    required this.id,
    required this.businessId,
    required this.name,
    this.description,
    required this.isActive,
    required this.itemsCount,
    this.items = const <ProductBundleItem>[],
    this.updatedAtDisplay,
  });

  factory ProductBundle.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map(
                (item) =>
                    ProductBundleItem.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : const <ProductBundleItem>[];
    return ProductBundle(
      id: _asInt(json['id']) ?? 0,
      businessId: _asInt(json['business_id']) ?? 0,
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      isActive: json['is_active'] == true,
      itemsCount: _asInt(json['items_count']) ?? items.length,
      items: items,
      updatedAtDisplay: _displayDate(json['updated_at']),
    );
  }
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

num? _asNum(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '');
}

String? _displayDate(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim().split(' ').first;
  }
  if (value is Map) {
    final raw = value['date_only'] ?? value['formatted'] ?? value['date_time'];
    if (raw != null && raw.toString().trim().isNotEmpty) {
      return raw.toString().trim().split(' ').first;
    }
  }
  return null;
}
