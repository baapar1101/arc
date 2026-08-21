import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'customer_model.dart';
import 'invoice_line_item.dart';
import 'invoice_transaction.dart';

/// یک فروش باز در صندوق فروش سریع (Park / Hold).
///
/// سبد فعال در state صفحه است؛ این مدل برای سبدهای دیگر و برای ماندگاری محلی است.
class QuickSalesParkedSale {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Customer? customer;
  final List<InvoiceLineItem> cartItems;
  final List<InvoiceTransaction> payments;
  final bool cashFollowsTotal;
  final String? cashRegisterId;
  final int? warehouseId;
  final DateTime documentDate;
  final String documentDescription;
  final String globalDiscountType;
  final String globalDiscountValue;
  final bool autoCreatePaymentDocument;
  final bool shareOnlinePaymentEnabled;
  final int? shareGatewayId;
  final bool shareSendSms;
  final bool shareSendEmail;
  final bool shareViaNativeShare;
  final int shareExpiryHours;
  final int itemCount;
  final num totalAmount;

  const QuickSalesParkedSale({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.customer,
    this.cartItems = const [],
    this.payments = const [],
    this.cashFollowsTotal = true,
    this.cashRegisterId,
    this.warehouseId,
    required this.documentDate,
    this.documentDescription = '',
    this.globalDiscountType = 'percent',
    this.globalDiscountValue = '',
    this.autoCreatePaymentDocument = true,
    this.shareOnlinePaymentEnabled = true,
    this.shareGatewayId,
    this.shareSendSms = true,
    this.shareSendEmail = false,
    this.shareViaNativeShare = true,
    this.shareExpiryHours = 168,
    this.itemCount = 0,
    this.totalAmount = 0,
  });

  static String newId() => const Uuid().v4();

  bool isBlank({int? anonymousCustomerId}) {
    final isAnon =
        customer == null ||
        (anonymousCustomerId != null && customer!.id == anonymousCustomerId);
    return cartItems.isEmpty &&
        isAnon &&
        documentDescription.trim().isEmpty &&
        globalDiscountValue.trim().isEmpty &&
        !_hasCustomPayments;
  }

  bool get _hasCustomPayments {
    if (payments.isEmpty) return false;
    if (cashFollowsTotal &&
        payments.length == 1 &&
        payments.first.type == TransactionType.cashRegister) {
      return false;
    }
    return true;
  }

  QuickSalesParkedSale copyWith({
    DateTime? updatedAt,
    Customer? customer,
    List<InvoiceLineItem>? cartItems,
    List<InvoiceTransaction>? payments,
    bool? cashFollowsTotal,
    String? cashRegisterId,
    int? warehouseId,
    DateTime? documentDate,
    String? documentDescription,
    String? globalDiscountType,
    String? globalDiscountValue,
    bool? autoCreatePaymentDocument,
    bool? shareOnlinePaymentEnabled,
    int? shareGatewayId,
    bool? shareSendSms,
    bool? shareSendEmail,
    bool? shareViaNativeShare,
    int? shareExpiryHours,
    int? itemCount,
    num? totalAmount,
  }) {
    return QuickSalesParkedSale(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      customer: customer ?? this.customer,
      cartItems: cartItems ?? this.cartItems,
      payments: payments ?? this.payments,
      cashFollowsTotal: cashFollowsTotal ?? this.cashFollowsTotal,
      cashRegisterId: cashRegisterId ?? this.cashRegisterId,
      warehouseId: warehouseId ?? this.warehouseId,
      documentDate: documentDate ?? this.documentDate,
      documentDescription: documentDescription ?? this.documentDescription,
      globalDiscountType: globalDiscountType ?? this.globalDiscountType,
      globalDiscountValue: globalDiscountValue ?? this.globalDiscountValue,
      autoCreatePaymentDocument:
          autoCreatePaymentDocument ?? this.autoCreatePaymentDocument,
      shareOnlinePaymentEnabled:
          shareOnlinePaymentEnabled ?? this.shareOnlinePaymentEnabled,
      shareGatewayId: shareGatewayId ?? this.shareGatewayId,
      shareSendSms: shareSendSms ?? this.shareSendSms,
      shareSendEmail: shareSendEmail ?? this.shareSendEmail,
      shareViaNativeShare: shareViaNativeShare ?? this.shareViaNativeShare,
      shareExpiryHours: shareExpiryHours ?? this.shareExpiryHours,
      itemCount: itemCount ?? this.itemCount,
      totalAmount: totalAmount ?? this.totalAmount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'customer': customer?.toJson(),
      'cart_items': cartItems.map(encodeLine).toList(),
      'payments': payments.map((p) => p.toJson()).toList(),
      'cash_follows_total': cashFollowsTotal,
      'cash_register_id': cashRegisterId,
      'warehouse_id': warehouseId,
      'document_date': documentDate.toIso8601String(),
      'document_description': documentDescription,
      'global_discount_type': globalDiscountType,
      'global_discount_value': globalDiscountValue,
      'auto_create_payment_document': autoCreatePaymentDocument,
      'share_online_payment_enabled': shareOnlinePaymentEnabled,
      'share_gateway_id': shareGatewayId,
      'share_send_sms': shareSendSms,
      'share_send_email': shareSendEmail,
      'share_via_native_share': shareViaNativeShare,
      'share_expiry_hours': shareExpiryHours,
      'item_count': itemCount,
      'total_amount': totalAmount,
    };
  }

