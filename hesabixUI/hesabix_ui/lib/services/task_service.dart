import 'package:dio/dio.dart' as dio;
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/task_model.dart';

class TaskService {
  final ApiClient apiClient;

  TaskService(this.apiClient);

  Future<List<TaskLabelModel>> listLabels(int businessId) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/task-labels',
    );
    final items = (response.data['data']?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => TaskLabelModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<TaskLabelModel> createLabel({
    required int businessId,
    required String name,
    String? color,
    String? description,
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/task-labels',
      data: {
        'name': name,
        if (color != null) 'color': color,
        if (description != null) 'description': description,
      },
    );
    return TaskLabelModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['label'] as Map),
    );
  }

  Future<void> deleteLabel({
    required int businessId,
    required int labelId,
  }) async {
    await apiClient.delete(
      '/api/v1/businesses/$businessId/task-labels/$labelId',
    );
  }

  Future<List<TaskSavedViewModel>> listSavedViews(int businessId) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/task-views',
    );
    final items = (response.data['data']?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => TaskSavedViewModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<TaskSavedViewModel> createSavedView({
    required int businessId,
    required String name,
    int? projectId,
    String viewType = 'list',
    required Map<String, dynamic> filters,
    required Map<String, dynamic> sort,
    bool isShared = false,
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/task-views',
      data: {
        'name': name,
        'project_id': projectId,
        'view_type': viewType,
        'filters': filters,
        'sort': sort,
        'is_shared': isShared,
      },
    );
    return TaskSavedViewModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['view'] as Map),
    );
  }

  Future<void> deleteSavedView({
    required int businessId,
    required int viewId,
  }) async {
    await apiClient.delete(
      '/api/v1/businesses/$businessId/task-views/$viewId',
    );
  }

  Future<List<TaskStatusModel>> listStatuses(int businessId) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/task-statuses',
    );
    final items = (response.data['data']?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => TaskStatusModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<TaskAssigneeOption>> listAssignees(int businessId) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/task-assignees',
    );
    final users = (response.data['data']?['users'] as List?) ?? const [];
    return users
        .whereType<Map>()
        .map((e) => TaskAssigneeOption.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> listTasks({
    required int businessId,
    String? search,
    int? projectId,
    int? statusId,
    int? assigneeUserId,
    String? priority,
    int? labelId,
    int? createdByUserId,
    DateTime? dueFrom,
    DateTime? dueTo,
    bool? completed,
    String? sortBy,
    String sortDir = 'asc',
    int page = 1,
    int limit = 100,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'limit': limit,
    };
    if (search != null && search.trim().isNotEmpty) query['search'] = search.trim();
    if (projectId != null) query['project_id'] = projectId;
    if (statusId != null) query['status_id'] = statusId;
    if (assigneeUserId != null) query['assignee_user_id'] = assigneeUserId;
    if (priority != null && priority.isNotEmpty) query['priority'] = priority;
    if (labelId != null) query['label_id'] = labelId;
    if (createdByUserId != null) query['created_by_user_id'] = createdByUserId;
    if (dueFrom != null) query['due_from'] = dueFrom.toUtc().toIso8601String();
    if (dueTo != null) query['due_to'] = dueTo.toUtc().toIso8601String();
    if (completed != null) query['completed'] = completed;
    if (sortBy != null && sortBy.isNotEmpty) query['sort_by'] = sortBy;
    query['sort_dir'] = sortDir;

    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/tasks',
      query: query,
    );
    final data = Map<String, dynamic>.from(response.data['data'] as Map);
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => TaskModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return {
      'items': items,
      'total': (data['total'] as num?)?.toInt() ?? items.length,
      'page': (data['page'] as num?)?.toInt() ?? page,
      'pages': (data['pages'] as num?)?.toInt() ?? 1,
    };
  }

  Future<TaskModel> getTask({
    required int businessId,
    required int taskId,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/tasks/$taskId',
    );
    return TaskModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['task'] as Map),
    );
  }

  Future<Map<String, dynamic>> listTimeEntries({
    required int businessId,
    int? taskId,
    int? projectId,
    int? userId,
    int limit = 200,
  }) async {
    final query = <String, dynamic>{'limit': limit};
    if (taskId != null) query['task_id'] = taskId;
    if (projectId != null) query['project_id'] = projectId;
    if (userId != null) query['user_id'] = userId;
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/time-entries',
      query: query,
    );
    final data = Map<String, dynamic>.from(response.data['data'] as Map);
    final raw = (data['items'] as List?) ?? const [];
    return {
      'items': raw
          .whereType<Map>()
          .map(
            (e) => TaskTimeEntryModel.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(),
      'total_seconds': (data['total_seconds'] as num?)?.toInt() ?? 0,
    };
  }

  Future<TaskTimeEntryModel?> getActiveTimer({
    required int businessId,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/timer/active',
    );
    final entry = response.data['data']?['entry'];
    return entry is Map
        ? TaskTimeEntryModel.fromJson(Map<String, dynamic>.from(entry))
        : null;
  }

  Future<TaskTimeEntryModel> startTimer({
    required int businessId,
    required int taskId,
    String? description,
    bool billable = false,
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/tasks/$taskId/timer/start',
      data: {
        'description': description,
        'billable': billable,
      },
    );
    return TaskTimeEntryModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['entry'] as Map),
    );
  }

  Future<TaskTimeEntryModel> stopTimer({
    required int businessId,
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/timer/stop',
    );
    return TaskTimeEntryModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['entry'] as Map),
    );
  }

  Future<TaskTimeEntryModel> createTimeEntry({
    required int businessId,
    required int taskId,
    required DateTime startedAt,
    DateTime? endedAt,
    int? durationMinutes,
    String? description,
    bool billable = false,
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/tasks/$taskId/time-entries',
      data: {
        'started_at': startedAt.toUtc().toIso8601String(),
        if (endedAt != null)
          'ended_at': endedAt.toUtc().toIso8601String(),
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
        'description': description,
        'billable': billable,
      },
    );
    return TaskTimeEntryModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['entry'] as Map),
    );
  }

  Future<void> deleteTimeEntry({
    required int businessId,
    required int entryId,
  }) async {
    await apiClient.delete(
      '/api/v1/businesses/$businessId/time-entries/$entryId',
    );
  }

  Future<List<TaskCycleModel>> listTaskCycles({
    required int businessId, required int taskId,
  }) async {
    final r=await apiClient.get('/api/v1/businesses/$businessId/tasks/$taskId/cycles');
    final items=(r.data['data']?['items'] as List?)??const [];
    return items.whereType<Map>().map((e)=>TaskCycleModel.fromJson(Map<String,dynamic>.from(e))).toList();
  }

  Future<List<TaskCycleModel>> replaceTaskCycles({
    required int businessId, required int taskId, required List<int> cycleIds,
  }) async {
    final r=await apiClient.put('/api/v1/businesses/$businessId/tasks/$taskId/cycles', data:{'cycle_ids':cycleIds});
    final items=(r.data['data']?['items'] as List?)??const [];
    return items.whereType<Map>().map((e)=>TaskCycleModel.fromJson(Map<String,dynamic>.from(e))).toList();
  }

  Future<List<TaskReminderModel>> listReminders({
    required int businessId,
    required int taskId,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/tasks/$taskId/reminders',
    );
    final items = (response.data['data']?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => TaskReminderModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<TaskReminderModel> createReminder({
    required int businessId,
    required int taskId,
    int? userId,
    DateTime? remindAt,
    String? relativeTo,
    int? offsetMinutes,
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/tasks/$taskId/reminders',
      data: {
        if (userId != null) 'user_id': userId,
        if (remindAt != null) 'remind_at': remindAt.toUtc().toIso8601String(),
        if (relativeTo != null) 'relative_to': relativeTo,
        if (offsetMinutes != null) 'offset_minutes': offsetMinutes,
      },
    );
    return TaskReminderModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['reminder'] as Map),
    );
  }

  Future<void> deleteReminder({
    required int businessId,
    required int taskId,
    required int reminderId,
  }) async {
    await apiClient.delete(
      '/api/v1/businesses/$businessId/tasks/$taskId/reminders/$reminderId',
    );
  }

  Future<List<TaskCommentModel>> listComments({
    required int businessId,
    required int taskId,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/tasks/$taskId/comments',
    );
    final items = (response.data['data']?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => TaskCommentModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<TaskCommentModel> addComment({
    required int businessId,
    required int taskId,
    required String body,
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/tasks/$taskId/comments',
      data: {'body': body},
    );
    return TaskCommentModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['comment'] as Map),
    );
  }

  Future<TaskCommentModel> updateComment({
    required int businessId,
    required int taskId,
    required int commentId,
    required String body,
  }) async {
    final response = await apiClient.patch(
      '/api/v1/businesses/$businessId/tasks/$taskId/comments/$commentId',
      data: {'body': body},
    );
    return TaskCommentModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['comment'] as Map),
    );
  }

  Future<void> deleteComment({
    required int businessId,
    required int taskId,
    required int commentId,
  }) async {
    await apiClient.delete(
      '/api/v1/businesses/$businessId/tasks/$taskId/comments/$commentId',
    );
  }

  Future<List<TaskActivityModel>> listActivity({
    required int businessId,
    required int taskId,
    int limit = 100,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/tasks/$taskId/activity',
      query: {'limit': limit},
    );
    final items = (response.data['data']?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => TaskActivityModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<TaskStructureModel> getTaskStructure({
    required int businessId,
    required int taskId,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/tasks/$taskId/structure',
    );
    return TaskStructureModel.fromJson(
      Map<String, dynamic>.from(response.data['data'] as Map),
    );
  }

  Future<TaskModel> createSubtask({
    required int businessId,
    required int parentTaskId,
    required String title,
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/tasks/$parentTaskId/subtasks',
      data: {'title': title},
    );
    return TaskModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['task'] as Map),
    );
  }

  Future<void> addTaskRelation({
    required int businessId,
    required int taskId,
    required int relatedTaskId,
    required String relationType,
  }) async {
    await apiClient.post(
      '/api/v1/businesses/$businessId/tasks/$taskId/relations',
      data: {
        'related_task_id': relatedTaskId,
        'relation_type': relationType,
      },
    );
  }

  Future<void> deleteTaskRelation({
    required int businessId,
    required int taskId,
    required int relationId,
  }) async {
    await apiClient.delete(
      '/api/v1/businesses/$businessId/tasks/$taskId/relations/$relationId',
    );
  }

  Future<TaskModel> createTask({
    required int businessId,
    required Map<String, dynamic> data,
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/tasks',
      data: data,
    );
    return TaskModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['task'] as Map),
    );
  }

  Future<TaskModel> updateTask({
    required int businessId,
    required int taskId,
    required Map<String, dynamic> data,
  }) async {
    final response = await apiClient.patch(
      '/api/v1/businesses/$businessId/tasks/$taskId',
      data: data,
    );
    return TaskModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['task'] as Map),
    );
  }

  Future<void> deleteTask({
    required int businessId,
    required int taskId,
  }) async {
    await apiClient.delete(
      '/api/v1/businesses/$businessId/tasks/$taskId',
    );
  }

  Future<TaskModel> moveTask({
    required int businessId,
    required int taskId,
    required int targetStatusId,
    required int targetIndex,
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/tasks/$taskId/move',
      data: {
        'target_status_id': targetStatusId,
        'target_index': targetIndex,
      },
    );
    return TaskModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['task'] as Map),
    );
  }

  Future<TaskModel> completeTask({
    required int businessId,
    required int taskId,
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/tasks/$taskId/complete',
    );
    return TaskModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['task'] as Map),
    );
  }

  Future<TaskModel> reopenTask({
    required int businessId,
    required int taskId,
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/tasks/$taskId/reopen',
    );
    return TaskModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['task'] as Map),
    );
  }
  Future<List<TaskEntityTypeModel>> listEntityTypes({
    required int businessId,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/task-link-entity-types',
    );
    final items = (response.data['data']?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => TaskEntityTypeModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<TaskLinkTargetModel>> searchEntityTargets({
    required int businessId,
    required String entityType,
    String? search,
    int limit = 25,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/task-link-targets',
      query: {
        'entity_type': entityType,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'limit': limit,
      },
    );
    final items = (response.data['data']?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => TaskLinkTargetModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<TaskEntityLinkModel>> listEntityLinks({
    required int businessId,
    required int taskId,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/tasks/$taskId/entity-links',
    );
    final items = (response.data['data']?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => TaskEntityLinkModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<TaskEntityLinkModel> addEntityLink({
    required int businessId,
    required int taskId,
    required String entityType,
    required String entityId,
    String relationshipType = 'related',
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/tasks/$taskId/entity-links',
      data: {
        'entity_type': entityType,
        'entity_id': entityId,
        'relationship_type': relationshipType,
      },
    );
    return TaskEntityLinkModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['link'] as Map),
    );
  }

  Future<void> deleteEntityLink({
    required int businessId,
    required int taskId,
    required int linkId,
  }) async {
    await apiClient.delete(
      '/api/v1/businesses/$businessId/tasks/$taskId/entity-links/$linkId',
    );
  }

  Future<List<TaskModel>> listTasksForEntity({
    required int businessId,
    required String entityType,
    required String entityId,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/entities/$entityType/$entityId/tasks',
    );
    final items = (response.data['data']?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => TaskModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }


  Future<List<TaskAttachmentModel>> listAttachments({
    required int businessId,
    required int taskId,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/tasks/$taskId/attachments',
    );
    final items = (response.data['data']?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => TaskAttachmentModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<TaskAttachmentModel> uploadAttachment({
    required int businessId,
    required int taskId,
    required List<int> bytes,
    required String filename,
  }) async {
    final form = dio.FormData.fromMap({
      'file': dio.MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/tasks/$taskId/attachments',
      data: form,
      options: dio.Options(contentType: 'multipart/form-data'),
    );
    return TaskAttachmentModel.fromJson(
      Map<String, dynamic>.from(response.data['data']['attachment'] as Map),
    );
  }

  Future<List<int>> downloadAttachment({
    required int businessId,
    required int taskId,
    required int attachmentId,
  }) async {
    final response = await apiClient.get<List<int>>(
      '/api/v1/businesses/$businessId/tasks/$taskId/attachments/$attachmentId/download',
      options: dio.Options(
        responseType: dio.ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 5),
      ),
    );
    return response.data ?? <int>[];
  }

  Future<void> deleteAttachment({
    required int businessId,
    required int taskId,
    required int attachmentId,
  }) async {
    await apiClient.delete(
      '/api/v1/businesses/$businessId/tasks/$taskId/attachments/$attachmentId',
    );
  }


}
