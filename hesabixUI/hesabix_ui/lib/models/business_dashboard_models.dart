class BusinessInfo {
  final int id;
  final String name;
  final String businessType;
  final String businessField;
  final int ownerId;
  final String? address;
  final String? phone;
  final String? mobile;
  final String createdAt;
  final int memberCount;

  BusinessInfo({
    required this.id,
    required this.name,
    required this.businessType,
    required this.businessField,
    required this.ownerId,
    this.address,
    this.phone,
    this.mobile,
    required this.createdAt,
    required this.memberCount,
  });

  factory BusinessInfo.fromJson(Map<String, dynamic> json) {
    // Handle both string and object formats for created_at
    String createdAt;
    if (json['created_at'] is String) {
      createdAt = json['created_at'];
    } else if (json['created_at'] is Map<String, dynamic>) {
      createdAt = json['created_at']['formatted'] ?? json['created_at']['date_only'] ?? '';
    } else {
      createdAt = '';
    }

    return BusinessInfo(
      id: json['id'],
      name: json['name'],
      businessType: json['business_type'],
      businessField: json['business_field'],
      ownerId: json['owner_id'],
      address: json['address'],
      phone: json['phone'],
      mobile: json['mobile'],
      createdAt: createdAt,
      memberCount: json['member_count'],
    );
  }
}

class BusinessStatistics {
  final double totalSales;
  final double totalPurchases;
  final int activeMembers;
  final int recentTransactions;

  BusinessStatistics({
    required this.totalSales,
    required this.totalPurchases,
    required this.activeMembers,
    required this.recentTransactions,
  });

  factory BusinessStatistics.fromJson(Map<String, dynamic> json) {
    return BusinessStatistics(
      totalSales: (json['total_sales'] ?? 0).toDouble(),
      totalPurchases: (json['total_purchases'] ?? 0).toDouble(),
      activeMembers: json['active_members'] ?? 0,
      recentTransactions: json['recent_transactions'] ?? 0,
    );
  }
}

class Activity {
  final int id;
  final String title;
  final String description;
  final String icon;
  final String timeAgo;

  Activity({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.timeAgo,
  });

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      icon: json['icon'],
      timeAgo: json['time_ago'],
    );
  }
}

class BusinessDashboardResponse {
  final BusinessInfo businessInfo;
  final BusinessStatistics statistics;
  final List<Activity> recentActivities;

  BusinessDashboardResponse({
    required this.businessInfo,
    required this.statistics,
    required this.recentActivities,
  });

  factory BusinessDashboardResponse.fromJson(Map<String, dynamic> json) {
    return BusinessDashboardResponse(
      businessInfo: BusinessInfo.fromJson(json['business_info']),
      statistics: BusinessStatistics.fromJson(json['statistics']),
      recentActivities: (json['recent_activities'] as List<dynamic>)
          .map((activity) => Activity.fromJson(activity))
          .toList(),
    );
  }
}

class BusinessMember {
  final int id;
  final int userId;
  final String firstName;
  final String lastName;
  final String email;
  final String? mobile;
  final String role;
  final Map<String, dynamic> permissions;
  final String joinedAt;

  BusinessMember({
    required this.id,
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.mobile,
    required this.role,
    required this.permissions,
    required this.joinedAt,
  });

  factory BusinessMember.fromJson(Map<String, dynamic> json) {
    // Handle both string and object formats for joined_at
    String joinedAt;
    if (json['joined_at'] is String) {
      joinedAt = json['joined_at'];
    } else if (json['joined_at'] is Map<String, dynamic>) {
      joinedAt = json['joined_at']['formatted'] ?? json['joined_at']['date_only'] ?? '';
    } else {
      joinedAt = '';
    }

    return BusinessMember(
      id: json['id'],
      userId: json['user_id'],
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      email: json['email'] ?? '',
      mobile: json['mobile'],
      role: json['role'] ?? 'عضو',
      permissions: Map<String, dynamic>.from(json['permissions'] ?? {}),
      joinedAt: joinedAt,
    );
  }
}

class BusinessMembersResponse {
  final List<BusinessMember> items;
  final Map<String, dynamic> pagination;

  BusinessMembersResponse({
    required this.items,
    required this.pagination,
  });

  factory BusinessMembersResponse.fromJson(Map<String, dynamic> json) {
    return BusinessMembersResponse(
      items: (json['items'] as List<dynamic>)
          .map((member) => BusinessMember.fromJson(member))
          .toList(),
      pagination: json['pagination'],
    );
  }
}

class CurrencyLite {
  final int id;
  final String code;
  final String title;
  final String symbol;

  CurrencyLite({
    required this.id,
    required this.code,
    required this.title,
    required this.symbol,
  });

  factory CurrencyLite.fromJson(Map<String, dynamic> json) {
    return CurrencyLite(
      id: json['id'] as int,
      code: json['code'] as String? ?? '',
      title: json['title'] as String? ?? '',
      symbol: json['symbol'] as String? ?? '',
    );
  }
}

class BusinessWithPermission {
  final int id;
  final String name;
  final String businessType;
  final String businessField;
  final int ownerId;
  final String? address;
  final String? phone;
  final String? mobile;
  final String createdAt;
  final bool isOwner;
  final String role;
  final Map<String, dynamic> permissions;
  final CurrencyLite? defaultCurrency;
  final List<CurrencyLite> currencies;

  BusinessWithPermission({
    required this.id,
    required this.name,
    required this.businessType,
    required this.businessField,
    required this.ownerId,
    this.address,
    this.phone,
    this.mobile,
    required this.createdAt,
    required this.isOwner,
    required this.role,
    required this.permissions,
    this.defaultCurrency,
    this.currencies = const <CurrencyLite>[],
  });

