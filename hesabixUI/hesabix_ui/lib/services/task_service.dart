import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/task_model.dart';

class TaskService {
  final ApiClient apiClient;

  TaskService(this.apiClient);

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
    bool? completed,
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
    if (completed != null) query['completed'] = completed;

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
}
