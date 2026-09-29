import 'package:hesabix_ui/models/project_model.dart';
import 'package:hesabix_ui/models/task_model.dart';

Map<String, dynamic> _statusJson(TaskStatusModel? status) {
  if (status == null) return const <String, dynamic>{};
  return <String, dynamic>{
    'id': status.id,
    'key': status.key,
    'name': status.name,
    'category': status.category,
    'color': status.color,
    'is_default': status.isDefault,
    'is_closed': status.isClosed,
  };
}

Map<String, dynamic> _taskJson(TaskModel task) => <String, dynamic>{
      'id': task.id,
      'business_id': task.businessId,
      'project_id': task.projectId,
      'project_name': task.projectName,
      'parent_task_id': task.parentTaskId,
      'status_id': task.statusId,
      if (task.status != null) 'status': _statusJson(task.status),
      'milestone_id': task.milestoneId,
      'milestone_name': task.milestoneName,
      'title': task.title,
      'description': task.description,
      'priority': task.priority,
      'sort_order': task.sortOrder,
      'start_at_raw': task.startAt?.toIso8601String(),
      'due_at_raw': task.dueAt?.toIso8601String(),
      'completed_at_raw': task.completedAt?.toIso8601String(),
      'estimated_minutes': task.estimatedMinutes,
      'recurrence_rule': task.recurrenceRule,
      'recurrence_timezone': task.recurrenceTimezone,
      'recurrence_end_at_raw': task.recurrenceEndAt?.toIso8601String(),
      'assignees': task.assignees
          .map(
            (item) => <String, dynamic>{
              'user_id': item.userId,
              'name': item.name,
            },
          )
          .toList(),
      'labels': task.labels
          .map(
            (item) => <String, dynamic>{
              'id': item.id,
              'name': item.name,
              'color': item.color,
              'description': item.description,
            },
          )
          .toList(),
      'created_by_user_id': task.createdByUserId,
      'created_at_raw': task.createdAt?.toIso8601String(),
      'updated_at_raw': task.updatedAt?.toIso8601String(),
    };

TaskStatusModel? _statusById(
  List<TaskStatusModel> statuses,
  int? id,
) {
  if (id == null) return null;
  for (final status in statuses) {
    if (status.id == id) return status;
  }
  return null;
}

TaskStatusModel? _defaultStatus(List<TaskStatusModel> statuses) {
  for (final status in statuses) {
    if (status.isDefault) return status;
  }
  for (final status in statuses) {
    if (status.key == 'todo') return status;
  }
  for (final status in statuses) {
    if (status.category == 'unstarted') return status;
  }
  return statuses.isEmpty ? null : statuses.first;
}

TaskStatusModel? _completedStatus(List<TaskStatusModel> statuses) {
  for (final status in statuses) {
    if (status.category == 'completed') return status;
  }
  return null;
}

DateTime? _patchDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final raw = value.toString().trim();
  return raw.isEmpty ? null : DateTime.tryParse(raw);
}