  factory BusinessWithPermission.fromJson(Map<String, dynamic> json) {
    // Handle both string and object formats for created_at
    String createdAt;
    if (json['created_at'] is String) {
      createdAt = json['created_at'];
    } else if (json['created_at'] is Map<String, dynamic>) {
      createdAt = json['created_at']['formatted'] ?? json['created_at']['date_only'] ?? '';
    } else {
      createdAt = '';
    }

    return BusinessWithPermission(
      id: json['id'],
      name: json['name'],
      businessType: json['business_type'],
      businessField: json['business_field'],
      ownerId: json['owner_id'],
      address: json['address'],
      phone: json['phone'],
      mobile: json['mobile'],
      createdAt: createdAt,
      isOwner: json['is_owner'] ?? false,
      role: json['role'] ?? 'عضو',
      permissions: Map<String, dynamic>.from(json['permissions'] ?? {}),
      defaultCurrency: json['default_currency'] != null
          ? CurrencyLite.fromJson(Map<String, dynamic>.from(json['default_currency']))
          : null,
      currencies: (json['currencies'] as List<dynamic>? ?? const [])
          .map((c) => CurrencyLite.fromJson(Map<String, dynamic>.from(c)))
          .toList(),
    );
  }
}

// ===== Dashboard V2 (Responsive Widgets) =====

class DashboardWidgetDefinition {
  final String key;
  final String title;
  final String icon;
  final int version;
  final List<String> permissionsRequired;
  final Map<String, Map<String, int>> defaults; // breakpoint -> { colSpan,rowSpan }

  DashboardWidgetDefinition({
    required this.key,
    required this.title,
    required this.icon,
    required this.version,
    required this.permissionsRequired,
    required this.defaults,
  });

  factory DashboardWidgetDefinition.fromJson(Map<String, dynamic> json) {
    final defaultsRaw = json['defaults'] as Map<String, dynamic>? ?? const {};
    final defaults = <String, Map<String, int>>{};
    defaultsRaw.forEach((bp, v) {
      final m = Map<String, dynamic>.from(v as Map);
      defaults[bp] = {
        'colSpan': (m['colSpan'] ?? 1) is int ? m['colSpan'] as int : int.tryParse('${m['colSpan']}') ?? 1,
        'rowSpan': (m['rowSpan'] ?? 1) is int ? m['rowSpan'] as int : int.tryParse('${m['rowSpan']}') ?? 1,
      };
    });
    return DashboardWidgetDefinition(
      key: json['key'] as String,
      title: json['title'] as String? ?? json['key'] as String,
      icon: json['icon'] as String? ?? 'widgets',
      version: (json['version'] ?? 1) as int,
      permissionsRequired: (json['permissions_required'] as List?)?.map((e) => '$e').toList() ?? const <String>[],
      defaults: defaults,
    );
  }
}

class DashboardLayoutItem {
  final String key;
  final int order;
  final int colSpan;
  final int rowSpan;
  final bool hidden;

  DashboardLayoutItem({
    required this.key,
    required this.order,
    required this.colSpan,
    required this.rowSpan,
    required this.hidden,
  });

  factory DashboardLayoutItem.fromJson(Map<String, dynamic> json) {
    return DashboardLayoutItem(
      key: json['key'] as String,
      order: (json['order'] ?? 1) as int,
      colSpan: (json['colSpan'] ?? 1) as int,
      rowSpan: (json['rowSpan'] ?? 1) as int,
      hidden: (json['hidden'] ?? false) as bool,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'order': order,
        'colSpan': colSpan,
        'rowSpan': rowSpan,
        'hidden': hidden,
      };

  DashboardLayoutItem copyWith({
    String? key,
    int? order,
    int? colSpan,
    int? rowSpan,
    bool? hidden,
  }) {
    return DashboardLayoutItem(
      key: key ?? this.key,
      order: order ?? this.order,
      colSpan: colSpan ?? this.colSpan,
      rowSpan: rowSpan ?? this.rowSpan,
      hidden: hidden ?? this.hidden,
    );
  }
}

class DashboardLayoutProfile {
  final String breakpoint;
  final int columns;
  final List<DashboardLayoutItem> items;
  final int version;
  final String updatedAt;

  DashboardLayoutProfile({
    required this.breakpoint,
    required this.columns,
    required this.items,
    required this.version,
    required this.updatedAt,
  });

  factory DashboardLayoutProfile.fromJson(Map<String, dynamic> json) {
    return DashboardLayoutProfile(
      breakpoint: json['breakpoint'] as String? ?? 'md',
      columns: (json['columns'] ?? 8) as int,
      items: (json['items'] as List? ?? const <dynamic>[])
          .map((e) => DashboardLayoutItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      version: (json['version'] ?? 2) as int,
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }
}

class DashboardDefinitionsResponse {
  final Map<String, int> columns;
  final List<DashboardWidgetDefinition> items;

  DashboardDefinitionsResponse({
    required this.columns,
    required this.items,
  });

  factory DashboardDefinitionsResponse.fromJson(Map<String, dynamic> json) {
    final colsRaw = Map<String, dynamic>.from(json['columns'] as Map? ?? const {});
    final cols = <String, int>{};
    colsRaw.forEach((k, v) {
      cols[k] = (v is int) ? v : int.tryParse('$v') ?? 0;
    });
    return DashboardDefinitionsResponse(
      columns: cols,
      items: (json['items'] as List? ?? const <dynamic>[])
          .map((e) => DashboardWidgetDefinition.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