  factory QuickSalesParkedSale.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['cart_items'];
    final items = <InvoiceLineItem>[];
    if (itemsRaw is List) {
      for (final raw in itemsRaw) {
        if (raw is Map) {
          items.add(decodeLine(Map<String, dynamic>.from(raw)));
        }
      }
    }

    final payments = <InvoiceTransaction>[];
    final paymentsRaw = json['payments'];
    if (paymentsRaw is List) {
      for (final raw in paymentsRaw) {
        if (raw is Map) {
          try {
            payments.add(
              InvoiceTransaction.fromJson(Map<String, dynamic>.from(raw)),
            );
          } catch (_) {}
        }
      }
    } else {
      final paymentRaw = json['payment'];
      if (paymentRaw is Map) {
        try {
          payments.add(
            InvoiceTransaction.fromJson(Map<String, dynamic>.from(paymentRaw)),
          );
        } catch (_) {}
      }
    }

    return QuickSalesParkedSale(
      id: json['id']?.toString() ?? newId(),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      customer: _customerFromJson(json['customer']),
      cartItems: items,
      payments: payments,
      cashFollowsTotal:
          json['cash_follows_total'] != false && (payments.length <= 1),
      cashRegisterId: json['cash_register_id']?.toString(),
      warehouseId: _asInt(json['warehouse_id']),
      documentDate:
          DateTime.tryParse(json['document_date']?.toString() ?? '') ??
          DateTime.now(),
      documentDescription: json['document_description']?.toString() ?? '',
      globalDiscountType: json['global_discount_type']?.toString() ?? 'percent',
      globalDiscountValue: json['global_discount_value']?.toString() ?? '',
      autoCreatePaymentDocument: json['auto_create_payment_document'] != false,
      shareOnlinePaymentEnabled: json['share_online_payment_enabled'] != false,
      shareGatewayId: _asInt(json['share_gateway_id']),
      shareSendSms: json['share_send_sms'] == true,
      shareSendEmail: json['share_send_email'] == true,
      shareViaNativeShare: json['share_via_native_share'] != false,
      shareExpiryHours: _asInt(json['share_expiry_hours']) ?? 168,
      itemCount: _asInt(json['item_count']) ?? items.length,
      totalAmount: _asNum(json['total_amount']) ?? 0,
    );
  }

  static InvoiceLineItem cloneLine(InvoiceLineItem item) =>
      decodeLine(encodeLine(item));

  static Map<String, dynamic> encodeLine(InvoiceLineItem item) {
    final map = <String, dynamic>{
      'line_key': item.lineKey,
      'product_id': item.productId,
      'product_code': item.productCode,
      'product_name': item.productName,
      'main_unit': item.mainUnit,
      'secondary_unit': item.secondaryUnit,
      'unit_conversion_factor': item.unitConversionFactor,
      'selected_unit': item.selectedUnit,
      'quantity': item.quantity,
      'unit_price_source': item.unitPriceSource,
      'unit_price': item.unitPrice,
      'base_sales_price_main_unit': item.baseSalesPriceMainUnit,
      'base_purchase_price_main_unit': item.basePurchasePriceMainUnit,
      'sales_price_fx_main_unit': item.salesPriceFxMainUnit,
      'purchase_price_fx_main_unit': item.purchasePriceFxMainUnit,
      'price_fx_currency_id': item.priceFxCurrencyId,
      'discount_type': item.discountType,
      'discount_value': item.discountValue,
      'tax_rate': item.taxRate,
      'min_order_qty': item.minOrderQty,
      'track_inventory': item.trackInventory,
      'warehouse_id': item.warehouseId,
      'description': item.description,
      'selected_instance_ids': item.selectedInstanceIds,
      'extra_info': item.extraInfo,
    };
    return Map<String, dynamic>.from(_jsonSafe(map) as Map? ?? map);
  }

  static InvoiceLineItem decodeLine(Map<String, dynamic> json) {
    final extraRaw = json['extra_info'];
    Map<String, dynamic>? extra;
    if (extraRaw is Map) {
      extra = Map<String, dynamic>.from(extraRaw);
    }
    final instanceRaw = json['selected_instance_ids'];
    List<int>? instances;
    if (instanceRaw is List) {
      instances = instanceRaw.map(_asInt).whereType<int>().toList();
    }
    return InvoiceLineItem(
      lineKey: json['line_key']?.toString(),
      productId: _asInt(json['product_id']),
      productCode: json['product_code']?.toString(),
      productName: json['product_name']?.toString(),
      mainUnit: json['main_unit']?.toString(),
      secondaryUnit: json['secondary_unit']?.toString(),
      unitConversionFactor: _asNum(json['unit_conversion_factor']),
      selectedUnit: json['selected_unit']?.toString(),
      quantity: _asNum(json['quantity']) ?? 1,
      unitPriceSource: json['unit_price_source']?.toString() ?? 'base',
      unitPrice: _asNum(json['unit_price']) ?? 0,
      discountType: json['discount_type']?.toString() ?? 'percent',
      discountValue: _asNum(json['discount_value']) ?? 0,
      taxRate: _asNum(json['tax_rate']) ?? 0,
      baseSalesPriceMainUnit: _asNum(json['base_sales_price_main_unit']),
      basePurchasePriceMainUnit: _asNum(json['base_purchase_price_main_unit']),
      salesPriceFxMainUnit: _asNum(json['sales_price_fx_main_unit']),
      purchasePriceFxMainUnit: _asNum(json['purchase_price_fx_main_unit']),
      priceFxCurrencyId: _asInt(json['price_fx_currency_id']),
      minOrderQty: _asInt(json['min_order_qty']),
      trackInventory: json['track_inventory'] == true,
      warehouseId: _asInt(json['warehouse_id']),
      description: json['description']?.toString(),
      selectedInstanceIds: instances,
      extraInfo: extra,
    );
  }
}

