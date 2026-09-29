import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/models/project_model.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/project_service.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/services/task_optimistic_patch.dart';
import 'package:hesabix_ui/services/in_app_notifications_hub.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/task/task_detail_drawer.dart';
import 'package:hesabix_ui/widgets/task/task_dashboard_view.dart';
import 'package:hesabix_ui/widgets/task/task_quick_create.dart';
import 'package:hesabix_ui/widgets/common/bounded_sliver_list.dart';
import 'package:intl/intl.dart';

class TaskManagementPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final Uri initialUri;

  const TaskManagementPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.initialUri,
  });

  @override
  State<TaskManagementPage> createState() => _TaskManagementPageState();
}

class _TaskManagementPageState extends State<TaskManagementPage> {
  late final TaskService _taskService;
  late final ProjectService _projectService;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<TaskModel> _tasks = const [];
  List<TaskStatusModel> _statuses = const [];
  List<ProjectModel> _projects = const [];
  List<TaskAssigneeOption> _assignees = const [];
  List<TaskLabelModel> _labels = const [];
  List<TaskSavedViewModel> _savedViews = const [];

  bool _loading = true;
  bool _showDashboard = false;
  int _dashboardRevision = 0;
  String? _error;
  bool? _completedFilter = false;
  int? _statusFilterId;
  int? _projectFilterId;
  int? _assigneeFilterId;
  int? _labelFilterId;
  int? _creatorFilterId;
  String? _priorityFilter;
  String _duePreset = 'any';
  String? _sortBy;
  String _sortDir = 'asc';
  int? _selectedViewId;
  TaskModel? _selectedTask;
  bool _selectionMode = false;
  final Set<int> _selectedTaskIds = <int>{};
  int _taskPage = 1;
  int _taskPages = 1;
  bool _loadingMore = false;
  late String _lastAppliedUriText;
  Timer? _realtimeRefreshTimer;
  bool _realtimeReconciling = false;
  final Set<String> _recentRealtimeEventIds = <String>{};
  final Map<int, int> _optimisticTaskRevisions = <int, int>{};

  @override
  void initState() {
    super.initState();
    _taskService = TaskService(ApiClient());
    _projectService = ProjectService(ApiClient());
    _hydrateFiltersFromUri(widget.initialUri);
    _lastAppliedUriText = widget.initialUri.toString();
    InAppNotificationsHub.instance.addRawMessageListener(_onRealtimeMessage);
    _loadAll();
  }

