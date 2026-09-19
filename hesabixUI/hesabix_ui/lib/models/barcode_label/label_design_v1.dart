// مدل‌های سند طراحی برچسب label_design_v1.

class LabelCanvas {
  final double widthMm;
  final double heightMm;
  final double gridMm;
  final bool snapToGrid;
  final List<double> guidesVertical;
  final List<double> guidesHorizontal;
  final int dpi;

  const LabelCanvas({
    required this.widthMm,
    required this.heightMm,
    this.gridMm = 1,
    this.snapToGrid = true,
    this.guidesVertical = const [],
    this.guidesHorizontal = const [],
    this.dpi = 300,
  });

  factory LabelCanvas.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    final guides = (j['guides_mm'] is Map) ? Map<String, dynamic>.from(j['guides_mm'] as Map) : const {};
    return LabelCanvas(
      widthMm: (j['width_mm'] as num?)?.toDouble() ?? 50,
      heightMm: (j['height_mm'] as num?)?.toDouble() ?? 30,
      gridMm: (j['grid_mm'] as num?)?.toDouble() ?? 1,
      snapToGrid: j['snap_to_grid'] != false,
      guidesVertical: ((guides['vertical'] as List?) ?? const []).map((e) => (e as num).toDouble()).toList(),
      guidesHorizontal: ((guides['horizontal'] as List?) ?? const []).map((e) => (e as num).toDouble()).toList(),
      dpi: (j['dpi'] as num?)?.toInt() ?? 300,
    );
  }

  Map<String, dynamic> toJson() => {
        'width_mm': widthMm,
        'height_mm': heightMm,
        'grid_mm': gridMm,
        'snap_to_grid': snapToGrid,
        'guides_mm': {
          'vertical': guidesVertical,
          'horizontal': guidesHorizontal,
        },
        'dpi': dpi,
      };

  LabelCanvas copyWith({
    double? widthMm,
    double? heightMm,
    double? gridMm,
    bool? snapToGrid,
    List<double>? guidesVertical,
    List<double>? guidesHorizontal,
    int? dpi,
  }) {
    return LabelCanvas(
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      gridMm: gridMm ?? this.gridMm,
      snapToGrid: snapToGrid ?? this.snapToGrid,
      guidesVertical: guidesVertical ?? this.guidesVertical,
      guidesHorizontal: guidesHorizontal ?? this.guidesHorizontal,
      dpi: dpi ?? this.dpi,
    );
  }
}

class LabelSheet {
  /// `sheet` = چیدمان روی کاغذ (A4/…)؛ `roll` = یک برچسب در هر صفحه (چاپگر حرارتی)
  final String printMode;
  final String paper;
  final String orientation;
  final Map<String, double>? customPaperMm;
  final Map<String, double> marginMm;
  final int columns;
  final int rows;
  final Map<String, double> gapMm;
  final bool labelFromCanvas;

  const LabelSheet({
    this.printMode = 'sheet',
    this.paper = 'A4',
    this.orientation = 'portrait',
    this.customPaperMm,
    this.marginMm = const {'top': 8, 'right': 8, 'bottom': 8, 'left': 8},
    this.columns = 3,
    this.rows = 8,
    this.gapMm = const {'x': 2, 'y': 2},
    this.labelFromCanvas = true,
  });

  bool get isRollMode => printMode == 'roll';

  factory LabelSheet.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    Map<String, double> mmMap(dynamic raw, Map<String, double> fallback) {
      if (raw is! Map) return fallback;
      return {
        for (final e in raw.entries) e.key.toString(): (e.value as num?)?.toDouble() ?? 0,
      };
    }

    Map<String, double>? custom;
    final rawCustom = j['custom_paper_mm'];
    if (rawCustom is Map) {
      custom = {
        for (final e in rawCustom.entries)
          e.key.toString(): (e.value as num?)?.toDouble() ?? 0,
      };
    }

