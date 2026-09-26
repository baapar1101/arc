import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/project_model.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/project_service.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/task/task_detail_drawer.dart';
import 'package:hesabix_ui/widgets/task/task_quick_create.dart';
import 'package:intl/intl.dart';

class TaskManagementPage extends StatefulWidget {
  final int businessId;

  const TaskManagementPage({
    super.key,
    required this.businessId,
  });

  @override
  State<TaskManagementPage> createState() => _TaskManagementPageState();
}

class _TaskManagementPageState extends State<TaskManagementPage> {
  late final TaskService _taskService;
  late final ProjectService _projectService;
  final TextEditingController _searchController = TextEditingController();

  List<TaskModel> _tasks = const [];
  List<TaskStatusModel> _statuses = const [];
  List<ProjectModel> _projects = const [];
  List<TaskAssigneeOption> _assignees = const [];

  bool _loading = true;
  String? _error;
  bool? _completedFilter = false;
  int? _statusFilterId;
  TaskModel? _selectedTask;

  @override
  void initState() {
    super.initState();
    _taskService = TaskService(ApiClient());
    _projectService = ProjectService(ApiClient());
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      final projectsFuture =
          _projectService.listActiveProjects(widget.businessId);
      final tasksFuture = _loadTasksRequest();

      final results = await Future.wait<dynamic>([
        statusesFuture,
        assigneesFuture,
        projectsFuture,
        tasksFuture,
      ]);

      if (!mounted) return;
      final nextTasks =
          (results[3] as Map<String, dynamic>)['items'] as List<TaskModel>? ??
              const <TaskModel>[];
      setState(() {
        _statuses = results[0] as List<TaskStatusModel>;
        _assignees = results[1] as List<TaskAssigneeOption>;
        _projects = results[2] as List<ProjectModel>;
        _tasks = nextTasks;
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

  Future<Map<String, dynamic>> _loadTasksRequest() {
    return _taskService.listTasks(
      businessId: widget.businessId,
      search: _searchController.text,
      statusId: _statusFilterId,
      completed: _completedFilter,
    );
  }

  Future<void> _reloadTasks() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _loadTasksRequest();
      final nextTasks =
          (result['items'] as List<TaskModel>?) ?? const <TaskModel>[];
      if (!mounted) return;
      setState(() {
        _tasks = nextTasks;
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
    if (!visibleByCompletion || !visibleByStatus) {
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
        data: {'title': title},
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
    try {
      final updated = await _taskService.updateTask(
        businessId: widget.businessId,
        taskId: source.id,
        data: data,
      );
      _upsertTask(updated);
      return updated;
    } catch (e) {
      if (!mounted) return null;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
      rethrow;
    }
  }

  Future<TaskModel?> _toggleComplete(TaskModel source) async {
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
      _upsertTask(updated);
      if (mounted) {
        SnackBarHelper.showSuccess(
          context,
          message: updated.isCompleted ? 'کار تکمیل شد' : 'کار دوباره باز شد',
        );
      }
      return updated;
    } catch (e) {
      if (!mounted) return null;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
      rethrow;
    }
  }

  Future<bool> _deleteTask(TaskModel source) async {
    try {
      await _taskService.deleteTask(
        businessId: widget.businessId,
        taskId: source.id,
      );
      if (!mounted) return false;
      setState(() {
        _tasks = _tasks.where((item) => item.id != source.id).toList();
        if (_selectedTask?.id == source.id) _selectedTask = null;
      });
      SnackBarHelper.showSuccess(context, message: 'کار حذف شد');
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
                task: liveTask,
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
    final body = _buildMainContent(context, padding, isMobile);

    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت کارها'),
        leading: IconButton(
          tooltip: 'بازگشت به پروژه‌ها',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/business/${widget.businessId}/projects'),
        ),
        actions: [
          IconButton(
            tooltip: 'بروزرسانی',
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: isMobile
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
                            task: _selectedTask!,
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
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          padding,
          16,
          padding,
          isMobile ? 32 : 32,
        ),
        children: [
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
                  backgroundColor: scheme.primary.withValues(alpha: 0.08),
                  side: BorderSide(
                    color: scheme.primary.withValues(alpha: 0.24),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TaskQuickCreate(
            enabled: !_loading,
            onCreate: _quickCreate,
          ),
          const SizedBox(height: 12),
          _filters(context),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _errorCard(context)
          else if (_tasks.isEmpty)
            _emptyCard(context)
          else
            ..._tasks.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _TaskCard(
                  task: task,
                  priorityLabel: _priorityLabel(task.priority),
                  priorityColor: _priorityColor(context, task.priority),
                  selected: _selectedTask?.id == task.id,
                  statuses: _statuses,
                  onOpen: () => _openDetails(task),
                  onToggle: () => _toggleComplete(task),
                  onStatusChanged: (statusId) =>
                      _updateTask(task, {'status_id': statusId}),
                ),
              ),
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
          TextField(
            controller: _searchController,
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
                  setState(() => _completedFilter = false);
                  _reloadTasks();
                },
              ),
              ChoiceChip(
                label: const Text('تکمیل‌شده'),
                selected: _completedFilter == true,
                onSelected: (_) {
                  setState(() => _completedFilter = true);
                  _reloadTasks();
                },
              ),
              ChoiceChip(
                label: const Text('همه'),
                selected: _completedFilter == null,
                onSelected: (_) {
                  setState(() => _completedFilter = null);
                  _reloadTasks();
                },
              ),
              SizedBox(
                width: 220,
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
                    });
                    _reloadTasks();
                  },
                ),
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
  final List<TaskStatusModel> statuses;
  final VoidCallback onOpen;
  final VoidCallback onToggle;
  final Future<TaskModel?> Function(int statusId) onStatusChanged;

  const _TaskCard({
    required this.task,
    required this.priorityLabel,
    required this.priorityColor,
    required this.selected,
    required this.statuses,
    required this.onOpen,
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
            value: task.isCompleted,
            onChanged: (_) => onToggle(),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onOpen,
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
