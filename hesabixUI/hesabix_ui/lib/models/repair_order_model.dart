import 'package:intl/intl.dart' as intl;

/// مدل سفارش تعمیر
class RepairOrder {
  final int id;
  final String code;
  final int businessId;
  final int customerPersonId;
  final String customerName;
  final String? customerPhone;
  final String? customerEmail;
  final int? productId;
  final String productName;
  final String? productSerial;
  final int? warrantyCodeId;
  final String status;
  final String problemDescription;
  final String? customerNotes;
  final String? technicianNotes;
  final int? assignedTechnicianId;
  final String? technicianName;
  final double? estimatedCost;
  final double finalCost;
  final double partsCost;
  final double laborCost;
  final double technicianCommission;
  final int currencyId;
  final String currencySymbol;
  final String? currencyCode;
  final DateTime receivedAt;
  final DateTime? estimatedDeliveryAt;
  final DateTime? completedAt;
  final DateTime? deliveredAt;
  final Map<String, dynamic> extraInfo;
  final List<RepairOrderPart> parts;
  final List<RepairOrderStatusItem> statusHistory;

  RepairOrder({
    required this.id,
    required this.code,
    required this.businessId,
    required this.customerPersonId,
    required this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.productId,
    required this.productName,
    this.productSerial,
    this.warrantyCodeId,
    required this.status,
    required this.problemDescription,
    this.customerNotes,
    this.technicianNotes,
    this.assignedTechnicianId,
    this.technicianName,
    this.estimatedCost,
    required this.finalCost,
    required this.partsCost,
    required this.laborCost,
    required this.technicianCommission,
    required this.currencyId,
    required this.currencySymbol,
    this.currencyCode,
    required this.receivedAt,
    this.estimatedDeliveryAt,
    this.completedAt,
    this.deliveredAt,
    required this.extraInfo,
    required this.parts,
    required this.statusHistory,
  });

