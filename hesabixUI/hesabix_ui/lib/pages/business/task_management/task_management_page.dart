import 'dart:math' as math;
import 'dart:ui' as ui;

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
  final TextEditingController _quickCreateController = TextEditingController();

  List<TaskModel> _tasks = const [];
  List<TaskStatusModel> _statuses = const [];
  List<ProjectModel> _projects = const [];
  List<TaskAssigneeOption> _assignees = const [];

  bool _loading = true;
  bool _quickCreating = false;
  String? _error;
  bool? _completedFilter = false;
  int? _statusFilterId;

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
    _quickCreateController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final statuses = await _taskService.listStatuses(widget.businessId);
      final assignees = await _taskService.listAssignees(widget.businessId);
      final projects =
          await _projectService.listActiveProjects(widget.businessId);
      final tasksResult = await _taskService.listTasks(
        businessId: widget.businessId,
        search: _searchController.text,
        statusId: _statusFilterId,
        completed: _completedFilter,
      );
      if (!mounted) return;
      setState(() {
        _statuses = statuses;
        _assignees = assignees;
        _projects = projects;
        _tasks = (tasksResult['items'] as List<TaskModel>?) ?? const [];
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

  Future<void> _reloadTasks() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _taskService.listTasks(
        businessId: widget.businessId,
        search: _searchController.text,
        statusId: _statusFilterId,
        completed: _completedFilter,
      );
      if (!mounted) return;
      setState(() {
        _tasks = (result['items'] as List<TaskModel>?) ?? const [];
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

  bool _matchesCurrentFilters(TaskModel task) {
    if (_completedFilter != null && task.isCompleted != _completedFilter) {
      return false;
    }
    if (_statusFilterId != null && task.statusId != _statusFilterId) {
      return false;
    }
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      final haystack =
          '${task.title} ${task.description ?? ''}'.toLowerCase();
      if (!haystack.contains(query)) return false;
    }
    return true;
  }

  void _applyTaskChange(TaskModel task) {
    if (!mounted) return;
    setState(() {
      final next = List<TaskModel>.from(_tasks)
        ..removeWhere((item) => item.id == task.id);
      if (_matchesCurrentFilters(task)) {
        next.insert(0, task);
      }
      _tasks = next;
    });
  }

  void _removeTask(int taskId) {
    if (!mounted) return;
    setState(() {
      _tasks = _tasks.where((task) => task.id != taskId).toList();
    });
  }

  Future<void> _quickCreate() async {
    final title = _quickCreateController.text.trim();
    if (title.isEmpty || _quickCreating) return;

    setState(() => _quickCreating = true);
    try {
      final created = await _taskService.createTask(
        businessId: widget.businessId,
        data: {'title': title},
      );
      if (!mounted) return;
      _quickCreateController.clear();
      _applyTaskChange(created);
      SnackBarHelper.showSuccess(context, message: 'کار ایجاد شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    } finally {
      if (mounted) setState(() => _quickCreating = false);
    }
  }

  Future<void> _openTaskPanel([TaskModel? task]) async {
    if (_statuses.isEmpty) {
      SnackBarHelper.showError(
        context,
        message: 'وضعیت‌های کار هنوز بارگذاری نشده‌اند.',
      );
      return;
    }

    final panel = _TaskDetailPanel(
      businessId: widget.businessId,
      taskService: _taskService,
      initialTask: task,
      statuses: _statuses,
      projects: _projects,
      assignees: _assignees,
      onTaskChanged: _applyTaskChange,
      onTaskDeleted: _removeTask,
    );

    if (ResponsiveHelper.isMobile(context)) {
      await showGlassModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => FractionallySizedBox(
          heightFactor: 0.96,
          child: panel,
        ),
      );
      return;
    }

    await _showGlassSidePanel<void>(
      context: context,
      builder: (_) => panel,
    );
  }

  Future<void> _toggleComplete(TaskModel task) async {
    try {
      final updated = task.isCompleted
          ? await _taskService.reopenTask(
              businessId: widget.businessId,
              taskId: task.id,
            )
          : await _taskService.completeTask(
              businessId: widget.businessId,
              taskId: task.id,
            );
      if (!mounted) return;
      _applyTaskChange(updated);
      SnackBarHelper.showSuccess(
        context,
        message: task.isCompleted ? 'کار دوباره باز شد' : 'کار تکمیل شد',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Future<void> _changeStatus(TaskModel task, int statusId) async {
    if (task.statusId == statusId) return;
    try {
      final updated = await _taskService.updateTask(
        businessId: widget.businessId,
        taskId: task.id,
        data: {'status_id': statusId},
      );
      if (!mounted) return;
      _applyTaskChange(updated);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
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
    final scheme = Theme.of(context).colorScheme;
    final openCount = _tasks.where((e) => !e.isCompleted).length;
    final doneCount = _tasks.where((e) => e.isCompleted).length;

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
          if (!isMobile)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: FilledButton.icon(
                onPressed: _loading ? null : () => _openTaskPanel(),
                icon: const Icon(Icons.add_task),
                label: const Text('کار جدید'),
              ),
            ),
        ],
      ),
      floatingActionButton: isMobile
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : () => _openTaskPanel(),
              icon: const Icon(Icons.add_task),
              label: const Text('کار جدید'),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              padding,
              16,
              padding,
              isMobile ? 96 : 32,
            ),
            children: [
              GlassSurface(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
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
              GlassSurface(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _quickCreateController,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _quickCreate(),
                            decoration: const InputDecoration(
                              hintText: 'عنوان کار جدید را بنویسید و Enter بزنید…',
                              prefixIcon: Icon(Icons.add_task_outlined),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'ایجاد سریع',
                          onPressed: _quickCreating ? null : _quickCreate,
                          icon: _quickCreating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _reloadTasks(),
                      decoration: InputDecoration(
                        labelText: 'جستجوی کارها',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          tooltip: 'جستجو',
                          icon: const Icon(Icons.search_rounded),
                          onPressed: _reloadTasks,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
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
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 64),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                GlassSurface(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 42,
                        color: scheme.error,
                      ),
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
                )
              else if (_tasks.isEmpty)
                GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 54,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.task_alt_outlined,
                        size: 54,
                        color: scheme.outline,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'کاری برای این فیلتر وجود ندارد.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _openTaskPanel(),
                        icon: const Icon(Icons.add),
                        label: const Text('ایجاد اولین کار'),
                      ),
                    ],
                  ),
                )
              else
                ..._tasks.map(
                  (task) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TaskCard(
                      task: task,
                      statuses: _statuses,
                      priorityLabel: _priorityLabel(task.priority),
                      priorityColor: _priorityColor(context, task.priority),
                      onToggle: () => _toggleComplete(task),
                      onOpen: () => _openTaskPanel(task),
                      onStatusChanged: (id) => _changeStatus(task, id),
                    ),
                  ),
                ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
          const SizedBox(width: 8),
          Text('$label: $value'),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskModel task;
  final List<TaskStatusModel> statuses;
  final String priorityLabel;
  final Color priorityColor;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final ValueChanged<int> onStatusChanged;

  const _TaskCard({
    required this.task,
    required this.statuses,
    required this.priorityLabel,
    required this.priorityColor,
    required this.onToggle,
    required this.onOpen,
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
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: task.isCompleted,
            onChanged: (_) => onToggle(),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
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
                      const SizedBox(height: 5),
                      Text(
                        task.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        meta.join(' · '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: overdue ? scheme.error : scheme.outline,
                            ),
                      ),
                    ],
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        PopupMenuButton<int>(
                          tooltip: 'تغییر وضعیت',
                          onSelected: onStatusChanged,
                          itemBuilder: (_) => statuses
                              .map(
                                (status) => PopupMenuItem<int>(
                                  value: status.id,
                                  child: Row(
                                    children: [
                                      if (status.id == task.statusId)
                                        const Padding(
                                          padding:
                                              EdgeInsetsDirectional.only(end: 8),
                                          child: Icon(Icons.check, size: 18),
                                        ),
                                      Text(status.name),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                          child: Chip(
                            avatar:
                                const Icon(Icons.swap_horiz_rounded, size: 16),
                            label: Text(task.status?.name ?? 'وضعیت'),
                            visualDensity: VisualDensity.compact,
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
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'باز کردن جزئیات',
            icon: const Icon(Icons.chevron_right),
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

class _TaskDetailPanel extends StatefulWidget {
  final int businessId;
  final TaskService taskService;
  final TaskModel? initialTask;
  final List<TaskStatusModel> statuses;
  final List<ProjectModel> projects;
  final List<TaskAssigneeOption> assignees;
  final ValueChanged<TaskModel> onTaskChanged;
  final ValueChanged<int> onTaskDeleted;

  const _TaskDetailPanel({
    required this.businessId,
    required this.taskService,
    required this.initialTask,
    required this.statuses,
    required this.projects,
    required this.assignees,
    required this.onTaskChanged,
    required this.onTaskDeleted,
  });

  @override
  State<_TaskDetailPanel> createState() => _TaskDetailPanelState();
}

class _TaskDetailPanelState extends State<_TaskDetailPanel> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  TaskModel? _task;
  late int _projectId;
  late int _statusId;
  late String _priority;
  late Set<int> _assigneeIds;
  DateTime? _dueDate;
  bool _saving = false;
  bool _togglingComplete = false;
  bool _deleting = false;
  String? _error;

  bool get _editing => _task != null;

  @override
  void initState() {
    super.initState();
    _task = widget.initialTask;
    _titleController = TextEditingController(text: _task?.title ?? '');
    _descriptionController =
        TextEditingController(text: _task?.description ?? '');
    _projectId = _task?.projectId ?? 0;
    _priority = _task?.priority ?? 'normal';
    _dueDate = _task?.dueAt?.toLocal();
    _assigneeIds = _task?.assignees.map((e) => e.userId).toSet() ?? <int>{};

    TaskStatusModel? defaultStatus;
    for (final status in widget.statuses) {
      if (status.isDefault) {
        defaultStatus = status;
        break;
      }
    }
    _statusId = _task?.statusId ??
        defaultStatus?.id ??
        (widget.statuses.isNotEmpty ? widget.statuses.first.id : 0);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    var selected = _dueDate ?? DateTime.now();
    final result = await showGlassDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('تاریخ سررسید'),
          content: SizedBox(
            width: 360,
            height: 330,
            child: CalendarDatePicker(
              initialDate: selected,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 3650)),
              onDateChanged: (value) {
                setDialogState(() => selected = value);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('انتخاب'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _dueDate = result);
    }
  }

  Map<String, dynamic> _payload() {
    final due = _dueDate == null
        ? null
        : DateTime(
            _dueDate!.year,
            _dueDate!.month,
            _dueDate!.day,
            17,
          ).toUtc();

    return {
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      'project_id': _projectId == 0 ? null : _projectId,
      'status_id': _statusId == 0 ? null : _statusId,
      'priority': _priority,
      'due_at': due?.toIso8601String(),
      'assignee_user_ids': _assigneeIds.toList(),
    };
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final updated = _task == null
          ? await widget.taskService.createTask(
              businessId: widget.businessId,
              data: _payload(),
            )
          : await widget.taskService.updateTask(
              businessId: widget.businessId,
              taskId: _task!.id,
              data: _payload(),
            );
      if (!mounted) return;
      setState(() {
        _task = updated;
        _projectId = updated.projectId ?? 0;
        _statusId = updated.statusId ?? _statusId;
        _priority = updated.priority;
        _dueDate = updated.dueAt?.toLocal();
        _assigneeIds = updated.assignees.map((e) => e.userId).toSet();
        _saving = false;
      });
      widget.onTaskChanged(updated);
      SnackBarHelper.showSuccess(
        context,
        message: widget.initialTask == null ? 'کار ایجاد شد' : 'تغییرات ذخیره شد',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = ErrorExtractor.forContext(e, context);
      });
    }
  }

  Future<void> _toggleComplete() async {
    final current = _task;
    if (current == null || _togglingComplete) return;

    setState(() => _togglingComplete = true);
    try {
      final updated = current.isCompleted
          ? await widget.taskService.reopenTask(
              businessId: widget.businessId,
              taskId: current.id,
            )
          : await widget.taskService.completeTask(
              businessId: widget.businessId,
              taskId: current.id,
            );
      if (!mounted) return;
      setState(() {
        _task = updated;
        _statusId = updated.statusId ?? _statusId;
        _togglingComplete = false;
      });
      widget.onTaskChanged(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _togglingComplete = false;
        _error = ErrorExtractor.forContext(e, context);
      });
    }
  }

  Future<void> _delete() async {
    final current = _task;
    if (current == null || _deleting) return;

    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف کار'),
        content: Text('«${current.title}» حذف شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await widget.taskService.deleteTask(
        businessId: widget.businessId,
        taskId: current.id,
      );
      if (!mounted) return;
      widget.onTaskDeleted(current.id);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = ErrorExtractor.forContext(e, context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = _task;

    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
            child: Row(
              children: [
                Icon(
                  _editing ? Icons.task_alt_outlined : Icons.add_task,
                  color: scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _editing ? 'TASK-${current!.id}' : 'کار جدید',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (_editing)
                  Tooltip(
                    message: current!.isCompleted ? 'بازگشایی' : 'تکمیل',
                    child: IconButton(
                      onPressed: _togglingComplete ? null : _toggleComplete,
                      icon: _togglingComplete
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              current.isCompleted
                                  ? Icons.undo_rounded
                                  : Icons.check_circle_outline,
                            ),
                    ),
                  ),
                if (_editing)
                  IconButton(
                    tooltip: 'حذف',
                    onPressed: _deleting ? null : _delete,
                    icon: Icon(Icons.delete_outline, color: scheme.error),
                  ),
                IconButton(
                  tooltip: 'بستن',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _titleController,
                      autofocus: !_editing,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      decoration: const InputDecoration(
                        labelText: 'عنوان',
                        prefixIcon: Icon(Icons.title),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'عنوان الزامی است';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _descriptionController,
                      minLines: 4,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        labelText: 'توضیحات',
                        alignLabelWithHint: true,
                        prefixIcon: Padding(
                          padding: EdgeInsets.only(bottom: 72),
                          child: Icon(Icons.notes),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'ویژگی‌ها',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 10),
                    _PropertyRow(
                      icon: Icons.radio_button_checked_outlined,
                      label: 'وضعیت',
                      child: DropdownButtonFormField<int>(
                        value: _statusId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                        ),
                        items: widget.statuses
                            .map(
                              (status) => DropdownMenuItem(
                                value: status.id,
                                child: Text(status.name),
                              ),
                            )
                            .toList(),
                        onChanged: _saving
                            ? null
                            : (value) =>
                                setState(() => _statusId = value ?? _statusId),
                      ),
                    ),
                    _PropertyRow(
                      icon: Icons.flag_outlined,
                      label: 'اولویت',
                      child: DropdownButtonFormField<String>(
                        value: _priority,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'low', child: Text('کم')),
                          DropdownMenuItem(
                            value: 'normal',
                            child: Text('معمولی'),
                          ),
                          DropdownMenuItem(value: 'high', child: Text('زیاد')),
                          DropdownMenuItem(
                            value: 'urgent',
                            child: Text('فوری'),
                          ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => setState(
                                  () => _priority = value ?? 'normal',
                                ),
                      ),
                    ),
                    _PropertyRow(
                      icon: Icons.folder_open_outlined,
                      label: 'پروژه',
                      child: DropdownButtonFormField<int>(
                        value: _projectId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 0,
                            child: Text('بدون پروژه'),
                          ),
                          ...widget.projects.map(
                            (project) => DropdownMenuItem(
                              value: project.id,
                              child: Text(
                                '${project.code} · ${project.name}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) =>
                                setState(() => _projectId = value ?? 0),
                      ),
                    ),
                    _PropertyRow(
                      icon: Icons.event_outlined,
                      label: 'سررسید',
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _dueDate == null
                                  ? 'بدون سررسید'
                                  : DateFormat('yyyy/MM/dd').format(_dueDate!),
                            ),
                          ),
                          if (_dueDate != null)
                            IconButton(
                              tooltip: 'پاک کردن',
                              onPressed: _saving
                                  ? null
                                  : () => setState(() => _dueDate = null),
                              icon: const Icon(Icons.clear, size: 19),
                            ),
                          IconButton(
                            tooltip: 'انتخاب تاریخ',
                            onPressed: _saving ? null : _pickDueDate,
                            icon: const Icon(
                              Icons.calendar_month_outlined,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'مسئولان',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 10),
                    if (widget.assignees.isEmpty)
                      Text(
                        'عضوی برای تخصیص وجود ندارد.',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.assignees.map((user) {
                          final selected = _assigneeIds.contains(user.userId);
                          return FilterChip(
                            selected: selected,
                            avatar: CircleAvatar(
                              radius: 11,
                              child: Text(
                                user.name.trim().isEmpty
                                    ? '?'
                                    : user.name.trim().characters.first,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            label: Text(user.name),
                            onSelected: _saving
                                ? null
                                : (value) {
                                    setState(() {
                                      if (value) {
                                        _assigneeIds.add(user.userId);
                                      } else {
                                        _assigneeIds.remove(user.userId);
                                      }
                                    });
                                  },
                          );
                        }).toList(),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_editing ? 'ذخیره تغییرات' : 'ایجاد کار'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PropertyRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;

  const _PropertyRow({
    required this.icon,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 8, 6),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: scheme.outline),
          const SizedBox(width: 9),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

Future<T?> _showGlassSidePanel<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final label = MaterialLocalizations.of(context).modalBarrierDismissLabel;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierLabel: label,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 190),
    pageBuilder: (routeContext, animation, secondaryAnimation) {
      final size = MediaQuery.sizeOf(routeContext);
      final width = math.min(680.0, size.width * 0.82);
      final slide = Tween<Offset>(
        begin: const Offset(0.08, 0),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      );

      return Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: GlassStyle.strongModalBlur,
                  sigmaY: GlassStyle.strongModalBlur,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(routeContext).pop(),
                  child: ColoredBox(
                    color: GlassStyle.modalBarrier(routeContext),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: SlideTransition(
                position: slide,
                child: SafeArea(
                  left: false,
                  child: SizedBox(
                    width: width,
                    height: size.height,
                    child: GlassSurface(
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(24),
                      ),
                      blur: GlassStyle.strongModalBlur,
                      opacity:
                          Theme.of(routeContext).brightness == Brightness.dark
                              ? 0.22
                              : 0.62,
                      child: builder(routeContext),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
