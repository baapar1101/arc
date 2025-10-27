class BomItem {
  final int lineNo;
  final int componentProductId;
  final double qtyPer;
  final String? uom;
  final double? wastagePercent;
  final bool isOptional;
  final String? substituteGroup;
  final int? suggestedWarehouseId;

  const BomItem({
    required this.lineNo,
    required this.componentProductId,
    required this.qtyPer,
    this.uom,
    this.wastagePercent,
    this.isOptional = false,
    this.substituteGroup,
    this.suggestedWarehouseId,
  });

  factory BomItem.fromJson(Map<String, dynamic> json) {
    return BomItem(
      lineNo: (json['line_no'] ?? json['lineNo']) as int,
      componentProductId: (json['component_product_id'] ?? json['componentProductId']) as int,
      qtyPer: double.tryParse(json['qty_per']?.toString() ?? '0') ?? 0,
      uom: json['uom'] as String?,
      wastagePercent: json['wastage_percent'] != null ? double.tryParse(json['wastage_percent'].toString()) : null,
      isOptional: (json['is_optional'] ?? false) as bool,
      substituteGroup: json['substitute_group'] as String?,
      suggestedWarehouseId: json['suggested_warehouse_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'line_no': lineNo,
      'component_product_id': componentProductId,
      'qty_per': qtyPer,
      'uom': uom,
      'wastage_percent': wastagePercent,
      'is_optional': isOptional,
      'substitute_group': substituteGroup,
      'suggested_warehouse_id': suggestedWarehouseId,
    };
  }
}

class BomOutput {
  final int lineNo;
  final int outputProductId;
  final double ratio;
  final String? uom;

  const BomOutput({
    required this.lineNo,
    required this.outputProductId,
    required this.ratio,
    this.uom,
  });

  factory BomOutput.fromJson(Map<String, dynamic> json) {
    return BomOutput(
      lineNo: (json['line_no'] ?? json['lineNo']) as int,
      outputProductId: (json['output_product_id'] ?? json['outputProductId']) as int,
      ratio: double.tryParse(json['ratio']?.toString() ?? '0') ?? 0,
      uom: json['uom'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'line_no': lineNo,
      'output_product_id': outputProductId,
      'ratio': ratio,
      'uom': uom,
    };
  }
}

class BomOperation {
  final int lineNo;
  final String operationName;
  final double? costFixed;
  final double? costPerUnit;
  final String? costUom;
  final String? workCenter;

  const BomOperation({
    required this.lineNo,
    required this.operationName,
    this.costFixed,
    this.costPerUnit,
    this.costUom,
    this.workCenter,
  });

  factory BomOperation.fromJson(Map<String, dynamic> json) {
    return BomOperation(
      lineNo: (json['line_no'] ?? json['lineNo']) as int,
      operationName: (json['operation_name'] ?? json['operationName'] ?? '') as String,
      costFixed: json['cost_fixed'] != null ? double.tryParse(json['cost_fixed'].toString()) : null,
      costPerUnit: json['cost_per_unit'] != null ? double.tryParse(json['cost_per_unit'].toString()) : null,
      costUom: json['cost_uom'] as String?,
      workCenter: json['work_center'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'line_no': lineNo,
      'operation_name': operationName,
      'cost_fixed': costFixed,
      'cost_per_unit': costPerUnit,
      'cost_uom': costUom,
      'work_center': workCenter,
    };
  }
}

class ProductBOM {
  final int? id;
  final int businessId;
  final int productId;
  final String version;
  final String name;
  final bool isDefault;
  final String? effectiveFrom;
  final String? effectiveTo;
  final double? yieldPercent;
  final double? wastagePercent;
  final String status;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final List<BomItem> items;
  final List<BomOutput> outputs;
  final List<BomOperation> operations;

  const ProductBOM({
    this.id,
    required this.businessId,
    required this.productId,
    required this.version,
    required this.name,
    this.isDefault = false,
    this.effectiveFrom,
    this.effectiveTo,
    this.yieldPercent,
    this.wastagePercent,
    this.status = 'draft',
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.items = const <BomItem>[],
    this.outputs = const <BomOutput>[],
    this.operations = const <BomOperation>[],
  });

  factory ProductBOM.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const <dynamic>[])
        .map((e) => BomItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final outputs = (json['outputs'] as List<dynamic>? ?? const <dynamic>[])
        .map((e) => BomOutput.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final operations = (json['operations'] as List<dynamic>? ?? const <dynamic>[])
        .map((e) => BomOperation.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return ProductBOM(
      id: json['id'] as int?,
      businessId: (json['business_id'] ?? json['businessId']) as int,
      productId: (json['product_id'] ?? json['productId']) as int,
      version: (json['version'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      isDefault: (json['is_default'] ?? json['isDefault'] ?? false) as bool,
      effectiveFrom: json['effective_from'] as String?,
      effectiveTo: json['effective_to'] as String?,
      yieldPercent: json['yield_percent'] != null ? double.tryParse(json['yield_percent'].toString()) : null,
      wastagePercent: json['wastage_percent'] != null ? double.tryParse(json['wastage_percent'].toString()) : null,
      status: (json['status'] ?? 'draft') as String,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
      items: items,
      outputs: outputs,
      operations: operations,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'business_id': businessId,
      'product_id': productId,
      'version': version,
      'name': name,
      'is_default': isDefault,
      'effective_from': effectiveFrom,
      'effective_to': effectiveTo,
      'yield_percent': yieldPercent,
      'wastage_percent': wastagePercent,
      'status': status,
      'notes': notes,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'items': items.map((e) => e.toJson()).toList(),
      'outputs': outputs.map((e) => e.toJson()).toList(),
      'operations': operations.map((e) => e.toJson()).toList(),
    };
  }
}

class BomExplosionItem {
  final int componentProductId;
  final double requiredQty;
  final String? uom;
  final int? suggestedWarehouseId;
  final bool isOptional;
  final String? substituteGroup;

  const BomExplosionItem({
    required this.componentProductId,
    required this.requiredQty,
    this.uom,
    this.suggestedWarehouseId,
    this.isOptional = false,
    this.substituteGroup,
  });

  factory BomExplosionItem.fromJson(Map<String, dynamic> json) {
    return BomExplosionItem(
      componentProductId: (json['component_product_id'] ?? json['componentProductId']) as int,
      requiredQty: double.tryParse(json['required_qty']?.toString() ?? '0') ?? 0,
      uom: json['uom'] as String?,
      suggestedWarehouseId: json['suggested_warehouse_id'] as int?,
      isOptional: (json['is_optional'] ?? false) as bool,
      substituteGroup: json['substitute_group'] as String?,
    );
  }
}

class BomExplosionResult {
  final List<BomExplosionItem> items;
  final List<BomOutput> outputs;

  const BomExplosionResult({this.items = const <BomExplosionItem>[], this.outputs = const <BomOutput>[]});

  factory BomExplosionResult.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const <dynamic>[])
        .map((e) => BomExplosionItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final outputs = (json['outputs'] as List<dynamic>? ?? const <dynamic>[])
        .map((e) => BomOutput.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return BomExplosionResult(items: items, outputs: outputs);
  }
}
