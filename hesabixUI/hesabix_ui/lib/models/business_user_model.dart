import 'package:shamsi_date/shamsi_date.dart';

class BusinessUser {
  final int id;
  final int businessId;
  final int userId;
  final String userName;
  final String userEmail;
  final String? userPhone;
  final String role;
  final String status;
  final DateTime addedAt;
  final DateTime? lastActive;
  final Map<String, dynamic> permissions;
  final DateTime? membershipExpiresAt;
  final bool membershipUnlimited;
  final bool membershipActive;

  const BusinessUser({
    required this.id,
    required this.businessId,
    required this.userId,
    required this.userName,
    required this.userEmail,
    this.userPhone,
    required this.role,
    required this.status,
    required this.addedAt,
    this.lastActive,
    required this.permissions,
    this.membershipExpiresAt,
    this.membershipUnlimited = true,
    this.membershipActive = true,
  });

  factory BusinessUser.fromJson(Map<String, dynamic> json) {
    final expiresRaw = json['membership_expires_at'];
    final expiresAt = _parseOptionalDateTime(expiresRaw);
    final unlimited = json['membership_unlimited'] as bool? ?? (expiresAt == null);
    final active = json['membership_active'] as bool? ?? true;
    return BusinessUser(
      id: json['id'] as int,
      businessId: json['business_id'] as int,
      userId: json['user_id'] as int,
      userName: json['user_name'] as String,
      userEmail: json['user_email'] as String,
      userPhone: json['user_phone'] as String?,
      role: json['role'] as String,
      status: json['status'] as String,
      addedAt: _parseDateTime(json['added_at']),
      lastActive: json['last_active'] != null 
          ? _parseDateTime(json['last_active'])
          : null,
      permissions: (json['permissions'] as Map<String, dynamic>?) ?? {},
      membershipExpiresAt: expiresAt,
      membershipUnlimited: unlimited,
      membershipActive: active,
    );
  }

  static DateTime _parseDateTime(dynamic dateValue) {
    if (dateValue == null) return DateTime.now();
    
    if (dateValue is String) {
      // Check if it's a Jalali date format (YYYY/MM/DD HH:MM:SS)
      if (dateValue.contains('/') && !dateValue.contains('-')) {
        try {
          // Parse Jalali date format: YYYY/MM/DD HH:MM:SS
          final parts = dateValue.split(' ');
          if (parts.isNotEmpty) {
            final dateParts = parts[0].split('/');
            if (dateParts.length == 3) {
              final year = int.parse(dateParts[0]);
              final month = int.parse(dateParts[1]);
              final day = int.parse(dateParts[2]);
              final jalali = Jalali(year, month, day);
              return jalali.toDateTime();
            }
          }
        } catch (e) {
          // Fall back to standard parsing
        }
      }
      return DateTime.parse(dateValue);
    } else if (dateValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(dateValue);
    }
    
    return DateTime.now();
  }

  static DateTime? _parseOptionalDateTime(dynamic dateValue) {
    if (dateValue == null) return null;
    if (dateValue is String) {
      if (dateValue.isEmpty) return null;
      try {
        if (dateValue.contains('/') && !dateValue.contains('-')) {
          final parts = dateValue.split(' ');
          if (parts.isNotEmpty) {
            final dateParts = parts[0].split('/');
            if (dateParts.length == 3) {
              final year = int.parse(dateParts[0]);
              final month = int.parse(dateParts[1]);
              final day = int.parse(dateParts[2]);
              final jalali = Jalali(year, month, day);
              return jalali.toDateTime();
            }
          }
        }
        return DateTime.parse(dateValue);
      } catch (_) {
        return null;
      }
    } else if (dateValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(dateValue);
    }
    return null;
  }


  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'user_id': userId,
      'user_name': userName,
      'user_email': userEmail,
      'user_phone': userPhone,
      'role': role,
      'status': status,
      'added_at': addedAt.toIso8601String(),
      'last_active': lastActive?.toIso8601String(),
      'permissions': permissions,
      'membership_expires_at': membershipExpiresAt?.toUtc().toIso8601String(),
      'membership_unlimited': membershipUnlimited,
      'membership_active': membershipActive,
    };
  }

  BusinessUser copyWith({
    int? id,
    int? businessId,
    int? userId,
    String? userName,
    String? userEmail,
    String? userPhone,
    String? role,
    String? status,
    DateTime? addedAt,
    DateTime? lastActive,
    Map<String, dynamic>? permissions,
    DateTime? membershipExpiresAt,
    bool? membershipUnlimited,
    bool? membershipActive,
  }) {
    return BusinessUser(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      userPhone: userPhone ?? this.userPhone,
      role: role ?? this.role,
      status: status ?? this.status,
      addedAt: addedAt ?? this.addedAt,
      lastActive: lastActive ?? this.lastActive,
      permissions: permissions ?? this.permissions,
      membershipExpiresAt: membershipExpiresAt ?? this.membershipExpiresAt,
      membershipUnlimited: membershipUnlimited ?? this.membershipUnlimited,
      membershipActive: membershipActive ?? this.membershipActive,
    );
  }

  // Helper methods for permissions
  bool hasPermission(String section, String action) {
    if (permissions.isEmpty) return false;
    if (!permissions.containsKey(section)) return false;
    
    final sectionPerms = permissions[section] as Map<String, dynamic>?;
    if (sectionPerms == null) return action == 'read';
    
    return sectionPerms[action] == true;
  }

  bool canRead(String section) {
    return hasPermission(section, 'read') || permissions.containsKey(section);
  }

  bool canWrite(String section) {
    return hasPermission(section, 'write');
  }

  bool canDelete(String section) {
    return hasPermission(section, 'delete');
  }

  bool canApprove(String section) {
    return hasPermission(section, 'approve');
  }

  bool canExport(String section) {
    return hasPermission(section, 'export');
  }

  bool canManageUsers() {
    return hasPermission('settings', 'manage_users');
  }

  // Get all available sections
  List<String> get availableSections {
    return permissions.keys.toList();
  }

  // Get all actions for a section
  List<String> getActionsForSection(String section) {
    final sectionPerms = permissions[section] as Map<String, dynamic>?;
    if (sectionPerms == null) return ['read'];
    return sectionPerms.keys.where((key) => sectionPerms[key] == true).toList();
  }
}

