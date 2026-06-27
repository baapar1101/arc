import 'package:shamsi_date/shamsi_date.dart';

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
        // Parse ISO string and convert UTC to local time
        final parsed = DateTime.parse(dateTime);
        return parsed.isUtc ? parsed.toLocal() : parsed;
      } catch (e) {
        // If parsing fails, return current time
        return DateTime.now();
      }
    } else if (dateTime is Map<String, dynamic>) {
      // Handle formatted date from backend
      // Try to find raw field (could be 'raw' or 'created_at_raw', etc.)
      String? raw;
      for (final key in dateTime.keys) {
        if (key.endsWith('_raw')) {
          raw = dateTime[key] as String?;
          break;
        }
      }
      // If no _raw field found, try 'raw' directly
      raw ??= dateTime['raw'] as String?;
      
      if (raw != null) {
        try {
          final parsed = DateTime.parse(raw);
          return parsed.isUtc ? parsed.toLocal() : parsed;
        } catch (e) {
          // Fall through to try other methods
        }
      }
      
      // Fallback to formatted if raw is not available
      String? formatted;
      for (final key in dateTime.keys) {
        if (key.endsWith('_formatted')) {
          formatted = dateTime[key] as String?;
          break;
        }
      }
      // If no _formatted field found, try 'formatted' directly
      formatted ??= dateTime['formatted'] as String?;
      
      if (formatted != null) {
        try {
          final parsed = DateTime.parse(formatted);
          return parsed.isUtc ? parsed.toLocal() : parsed;
        } catch (e) {
          // Fall through to try other methods
        }
      }
      
      // Try to parse individual date components
      // These might be Jalali (Persian) dates, so we need to convert them
      final year = dateTime['year'] as int?;
      final month = dateTime['month'] as int?;
      final day = dateTime['day'] as int?;
      final hour = dateTime['hour'] as int? ?? 0;
      final minute = dateTime['minute'] as int? ?? 0;
      final second = dateTime['second'] as int? ?? 0;
      
      if (year != null && month != null && day != null) {
        try {
          // Check if this is a Jalali date (year > 1300 typically indicates Jalali)
          // Jalali years are usually between 1300-1500, Gregorian are 1900-2100
          if (year > 1300 && year < 1500) {
            // This is a Jalali date, convert to Gregorian
            final jalali = Jalali(year, month, day);
            final gregorian = jalali.toDateTime();
            // Add time components
            return DateTime(
              gregorian.year,
              gregorian.month,
              gregorian.day,
              hour,
              minute,
              second,
            ).toLocal();
          } else {
            // This is a Gregorian date
            return DateTime.utc(year, month, day, hour, minute, second).toLocal();
          }
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
  final List<SupportAttachment>? attachments;

  SupportMessage({
    required this.id,
    required this.ticketId,
    required this.senderId,
    required this.senderType,
    required this.content,
    required this.isInternal,
    required this.createdAt,
    this.sender,
    this.attachments,
  });

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    // Try to use created_at_formatted (Map with date components) first, 
    // then created_at_raw (might be Jalali string), then created_at
    dynamic createdAtData = json['created_at_formatted'];
    if (createdAtData == null) {
      createdAtData = json['created_at_raw'] ?? json['created_at'];
    }
    return SupportMessage(
      id: json['id'],
      ticketId: json['ticket_id'],
      senderId: json['sender_id'],
      senderType: json['sender_type'],
      content: json['content'],
      isInternal: json['is_internal'],
      createdAt: SupportCategory._parseDateTime(createdAtData),
      sender: json['sender'] != null ? SupportUser.fromJson(json['sender']) : null,
      attachments: json['attachments'] != null
          ? (json['attachments'] as List).map((a) => SupportAttachment.fromJson(a as Map<String, dynamic>)).toList()
          : null,
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
  final DateTime? firstResponseDueAt;
  final DateTime? resolutionDueAt;
  final DateTime? firstRespondedAt;
  final bool slaBreached;
  
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
    this.firstResponseDueAt,
    this.resolutionDueAt,
    this.firstRespondedAt,
    this.slaBreached = false,
    this.user,
    this.assignedOperator,
    this.category,
    this.priority,
    this.status,
    this.messages,
  });

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    // Try to use _formatted fields (Map with date components) first,
    // then _raw fields (might be Jalali string), then regular fields
    dynamic createdAtData = json['created_at_formatted'];
    if (createdAtData == null) {
      createdAtData = json['created_at_raw'] ?? json['created_at'];
    }
    dynamic updatedAtData = json['updated_at_formatted'];
    if (updatedAtData == null) {
      updatedAtData = json['updated_at_raw'] ?? json['updated_at'];
    }
    dynamic closedAtData = json['closed_at_formatted'];
    if (closedAtData == null) {
      closedAtData = json['closed_at_raw'] ?? json['closed_at'];
    }
    DateTime? parseOpt(dynamic v) => v != null ? SupportCategory._parseDateTime(v) : null;
    
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
      closedAt: closedAtData != null ? SupportCategory._parseDateTime(closedAtData) : null,
      createdAt: SupportCategory._parseDateTime(createdAtData),
      updatedAt: SupportCategory._parseDateTime(updatedAtData),
      firstResponseDueAt: parseOpt(json['first_response_due_at_raw'] ?? json['first_response_due_at']),
      resolutionDueAt: parseOpt(json['resolution_due_at_raw'] ?? json['resolution_due_at']),
      firstRespondedAt: parseOpt(json['first_responded_at_raw'] ?? json['first_responded_at']),
      slaBreached: json['sla_breached'] == true,
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
  bool get isClosedFinal => status?.isFinal ?? false;

  String get slaStatus {
    if (slaBreached) return 'breached';
    if (closedAt != null) return 'ok';
    final due = resolutionDueAt ?? (firstRespondedAt == null ? firstResponseDueAt : null);
    if (due != null && DateTime.now().isAfter(due.subtract(const Duration(minutes: 30)))) {
      if (DateTime.now().isAfter(due)) return 'breached';
      return 'warning';
    }
    return 'ok';
  }
}

class SupportAttachment {
  final int id;
  final int ticketId;
  final int? messageId;
  final String fileStorageId;
  final String originalName;
  final String? mimeType;
  final int sizeBytes;
  final int uploadedBy;
  final DateTime createdAt;

  SupportAttachment({
    required this.id,
    required this.ticketId,
    this.messageId,
    required this.fileStorageId,
    required this.originalName,
    this.mimeType,
    required this.sizeBytes,
    required this.uploadedBy,
    required this.createdAt,
  });

  factory SupportAttachment.fromJson(Map<String, dynamic> json) {
    return SupportAttachment(
      id: json['id'],
      ticketId: json['ticket_id'],
      messageId: json['message_id'],
      fileStorageId: json['file_storage_id'],
      originalName: json['original_name'],
      mimeType: json['mime_type'],
      sizeBytes: json['size_bytes'] ?? 0,
      uploadedBy: json['uploaded_by'],
      createdAt: SupportCategory._parseDateTime(json['created_at']),
    );
  }

  bool get isImage => (mimeType ?? '').startsWith('image/');
}

class SupportTicketEvent {
  final int id;
  final int ticketId;
  final int? actorId;
  final String eventType;
  final Map<String, dynamic>? oldValue;
  final Map<String, dynamic>? newValue;
  final DateTime createdAt;

  SupportTicketEvent({
    required this.id,
    required this.ticketId,
    this.actorId,
    required this.eventType,
    this.oldValue,
    this.newValue,
    required this.createdAt,
  });

  factory SupportTicketEvent.fromJson(Map<String, dynamic> json) {
    return SupportTicketEvent(
      id: json['id'],
      ticketId: json['ticket_id'],
      actorId: json['actor_id'],
      eventType: json['event_type'],
      oldValue: json['old_value'] as Map<String, dynamic>?,
      newValue: json['new_value'] as Map<String, dynamic>?,
      createdAt: SupportCategory._parseDateTime(json['created_at']),
    );
  }
}

class ServerResponseTemplate {
  final int id;
  final String name;
  final String content;

  ServerResponseTemplate({required this.id, required this.name, required this.content});

  factory ServerResponseTemplate.fromJson(Map<String, dynamic> json) {
    return ServerResponseTemplate(
      id: json['id'],
      name: json['name'],
      content: json['content'],
    );
  }
}

class SupportOperatorInfo {
  final int id;
  final String? firstName;
  final String? lastName;
  final String? email;

  SupportOperatorInfo({
    required this.id,
    this.firstName,
    this.lastName,
    this.email,
  });

  factory SupportOperatorInfo.fromJson(Map<String, dynamic> json) {
    return SupportOperatorInfo(
      id: json['id'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      email: json['email'],
    );
  }

  String get displayName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    }
    if (firstName != null) return firstName!;
    if (lastName != null) return lastName!;
    if (email != null) return email!;
    return 'اپراتور $id';
  }
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
  final List<int> attachmentIds;

  CreateMessageRequest({
    required this.content,
    this.isInternal = false,
    this.attachmentIds = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'is_internal': isInternal,
      'attachment_ids': attachmentIds,
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

class UpdatePriorityRequest {
  final int priorityId;

  UpdatePriorityRequest({required this.priorityId});

  Map<String, dynamic> toJson() => {'priority_id': priorityId};
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
