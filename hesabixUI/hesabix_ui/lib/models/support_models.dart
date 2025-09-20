class SupportCategory {
  final int id;
  final String name;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  SupportCategory({
    required this.id,
    required this.name,
    this.description,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SupportCategory.fromJson(Map<String, dynamic> json) {
    return SupportCategory(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      isActive: json['is_active'],
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  static DateTime _parseDateTime(dynamic dateTime) {
    if (dateTime is String) {
      try {
        return DateTime.parse(dateTime);
      } catch (e) {
        // If parsing fails, return current time
        return DateTime.now();
      }
    } else if (dateTime is Map<String, dynamic>) {
      // Handle formatted date from backend
      final formatted = dateTime['formatted'] as String?;
      if (formatted != null) {
        try {
          return DateTime.parse(formatted);
        } catch (e) {
          return DateTime.now();
        }
      }
    }
    return DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class SupportPriority {
  final int id;
  final String name;
  final String? description;
  final String? color;
  final int order;
  final DateTime createdAt;
  final DateTime updatedAt;

  SupportPriority({
    required this.id,
    required this.name,
    this.description,
    this.color,
    required this.order,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SupportPriority.fromJson(Map<String, dynamic> json) {
    return SupportPriority(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      color: json['color'],
      order: json['order'],
      createdAt: SupportCategory._parseDateTime(json['created_at']),
      updatedAt: SupportCategory._parseDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'color': color,
      'order': order,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class SupportStatus {
  final int id;
  final String name;
  final String? description;
  final String? color;
  final bool isFinal;
  final DateTime createdAt;
  final DateTime updatedAt;

  SupportStatus({
    required this.id,
    required this.name,
    this.description,
    this.color,
    required this.isFinal,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SupportStatus.fromJson(Map<String, dynamic> json) {
    return SupportStatus(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      color: json['color'],
      isFinal: json['is_final'],
      createdAt: SupportCategory._parseDateTime(json['created_at']),
      updatedAt: SupportCategory._parseDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'color': color,
      'is_final': isFinal,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class SupportUser {
  final int id;
  final String? firstName;
  final String? lastName;
  final String? email;

  SupportUser({
    required this.id,
    this.firstName,
    this.lastName,
    this.email,
  });

  factory SupportUser.fromJson(Map<String, dynamic> json) {
    return SupportUser(
      id: json['id'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      email: json['email'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
    };
  }

  String get displayName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    } else if (firstName != null) {
      return firstName!;
    } else if (lastName != null) {
      return lastName!;
    } else if (email != null) {
      return email!;
    }
    return 'کاربر $id';
  }
}

class SupportMessage {
  final int id;
  final int ticketId;
  final int senderId;
  final String senderType; // 'user', 'operator', 'system'
  final String content;
  final bool isInternal;
  final DateTime createdAt;
  final SupportUser? sender;

  SupportMessage({
    required this.id,
    required this.ticketId,
    required this.senderId,
    required this.senderType,
    required this.content,
    required this.isInternal,
    required this.createdAt,
    this.sender,
  });

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    return SupportMessage(
      id: json['id'],
      ticketId: json['ticket_id'],
      senderId: json['sender_id'],
      senderType: json['sender_type'],
      content: json['content'],
      isInternal: json['is_internal'],
      createdAt: SupportCategory._parseDateTime(json['created_at']),
      sender: json['sender'] != null ? SupportUser.fromJson(json['sender']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ticket_id': ticketId,
      'sender_id': senderId,
      'sender_type': senderType,
      'content': content,
      'is_internal': isInternal,
      'created_at': createdAt.toIso8601String(),
      'sender': sender?.toJson(),
    };
  }

  bool get isFromUser => senderType == 'user';
  bool get isFromOperator => senderType == 'operator';
  bool get isFromSystem => senderType == 'system';
}

class SupportTicket {
  final int id;
  final String title;
  final String description;
  final int userId;
  final int categoryId;
  final int priorityId;
  final int statusId;
  final int? assignedOperatorId;
  final bool isInternal;
  final DateTime? closedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Related objects
  final SupportUser? user;
  final SupportUser? assignedOperator;
  final SupportCategory? category;
  final SupportPriority? priority;
  final SupportStatus? status;
  final List<SupportMessage>? messages;

  SupportTicket({
    required this.id,
    required this.title,
    required this.description,
    required this.userId,
    required this.categoryId,
    required this.priorityId,
    required this.statusId,
    this.assignedOperatorId,
    required this.isInternal,
    this.closedAt,
    required this.createdAt,
    required this.updatedAt,
    this.user,
    this.assignedOperator,
    this.category,
    this.priority,
    this.status,
    this.messages,
  });

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    return SupportTicket(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      userId: json['user_id'],
      categoryId: json['category_id'],
      priorityId: json['priority_id'],
      statusId: json['status_id'],
      assignedOperatorId: json['assigned_operator_id'],
      isInternal: json['is_internal'],
      closedAt: json['closed_at'] != null ? SupportCategory._parseDateTime(json['closed_at']) : null,
      createdAt: SupportCategory._parseDateTime(json['created_at']),
      updatedAt: SupportCategory._parseDateTime(json['updated_at']),
      user: json['user'] != null ? SupportUser.fromJson(json['user']) : null,
      assignedOperator: json['assigned_operator'] != null ? SupportUser.fromJson(json['assigned_operator']) : null,
      category: json['category'] != null ? SupportCategory.fromJson(json['category']) : null,
      priority: json['priority'] != null ? SupportPriority.fromJson(json['priority']) : null,
      status: json['status'] != null ? SupportStatus.fromJson(json['status']) : null,
      messages: json['messages'] != null 
          ? (json['messages'] as List).map((m) => SupportMessage.fromJson(m)).toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'user_id': userId,
      'category_id': categoryId,
      'priority_id': priorityId,
      'status_id': statusId,
      'assigned_operator_id': assignedOperatorId,
      'is_internal': isInternal,
      'closed_at': closedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'user': user?.toJson(),
      'assigned_operator': assignedOperator?.toJson(),
      'category': category?.toJson(),
      'priority': priority?.toJson(),
      'status': status?.toJson(),
      'messages': messages?.map((m) => m.toJson()).toList(),
    };
  }

  bool get isOpen => statusId == 1; // وضعیت "باز"
  bool get isInProgress => statusId == 2; // وضعیت "در حال پیگیری"
  bool get isWaitingForUser => statusId == 3; // وضعیت "در انتظار کاربر"
  bool get isClosed => statusId == 4; // وضعیت "بسته"
  bool get isResolved => statusId == 5; // وضعیت "حل شده"
}

// Request models
class CreateTicketRequest {
  final String title;
  final String description;
  final int categoryId;
  final int priorityId;

  CreateTicketRequest({
    required this.title,
    required this.description,
    required this.categoryId,
    required this.priorityId,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'category_id': categoryId,
      'priority_id': priorityId,
    };
  }
}

class CreateMessageRequest {
  final String content;
  final bool isInternal;

  CreateMessageRequest({
    required this.content,
    this.isInternal = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'is_internal': isInternal,
    };
  }
}

class UpdateStatusRequest {
  final int statusId;
  final int? assignedOperatorId;

  UpdateStatusRequest({
    required this.statusId,
    this.assignedOperatorId,
  });

  Map<String, dynamic> toJson() {
    return {
      'status_id': statusId,
      'assigned_operator_id': assignedOperatorId,
    };
  }
}

class AssignTicketRequest {
  final int operatorId;

  AssignTicketRequest({
    required this.operatorId,
  });

  Map<String, dynamic> toJson() {
    return {
      'operator_id': operatorId,
    };
  }
}

// Pagination response
class PaginatedResponse<T> {
  final List<T> items;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  PaginatedResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    return PaginatedResponse<T>(
      items: (json['items'] as List).map((item) => fromJsonT(item)).toList(),
      total: json['total'],
      page: json['page'],
      limit: json['limit'],
      totalPages: json['total_pages'],
    );
  }
}