  factory RepairOrder.fromJson(Map<String, dynamic> json) {
    return RepairOrder(
      id: json['id'] as int,
      code: json['code'] as String,
      businessId: json['business_id'] as int,
      customerPersonId: json['customer_person_id'] as int,
      customerName: json['customer_name'] as String,
      customerPhone: json['customer_phone'] as String?,
      customerEmail: json['customer_email'] as String?,
      productId: json['product_id'] as int?,
      productName: json['product_name'] as String,
      productSerial: json['product_serial'] as String?,
      warrantyCodeId: json['warranty_code_id'] as int?,
      status: json['status'] as String,
      problemDescription: json['problem_description'] as String,
      customerNotes: json['customer_notes'] as String?,
      technicianNotes: json['technician_notes'] as String?,
      assignedTechnicianId: json['assigned_technician_id'] as int?,
      technicianName: json['technician_name'] as String?,
      estimatedCost: (json['estimated_cost'] as num?)?.toDouble(),
      finalCost: (json['final_cost'] as num).toDouble(),
      partsCost: (json['parts_cost'] as num).toDouble(),
      laborCost: (json['labor_cost'] as num).toDouble(),
      technicianCommission: (json['technician_commission'] as num).toDouble(),
      currencyId: json['currency_id'] as int,
      currencySymbol: json['currency_symbol'] as String? ?? 'تومان',
      currencyCode: json['currency_code'] as String?,
      receivedAt: DateTime.parse(json['received_at'] as String),
      estimatedDeliveryAt: json['estimated_delivery_at'] != null
          ? DateTime.parse(json['estimated_delivery_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.parse(json['delivered_at'] as String)
          : null,
      extraInfo: (json['extra_info'] as Map<String, dynamic>?) ?? {},
      parts: (json['parts'] as List<dynamic>?)
              ?.map((e) => RepairOrderPart.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      statusHistory: (json['status_history'] as List<dynamic>?)
              ?.map((e) =>
                  RepairOrderStatusItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'business_id': businessId,
      'customer_person_id': customerPersonId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_email': customerEmail,
      'product_id': productId,
      'product_name': productName,
      'product_serial': productSerial,
      'warranty_code_id': warrantyCodeId,
      'status': status,
      'problem_description': problemDescription,
      'customer_notes': customerNotes,
      'technician_notes': technicianNotes,
      'assigned_technician_id': assignedTechnicianId,
      'technician_name': technicianName,
      'estimated_cost': estimatedCost,
      'final_cost': finalCost,
      'parts_cost': partsCost,
      'labor_cost': laborCost,
      'technician_commission': technicianCommission,
      'currency_id': currencyId,
      'currency_symbol': currencySymbol,
      'currency_code': currencyCode,
      'received_at': receivedAt.toIso8601String(),
      'estimated_delivery_at': estimatedDeliveryAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'extra_info': extraInfo,
      'parts': parts.map((e) => e.toJson()).toList(),
      'status_history': statusHistory.map((e) => e.toJson()).toList(),
    };
  }

  RepairOrder copyWith({
    int? id,
    String? code,
    int? businessId,
    int? customerPersonId,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    int? productId,
    String? productName,
    String? productSerial,
    int? warrantyCodeId,
    String? status,
    String? problemDescription,
    String? customerNotes,
    String? technicianNotes,
    int? assignedTechnicianId,
    String? technicianName,
    double? estimatedCost,
    double? finalCost,
    double? partsCost,
    double? laborCost,
    double? technicianCommission,
    int? currencyId,
    String? currencySymbol,
    String? currencyCode,
    DateTime? receivedAt,
    DateTime? estimatedDeliveryAt,
    DateTime? completedAt,
    DateTime? deliveredAt,
    Map<String, dynamic>? extraInfo,
    List<RepairOrderPart>? parts,
    List<RepairOrderStatusItem>? statusHistory,
  }) {
    return RepairOrder(
      id: id ?? this.id,
      code: code ?? this.code,
      businessId: businessId ?? this.businessId,
      customerPersonId: customerPersonId ?? this.customerPersonId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerEmail: customerEmail ?? this.customerEmail,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSerial: productSerial ?? this.productSerial,
      warrantyCodeId: warrantyCodeId ?? this.warrantyCodeId,
      status: status ?? this.status,
      problemDescription: problemDescription ?? this.problemDescription,
      customerNotes: customerNotes ?? this.customerNotes,
      technicianNotes: technicianNotes ?? this.technicianNotes,
      assignedTechnicianId: assignedTechnicianId ?? this.assignedTechnicianId,
      technicianName: technicianName ?? this.technicianName,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      finalCost: finalCost ?? this.finalCost,
      partsCost: partsCost ?? this.partsCost,
      laborCost: laborCost ?? this.laborCost,
      technicianCommission: technicianCommission ?? this.technicianCommission,
      currencyId: currencyId ?? this.currencyId,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      currencyCode: currencyCode ?? this.currencyCode,
      receivedAt: receivedAt ?? this.receivedAt,
      estimatedDeliveryAt: estimatedDeliveryAt ?? this.estimatedDeliveryAt,
      completedAt: completedAt ?? this.completedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      extraInfo: extraInfo ?? this.extraInfo,
      parts: parts ?? this.parts,
      statusHistory: statusHistory ?? this.statusHistory,
    );
  }

  /// فرمت قیمت با ارز
  String formatPrice(double amount) {
    final formatter = intl.NumberFormat('#,###');
    return '${formatter.format(amount)} $currencySymbol';
  }

  /// فرمت هزینه نهایی
  String get formattedFinalCost => formatPrice(finalCost);

  /// فرمت هزینه قطعات
  String get formattedPartsCost => formatPrice(partsCost);

  /// فرمت دستمزد
  String get formattedLaborCost => formatPrice(laborCost);

  /// فرمت حق‌الزحمه
  String get formattedCommission => formatPrice(technicianCommission);
}

/// آیتم لیست سفارشات (نسخه ساده‌تر برای لیست)
class RepairOrderListItem {
  final int id;
  final String code;
  final int customerPersonId;
  final String customerName;
  final String? customerPhone;
  final String productName;
  final String? productSerial;
  final String status;
  final String problemDescription;
  final int? assignedTechnicianId;
  final String? technicianName;
  final double finalCost;
  final int currencyId;
  final String currencySymbol;
  final DateTime receivedAt;
  final DateTime? estimatedDeliveryAt;
  final DateTime? completedAt;

  RepairOrderListItem({
    required this.id,
    required this.code,
    required this.customerPersonId,
    required this.customerName,
    this.customerPhone,
    required this.productName,
    this.productSerial,
    required this.status,
    required this.problemDescription,
    this.assignedTechnicianId,
    this.technicianName,
    required this.finalCost,
    required this.currencyId,
    required this.currencySymbol,
    required this.receivedAt,
    this.estimatedDeliveryAt,
    this.completedAt,
  });

  factory RepairOrderListItem.fromJson(Map<String, dynamic> json) {
    return RepairOrderListItem(
      id: json['id'] as int,
      code: json['code'] as String,
      customerPersonId: json['customer_person_id'] as int,
      customerName: json['customer_name'] as String,
      customerPhone: json['customer_phone'] as String?,
      productName: json['product_name'] as String,
      productSerial: json['product_serial'] as String?,
      status: json['status'] as String,
      problemDescription: json['problem_description'] as String,
      assignedTechnicianId: json['assigned_technician_id'] as int?,
      technicianName: json['technician_name'] as String?,
      finalCost: (json['final_cost'] as num).toDouble(),
      currencyId: json['currency_id'] as int,
      currencySymbol: json['currency_symbol'] as String? ?? 'تومان',
      receivedAt: DateTime.parse(json['received_at'] as String),
      estimatedDeliveryAt: json['estimated_delivery_at'] != null
          ? DateTime.parse(json['estimated_delivery_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'customer_person_id': customerPersonId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'product_name': productName,
      'product_serial': productSerial,
      'status': status,
      'problem_description': problemDescription,
      'assigned_technician_id': assignedTechnicianId,
      'technician_name': technicianName,
      'final_cost': finalCost,
      'currency_id': currencyId,
      'currency_symbol': currencySymbol,
      'received_at': receivedAt.toIso8601String(),
      'estimated_delivery_at': estimatedDeliveryAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  /// فرمت قیمت نهایی با ارز
  String get formattedFinalCost {
    final formatter = intl.NumberFormat('#,###');
    return '${formatter.format(finalCost)} $currencySymbol';
  }
}

/// قطعه استفاده شده در تعمیر
class RepairOrderPart {
  final int id;
  final int productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double totalPrice;
  final int? warehouseId;
  final String? description;

  RepairOrderPart({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.warehouseId,
    this.description,
  });

  factory RepairOrderPart.fromJson(Map<String, dynamic> json) {
    return RepairOrderPart(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      productName: json['product_name'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unitPrice: (json['unit_price'] as num).toDouble(),
      totalPrice: (json['total_price'] as num).toDouble(),
      warehouseId: json['warehouse_id'] as int?,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'warehouse_id': warehouseId,
      'description': description,
    };
  }
}

/// آیتم تاریخچه وضعیت
class RepairOrderStatusItem {
  final int id;
  final String status;
  final String? notes;
  final DateTime createdAt;
  final bool smsSent;
  final bool emailSent;

  RepairOrderStatusItem({
    required this.id,
    required this.status,
    this.notes,
    required this.createdAt,
    required this.smsSent,
    required this.emailSent,
  });

  factory RepairOrderStatusItem.fromJson(Map<String, dynamic> json) {
    return RepairOrderStatusItem(
      id: json['id'] as int,
      status: json['status'] as String,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      smsSent: json['sms_sent'] as bool,
      emailSent: json['email_sent'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'status': status,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'sms_sent': smsSent,
      'email_sent': emailSent,
    };
  }
}

