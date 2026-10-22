class ProductionOrderMaterial {
  final int? id;
  final int lineNo;
  final int productId;
  final String? productName;
  final String? productCode;
  final String? uom;
  final int warehouseId;
  final double plannedQuantity;
  final double reservedQuantity;
  final double issuedQuantity;
  final double standardUnitCost;
  final double standardTotalCost;
  final String? lotCode;
  final String? bomPath;
  final bool isOptional;
  final int? sourceBomId;

  const ProductionOrderMaterial({
    this.id,
    required this.lineNo,
    required this.productId,
    this.productName,
    this.productCode,
    this.uom,
    required this.warehouseId,
    required this.plannedQuantity,
    this.reservedQuantity = 0,
    this.issuedQuantity = 0,
    this.standardUnitCost = 0,
    this.standardTotalCost = 0,
    this.lotCode,
    this.bomPath,
    this.isOptional = false,
    this.sourceBomId,
  });

  factory ProductionOrderMaterial.fromJson(Map<String, dynamic> json) {
    return ProductionOrderMaterial(
      id: (json['id'] as num?)?.toInt(),
      lineNo: (json['line_no'] as num?)?.toInt() ?? 0,
      productId: (json['product_id'] as num?)?.toInt() ?? 0,
      productName: json['product_name']?.toString(),
      productCode: json['product_code']?.toString(),
      uom: json['uom']?.toString(),
      warehouseId: (json['warehouse_id'] as num?)?.toInt() ?? 0,
      plannedQuantity:
          double.tryParse(json['planned_quantity']?.toString() ?? '0') ?? 0,
      reservedQuantity:
          double.tryParse(json['reserved_quantity']?.toString() ?? '0') ?? 0,
      issuedQuantity:
          double.tryParse(json['issued_quantity']?.toString() ?? '0') ?? 0,
      standardUnitCost:
          double.tryParse(json['standard_unit_cost']?.toString() ?? '0') ?? 0,
      standardTotalCost:
          double.tryParse(json['standard_total_cost']?.toString() ?? '0') ?? 0,
      lotCode: json['lot_code']?.toString(),
      bomPath: json['bom_path']?.toString(),
      isOptional: json['is_optional'] == true,
      sourceBomId: (json['source_bom_id'] as num?)?.toInt(),
    );
  }
}

class ProductionOrderOutput {
  final int? id;
  final int lineNo;
  final int productId;
  final String? productName;
  final String? productCode;
  final String? uom;
  final double plannedQuantity;
  final double producedQuantity;
  final double standardUnitCost;
  final double standardTotalCost;
  final double actualTotalCost;
  final double scrapQuantity;
  final String? lotCode;

  const ProductionOrderOutput({
    this.id,
    required this.lineNo,
    required this.productId,
    this.productName,
    this.productCode,
    this.uom,
    required this.plannedQuantity,
    this.producedQuantity = 0,
    this.standardUnitCost = 0,
    this.standardTotalCost = 0,
    this.actualTotalCost = 0,
    this.scrapQuantity = 0,
    this.lotCode,
  });

  factory ProductionOrderOutput.fromJson(Map<String, dynamic> json) {
    return ProductionOrderOutput(
      id: (json['id'] as num?)?.toInt(),
      lineNo: (json['line_no'] as num?)?.toInt() ?? 0,
      productId: (json['product_id'] as num?)?.toInt() ?? 0,
      productName: json['product_name']?.toString(),
      productCode: json['product_code']?.toString(),
      uom: json['uom']?.toString(),
      plannedQuantity:
          double.tryParse(json['planned_quantity']?.toString() ?? '0') ?? 0,
      producedQuantity:
          double.tryParse(json['produced_quantity']?.toString() ?? '0') ?? 0,
      standardUnitCost:
          double.tryParse(json['standard_unit_cost']?.toString() ?? '0') ?? 0,
      standardTotalCost:
          double.tryParse(json['standard_total_cost']?.toString() ?? '0') ?? 0,
      actualTotalCost:
          double.tryParse(json['actual_total_cost']?.toString() ?? '0') ?? 0,
      scrapQuantity:
          double.tryParse(json['scrap_quantity']?.toString() ?? '0') ?? 0,
      lotCode: json['lot_code']?.toString(),
    );
  }
}

