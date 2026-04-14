class TaxSettingsModel {
  final int businessId;
  final String? taxMemoryId;
  final String? economicCode;
  final String? privateKey;
  final String? publicKey;
  final String? certificate;
  final String? certificateRequest;
  final bool sandboxMode;
  final bool hasPrivateKey;
  final DateTime? updatedAt;

  const TaxSettingsModel({
    required this.businessId,
    this.taxMemoryId,
    this.economicCode,
    this.privateKey,
    this.publicKey,
    this.certificate,
    this.certificateRequest,
    this.sandboxMode = false,
    this.hasPrivateKey = false,
    this.updatedAt,
  });

  factory TaxSettingsModel.fromJson(Map<String, dynamic> json) {
    return TaxSettingsModel(
      businessId: json['business_id'] is int
          ? json['business_id'] as int
          : int.tryParse(json['business_id']?.toString() ?? '') ?? 0,
      taxMemoryId: json['tax_memory_id']?.toString(),
      economicCode: json['economic_code']?.toString(),
      privateKey: json['private_key']?.toString(),
      publicKey: json['public_key']?.toString(),
      certificate: json['certificate']?.toString(),
      certificateRequest: json['certificate_request']?.toString(),
      sandboxMode: json['sandbox_mode'] == true,
      hasPrivateKey: json['has_private_key'] == true,
      updatedAt: json['updated_at'] != null && json['updated_at'].toString().isNotEmpty
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toPayload() {
    return {
      'tax_memory_id': taxMemoryId?.trim(),
      'economic_code': economicCode?.trim(),
      'private_key': privateKey?.trim(),
      'public_key': publicKey?.trim(),
      'certificate': certificate?.trim(),
      'certificate_request': certificateRequest?.trim(),
      'sandbox_mode': sandboxMode,
    };
  }

  TaxSettingsModel copyWith({
    String? taxMemoryId,
    String? economicCode,
    String? privateKey,
    String? publicKey,
    String? certificate,
    String? certificateRequest,
    bool? sandboxMode,
    bool? hasPrivateKey,
    DateTime? updatedAt,
  }) {
    return TaxSettingsModel(
      businessId: businessId,
      taxMemoryId: taxMemoryId ?? this.taxMemoryId,
      economicCode: economicCode ?? this.economicCode,
      privateKey: privateKey ?? this.privateKey,
      publicKey: publicKey ?? this.publicKey,
      certificate: certificate ?? this.certificate,
      certificateRequest: certificateRequest ?? this.certificateRequest,
      sandboxMode: sandboxMode ?? this.sandboxMode,
      hasPrivateKey: hasPrivateKey ?? this.hasPrivateKey,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class TaxGeneratedKeys {
  final String privateKey;
  final String publicKey;
  final String? csr;

  const TaxGeneratedKeys({
    required this.privateKey,
    required this.publicKey,
    this.csr,
  });

  factory TaxGeneratedKeys.fromJson(Map<String, dynamic> json) {
    return TaxGeneratedKeys(
      privateKey: json['private_key']?.toString() ?? '',
      publicKey: json['public_key']?.toString() ?? '',
      csr: json['csr']?.toString(),
    );
  }
}

class TaxDataQualityReport {
  final int businessId;
  final TaxDataQualityProducts products;
  final TaxDataQualityPersons persons;

  TaxDataQualityReport({
    required this.businessId,
    required this.products,
    required this.persons,
  });

  factory TaxDataQualityReport.fromJson(Map<String, dynamic> json) {
    return TaxDataQualityReport(
      businessId: json['business_id'] is int
          ? json['business_id'] as int
          : int.tryParse(json['business_id']?.toString() ?? '') ?? 0,
      products: TaxDataQualityProducts.fromJson(json['products'] as Map<String, dynamic>? ?? const {}),
      persons: TaxDataQualityPersons.fromJson(json['persons'] as Map<String, dynamic>? ?? const {}),
    );
  }
}

class TaxDataQualityProducts {
  final int missingTaxCode;
  final int missingTaxUnit;
  final List<TaxDataQualityProductSample> samples;

  const TaxDataQualityProducts({
    required this.missingTaxCode,
    required this.missingTaxUnit,
    required this.samples,
  });

  factory TaxDataQualityProducts.fromJson(Map<String, dynamic> json) {
    final sampleList = (json['samples'] as List<dynamic>? ?? const [])
        .map((item) => TaxDataQualityProductSample.fromJson(item as Map<String, dynamic>? ?? const {}))
        .toList();
    return TaxDataQualityProducts(
      missingTaxCode: json['missing_tax_code'] is int ? json['missing_tax_code'] as int : int.tryParse(json['missing_tax_code']?.toString() ?? '') ?? 0,
      missingTaxUnit: json['missing_tax_unit'] is int ? json['missing_tax_unit'] as int : int.tryParse(json['missing_tax_unit']?.toString() ?? '') ?? 0,
      samples: sampleList,
    );
  }
}

class TaxDataQualityPersons {
  final int missingNationalId;
  final int missingEconomicId;
  final List<TaxDataQualityPersonSample> samples;

  const TaxDataQualityPersons({
    required this.missingNationalId,
    required this.missingEconomicId,
    required this.samples,
  });

  factory TaxDataQualityPersons.fromJson(Map<String, dynamic> json) {
    final sampleList = (json['samples'] as List<dynamic>? ?? const [])
        .map((item) => TaxDataQualityPersonSample.fromJson(item as Map<String, dynamic>? ?? const {}))
        .toList();
    return TaxDataQualityPersons(
      missingNationalId: json['missing_national_id'] is int ? json['missing_national_id'] as int : int.tryParse(json['missing_national_id']?.toString() ?? '') ?? 0,
      missingEconomicId: json['missing_economic_id'] is int ? json['missing_economic_id'] as int : int.tryParse(json['missing_economic_id']?.toString() ?? '') ?? 0,
      samples: sampleList,
    );
  }
}

class TaxDataQualityProductSample {
  final int? id;
  final String? code;
  final String? name;
  final String? taxCode;
  final int? taxUnitId;
  final String? taxUnitCode;
  final String? taxUnitName;
  final String? productMainUnit;

  const TaxDataQualityProductSample({
    this.id,
    this.code,
    this.name,
    this.taxCode,
    this.taxUnitId,
    this.taxUnitCode,
    this.taxUnitName,
    this.productMainUnit,
  });

  factory TaxDataQualityProductSample.fromJson(Map<String, dynamic> json) {
    return TaxDataQualityProductSample(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id']?.toString() ?? ''),
      code: json['code']?.toString(),
      name: json['name']?.toString(),
      taxCode: json['tax_code']?.toString(),
      taxUnitId: json['tax_unit_id'] is int ? json['tax_unit_id'] as int : int.tryParse(json['tax_unit_id']?.toString() ?? ''),
      taxUnitCode: json['tax_unit_code']?.toString(),
      taxUnitName: json['tax_unit_name']?.toString(),
      productMainUnit: json['product_main_unit']?.toString(),
    );
  }
}

class TaxDataQualityPersonSample {
  final int? id;
  final String? code;
  final String? name;
  final List<dynamic>? personTypes;
  final String? nationalId;
  final String? economicId;

  const TaxDataQualityPersonSample({
    this.id,
    this.code,
    this.name,
    this.personTypes,
    this.nationalId,
    this.economicId,
  });

  factory TaxDataQualityPersonSample.fromJson(Map<String, dynamic> json) {
    return TaxDataQualityPersonSample(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id']?.toString() ?? ''),
      code: json['code']?.toString(),
      name: json['name']?.toString(),
      personTypes: json['person_types'] is List ? List<dynamic>.from(json['person_types']) : null,
      nationalId: json['national_id']?.toString(),
      economicId: json['economic_id']?.toString(),
    );
  }
}