// Request/Response models
class AddUserRequest {
  final int businessId;
  final String emailOrPhone;
  final DateTime? membershipExpiresAt;

  const AddUserRequest({
    required this.businessId,
    required this.emailOrPhone,
    this.membershipExpiresAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'email_or_phone': emailOrPhone,
      if (membershipExpiresAt != null)
        'membership_expires_at': membershipExpiresAt!.toUtc().toIso8601String(),
    };
  }
}

class AddUserResponse {
  final bool success;
  final String message;
  final BusinessUser? user;

  const AddUserResponse({
    required this.success,
    required this.message,
    this.user,
  });

  factory AddUserResponse.fromJson(Map<String, dynamic> json) {
    return AddUserResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      user: json['user'] != null 
          ? BusinessUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }
}

class UpdatePermissionsRequest {
  final int businessId;
  final int userId;
  final Map<String, dynamic> permissions;
  final bool applyMembershipExpiry;
  final DateTime? membershipExpiresAt;

  const UpdatePermissionsRequest({
    required this.businessId,
    required this.userId,
    required this.permissions,
    this.applyMembershipExpiry = false,
    this.membershipExpiresAt,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'permissions': permissions};
    if (applyMembershipExpiry) {
      m['apply_membership_expiry'] = true;
      m['membership_expires_at'] = membershipExpiresAt?.toUtc().toIso8601String();
    }
    return m;
  }
}

class UpdatePermissionsResponse {
  final bool success;
  final String message;

  const UpdatePermissionsResponse({
    required this.success,
    required this.message,
  });

  factory UpdatePermissionsResponse.fromJson(Map<String, dynamic> json) {
    return UpdatePermissionsResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }
}

class RemoveUserRequest {
  final int businessId;
  final int userId;

  const RemoveUserRequest({
    required this.businessId,
    required this.userId,
  });

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'user_id': userId,
    };
  }
}

class RemoveUserResponse {
  final bool success;
  final String message;

  const RemoveUserResponse({
    required this.success,
    required this.message,
  });

  factory RemoveUserResponse.fromJson(Map<String, dynamic> json) {
    return RemoveUserResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }
}

class LeaveBusinessRequest {
  final int businessId;

  const LeaveBusinessRequest({
    required this.businessId,
  });

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
    };
  }
}

class LeaveBusinessResponse {
  final bool success;
  final String message;

  const LeaveBusinessResponse({
    required this.success,
    required this.message,
  });

  factory LeaveBusinessResponse.fromJson(Map<String, dynamic> json) {
    return LeaveBusinessResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }
}

class BusinessUsersResponse {
  final bool success;
  final String message;
  final List<BusinessUser> users;
  final int totalCount;

  const BusinessUsersResponse({
    required this.success,
    required this.message,
    required this.users,
    required this.totalCount,
  });

  factory BusinessUsersResponse.fromJson(Map<String, dynamic> json) {
    return BusinessUsersResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      users: (json['users'] as List<dynamic>?)
          ?.map((userJson) => BusinessUser.fromJson(userJson as Map<String, dynamic>))
          .toList() ?? [],
      totalCount: json['total_count'] as int? ?? 0,
    );
  }
}