class ProductionOrder {
  final int id;
  final int businessId;
  final String code;
  final int productId;
  final String? productName;
  final String? productCode;
  final int bomId;
  final int warehouseId;
  final int outputWarehouseId;
  final double plannedQuantity;
  final double producedQuantity;
  final String status;
  final int priority;
  final String? plannedStartDate;
  final String? dueDate;
  final String? startedAt;
  final String? completedAt;
  final int? createdByUserId;
  final int version;
  final String? notes;
  final String? closeReason;
  final bool closedShort;
  final String? createdAt;
  final String? updatedAt;
  final List<ProductionOrderMaterial> materials;
  final List<ProductionOrderOutput> outputs;

  const ProductionOrder({
    required this.id,
    required this.businessId,
    required this.code,
    required this.productId,
    this.productName,
    this.productCode,
    required this.bomId,
    required this.warehouseId,
    required this.outputWarehouseId,
    required this.plannedQuantity,
    this.producedQuantity = 0,
    required this.status,
    this.priority = 3,
    this.plannedStartDate,
    this.dueDate,
    this.startedAt,
    this.completedAt,
    this.createdByUserId,
    this.version = 1,
    this.notes,
    this.closeReason,
    this.closedShort = false,
    this.createdAt,
    this.updatedAt,
    this.materials = const [],
    this.outputs = const [],
  });

  factory ProductionOrder.fromJson(Map<String, dynamic> json) {
    final materialsRaw = json['materials'] as List? ?? const [];
    final outputsRaw = json['outputs'] as List? ?? const [];
    return ProductionOrder(
      id: (json['id'] as num?)?.toInt() ?? 0,
      businessId: (json['business_id'] as num?)?.toInt() ?? 0,
      code: json['code']?.toString() ?? '',
      productId: (json['product_id'] as num?)?.toInt() ?? 0,
      productName: json['product_name']?.toString(),
      productCode: json['product_code']?.toString(),
      bomId: (json['bom_id'] as num?)?.toInt() ?? 0,
      warehouseId: (json['warehouse_id'] as num?)?.toInt() ?? 0,
      outputWarehouseId: (json['output_warehouse_id'] as num?)?.toInt() ?? 0,
      plannedQuantity:
          double.tryParse(json['planned_quantity']?.toString() ?? '0') ?? 0,
      producedQuantity:
          double.tryParse(json['produced_quantity']?.toString() ?? '0') ?? 0,
      status: json['status']?.toString() ?? 'draft',
      priority: (json['priority'] as num?)?.toInt() ?? 3,
      plannedStartDate: json['planned_start_date']?.toString(),
      dueDate: json['due_date']?.toString(),
      startedAt: json['started_at']?.toString(),
      completedAt: json['completed_at']?.toString(),
      createdByUserId: (json['created_by_user_id'] as num?)?.toInt(),
      version: (json['version'] as num?)?.toInt() ?? 1,
      notes: json['notes']?.toString(),
      closeReason: json['close_reason']?.toString(),
      closedShort: json['closed_short'] == true,
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
      materials: materialsRaw
          .map(
            (e) => ProductionOrderMaterial.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      outputs: outputsRaw
          .map(
            (e) => ProductionOrderOutput.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
    );
  }

  bool get isDraft => status == 'draft';
  bool get isReleased => status == 'released';
  bool get isInProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
}

String productionOrderStatusLabel(String? status) {
  switch (status) {
    case 'draft':
      return 'پیش‌نویس';
    case 'released':
      return 'آزادسازی‌شده';
    case 'in_progress':
      return 'در حال اجرا';
    case 'completed':
      return 'تکمیل‌شده';
    case 'cancelled':
      return 'لغوشده';
    default:
      return status ?? '-';
  }
}