TaskModel applyTaskOptimisticPatch(
  TaskModel source,
  Map<String, dynamic> data, {
  required List<TaskStatusModel> statuses,
  required List<ProjectModel> projects,
  required List<TaskAssigneeOption> assignees,
  required List<TaskLabelModel> labels,
}) {
  final json = _taskJson(source);

  if (data.containsKey('title')) {
    json['title'] = data['title']?.toString() ?? source.title;
  }
  if (data.containsKey('description')) {
    json['description'] = data['description'];
  }
  if (data.containsKey('priority')) {
    json['priority'] = data['priority']?.toString() ?? 'normal';
  }
  if (data.containsKey('project_id')) {
    final raw = data['project_id'];
    final projectId = raw is num ? raw.toInt() : int.tryParse('$raw');
    json['project_id'] = projectId;
    String? projectName;
    if (projectId != null) {
      for (final project in projects) {
        if (project.id == projectId) {
          projectName = project.name;
          break;
        }
      }
    }
    json['project_name'] = projectName;
  }
  if (data.containsKey('parent_task_id')) {
    final raw = data['parent_task_id'];
    json['parent_task_id'] =
        raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
  }
  if (data.containsKey('milestone_id')) {
    final raw = data['milestone_id'];
    json['milestone_id'] =
        raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
    json['milestone_name'] = null;
  }
  if (data.containsKey('status_id')) {
    final raw = data['status_id'];
    final requestedId = raw is num ? raw.toInt() : int.tryParse('$raw');
    final status = _statusById(statuses, requestedId) ??
        (requestedId == null ? _defaultStatus(statuses) : null);
    if (status != null) {
      json['status_id'] = status.id;
      json['status'] = _statusJson(status);
      json['completed_at_raw'] = status.category == 'completed'
          ? source.completedAt?.toIso8601String() ??
              DateTime.now().toUtc().toIso8601String()
          : null;
    }
  }
  if (data.containsKey('start_at')) {
    json['start_at_raw'] = _patchDate(data['start_at'])?.toIso8601String();
  }
  if (data.containsKey('due_at')) {
    json['due_at_raw'] = _patchDate(data['due_at'])?.toIso8601String();
  }
  if (data.containsKey('estimated_minutes')) {
    final raw = data['estimated_minutes'];
    json['estimated_minutes'] =
        raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
  }
  if (data.containsKey('recurrence_rule')) {
    json['recurrence_rule'] = data['recurrence_rule'];
  }
  if (data.containsKey('recurrence_timezone')) {
    json['recurrence_timezone'] = data['recurrence_timezone'];
  }
  if (data.containsKey('recurrence_end_at')) {
    json['recurrence_end_at_raw'] =
        _patchDate(data['recurrence_end_at'])?.toIso8601String();
  }
  if (data.containsKey('assignee_user_ids')) {
    final ids = ((data['assignee_user_ids'] as List?) ?? const [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toSet();
    json['assignees'] = assignees
        .where((item) => ids.contains(item.userId))
        .map(
          (item) => <String, dynamic>{
            'user_id': item.userId,
            'name': item.name,
          },
        )
        .toList();
  }
  if (data.containsKey('label_ids')) {
    final ids = ((data['label_ids'] as List?) ?? const [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toSet();
    json['labels'] = labels
        .where((item) => ids.contains(item.id))
        .map(
          (item) => <String, dynamic>{
            'id': item.id,
            'name': item.name,
            'color': item.color,
            'description': item.description,
          },
        )
        .toList();
  }

  json['updated_at_raw'] = DateTime.now().toUtc().toIso8601String();
  return TaskModel.fromJson(json);
}

TaskModel optimisticCompleteTask(
  TaskModel source,
  List<TaskStatusModel> statuses,
) {
  final json = _taskJson(source);
  final status = _completedStatus(statuses);
  if (status != null) {
    json['status_id'] = status.id;
    json['status'] = _statusJson(status);
  }
  json['completed_at_raw'] =
      source.completedAt?.toIso8601String() ??
      DateTime.now().toUtc().toIso8601String();
  json['updated_at_raw'] = DateTime.now().toUtc().toIso8601String();
  return TaskModel.fromJson(json);
}

TaskModel optimisticReopenTask(
  TaskModel source,
  List<TaskStatusModel> statuses,
) {
  final json = _taskJson(source);
  final status = _defaultStatus(statuses);
  if (status != null) {
    json['status_id'] = status.id;
    json['status'] = _statusJson(status);
  }
  json['completed_at_raw'] = null;
  json['updated_at_raw'] = DateTime.now().toUtc().toIso8601String();
  return TaskModel.fromJson(json);
}

TaskModel optimisticMoveTask(
  TaskModel source, {
  required int targetStatusId,
  required int targetIndex,
  required List<TaskModel> allTasks,
  required List<TaskStatusModel> statuses,
}) {
  final status = _statusById(statuses, targetStatusId);
  if (status == null) return source;

  final peers = allTasks
      .where(
        (task) =>
            task.id != source.id &&
            task.projectId == source.projectId &&
            task.statusId == targetStatusId,
      )
      .toList()
    ..sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
    });

  final insertAt = targetIndex < 0
      ? 0
      : targetIndex > peers.length
          ? peers.length
          : targetIndex;

  double nextOrder;
  if (peers.isEmpty) {
    nextOrder = 1000;
  } else if (insertAt == 0) {
    nextOrder = peers.first.sortOrder - 1000;
  } else if (insertAt >= peers.length) {
    nextOrder = peers.last.sortOrder + 1000;
  } else {
    final before = peers[insertAt - 1].sortOrder;
    final after = peers[insertAt].sortOrder;
    nextOrder = before == after
        ? before + 0.000001
        : before + ((after - before) / 2);
  }

  final json = _taskJson(source);
  json['status_id'] = status.id;
  json['status'] = _statusJson(status);
  json['sort_order'] = nextOrder;
  json['completed_at_raw'] = status.category == 'completed'
      ? source.completedAt?.toIso8601String() ??
          DateTime.now().toUtc().toIso8601String()
      : null;
  json['updated_at_raw'] = DateTime.now().toUtc().toIso8601String();
  return TaskModel.fromJson(json);
}