  @override
  void didUpdateWidget(covariant TaskManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextUri = widget.initialUri.toString();
    if (nextUri == oldWidget.initialUri.toString() ||
        nextUri == _lastAppliedUriText) {
      return;
    }
    setState(() {
      _hydrateFiltersFromUri(widget.initialUri);
      _selectedTask = null;
      _selectionMode = false;
      _selectedTaskIds.clear();
    });
    _lastAppliedUriText = nextUri;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reloadTasks();
    });
  }

  @override
  void dispose() {
    InAppNotificationsHub.instance.removeRawMessageListener(_onRealtimeMessage);
    _realtimeRefreshTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onRealtimeMessage(Map<String, dynamic> message) {
    if ('${message['type'] ?? ''}' != 'task.realtime') return;
    final businessId = (message['business_id'] as num?)?.toInt();
    if (businessId != widget.businessId) return;

    final taskId = (message['task_id'] as num?)?.toInt();
    if (taskId != null && _optimisticTaskRevisions.containsKey(taskId)) {
      _optimisticTaskRevisions[taskId] =
          (_optimisticTaskRevisions[taskId] ?? 0) + 1;
    }

    final eventId = message['event_id']?.toString();
    if (eventId != null && eventId.isNotEmpty) {
      if (!_recentRealtimeEventIds.add(eventId)) return;
      if (_recentRealtimeEventIds.length > 256) {
        _recentRealtimeEventIds.clear();
        _recentRealtimeEventIds.add(eventId);
      }
    }

    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = Timer(
      const Duration(milliseconds: 250),
      () {
        if (mounted) unawaited(_reconcileRealtime());
      },
    );
  }

  Future<void> _reconcileRealtime() async {
    if (!mounted || _realtimeReconciling) return;
    _realtimeReconciling = true;
    try {
      final result = await _loadTasksRequest(page: 1);
      final nextTasks =
          (result['items'] as List<TaskModel>?) ?? const <TaskModel>[];
      if (!mounted) return;
      setState(() {
        _tasks = nextTasks;
        _taskPage = (result['page'] as num?)?.toInt() ?? 1;
        _taskPages = (result['pages'] as num?)?.toInt() ?? 1;
        _selectedTask = _selectedTask == null
            ? null
            : _findTask(nextTasks, _selectedTask!.id);
        _dashboardRevision++;
      });
    } catch (_) {
      // Realtime is best-effort. Normal REST interactions remain authoritative.
    } finally {
      _realtimeReconciling = false;
    }
  }

  int? _queryInt(Uri uri, String key) {
    final raw = uri.queryParameters[key];
    final value = raw == null ? null : int.tryParse(raw);
    return value != null && value > 0 ? value : null;
  }

  void _hydrateFiltersFromUri(Uri uri) {
    final query = uri.queryParameters;
    _searchController.text = query['q']?.trim() ?? '';
    _statusFilterId = _queryInt(uri, 'status');
    _projectFilterId = _queryInt(uri, 'project');
    _assigneeFilterId = _queryInt(uri, 'assignee');
    _labelFilterId = _queryInt(uri, 'label');
    _creatorFilterId = _queryInt(uri, 'creator');

    final priority = query['priority'];
    _priorityFilter = const {'low', 'normal', 'high', 'urgent'}.contains(priority)
        ? priority
        : null;

    final due = query['due'];
    _duePreset = const {'overdue', 'today', 'next7'}.contains(due)
        ? due!
        : 'any';

    switch (query['completed']) {
      case 'done':
      case 'true':
        _completedFilter = true;
        break;
      case 'all':
        _completedFilter = null;
        break;
      default:
        _completedFilter = false;
        break;
    }

    final sortBy = query['sort'];
    _sortBy = const {'due_at', 'created_at', 'updated_at', 'title'}
            .contains(sortBy)
        ? sortBy
        : null;
    _sortDir = query['dir'] == 'desc' ? 'desc' : 'asc';
    _selectedViewId = _queryInt(uri, 'view');
  }

  Map<String, String> _currentUrlQuery() {
    final query = <String, String>{};
    final search = _searchController.text.trim();
    if (search.isNotEmpty) query['q'] = search;
    if (_statusFilterId != null) query['status'] = '$_statusFilterId';
    if (_projectFilterId != null) query['project'] = '$_projectFilterId';
    if (_assigneeFilterId != null) query['assignee'] = '$_assigneeFilterId';
    if (_labelFilterId != null) query['label'] = '$_labelFilterId';
    if (_creatorFilterId != null) query['creator'] = '$_creatorFilterId';
    if (_priorityFilter != null) query['priority'] = _priorityFilter!;
    if (_duePreset != 'any') query['due'] = _duePreset;
    if (_completedFilter == true) {
      query['completed'] = 'done';
    } else if (_completedFilter == null) {
      query['completed'] = 'all';
    }
    if (_sortBy != null) {
      query['sort'] = _sortBy!;
      if (_sortDir == 'desc') query['dir'] = 'desc';
    }
    if (_selectedViewId != null) query['view'] = '$_selectedViewId';
    return query;
  }

  void _syncUrl() {
    if (!mounted) return;
    final query = _currentUrlQuery();
    final uri = Uri(
      path: '/business/${widget.businessId}/tasks',
      queryParameters: query.isEmpty ? null : query,
    );
    final next = uri.toString();
    if (next == _lastAppliedUriText) return;
    _lastAppliedUriText = next;
    Router.neglect(context, () => context.go(next));
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final statusesFuture = _taskService.listStatuses(widget.businessId);
      final assigneesFuture = _taskService.listAssignees(widget.businessId);
      final labelsFuture = _taskService.listLabels(widget.businessId);
      final viewsFuture = _taskService.listSavedViews(widget.businessId);
      final projectsFuture =
          _projectService.listActiveProjects(widget.businessId);
      final tasksFuture = _loadTasksRequest();

      final results = await Future.wait<dynamic>([
        statusesFuture,
        assigneesFuture,
        labelsFuture,
        viewsFuture,
        projectsFuture,
        tasksFuture,
      ]);

      if (!mounted) return;
      final taskResult = results[5] as Map<String, dynamic>;
      final nextTasks =
          taskResult['items'] as List<TaskModel>? ?? const <TaskModel>[];
      setState(() {
        _statuses = results[0] as List<TaskStatusModel>;
        _assignees = results[1] as List<TaskAssigneeOption>;
        _labels = results[2] as List<TaskLabelModel>;
        _savedViews = results[3] as List<TaskSavedViewModel>;
        if (_selectedViewId != null &&
            !_savedViews.any((view) => view.id == _selectedViewId)) {
          _selectedViewId = null;
        }
        _projects = results[4] as List<ProjectModel>;
        _tasks = nextTasks;
        _taskPage = (taskResult['page'] as num?)?.toInt() ?? 1;
        _taskPages = (taskResult['pages'] as num?)?.toInt() ?? 1;
        _selectedTaskIds.removeWhere(
          (id) => !nextTasks.any((task) => task.id == id),
        );
        _selectedTask = _selectedTask == null
            ? null
            : _findTask(nextTasks, _selectedTask!.id);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<Map<String, dynamic>> _loadTasksRequest({int page = 1}) {
    final now = DateTime.now();
    DateTime? dueFrom;
    DateTime? dueTo;
    if (_duePreset == 'overdue') {
      dueTo = now;
    } else if (_duePreset == 'today') {
      dueFrom = DateTime(now.year, now.month, now.day);
      dueTo = dueFrom.add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
    } else if (_duePreset == 'next7') {
      dueFrom = now;
      dueTo = now.add(const Duration(days: 7));
    }

    return _taskService.listTasks(
      businessId: widget.businessId,
      search: _searchController.text,
      projectId: _projectFilterId,
      statusId: _statusFilterId,
      assigneeUserId: _assigneeFilterId,
      priority: _priorityFilter,
      labelId: _labelFilterId,
      createdByUserId: _creatorFilterId,
      dueFrom: dueFrom,
      dueTo: dueTo,
      completed: _completedFilter,
      sortBy: _sortBy,
      sortDir: _sortDir,
      page: page,
      limit: 100,
    );
  }

  Map<String, dynamic> _currentFilterSnapshot() => {
        if (_searchController.text.trim().isNotEmpty)
          'search': _searchController.text.trim(),
        if (_statusFilterId != null) 'status_id': _statusFilterId,
        if (_projectFilterId != null) 'project_id': _projectFilterId,
        if (_assigneeFilterId != null)
          'assignee_user_id': _assigneeFilterId,
        if (_labelFilterId != null) 'label_id': _labelFilterId,
        if (_creatorFilterId != null)
          'created_by_user_id': _creatorFilterId,
        if (_priorityFilter != null) 'priority': _priorityFilter,
        if (_completedFilter != null) 'completed': _completedFilter,
        if (_duePreset != 'any') 'due_preset': _duePreset,
      };

  Map<String, dynamic> _currentSortSnapshot() => {
        if (_sortBy != null) 'sort_by': _sortBy,
        'sort_dir': _sortDir,
      };

  void _applySavedView(TaskSavedViewModel? view) {
    if (view == null) return;
    final filters = view.filters;
    final sort = view.sort;
    setState(() {
      _selectedViewId = view.id;
      _searchController.text = filters['search']?.toString() ?? '';
      _statusFilterId = (filters['status_id'] as num?)?.toInt();
      _projectFilterId = (filters['project_id'] as num?)?.toInt();
      _assigneeFilterId =
          (filters['assignee_user_id'] as num?)?.toInt();
      _labelFilterId = (filters['label_id'] as num?)?.toInt();
      _creatorFilterId =
          (filters['created_by_user_id'] as num?)?.toInt();
      _priorityFilter = filters['priority']?.toString();
      _completedFilter = filters.containsKey('completed')
          ? filters['completed'] == true
          : null;
      _duePreset = filters['due_preset']?.toString() ?? 'any';
      _sortBy = sort['sort_by']?.toString();
      _sortDir = sort['sort_dir']?.toString() == 'desc' ? 'desc' : 'asc';
      _selectedTask = null;
    });
    _reloadTasks();
  }

  void _resetFilters() {
    setState(() {
      _selectedViewId = null;
      _searchController.clear();
      _completedFilter = false;
      _statusFilterId = null;
      _projectFilterId = null;
      _assigneeFilterId = null;
      _labelFilterId = null;
      _creatorFilterId = null;
      _priorityFilter = null;
      _duePreset = 'any';
      _sortBy = null;
      _sortDir = 'asc';
      _selectedTask = null;
    });
    _reloadTasks();
  }

  Future<void> _saveCurrentView() async {
    final nameController = TextEditingController();
    var shared = false;
    final result = await showGlassDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('ذخیره نما'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'نام نما'),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('اشتراک با اعضای کسب‌وکار'),
                  value: shared,
                  onChanged: (value) => setInner(() => shared = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx, {'name': name, 'shared': shared});
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (result == null) return;

    try {
      final view = await _taskService.createSavedView(
        businessId: widget.businessId,
        name: result['name'].toString(),
        projectId: _projectFilterId,
        filters: _currentFilterSnapshot(),
        sort: _currentSortSnapshot(),
        isShared: result['shared'] == true,
      );
      if (!mounted) return;
      setState(() {
        _savedViews = [..._savedViews, view]
          ..sort((a, b) => a.name.compareTo(b.name));
        _selectedViewId = view.id;
      });
      SnackBarHelper.showSuccess(context, message: 'نما ذخیره شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Future<void> _deleteSelectedView() async {
    final id = _selectedViewId;
    if (id == null) return;
    try {
      await _taskService.deleteSavedView(
        businessId: widget.businessId,
        viewId: id,
      );
      if (!mounted) return;
      setState(() {
        _savedViews = _savedViews.where((view) => view.id != id).toList();
        _selectedViewId = null;
      });
      SnackBarHelper.showSuccess(context, message: 'نمای ذخیره‌شده حذف شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Future<void> _reloadTasks() async {
    if (!mounted) return;
    _syncUrl();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _loadTasksRequest(page: 1);
      final nextTasks =
          (result['items'] as List<TaskModel>?) ?? const <TaskModel>[];
      if (!mounted) return;
      setState(() {
        _tasks = nextTasks;
        _taskPage = (result['page'] as num?)?.toInt() ?? 1;
        _taskPages = (result['pages'] as num?)?.toInt() ?? 1;
        _selectedTaskIds.clear();
        _selectedTask = _selectedTask == null
            ? null
            : _findTask(nextTasks, _selectedTask!.id);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<void> _loadMoreTasks() async {
    if (_loadingMore || _taskPage >= _taskPages) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _loadTasksRequest(page: _taskPage + 1);
      final items =
          (result['items'] as List<TaskModel>?) ?? const <TaskModel>[];
      if (!mounted) return;
      final existing = {for (final task in _tasks) task.id: task};
      for (final task in items) {
        existing[task.id] = task;
      }
      setState(() {
        _tasks = existing.values.toList();
        _taskPage = (result['page'] as num?)?.toInt() ?? (_taskPage + 1);
        _taskPages = (result['pages'] as num?)?.toInt() ?? _taskPages;
      });
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _setSelectionMode(bool enabled) {
    setState(() {
      _selectionMode = enabled;
      if (!enabled) _selectedTaskIds.clear();
      _selectedTask = null;
    });
  }

  void _toggleSelection(int taskId, bool selected) {
    setState(() {
      _selectionMode = true;
      if (selected) {
        _selectedTaskIds.add(taskId);
      } else {
        _selectedTaskIds.remove(taskId);
        if (_selectedTaskIds.isEmpty) _selectionMode = false;
      }
    });
  }

  void _selectAllLoaded() {
    setState(() {
      _selectionMode = true;
      _selectedTaskIds
        ..clear()
        ..addAll(_tasks.map((task) => task.id));
    });
  }

  Future<void> _bulkUpdate({
    int? statusId,
    String? priority,
  }) async {
    if (_selectedTaskIds.isEmpty) return;
    try {
      final updated = await _taskService.bulkUpdateTasks(
        businessId: widget.businessId,
        taskIds: _selectedTaskIds.toList(),
        statusId: statusId,
        priority: priority,
      );
      for (final task in updated) {
        _upsertTask(task);
      }
      if (!mounted) return;
      _setSelectionMode(false);
      SnackBarHelper.showSuccess(
        context,
        message: '${updated.length} کار بروزرسانی شد',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Future<void> _restoreDeletedTasks(List<int> ids) async {
    try {
      for (final id in ids) {
        await _taskService.restoreTask(
          businessId: widget.businessId,
          taskId: id,
        );
      }
      await _reloadTasks();
      if (mounted) {
        SnackBarHelper.showSuccess(
          context,
          message: 'حذف برگردانده شد',
        );
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Future<void> _bulkDelete() async {
    if (_selectedTaskIds.isEmpty) return;
    final ids = _selectedTaskIds.toList();
    try {
      final deleted = await _taskService.bulkDeleteTasks(
        businessId: widget.businessId,
        taskIds: ids,
      );
      if (!mounted) return;
      setState(() {
        _tasks = _tasks
            .where((task) => !deleted.contains(task.id))
            .toList();
        _selectionMode = false;
        _selectedTaskIds.clear();
        _selectedTask = null;
      });
      SnackBarHelper.show(
        context,
        message: '${deleted.length} کار حذف شد',
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _restoreDeletedTasks(deleted),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Future<void> _commandCreateTask() async {
    final controller = TextEditingController();
    final title = await showGlassDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('کار جدید'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'عنوان'),
          onSubmitted: (value) =>
              Navigator.pop(ctx, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, controller.text.trim()),
            child: const Text('ایجاد'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title != null && title.isNotEmpty) {
      await _quickCreate(title);
    }
  }

  Future<void> _showCommandPalette() async {
    await showGlassDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.keyboard_command_key_rounded),
            SizedBox(width: 8),
            Text('Command Palette'),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (widget.authStore.hasProjectPermission('task_create'))
                ListTile(
                  leading: const Icon(Icons.add_task_outlined),
                  title: const Text('New task'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _commandCreateTask();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.analytics_outlined),
                title: Text(
                  _showDashboard ? 'Show task list' : 'Show dashboard',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _showDashboard = !_showDashboard;
                    _selectedTask = null;
                    if (_showDashboard) _dashboardRevision++;
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.today_outlined),
                title: const Text('Due today'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _showDashboard = false;
                    _duePreset = 'today';
                    _completedFilter = false;
                  });
                  _reloadTasks();
                },
              ),
              ListTile(
                leading: const Icon(Icons.warning_amber_rounded),
                title: const Text('Overdue'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _showDashboard = false;
                    _duePreset = 'overdue';
                    _completedFilter = false;
                  });
                  _reloadTasks();
                },
              ),
              ListTile(
                leading: const Icon(Icons.filter_alt_off_outlined),
                title: const Text('Clear filters'),
                onTap: () {
                  Navigator.pop(ctx);
                  _resetFilters();
                },
              ),
              ListTile(
                leading: const Icon(Icons.checklist_rounded),
                title: const Text('Selection mode'),
                onTap: () {
                  Navigator.pop(ctx);
                  _setSelectionMode(true);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
  }

  int _beginOptimisticTask(int taskId) {
    final revision = (_optimisticTaskRevisions[taskId] ?? 0) + 1;
    _optimisticTaskRevisions[taskId] = revision;
    return revision;
  }

  void _finishOptimisticTask(int taskId, int revision) {
    if (_optimisticTaskRevisions[taskId] == revision) {
      _optimisticTaskRevisions.remove(taskId);
    }
  }

  void _rollbackOptimisticTask(
    TaskModel source, {
    required int originalIndex,
    required int revision,
    required TaskModel? previousSelectedTask,
  }) {
    if (!mounted || _optimisticTaskRevisions[source.id] != revision) return;
    final next = List<TaskModel>.from(_tasks)
      ..removeWhere((task) => task.id == source.id);
    if (originalIndex >= 0) {
      final insertAt =
          originalIndex > next.length ? next.length : originalIndex;
      next.insert(insertAt, source);
    }
    setState(() {
      _tasks = next;
      if (_selectedTask?.id == source.id ||
          previousSelectedTask?.id == source.id) {
        _selectedTask = previousSelectedTask;
      }
    });
    _optimisticTaskRevisions.remove(source.id);
  }

  TaskModel? _findTask(List<TaskModel> tasks, int id) {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  void _upsertTask(TaskModel task) {
    if (!mounted) return;
    final next = List<TaskModel>.from(_tasks);
    final index = next.indexWhere((item) => item.id == task.id);
    if (index >= 0) {
      next[index] = task;
    } else {
      next.insert(0, task);
    }

    final visibleByCompletion = _completedFilter == null ||
        (_completedFilter == true && task.isCompleted) ||
        (_completedFilter == false && !task.isCompleted);
    final visibleByStatus =
        _statusFilterId == null || task.statusId == _statusFilterId;
    final visibleByProject =
        _projectFilterId == null || task.projectId == _projectFilterId;
    final visibleByAssignee = _assigneeFilterId == null ||
        task.assignees.any((a) => a.userId == _assigneeFilterId);
    final visibleByLabel = _labelFilterId == null ||
        task.labels.any((label) => label.id == _labelFilterId);
    final visibleByPriority =
        _priorityFilter == null || task.priority == _priorityFilter;
    if (!visibleByCompletion ||
        !visibleByStatus ||
        !visibleByProject ||
        !visibleByAssignee ||
        !visibleByLabel ||
        !visibleByPriority) {
      next.removeWhere((item) => item.id == task.id);
    }

    setState(() {
      _tasks = next;
      if (_selectedTask?.id == task.id) _selectedTask = task;
    });
  }

  Future<bool> _quickCreate(String title) async {
    try {
      final task = await _taskService.createTask(
        businessId: widget.businessId,
        data: {
          'title': title,
          if (_projectFilterId != null) 'project_id': _projectFilterId,
          if (_statusFilterId != null) 'status_id': _statusFilterId,
          if (_priorityFilter != null) 'priority': _priorityFilter,
          if (_assigneeFilterId != null)
            'assignee_user_ids': [_assigneeFilterId],
          if (_labelFilterId != null) 'label_ids': [_labelFilterId],
        },
      );
      _upsertTask(task);
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: 'کار ایجاد شد');
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
      return false;
    }
  }

  Future<TaskModel?> _updateTask(
    TaskModel source,
    Map<String, dynamic> data,
  ) async {
    final originalIndex = _tasks.indexWhere((task) => task.id == source.id);
    final previousSelectedTask = _selectedTask;
    final revision = _beginOptimisticTask(source.id);
    final optimistic = applyTaskOptimisticPatch(
      source,
      data,
      statuses: _statuses,
      projects: _projects,
      assignees: _assignees,
      labels: _labels,
    );
    _upsertTask(optimistic);

    try {
      final updated = await _taskService.updateTask(
        businessId: widget.businessId,
        taskId: source.id,
        data: data,
      );
      _finishOptimisticTask(source.id, revision);
      _upsertTask(updated);
      return updated;
    } catch (e) {
      _rollbackOptimisticTask(
        source,
        originalIndex: originalIndex,
        revision: revision,
        previousSelectedTask: previousSelectedTask,
      );
      if (!mounted) return null;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
      rethrow;
    }
  }

  Future<TaskModel?> _toggleComplete(TaskModel source) async {
    final originalIndex = _tasks.indexWhere((task) => task.id == source.id);
    final previousSelectedTask = _selectedTask;
    final revision = _beginOptimisticTask(source.id);
    final optimistic = source.isCompleted
        ? optimisticReopenTask(source, _statuses)
        : optimisticCompleteTask(source, _statuses);
    _upsertTask(optimistic);

    try {
      final updated = source.isCompleted
          ? await _taskService.reopenTask(
              businessId: widget.businessId,
              taskId: source.id,
            )
          : await _taskService.completeTask(
              businessId: widget.businessId,
              taskId: source.id,
            );
      _finishOptimisticTask(source.id, revision);
      _upsertTask(updated);
      if (mounted) {
        SnackBarHelper.showSuccess(
          context,
          message: updated.isCompleted ? 'کار تکمیل شد' : 'کار دوباره باز شد',
        );
      }
      return updated;
    } catch (e) {
      _rollbackOptimisticTask(
        source,
        originalIndex: originalIndex,
        revision: revision,
        previousSelectedTask: previousSelectedTask,
      );
      if (!mounted) return null;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
      rethrow;
    }
  }

  Future<bool> _deleteTask(TaskModel source) async {
    final originalIndex = _tasks.indexWhere((task) => task.id == source.id);
    final previousSelectedTask = _selectedTask;
    final revision = _beginOptimisticTask(source.id);
    if (mounted) {
      setState(() {
        _tasks = _tasks.where((item) => item.id != source.id).toList();
        if (_selectedTask?.id == source.id) _selectedTask = null;
      });
    }

    try {
      await _taskService.deleteTask(
        businessId: widget.businessId,
        taskId: source.id,
      );
      _finishOptimisticTask(source.id, revision);
      if (!mounted) return false;
      SnackBarHelper.show(
        context,
        message: 'کار حذف شد',
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _restoreDeletedTasks([source.id]),
        ),
      );
      return true;
    } catch (e) {
      _rollbackOptimisticTask(
        source,
        originalIndex: originalIndex,
        revision: revision,
        previousSelectedTask: previousSelectedTask,
      );
      if (!mounted) return false;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
      return false;
    }
  }

  Future<void> _openDashboardTask(int taskId) async {
    try {
      final task = _findTask(_tasks, taskId) ??
          await _taskService.getTask(
            businessId: widget.businessId,
            taskId: taskId,
          );
      if (!mounted) return;
      setState(() => _showDashboard = false);
      await _openDetails(task);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Future<void> _openDetails(TaskModel task) async {
    if (ResponsiveHelper.isMobile(context)) {
      await showGlassModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) {
          TaskModel liveTask = task;
          return FractionallySizedBox(
            heightFactor: 0.94,
            child: StatefulBuilder(
              builder: (sheetContext, setSheetState) => TaskDetailDrawer(
                businessId: widget.businessId,
                task: liveTask,
                relationCandidates: _tasks,
                onTaskCreated: _upsertTask,
                statuses: _statuses,
                projects: _projects,
                assignees: _assignees,
                onUpdate: (data) async {
                  final updated = await _updateTask(liveTask, data);
                  if (updated != null) {
                    liveTask = updated;
                    setSheetState(() {});
                  }
                  return updated;
                },
                onToggleComplete: () async {
                  final updated = await _toggleComplete(liveTask);
                  if (updated != null) {
                    liveTask = updated;
                    setSheetState(() {});
                  }
                  return updated;
                },
                onDelete: () => _deleteTask(liveTask),
                onClose: () => Navigator.pop(sheetContext),
              ),
            ),
          );
        },
      );
      return;
    }

    setState(() => _selectedTask = task);
  }

  String _priorityLabel(String priority) {
    switch (priority) {
      case 'urgent':
        return 'فوری';
      case 'high':
        return 'زیاد';
      case 'low':
        return 'کم';
      default:
        return 'معمولی';
    }
  }

  Color _priorityColor(BuildContext context, String priority) {
    final scheme = Theme.of(context).colorScheme;
    switch (priority) {
      case 'urgent':
        return scheme.error;
      case 'high':
        return Colors.orange;
      case 'low':
        return Colors.blueGrey;
      default:
        return scheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveHelper.getPadding(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final taskBody = _buildMainContent(context, padding, isMobile);
    final body = _showDashboard
        ? TaskDashboardView(
            key: ValueKey(_dashboardRevision),
            businessId: widget.businessId,
            onOpenTask: (id) => _openDashboardTask(id),
            onOpenProject: (id) => context.go(
              '/business/${widget.businessId}/projects/$id',
            ),
          )
        : taskBody;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(
          LogicalKeyboardKey.keyK,
          control: true,
        ): _showCommandPalette,
        const SingleActivator(
          LogicalKeyboardKey.keyK,
          meta: true,
        ): _showCommandPalette,
        const SingleActivator(
          LogicalKeyboardKey.keyD,
          alt: true,
        ): () {
          setState(() {
            _showDashboard = !_showDashboard;
            _selectedTask = null;
            if (_showDashboard) _dashboardRevision++;
          });
        },
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          alt: true,
        ): () => _setSelectionMode(!_selectionMode),
        const SingleActivator(
          LogicalKeyboardKey.escape,
        ): () {
          if (_selectionMode) _setSelectionMode(false);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت کارها'),
        leading: IconButton(
          tooltip: 'بازگشت به پروژه‌ها',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/business/${widget.businessId}/projects'),
        ),
        actions: [
          if (!_showDashboard)
            IconButton(
              tooltip: _selectionMode ? 'خروج از انتخاب' : 'انتخاب چندتایی',
              onPressed: () => _setSelectionMode(!_selectionMode),
              icon: Icon(
                _selectionMode
                    ? Icons.close_rounded
                    : Icons.checklist_rounded,
              ),
            ),
          IconButton(
            tooltip: 'Command Palette · Ctrl/Cmd+K',
            onPressed: _showCommandPalette,
            icon: const Icon(Icons.keyboard_command_key_rounded),
          ),
          IconButton(
            tooltip: _showDashboard ? 'لیست کارها' : 'داشبورد',
            onPressed: () {
              setState(() {
                _showDashboard = !_showDashboard;
                _selectedTask = null;
                if (_showDashboard) _dashboardRevision++;
              });
            },
            icon: Icon(
              _showDashboard
                  ? Icons.list_alt_outlined
                  : Icons.analytics_outlined,
            ),
          ),
          IconButton(
            tooltip: 'بروزرسانی',
            onPressed: () {
              if (_showDashboard) {
                setState(() => _dashboardRevision++);
              } else if (!_loading) {
                _loadAll();
              }
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: isMobile || _showDashboard
            ? body
            : Row(
                children: [
                  Expanded(child: body),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: _selectedTask == null ? 0 : 440,
                    child: _selectedTask == null
                        ? const SizedBox.shrink()
                        : TaskDetailDrawer(
                            key: ValueKey(_selectedTask!.id),
                            businessId: widget.businessId,
                            task: _selectedTask!,
                            relationCandidates: _tasks,
                            onTaskCreated: _upsertTask,
                            statuses: _statuses,
                            projects: _projects,
                            assignees: _assignees,
                            onUpdate: (data) =>
                                _updateTask(_selectedTask!, data),
                            onToggleComplete: () =>
                                _toggleComplete(_selectedTask!),
                            onDelete: () => _deleteTask(_selectedTask!),
                            onClose: () =>
                                setState(() => _selectedTask = null),
                          ),
                  ),
                ],
              ),
      ),
        ),
      ),
    );
  }

  Widget _buildMainContent(
    BuildContext context,
    double padding,
    bool isMobile,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final openCount = _tasks.where((e) => !e.isCompleted).length;
    final doneCount = _tasks.where((e) => e.isCompleted).length;

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        cacheExtent: 720,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(padding, 16, padding, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate.fixed([
                GlassSurface(
                  padding: const EdgeInsets.all(15),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _SummaryPill(
                        icon: Icons.pending_actions_outlined,
                        label: 'باز',
                        value: '$openCount',
                      ),
                      _SummaryPill(
                        icon: Icons.task_alt,
                        label: 'تکمیل‌شده',
                        value: '$doneCount',
                      ),
                      Chip(
                        avatar: Icon(
                          Icons.view_sidebar_outlined,
                          size: 18,
                          color: scheme.primary,
                        ),
                        label: const Text('Phase 2 · Task UX'),
                        backgroundColor:
                            scheme.primary.withValues(alpha: 0.08),
                        side: BorderSide(
                          color: scheme.primary.withValues(alpha: 0.24),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (widget.authStore.hasProjectPermission('task_create')) ...[
                  TaskQuickCreate(
                    enabled: !_loading,
                    onCreate: _quickCreate,
                  ),
                  const SizedBox(height: 12),
                ],
                _filters(context),
                const SizedBox(height: 12),
                if (_selectionMode) ...[
                  _bulkToolbar(context),
                  const SizedBox(height: 12),
                ],
              ]),
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_error != null)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              sliver: SliverToBoxAdapter(child: _errorCard(context)),
            )
          else if (_tasks.isEmpty)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              sliver: SliverToBoxAdapter(child: _emptyCard(context)),
            )
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              sliver: BoundedSliverList(
                itemCount: _tasks.length,
                itemBuilder: (context, index) {
                  final task = _tasks[index];
                  return Padding(
                    key: ValueKey(task.id),
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _TaskCard(
                      task: task,
                      priorityLabel: _priorityLabel(task.priority),
                      priorityColor: _priorityColor(context, task.priority),
                      selected: _selectedTask?.id == task.id ||
                          _selectedTaskIds.contains(task.id),
                      selectionMode: _selectionMode,
                      batchSelected: _selectedTaskIds.contains(task.id),
                      statuses: _statuses,
                      onOpen: () {
                        if (_selectionMode) {
                          _toggleSelection(
                            task.id,
                            !_selectedTaskIds.contains(task.id),
                          );
                        } else {
                          _openDetails(task);
                        }
                      },
                      onLongPress: () => _toggleSelection(task.id, true),
                      onSelectionChanged: (value) =>
                          _toggleSelection(task.id, value),
                      onToggle: () => _toggleComplete(task),
                      onStatusChanged: (statusId) =>
                          _updateTask(task, {'status_id': statusId}),
                    ),
                  );
                },
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              padding,
              6,
              padding,
              isMobile ? 32 : 32,
            ),
            sliver: SliverToBoxAdapter(
              child: !_loading && _taskPage < _taskPages
                  ? Center(
                      child: OutlinedButton.icon(
                        onPressed: _loadingMore ? null : _loadMoreTasks,
                        icon: _loadingMore
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.expand_more_rounded),
                        label: Text(
                          _loadingMore
                              ? 'در حال بارگذاری…'
                              : 'بارگذاری بیشتر ($_taskPage/$_taskPages)',
                        ),
                      ),
                    )
                  : const SizedBox(height: 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulkToolbar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSurface(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Chip(
            avatar: const Icon(Icons.checklist_rounded, size: 17),
            label: Text('${_selectedTaskIds.length} انتخاب‌شده'),
          ),
          TextButton.icon(
            onPressed: _selectAllLoaded,
            icon: const Icon(Icons.select_all_rounded),
            label: const Text('انتخاب همه بارگذاری‌شده'),
          ),
          PopupMenuButton<int>(
            enabled: _selectedTaskIds.isNotEmpty &&
                widget.authStore.hasProjectPermission('task_edit'),
            tooltip: 'تغییر گروهی وضعیت',
            onSelected: (value) => _bulkUpdate(statusId: value),
            itemBuilder: (_) => _statuses
                .map(
                  (status) => PopupMenuItem(
                    value: status.id,
                    child: Text(status.name),
                  ),
                )
                .toList(),
            child: const Chip(
              avatar: Icon(Icons.swap_horiz_rounded, size: 17),
              label: Text('وضعیت'),
            ),
          ),
          PopupMenuButton<String>(
            enabled: _selectedTaskIds.isNotEmpty &&
                widget.authStore.hasProjectPermission('task_edit'),
            tooltip: 'تغییر گروهی اولویت',
            onSelected: (value) => _bulkUpdate(priority: value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'low', child: Text('کم')),
              PopupMenuItem(value: 'normal', child: Text('معمولی')),
              PopupMenuItem(value: 'high', child: Text('زیاد')),
              PopupMenuItem(value: 'urgent', child: Text('فوری')),
            ],
            child: const Chip(
              avatar: Icon(Icons.priority_high_rounded, size: 17),
              label: Text('اولویت'),
            ),
          ),
          if (widget.authStore.hasProjectPermission('task_delete'))
            FilledButton.tonalIcon(
              onPressed:
                  _selectedTaskIds.isEmpty ? null : _bulkDelete,
              icon: Icon(Icons.delete_outline, color: scheme.error),
              label: Text(
                'حذف',
                style: TextStyle(color: scheme.error),
              ),
            ),
          TextButton(
            onPressed: () => _setSelectionMode(false),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
  }

  Widget _filters(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.all(13),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedViewId ?? 0,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'نماهای ذخیره‌شده',
                    prefixIcon: Icon(Icons.bookmarks_outlined),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('نمای فعلی / بدون نما'),
                    ),
                    ..._savedViews.map(
                      (view) => DropdownMenuItem(
                        value: view.id,
                        child: Row(
                          children: [
                            if (view.isShared)
                              const Padding(
                                padding: EdgeInsetsDirectional.only(end: 6),
                                child: Icon(Icons.groups_outlined, size: 17),
                              ),
                            Expanded(
                              child: Text(
                                view.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null || value == 0) {
                      setState(() => _selectedViewId = null);
                      _syncUrl();
                      return;
                    }
                    for (final view in _savedViews) {
                      if (view.id == value) {
                        _applySavedView(view);
                        break;
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 7),
              IconButton.filledTonal(
                tooltip: 'ذخیره فیلترهای فعلی',
                onPressed: _saveCurrentView,
                icon: const Icon(Icons.bookmark_add_outlined),
              ),
              if (_selectedViewId != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'حذف نمای انتخاب‌شده',
                  onPressed: _deleteSelectedView,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ),
          const SizedBox(height: 11),
          TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _reloadTasks(),
            decoration: InputDecoration(
              labelText: 'جستجوی کارها',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'جستجو',
                icon: const Icon(Icons.arrow_forward),
                onPressed: _reloadTasks,
              ),
            ),
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('باز'),
                selected: _completedFilter == false,
                onSelected: (_) {
                  setState(() {
                    _completedFilter = false;
                    _selectedViewId = null;
                  });
                  _reloadTasks();
                },
              ),
              ChoiceChip(
                label: const Text('تکمیل‌شده'),
                selected: _completedFilter == true,
                onSelected: (_) {
                  setState(() {
                    _completedFilter = true;
                    _selectedViewId = null;
                  });
                  _reloadTasks();
                },
              ),
              ChoiceChip(
                label: const Text('همه'),
                selected: _completedFilter == null,
                onSelected: (_) {
                  setState(() {
                    _completedFilter = null;
                    _selectedViewId = null;
                  });
                  _reloadTasks();
                },
              ),
              SizedBox(
                width: 205,
                child: DropdownButtonFormField<int>(
                  value: _statusFilterId ?? 0,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'وضعیت',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('همه وضعیت‌ها'),
                    ),
                    ..._statuses.map(
                      (status) => DropdownMenuItem(
                        value: status.id,
                        child: Text(status.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _statusFilterId =
                          value == null || value == 0 ? null : value;
                      _selectedViewId = null;
                    });
                    _reloadTasks();
                  },
                ),
              ),
              SizedBox(
                width: 235,
                child: DropdownButtonFormField<int>(
                  value: _projectFilterId ?? 0,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'پروژه',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('همه پروژه‌ها'),
                    ),
                    ..._projects.map(
                      (project) => DropdownMenuItem(
                        value: project.id,
                        child: Text(
                          '${project.code} · ${project.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _projectFilterId =
                          value == null || value == 0 ? null : value;
                      _selectedViewId = null;
                    });
                    _reloadTasks();
                  },
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int>(
                  value: _assigneeFilterId ?? 0,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'مسئول',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('همه مسئولان'),
                    ),
                    ..._assignees.map(
                      (user) => DropdownMenuItem(
                        value: user.userId,
                        child: Text(
                          user.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _assigneeFilterId =
                          value == null || value == 0 ? null : value;
                      _selectedViewId = null;
                    });
                    _reloadTasks();
                  },
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<int>(
                  value: _labelFilterId ?? 0,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'برچسب',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('همه برچسب‌ها'),
                    ),
                    ..._labels.map(
                      (label) => DropdownMenuItem(
                        value: label.id,
                        child: Text(label.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _labelFilterId =
                          value == null || value == 0 ? null : value;
                      _selectedViewId = null;
                    });
                    _reloadTasks();
                  },
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int>(
                  value: _creatorFilterId ?? 0,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'ایجادکننده',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('همه ایجادکنندگان'),
                    ),
                    ..._assignees.map(
                      (user) => DropdownMenuItem(
                        value: user.userId,
                        child: Text(
                          user.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _creatorFilterId =
                          value == null || value == 0 ? null : value;
                      _selectedViewId = null;
                    });
                    _reloadTasks();
                  },
                ),
              ),
              SizedBox(
                width: 165,
                child: DropdownButtonFormField<String>(
                  value: _priorityFilter ?? 'all',
                  decoration: const InputDecoration(
                    labelText: 'اولویت',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('همه')),
                    DropdownMenuItem(value: 'low', child: Text('کم')),
                    DropdownMenuItem(
                      value: 'normal',
                      child: Text('معمولی'),
                    ),
                    DropdownMenuItem(value: 'high', child: Text('زیاد')),
                    DropdownMenuItem(value: 'urgent', child: Text('فوری')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _priorityFilter =
                          value == null || value == 'all' ? null : value;
                      _selectedViewId = null;
                    });
                    _reloadTasks();
                  },
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _duePreset,
                  decoration: const InputDecoration(
                    labelText: 'سررسید',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'any', child: Text('همه')),
                    DropdownMenuItem(
                      value: 'overdue',
                      child: Text('گذشته'),
                    ),
                    DropdownMenuItem(value: 'today', child: Text('امروز')),
                    DropdownMenuItem(
                      value: 'next7',
                      child: Text('۷ روز آینده'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _duePreset = value ?? 'any';
                      _selectedViewId = null;
                    });
                    _reloadTasks();
                  },
                ),
              ),
              SizedBox(
                width: 195,
                child: DropdownButtonFormField<String>(
                  value: _sortBy ?? 'default',
                  decoration: const InputDecoration(
                    labelText: 'مرتب‌سازی',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'default',
                      child: Text('پیش‌فرض'),
                    ),
                    DropdownMenuItem(
                      value: 'due_at',
                      child: Text('سررسید'),
                    ),
                    DropdownMenuItem(
                      value: 'created_at',
                      child: Text('تاریخ ایجاد'),
                    ),
                    DropdownMenuItem(
                      value: 'updated_at',
                      child: Text('آخرین تغییر'),
                    ),
                    DropdownMenuItem(value: 'title', child: Text('عنوان')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _sortBy =
                          value == null || value == 'default' ? null : value;
                      _selectedViewId = null;
                    });
                    _reloadTasks();
                  },
                ),
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'asc', label: Text('صعودی')),
                  ButtonSegment(value: 'desc', label: Text('نزولی')),
                ],
                selected: {_sortDir},
                onSelectionChanged: (values) {
                  setState(() {
                    _sortDir = values.first;
                    _selectedViewId = null;
                  });
                  _reloadTasks();
                },
              ),
              OutlinedButton.icon(
                onPressed: _resetFilters,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('پاک کردن'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined, size: 42, color: scheme.error),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
            label: const Text('تلاش مجدد'),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
      child: Column(
        children: [
          Icon(Icons.task_alt_outlined, size: 52, color: scheme.outline),
          const SizedBox(height: 12),
          const Text(
            'کاری برای این فیلتر وجود ندارد. از کادر بالا یک کار جدید بسازید.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 7),
          Text('$label: $value'),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskModel task;
  final String priorityLabel;
  final Color priorityColor;
  final bool selected;
  final bool selectionMode;
  final bool batchSelected;
  final List<TaskStatusModel> statuses;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onToggle;
  final Future<TaskModel?> Function(int statusId) onStatusChanged;

  const _TaskCard({
    required this.task,
    required this.priorityLabel,
    required this.priorityColor,
    required this.selected,
    required this.selectionMode,
    required this.batchSelected,
    required this.statuses,
    required this.onOpen,
    required this.onLongPress,
    required this.onSelectionChanged,
    required this.onToggle,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final due = task.dueAt?.toLocal();
    final overdue =
        due != null && !task.isCompleted && due.isBefore(DateTime.now());
    final meta = <String>[
      if (task.projectName != null && task.projectName!.isNotEmpty)
        task.projectName!,
      if (task.assignees.isNotEmpty)
        task.assignees.map((e) => e.name).join('، '),
      if (due != null) 'سررسید ${DateFormat('yyyy/MM/dd').format(due)}',
    ];

    return GlassSurface(
      opacity: selected
          ? (Theme.of(context).brightness == Brightness.dark ? 0.12 : 0.76)
          : null,
      border: Border.all(
        color: selected
            ? scheme.primary.withValues(alpha: 0.48)
            : GlassStyle.border(context),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: selectionMode ? batchSelected : task.isCompleted,
            shape: selectionMode ? const CircleBorder() : null,
            onChanged: (value) {
              if (selectionMode) {
                onSelectionChanged(value == true);
              } else {
                onToggle();
              }
            },
          ),
          const SizedBox(width: 5),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onOpen,
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            decoration: task.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (task.description != null &&
                        task.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        task.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        meta.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: overdue ? scheme.error : scheme.outline,
                            ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        PopupMenuButton<int>(
                          tooltip: 'تغییر وضعیت',
                          onSelected: onStatusChanged,
                          itemBuilder: (context) => statuses
                              .map(
                                (status) => PopupMenuItem<int>(
                                  value: status.id,
                                  child: Text(status.name),
                                ),
                              )
                              .toList(),
                          child: Chip(
                            label: Text(task.status?.name ?? 'Status'),
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(
                              Icons.expand_more_rounded,
                              size: 16,
                            ),
                          ),
                        ),
                        Chip(
                          label: Text(priorityLabel),
                          visualDensity: VisualDensity.compact,
                          backgroundColor:
                              priorityColor.withValues(alpha: 0.12),
                          side: BorderSide(
                            color: priorityColor.withValues(alpha: 0.32),
                          ),
                        ),
                        ...task.labels.map(
                          (label) => Chip(
                            label: Text(label.name),
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(
                              Icons.label_outline,
                              size: 15,
                            ),
                          ),
                        ),
                        if (overdue)
                          Chip(
                            avatar: Icon(
                              Icons.warning_amber_rounded,
                              size: 17,
                              color: scheme.error,
                            ),
                            label: const Text('سررسید گذشته'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'جزئیات',
            onPressed: onOpen,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
        ],
      ),
    );
  }
}
