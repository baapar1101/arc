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

class TaskLabelModel {
  final int id;
  final String name;
  final String? color;
  final String? description;

  const TaskLabelModel({
    required this.id,
    required this.name,
    this.color,
    this.description,
  });

  factory TaskLabelModel.fromJson(Map<String, dynamic> json) {
    return TaskLabelModel(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? '',
      color: json['color']?.toString(),
      description: json['description']?.toString(),
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
  final int? parentTaskId;
  final int? statusId;
  final TaskStatusModel? status;
  final String title;
  final String? description;
  final String priority;
  final double sortOrder;
  final DateTime? startAt;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final int? estimatedMinutes;
  final List<TaskAssigneeModel> assignees;
  final List<TaskLabelModel> labels;
  final int? createdByUserId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TaskModel({
    required this.id,
    required this.businessId,
    this.projectId,
    this.projectName,
    this.parentTaskId,
    this.statusId,
    this.status,
    required this.title,
    this.description,
    required this.priority,
    this.sortOrder = 0,
    this.startAt,
    this.dueAt,
    this.completedAt,
    this.estimatedMinutes,
    required this.assignees,
    this.labels = const [],
    this.createdByUserId,
    this.createdAt,
    this.updatedAt,
  });

  bool get isCompleted => completedAt != null || status?.category == 'completed';

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    final statusJson = json['status'];
    final assigneeJson = (json['assignees'] as List?) ?? const [];
    final labelJson = (json['labels'] as List?) ?? const [];
    return TaskModel(
      id: (json['id'] as num).toInt(),
      businessId: (json['business_id'] as num).toInt(),
      projectId: (json['project_id'] as num?)?.toInt(),
      projectName: json['project_name']?.toString(),
      parentTaskId: (json['parent_task_id'] as num?)?.toInt(),
      statusId: (json['status_id'] as num?)?.toInt(),
      status: statusJson is Map
          ? TaskStatusModel.fromJson(Map<String, dynamic>.from(statusJson))
          : null,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      priority: json['priority']?.toString() ?? 'normal',
      sortOrder: (json['sort_order'] as num?)?.toDouble() ?? 0,
      startAt: _parseTaskDate(json['start_at_raw'] ?? json['start_at']),
      dueAt: _parseTaskDate(json['due_at_raw'] ?? json['due_at']),
      completedAt:
          _parseTaskDate(json['completed_at_raw'] ?? json['completed_at']),
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt(),
      assignees: assigneeJson
          .whereType<Map>()
          .map((e) => TaskAssigneeModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      labels: labelJson
          .whereType<Map>()
          .map((e) => TaskLabelModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      createdByUserId: (json['created_by_user_id'] as num?)?.toInt(),
      createdAt: _parseTaskDate(json['created_at_raw'] ?? json['created_at']),
      updatedAt: _parseTaskDate(json['updated_at_raw'] ?? json['updated_at']),
    );
  }
}



class TaskBriefModel {
  final int id;
  final int businessId;
  final int? projectId;
  final int? parentTaskId;
  final int? statusId;
  final String? statusName;
  final String title;
  final String priority;
  final DateTime? completedAt;

  const TaskBriefModel({
    required this.id,
    required this.businessId,
    this.projectId,
    this.parentTaskId,
    this.statusId,
    this.statusName,
    required this.title,
    required this.priority,
    this.completedAt,
  });

  bool get isCompleted => completedAt != null;

  factory TaskBriefModel.fromJson(Map<String, dynamic> json) {
    return TaskBriefModel(
      id: (json['id'] as num).toInt(),
      businessId: (json['business_id'] as num).toInt(),
      projectId: (json['project_id'] as num?)?.toInt(),
      parentTaskId: (json['parent_task_id'] as num?)?.toInt(),
      statusId: (json['status_id'] as num?)?.toInt(),
      statusName: json['status_name']?.toString(),
      title: json['title']?.toString() ?? '',
      priority: json['priority']?.toString() ?? 'normal',
      completedAt:
          _parseTaskDate(json['completed_at_raw'] ?? json['completed_at']),
    );
  }
}

class TaskRelationModel {
  final int id;
  final String relationType;
  final String direction;
  final TaskBriefModel task;
  final DateTime? createdAt;

  const TaskRelationModel({
    required this.id,
    required this.relationType,
    required this.direction,
    required this.task,
    this.createdAt,
  });

  factory TaskRelationModel.fromJson(Map<String, dynamic> json) {
    return TaskRelationModel(
      id: (json['id'] as num).toInt(),
      relationType: json['relation_type']?.toString() ?? 'related',
      direction: json['direction']?.toString() ?? 'outgoing',
      task: TaskBriefModel.fromJson(
        Map<String, dynamic>.from(json['task'] as Map),
      ),
      createdAt: _parseTaskDate(
        json['created_at_raw'] ?? json['created_at'],
      ),
    );
  }
}

class TaskStructureModel {
  final TaskBriefModel? parent;
  final List<TaskBriefModel> subtasks;
  final List<TaskRelationModel> relations;

  const TaskStructureModel({
    this.parent,
    required this.subtasks,
    required this.relations,
  });

  factory TaskStructureModel.fromJson(Map<String, dynamic> json) {
    final parentJson = json['parent'];
    return TaskStructureModel(
      parent: parentJson is Map
          ? TaskBriefModel.fromJson(Map<String, dynamic>.from(parentJson))
          : null,
      subtasks: ((json['subtasks'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => TaskBriefModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      relations: ((json['relations'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => TaskRelationModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}



class TaskCommentModel {
  final int id;
  final int taskId;
  final int? authorUserId;
  final String? authorName;
  final String body;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TaskCommentModel({
    required this.id,
    required this.taskId,
    this.authorUserId,
    this.authorName,
    required this.body,
    this.createdAt,
    this.updatedAt,
  });

  factory TaskCommentModel.fromJson(Map<String, dynamic> json) {
    return TaskCommentModel(
      id: (json['id'] as num).toInt(),
      taskId: (json['task_id'] as num).toInt(),
      authorUserId: (json['author_user_id'] as num?)?.toInt(),
      authorName: json['author_name']?.toString(),
      body: json['body']?.toString() ?? '',
      createdAt: _parseTaskDate(
        json['created_at_raw'] ?? json['created_at'],
      ),
      updatedAt: _parseTaskDate(
        json['updated_at_raw'] ?? json['updated_at'],
      ),
    );
  }
}

class TaskActivityModel {
  final int id;
  final int taskId;
  final int? actorUserId;
  final String? actorName;
  final String eventType;
  final Map<String, dynamic> eventData;
  final DateTime? createdAt;

  const TaskActivityModel({
    required this.id,
    required this.taskId,
    this.actorUserId,
    this.actorName,
    required this.eventType,
    required this.eventData,
    this.createdAt,
  });

  factory TaskActivityModel.fromJson(Map<String, dynamic> json) {
    return TaskActivityModel(
      id: (json['id'] as num).toInt(),
      taskId: (json['task_id'] as num).toInt(),
      actorUserId: (json['actor_user_id'] as num?)?.toInt(),
      actorName: json['actor_name']?.toString(),
      eventType: json['event_type']?.toString() ?? '',
      eventData: json['event_data'] is Map
          ? Map<String, dynamic>.from(json['event_data'] as Map)
          : const {},
      createdAt: _parseTaskDate(
        json['created_at_raw'] ?? json['created_at'],
      ),
    );
  }
}



class TaskSavedViewModel {
  final int id;
  final int businessId;
  final int userId;
  final int? projectId;
  final String name;
  final String viewType;
  final Map<String, dynamic> filters;
  final Map<String, dynamic> sort;
  final bool isShared;

  const TaskSavedViewModel({
    required this.id,
    required this.businessId,
    required this.userId,
    this.projectId,
    required this.name,
    required this.viewType,
    required this.filters,
    required this.sort,
    required this.isShared,
  });

  factory TaskSavedViewModel.fromJson(Map<String, dynamic> json) {
    return TaskSavedViewModel(
      id: (json['id'] as num).toInt(),
      businessId: (json['business_id'] as num).toInt(),
      userId: (json['user_id'] as num).toInt(),
      projectId: (json['project_id'] as num?)?.toInt(),
      name: json['name']?.toString() ?? '',
      viewType: json['view_type']?.toString() ?? 'list',
      filters: json['filters'] is Map
          ? Map<String, dynamic>.from(json['filters'] as Map)
          : const {},
      sort: json['sort'] is Map
          ? Map<String, dynamic>.from(json['sort'] as Map)
          : const {},
      isShared: json['is_shared'] == true,
    );
  }
}