class QuickSalesParkedSalesBundle {
  static const int version = 1;

  final String activeId;
  final List<QuickSalesParkedSale> sales;

  const QuickSalesParkedSalesBundle({
    required this.activeId,
    required this.sales,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'active_id': activeId,
    'sales': sales.map((s) => s.toJson()).toList(),
  };

  static QuickSalesParkedSalesBundle? tryParse(Object? decoded) {
    if (decoded is! Map) return null;
    final json = Map<String, dynamic>.from(decoded);
    if (_asInt(json['version']) != version) return null;
    final rawSales = json['sales'];
    if (rawSales is! List || rawSales.isEmpty) return null;
    final sales = <QuickSalesParkedSale>[];
    for (final raw in rawSales) {
      if (raw is Map) {
        sales.add(
          QuickSalesParkedSale.fromJson(Map<String, dynamic>.from(raw)),
        );
      }
    }
    if (sales.isEmpty) return null;
    var activeId = json['active_id']?.toString() ?? sales.first.id;
    if (!sales.any((s) => s.id == activeId)) {
      activeId = sales.first.id;
    }
    return QuickSalesParkedSalesBundle(activeId: activeId, sales: sales);
  }
}

class QuickSalesParkedSalesStorage {
  static const prefix = 'quick_sales_parked_sales_';

  static String keyFor(int businessId) => '$prefix$businessId';

  static Future<QuickSalesParkedSalesBundle?> load(int businessId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(keyFor(businessId));
      if (raw == null || raw.isEmpty) return null;
      return QuickSalesParkedSalesBundle.tryParse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(
    int businessId,
    QuickSalesParkedSalesBundle bundle,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyFor(businessId), jsonEncode(bundle.toJson()));
    } catch (_) {}
  }
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

num? _asNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString());
}

Customer? _customerFromJson(dynamic raw) {
  if (raw is! Map) return null;
  final json = Map<String, dynamic>.from(raw);
  final id = _asInt(json['id']);
  final name = json['name']?.toString().trim() ?? '';
  if (id == null || name.isEmpty) return null;
  return Customer(
    id: id,
    name: name,
    code: json['code']?.toString(),
    phone: json['phone']?.toString(),
    email: json['email']?.toString(),
    address: json['address']?.toString(),
    isActive: json['is_active'] != false,
  );
}

dynamic _jsonSafe(dynamic value) {
  try {
    return jsonDecode(jsonEncode(value));
  } catch (_) {
    return null;
  }
}
