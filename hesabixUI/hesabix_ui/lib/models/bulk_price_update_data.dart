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

class BulkPriceUpdateRequest {
  final BulkPriceUpdateType updateType;
  final BulkPriceUpdateDirection direction;
  final BulkPriceUpdateTarget target;
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
  });

  factory BulkPriceUpdatePreview.fromJson(Map<String, dynamic> json) {
    return BulkPriceUpdatePreview(
      productId: json['product_id'] as int,
      productName: json['product_name']?.toString() ?? 'بدون نام',
      productCode: json['product_code']?.toString() ?? 'بدون کد',
      categoryName: json['category_name']?.toString(),
      currentSalesPrice: _parsePrice(json['current_sales_price']),
      currentPurchasePrice: _parsePrice(json['current_purchase_price']),
      newSalesPrice: _parsePrice(json['new_sales_price']),
      newPurchasePrice: _parsePrice(json['new_purchase_price']),
      salesPriceChange: _parsePrice(json['sales_price_change']),
      purchasePriceChange: _parsePrice(json['purchase_price_change']),
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
    return BulkPriceUpdatePreviewResponse(
      totalProducts: json['total_products'] as int,
      affectedProducts: (json['affected_products'] as List<dynamic>)
          .map((e) => BulkPriceUpdatePreview.fromJson(e as Map<String, dynamic>))
          .toList(),
      summary: json['summary'] as Map<String, dynamic>,
    );
  }
}
