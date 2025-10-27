/// مدل ساده برای کالا - برای استفاده در انتخابگرهای تفصیل
class Product {
  final int? id;
  final int businessId;
  final String? code;
  final String name;
  final String itemType;
  final String? description;
  final int? categoryId;
  final bool trackInventory;
  final num? baseSalesPrice;
  final num? basePurchasePrice;
  final String? mainUnit;
  final String? secondaryUnit;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Product({
    this.id,
    required this.businessId,
    this.code,
    required this.name,
    this.itemType = 'کالا',
    this.description,
    this.categoryId,
    this.trackInventory = false,
    this.baseSalesPrice,
    this.basePurchasePrice,
    this.mainUnit,
    this.secondaryUnit,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int?,
      businessId: (json['business_id'] ?? json['businessId']) as int,
      code: json['code'] as String?,
      name: (json['name'] ?? '') as String,
      itemType: (json['item_type'] ?? 'کالا') as String,
      description: json['description'] as String?,
      categoryId: json['category_id'] as int?,
      trackInventory: (json['track_inventory'] ?? false) as bool,
      baseSalesPrice: json['base_sales_price'] != null ? num.tryParse(json['base_sales_price'].toString()) : null,
      basePurchasePrice: json['base_purchase_price'] != null ? num.tryParse(json['base_purchase_price'].toString()) : null,
      mainUnit: json['main_unit'] as String?,
      secondaryUnit: json['secondary_unit'] as String?,
      isActive: (json['is_active'] ?? true) as bool,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'business_id': businessId,
      'code': code,
      'name': name,
      'item_type': itemType,
      'description': description,
      'category_id': categoryId,
      'track_inventory': trackInventory,
      'base_sales_price': baseSalesPrice,
      'base_purchase_price': basePurchasePrice,
      'main_unit': mainUnit,
      'secondary_unit': secondaryUnit,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// نمایش نام کامل برای UI
  String get displayName {
    if (code != null && code!.isNotEmpty) {
      return '$code - $name';
    }
    return name;
  }
}