    return LabelSheet(
      printMode: (j['print_mode'] as String?) ?? 'sheet',
      paper: (j['paper'] as String?) ?? 'A4',
      orientation: (j['orientation'] as String?) ?? 'portrait',
      customPaperMm: custom,
      marginMm: mmMap(j['margin_mm'], const {'top': 8, 'right': 8, 'bottom': 8, 'left': 8}),
      columns: (j['columns'] as num?)?.toInt() ?? 3,
      rows: (j['rows'] as num?)?.toInt() ?? 8,
      gapMm: mmMap(j['gap_mm'], const {'x': 2, 'y': 2}),
      labelFromCanvas: j['label_from_canvas'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'print_mode': printMode,
        'paper': paper,
        'orientation': orientation,
        'custom_paper_mm': customPaperMm,
        'margin_mm': marginMm,
        'columns': columns,
        'rows': rows,
        'gap_mm': gapMm,
        'label_from_canvas': labelFromCanvas,
      };

  LabelSheet copyWith({
    String? printMode,
    String? paper,
    String? orientation,
    Map<String, double>? customPaperMm,
    Map<String, double>? marginMm,
    int? columns,
    int? rows,
    Map<String, double>? gapMm,
    bool? labelFromCanvas,
  }) {
    return LabelSheet(
      printMode: printMode ?? this.printMode,
      paper: paper ?? this.paper,
      orientation: orientation ?? this.orientation,
      customPaperMm: customPaperMm ?? this.customPaperMm,
      marginMm: marginMm ?? this.marginMm,
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
      gapMm: gapMm ?? this.gapMm,
      labelFromCanvas: labelFromCanvas ?? this.labelFromCanvas,
    );
  }
}

enum LabelElementType { text, barcode, qr, datamatrix, image, shape, line }

LabelElementType parseLabelElementType(String? raw) {
  switch (raw) {
    case 'barcode':
      return LabelElementType.barcode;
    case 'qr':
      return LabelElementType.qr;
    case 'datamatrix':
      return LabelElementType.datamatrix;
    case 'image':
      return LabelElementType.image;
    case 'shape':
      return LabelElementType.shape;
    case 'line':
      return LabelElementType.line;
    case 'text':
    default:
      return LabelElementType.text;
  }
}

String labelElementTypeToJson(LabelElementType t) {
  switch (t) {
    case LabelElementType.text:
      return 'text';
    case LabelElementType.barcode:
      return 'barcode';
    case LabelElementType.qr:
      return 'qr';
    case LabelElementType.datamatrix:
      return 'datamatrix';
    case LabelElementType.image:
      return 'image';
    case LabelElementType.shape:
      return 'shape';
    case LabelElementType.line:
      return 'line';
  }
}

class LabelElement {
  final String id;
  final LabelElementType type;
  final String name;
  final double xMm;
  final double yMm;
  final double wMm;
  final double hMm;
  final double rotationDeg;
  final int zIndex;
  final bool locked;
  final bool visible;
  final Map<String, dynamic> props;

  const LabelElement({
    required this.id,
    required this.type,
    required this.name,
    required this.xMm,
    required this.yMm,
    required this.wMm,
    required this.hMm,
    this.rotationDeg = 0,
    this.zIndex = 0,
    this.locked = false,
    this.visible = true,
    this.props = const {},
  });

  factory LabelElement.fromJson(Map<String, dynamic> json) {
    return LabelElement(
      id: (json['id'] ?? '').toString(),
      type: parseLabelElementType(json['type']?.toString()),
      name: (json['name'] ?? json['id'] ?? '').toString(),
      xMm: (json['x_mm'] as num?)?.toDouble() ?? 0,
      yMm: (json['y_mm'] as num?)?.toDouble() ?? 0,
      wMm: (json['w_mm'] as num?)?.toDouble() ?? 10,
      hMm: (json['h_mm'] as num?)?.toDouble() ?? 6,
      rotationDeg: (json['rotation_deg'] as num?)?.toDouble() ?? 0,
      zIndex: (json['z_index'] as num?)?.toInt() ?? 0,
      locked: json['locked'] == true,
      visible: json['visible'] != false,
      props: json['props'] is Map ? Map<String, dynamic>.from(json['props'] as Map) : const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': labelElementTypeToJson(type),
        'name': name,
        'x_mm': xMm,
        'y_mm': yMm,
        'w_mm': wMm,
        'h_mm': hMm,
        'rotation_deg': rotationDeg,
        'z_index': zIndex,
        'locked': locked,
        'visible': visible,
        'props': props,
      };

  LabelElement copyWith({
    String? id,
    LabelElementType? type,
    String? name,
    double? xMm,
    double? yMm,
    double? wMm,
    double? hMm,
    double? rotationDeg,
    int? zIndex,
    bool? locked,
    bool? visible,
    Map<String, dynamic>? props,
  }) {
    return LabelElement(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      xMm: xMm ?? this.xMm,
      yMm: yMm ?? this.yMm,
      wMm: wMm ?? this.wMm,
      hMm: hMm ?? this.hMm,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      zIndex: zIndex ?? this.zIndex,
      locked: locked ?? this.locked,
      visible: visible ?? this.visible,
      props: props ?? this.props,
    );
  }
}

class LabelDesignDocument {
  final int schemaVersion;
  final LabelCanvas canvas;
  final List<LabelElement> elements;

  const LabelDesignDocument({
    this.schemaVersion = 1,
    required this.canvas,
    this.elements = const [],
  });

  factory LabelDesignDocument.empty({double widthMm = 50, double heightMm = 30}) {
    return LabelDesignDocument(
      canvas: LabelCanvas(widthMm: widthMm, heightMm: heightMm),
      elements: const [],
    );
  }

