class PersonShareLinkOptionsModel {
  final bool includeLedger;
  final bool includeInvoices;
  final int documentsLimit;

  const PersonShareLinkOptionsModel({
    required this.includeLedger,
    required this.includeInvoices,
    required this.documentsLimit,
  });

  factory PersonShareLinkOptionsModel.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const {};
    return PersonShareLinkOptionsModel(
      includeLedger: data['include_ledger'] != false,
      includeInvoices: data['include_invoices'] != false,
      documentsLimit: (data['documents_limit'] as num?)?.toInt() ?? 50,
    );
  }

  Map<String, dynamic> toJson() => {
        'include_ledger': includeLedger,
        'include_invoices': includeInvoices,
        'documents_limit': documentsLimit,
      };

  PersonShareLinkOptionsModel copyWith({
    bool? includeLedger,
    bool? includeInvoices,
    int? documentsLimit,
  }) {
    return PersonShareLinkOptionsModel(
      includeLedger: includeLedger ?? this.includeLedger,
      includeInvoices: includeInvoices ?? this.includeInvoices,
      documentsLimit: documentsLimit ?? this.documentsLimit,
    );
  }
}

class PersonShareLink {
  final int id;
  final int businessId;
  final int personId;
  final String code;
  final String shortUrl;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final DateTime? lastViewAt;
  final int viewCount;
  final int? maxViewCount;
  final bool isActive;
  final bool isExpired;
  final String status;
  final double? remainingHours;
  final PersonShareLinkOptionsModel options;

  PersonShareLink({
    required this.id,
    required this.businessId,
    required this.personId,
    required this.code,
    required this.shortUrl,
    required this.createdAt,
    this.expiresAt,
    this.revokedAt,
    this.lastViewAt,
    required this.viewCount,
    this.maxViewCount,
    required this.isActive,
    required this.isExpired,
    required this.status,
    this.remainingHours,
    required this.options,
  });

  factory PersonShareLink.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      try {
        return DateTime.parse(value.toString()).toUtc();
      } catch (_) {
        return null;
      }
    }

    return PersonShareLink(
      id: json['id'] as int,
      businessId: json['business_id'] as int,
      personId: json['person_id'] as int,
      code: json['code'] as String,
      shortUrl: json['short_url'] as String,
      createdAt: parseDate(json['created_at']) ?? DateTime.now().toUtc(),
      expiresAt: parseDate(json['expires_at']),
      revokedAt: parseDate(json['revoked_at']),
      lastViewAt: parseDate(json['last_view_at']),
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      maxViewCount: (json['max_view_count'] as num?)?.toInt(),
      isActive: json['is_active'] == true,
      isExpired: json['is_expired'] == true,
      status: json['status']?.toString() ?? '',
      remainingHours: (json['remaining_hours'] as num?)?.toDouble(),
      options: PersonShareLinkOptionsModel.fromJson(
        json['options'] as Map<String, dynamic>?,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'person_id': personId,
      'code': code,
      'short_url': shortUrl,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'revoked_at': revokedAt?.toIso8601String(),
      'last_view_at': lastViewAt?.toIso8601String(),
      'view_count': viewCount,
      'max_view_count': maxViewCount,
      'is_active': isActive,
      'is_expired': isExpired,
      'status': status,
      'remaining_hours': remainingHours,
      'options': options.toJson(),
    };
  }

  PersonShareLink copyWith({
    int? viewCount,
    int? maxViewCount,
    bool? isActive,
    bool? isExpired,
    String? status,
    double? remainingHours,
    PersonShareLinkOptionsModel? options,
  }) {
    return PersonShareLink(
      id: id,
      businessId: businessId,
      personId: personId,
      code: code,
      shortUrl: shortUrl,
      createdAt: createdAt,
      expiresAt: expiresAt,
      revokedAt: revokedAt,
      lastViewAt: lastViewAt,
      viewCount: viewCount ?? this.viewCount,
      maxViewCount: maxViewCount ?? this.maxViewCount,
      isActive: isActive ?? this.isActive,
      isExpired: isExpired ?? this.isExpired,
      status: status ?? this.status,
      remainingHours: remainingHours ?? this.remainingHours,
      options: options ?? this.options,
    );
  }
}

