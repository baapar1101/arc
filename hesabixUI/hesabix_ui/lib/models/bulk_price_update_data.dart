enum BulkPriceUpdateType {
  percentage,
  amount,
}

enum BulkPriceUpdateDirection {
  increase,
  decrease,
}

enum BulkPriceUpdateTarget {
  salesPrice,
  purchasePrice,
  both,
}

/// محدوده اعمال تغییر قیمت گروهی (هم‌نام با بک‌اند snake_case در JSON)
enum BulkPriceUpdateScope {
  basePrices,
  priceListItems,
  both,
}

class BulkPriceUpdateRequest {
  final BulkPriceUpdateType updateType;
  final BulkPriceUpdateDirection direction;
  final BulkPriceUpdateTarget target;
  final BulkPriceUpdateScope updateScope;
  final double value;

  // فیلترهای انتخاب کالاها
  final List<int>? categoryIds;
  final List<int>? currencyIds;
  final List<int>? priceListIds;
  final List<String>? itemTypes;
  final List<int>? productIds;

  // گزینه‌های اضافی
  final bool? onlyProductsWithInventory;
  final bool onlyProductsWithBasePrice;

  BulkPriceUpdateRequest({
    required this.updateType,
    this.direction = BulkPriceUpdateDirection.increase,
    required this.target,
    this.updateScope = BulkPriceUpdateScope.both,
    required this.value,
    this.categoryIds,
    this.currencyIds,
    this.priceListIds,
    this.itemTypes,
    this.productIds,
    this.onlyProductsWithInventory,
    this.onlyProductsWithBasePrice = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'update_type': updateType.name,
      'direction': direction.name,
      'target': _targetToSnakeCase(target),
      'update_scope': _scopeToSnakeCase(updateScope),
      'value': value,
      if (categoryIds != null) 'category_ids': categoryIds,
      if (currencyIds != null) 'currency_ids': currencyIds,
      if (priceListIds != null) 'price_list_ids': priceListIds,
      if (itemTypes != null) 'item_types': itemTypes,
      if (productIds != null) 'product_ids': productIds,
      if (onlyProductsWithInventory != null) 'only_products_with_inventory': onlyProductsWithInventory,
      'only_products_with_base_price': onlyProductsWithBasePrice,
    };
  }

  String _targetToSnakeCase(BulkPriceUpdateTarget target) {
    switch (target) {
      case BulkPriceUpdateTarget.salesPrice:
        return 'sales_price';
      case BulkPriceUpdateTarget.purchasePrice:
        return 'purchase_price';
      case BulkPriceUpdateTarget.both:
        return 'both';
    }
  }

  String _scopeToSnakeCase(BulkPriceUpdateScope scope) {
    switch (scope) {
      case BulkPriceUpdateScope.basePrices:
        return 'base_prices';
      case BulkPriceUpdateScope.priceListItems:
        return 'price_list_items';
      case BulkPriceUpdateScope.both:
        return 'both';
    }
  }
}

class BulkPriceListItemPreview {
  final int priceItemId;
  final int priceListId;
  final String? priceListName;
  final int currencyId;
  final String tierName;
  final double currentPrice;
  final double newPrice;
  final double priceChange;

  BulkPriceListItemPreview({
    required this.priceItemId,
    required this.priceListId,
    this.priceListName,
    required this.currencyId,
    required this.tierName,
    required this.currentPrice,
    required this.newPrice,
    required this.priceChange,
  });

  factory BulkPriceListItemPreview.fromJson(Map<String, dynamic> json) {
    return BulkPriceListItemPreview(
      priceItemId: _toInt(json['price_item_id']),
      priceListId: _toInt(json['price_list_id']),
      priceListName: json['price_list_name']?.toString(),
      currencyId: _toInt(json['currency_id']),
      tierName: json['tier_name']?.toString() ?? '',
      currentPrice: _parsePrice(json['current_price']) ?? 0,
      newPrice: _parsePrice(json['new_price']) ?? 0,
      priceChange: _parsePrice(json['price_change']) ?? 0,
    );
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double? _parsePrice(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

class BulkPriceUpdatePreview {
  final int productId;
  final String productName;
  final String productCode;
  final String? categoryName;
  final double? currentSalesPrice;
  final double? currentPurchasePrice;
  final double? newSalesPrice;
  final double? newPurchasePrice;
  final double? salesPriceChange;
  final double? purchasePriceChange;
  final List<BulkPriceListItemPreview> priceListItems;

  BulkPriceUpdatePreview({
    required this.productId,
    required this.productName,
    required this.productCode,
    this.categoryName,
    this.currentSalesPrice,
    this.currentPurchasePrice,
    this.newSalesPrice,
    this.newPurchasePrice,
    this.salesPriceChange,
    this.purchasePriceChange,
    this.priceListItems = const [],
  });

  factory BulkPriceUpdatePreview.fromJson(Map<String, dynamic> json) {
    final rawList = json['price_list_items'];
    final list = <BulkPriceListItemPreview>[];
    if (rawList is List<dynamic>) {
      for (final e in rawList) {
        if (e is Map<String, dynamic>) {
          list.add(BulkPriceListItemPreview.fromJson(e));
        }
      }
    }
    final rawId = json['product_id'];
    final pid = rawId is int ? rawId : (rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '') ?? 0);
    return BulkPriceUpdatePreview(
      productId: pid,
      productName: json['product_name']?.toString() ?? 'بدون نام',
      productCode: json['product_code']?.toString() ?? 'بدون کد',
      categoryName: json['category_name']?.toString(),
      currentSalesPrice: _parsePrice(json['current_sales_price']),
      currentPurchasePrice: _parsePrice(json['current_purchase_price']),
      newSalesPrice: _parsePrice(json['new_sales_price']),
      newPurchasePrice: _parsePrice(json['new_purchase_price']),
      salesPriceChange: _parsePrice(json['sales_price_change']),
      purchasePriceChange: _parsePrice(json['purchase_price_change']),
      priceListItems: list,
    );
  }

  static double? _parsePrice(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed;
    }
    return null;
  }
}

class BulkPriceUpdatePreviewResponse {
  final int totalProducts;
  final List<BulkPriceUpdatePreview> affectedProducts;
  final Map<String, dynamic> summary;

  BulkPriceUpdatePreviewResponse({
    required this.totalProducts,
    required this.affectedProducts,
    required this.summary,
  });

  factory BulkPriceUpdatePreviewResponse.fromJson(Map<String, dynamic> json) {
    final tp = json['total_products'];
    final total = tp is int ? tp : (tp is num ? tp.toInt() : int.tryParse(tp?.toString() ?? '') ?? 0);
    return BulkPriceUpdatePreviewResponse(
      totalProducts: total,
      affectedProducts: (json['affected_products'] as List<dynamic>)
          .map((e) => BulkPriceUpdatePreview.fromJson(e as Map<String, dynamic>))
          .toList(),
      summary: Map<String, dynamic>.from(json['summary'] as Map),
    );
  }
}