  factory LabelDesignDocument.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    final els = (j['elements'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => LabelElement.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    els.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return LabelDesignDocument(
      schemaVersion: (j['schema_version'] as num?)?.toInt() ?? 1,
      canvas: LabelCanvas.fromJson(j['canvas'] is Map ? Map<String, dynamic>.from(j['canvas'] as Map) : null),
      elements: els,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'canvas': canvas.toJson(),
        'elements': elements.map((e) => e.toJson()).toList(),
      };

  LabelDesignDocument copyWith({
    LabelCanvas? canvas,
    List<LabelElement>? elements,
  }) {
    return LabelDesignDocument(
      schemaVersion: schemaVersion,
      canvas: canvas ?? this.canvas,
      elements: elements ?? this.elements,
    );
  }
}

class LabelTemplateSummary {
  final int id;
  final String name;
  final String? description;
  final String status;
  final bool isDefault;
  final int version;
  final double? canvasWidthMm;
  final double? canvasHeightMm;
  final String? updatedAt;
  final String? publishedAt;

  const LabelTemplateSummary({
    required this.id,
    required this.name,
    this.description,
    required this.status,
    required this.isDefault,
    required this.version,
    this.canvasWidthMm,
    this.canvasHeightMm,
    this.updatedAt,
    this.publishedAt,
  });

  factory LabelTemplateSummary.fromJson(Map<String, dynamic> json) {
    return LabelTemplateSummary(
      id: (json['id'] as num).toInt(),
      name: (json['name'] ?? '').toString(),
      description: json['description']?.toString(),
      status: (json['status'] ?? 'draft').toString(),
      isDefault: json['is_default'] == true,
      version: (json['version'] as num?)?.toInt() ?? 1,
      canvasWidthMm: (json['canvas_width_mm'] as num?)?.toDouble(),
      canvasHeightMm: (json['canvas_height_mm'] as num?)?.toDouble(),
      updatedAt: json['updated_at']?.toString(),
      publishedAt: json['published_at']?.toString(),
    );
  }
}

class LabelTemplateDetail extends LabelTemplateSummary {
  final LabelDesignDocument design;
  final LabelSheet sheet;
  final List<Map<String, dynamic>> warnings;

  const LabelTemplateDetail({
    required super.id,
    required super.name,
    super.description,
    required super.status,
    required super.isDefault,
    required super.version,
    super.canvasWidthMm,
    super.canvasHeightMm,
    super.updatedAt,
    super.publishedAt,
    required this.design,
    required this.sheet,
    this.warnings = const [],
  });

  factory LabelTemplateDetail.fromJson(Map<String, dynamic> json) {
    final summary = LabelTemplateSummary.fromJson(json);
    return LabelTemplateDetail(
      id: summary.id,
      name: summary.name,
      description: summary.description,
      status: summary.status,
      isDefault: summary.isDefault,
      version: summary.version,
      canvasWidthMm: summary.canvasWidthMm,
      canvasHeightMm: summary.canvasHeightMm,
      updatedAt: summary.updatedAt,
      publishedAt: summary.publishedAt,
      design: LabelDesignDocument.fromJson(
        json['design_json'] is Map ? Map<String, dynamic>.from(json['design_json'] as Map) : null,
      ),
      sheet: LabelSheet.fromJson(
        json['sheet_json'] is Map ? Map<String, dynamic>.from(json['sheet_json'] as Map) : null,
      ),
      warnings: ((json['warnings'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
    );
  }
}

class LabelPreset {
  final String code;
  final String name;
  final String? nameEn;
  final String? description;
  final double widthMm;
  final double heightMm;

  const LabelPreset({
    required this.code,
    required this.name,
    this.nameEn,
    this.description,
    required this.widthMm,
    required this.heightMm,
  });

  factory LabelPreset.fromJson(Map<String, dynamic> json) {
    return LabelPreset(
      code: (json['code'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      nameEn: json['name_en']?.toString(),
      description: json['description']?.toString(),
      widthMm: (json['width_mm'] as num?)?.toDouble() ?? 50,
      heightMm: (json['height_mm'] as num?)?.toDouble() ?? 30,
    );
  }
}

/// کاتالوگ binding برای inspector.
class LabelBindingCatalog {
  static const entries = <Map<String, String>>[
    {'key': 'product.name', 'label_fa': 'نام کالا', 'label_en': 'Product name'},
    {'key': 'product.code', 'label_fa': 'کد کالا', 'label_en': 'Product code'},
    {'key': 'product.general_barcode', 'label_fa': 'بارکد عمومی', 'label_en': 'General barcode'},
    {'key': 'product.price', 'label_fa': 'قیمت', 'label_en': 'Price'},
    {'key': 'product.sale_price', 'label_fa': 'قیمت فروش', 'label_en': 'Sale price'},
    {'key': 'instance.serial', 'label_fa': 'سریال', 'label_en': 'Serial'},
    {'key': 'instance.barcode', 'label_fa': 'بارکد واحد', 'label_en': 'Instance barcode'},
    {'key': 'warehouse.name', 'label_fa': 'انبار', 'label_en': 'Warehouse'},
    {'key': 'business.name', 'label_fa': 'نام کسب‌وکار', 'label_en': 'Business name'},
    {'key': 'print.counter', 'label_fa': 'شمارنده چاپ', 'label_en': 'Print counter'},
  ];
}
