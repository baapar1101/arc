class TaskStatusModel {
  final int id;
  final String key;
  final String name;
  final String category;
  final String? color;
  final bool isDefault;
  final bool isClosed;

  const TaskStatusModel({
    required this.id,
    required this.key,
    required this.name,
    required this.category,
    this.color,
    required this.isDefault,
    required this.isClosed,
  });

  factory TaskStatusModel.fromJson(Map<String, dynamic> json) {
    return TaskStatusModel(
      id: (json['id'] as num).toInt(),
      key: json['key']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? 'unstarted',
      color: json['color']?.toString(),
      isDefault: json['is_default'] == true,
      isClosed: json['is_closed'] == true,
    );
  }
}

class TaskAssigneeModel {
  final int userId;
  final String name;

  const TaskAssigneeModel({
    required this.userId,
    required this.name,
  });

  factory TaskAssigneeModel.fromJson(Map<String, dynamic> json) {
    return TaskAssigneeModel(
      userId: (json['user_id'] as num).toInt(),
      name: json['name']?.toString() ?? 'User ${json['user_id']}',
    );
  }
}

class TaskAssigneeOption {
  final int userId;
  final String name;
  final String? email;
  final String? mobile;
  final String role;

  const TaskAssigneeOption({
    required this.userId,
    required this.name,
    this.email,
    this.mobile,
    required this.role,
  });

  factory TaskAssigneeOption.fromJson(Map<String, dynamic> json) {
    return TaskAssigneeOption(
      userId: (json['user_id'] as num).toInt(),
      name: json['name']?.toString() ?? 'User ${json['user_id']}',
      email: json['email']?.toString(),
      mobile: json['mobile']?.toString(),
      role: json['role']?.toString() ?? 'member',
    );
  }
}

DateTime? _parseTaskDate(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

class TaskModel {
  final int id;
  final int businessId;
  final int? projectId;
  final String? projectName;
  final int? statusId;
  final TaskStatusModel? status;
  final String title;
  final String? description;
  final String priority;
  final DateTime? startAt;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final int? estimatedMinutes;
  final List<TaskAssigneeModel> assignees;
  final int? createdByUserId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TaskModel({
    required this.id,
    required this.businessId,
    this.projectId,
    this.projectName,
    this.statusId,
    this.status,
    required this.title,
    this.description,
    required this.priority,
    this.startAt,
    this.dueAt,
    this.completedAt,
    this.estimatedMinutes,
    required this.assignees,
    this.createdByUserId,
    this.createdAt,
    this.updatedAt,
  });

  bool get isCompleted => completedAt != null || status?.category == 'completed';

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    final statusJson = json['status'];
    final assigneeJson = (json['assignees'] as List?) ?? const [];
    return TaskModel(
      id: (json['id'] as num).toInt(),
      businessId: (json['business_id'] as num).toInt(),
      projectId: (json['project_id'] as num?)?.toInt(),
      projectName: json['project_name']?.toString(),
      statusId: (json['status_id'] as num?)?.toInt(),
      status: statusJson is Map
          ? TaskStatusModel.fromJson(Map<String, dynamic>.from(statusJson))
          : null,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      priority: json['priority']?.toString() ?? 'normal',
      startAt: _parseTaskDate(json['start_at_raw'] ?? json['start_at']),
      dueAt: _parseTaskDate(json['due_at_raw'] ?? json['due_at']),
      completedAt:
          _parseTaskDate(json['completed_at_raw'] ?? json['completed_at']),
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt(),
      assignees: assigneeJson
          .whereType<Map>()
          .map((e) => TaskAssigneeModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      createdByUserId: (json['created_by_user_id'] as num?)?.toInt(),
      createdAt: _parseTaskDate(json['created_at_raw'] ?? json['created_at']),
      updatedAt: _parseTaskDate(json['updated_at_raw'] ?? json['updated_at']),
    );
  }
}
