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

  List<TaskModel> _tasks = const [];
  List<TaskStatusModel> _statuses = const [];
  List<ProjectModel> _projects = const [];
  List<TaskAssigneeOption> _assignees = const [];

  bool _loading = true;
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
      final projects = await _projectService.listActiveProjects(widget.businessId);
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

  Future<void> _openForm([TaskModel? task]) async {
    if (_statuses.isEmpty) {
      SnackBarHelper.showError(
        context,
        message: 'وضعیت‌های کار هنوز بارگذاری نشده‌اند.',
      );
      return;
    }
    final changed = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => _TaskFormDialog(
        businessId: widget.businessId,
        taskService: _taskService,
        task: task,
        statuses: _statuses,
        projects: _projects,
        assignees: _assignees,
      ),
    );
    if (changed == true) {
      await _reloadTasks();
    }
  }

  Future<void> _toggleComplete(TaskModel task) async {
    try {
      if (task.isCompleted) {
        await _taskService.reopenTask(
          businessId: widget.businessId,
          taskId: task.id,
        );
        if (mounted) {
          SnackBarHelper.showSuccess(context, message: 'کار دوباره باز شد');
        }
      } else {
        await _taskService.completeTask(
          businessId: widget.businessId,
          taskId: task.id,
        );
        if (mounted) {
          SnackBarHelper.showSuccess(context, message: 'کار تکمیل شد');
        }
      }
      await _reloadTasks();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Future<void> _deleteTask(TaskModel task) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف کار'),
        content: Text('«${task.title}» حذف شود؟'),
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
    if (confirmed != true) return;

    try {
      await _taskService.deleteTask(
        businessId: widget.businessId,
        taskId: task.id,
      );
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: 'کار حذف شد');
      }
      await _reloadTasks();
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
                onPressed: _loading ? null : () => _openForm(),
                icon: const Icon(Icons.add_task),
                label: const Text('کار جدید'),
              ),
            ),
        ],
      ),
      floatingActionButton: isMobile
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : () => _openForm(),
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
                        Icons.check_circle_outline,
                        size: 18,
                        color: scheme.primary,
                      ),
                      label: const Text('Phase 1 · Core Task Engine'),
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
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                      ),
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
                        onPressed: () => _openForm(),
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
                      priorityLabel: _priorityLabel(task.priority),
                      priorityColor: _priorityColor(context, task.priority),
                      onToggle: () => _toggleComplete(task),
                      onEdit: () => _openForm(task),
                      onDelete: () => _deleteTask(task),
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
  final String priorityLabel;
  final Color priorityColor;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TaskCard({
    required this.task,
    required this.priorityLabel,
    required this.priorityColor,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final due = task.dueAt?.toLocal();
    final overdue = due != null &&
        !task.isCompleted &&
        due.isBefore(DateTime.now());

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
              onTap: onEdit,
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
                      children: [
                        if (task.status != null)
                          Chip(
                            label: Text(task.status!.name),
                            visualDensity: VisualDensity.compact,
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
          Column(
            children: [
              IconButton(
                tooltip: 'ویرایش',
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
              IconButton(
                tooltip: 'حذف',
                icon: Icon(Icons.delete_outline, color: scheme.error),
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskFormDialog extends StatefulWidget {
  final int businessId;
  final TaskService taskService;
  final TaskModel? task;
  final List<TaskStatusModel> statuses;
  final List<ProjectModel> projects;
  final List<TaskAssigneeOption> assignees;

  const _TaskFormDialog({
    required this.businessId,
    required this.taskService,
    required this.task,
    required this.statuses,
    required this.projects,
    required this.assignees,
  });

  @override
  State<_TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<_TaskFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late int _projectId;
  late int _statusId;
  late int _assigneeUserId;
  late String _priority;
  DateTime? _dueDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _descriptionController = TextEditingController(text: task?.description ?? '');
    _projectId = task?.projectId ?? 0;
    _assigneeUserId =
        task != null && task.assignees.isNotEmpty ? task.assignees.first.userId : 0;
    _priority = task?.priority ?? 'normal';
    _dueDate = task?.dueAt?.toLocal();

    TaskStatusModel? defaultStatus;
    for (final status in widget.statuses) {
      if (status.isDefault) {
        defaultStatus = status;
        break;
      }
    }
    _statusId = task?.statusId ??
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

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final due = _dueDate == null
        ? null
        : DateTime(
            _dueDate!.year,
            _dueDate!.month,
            _dueDate!.day,
            17,
          ).toUtc();

    final data = <String, dynamic>{
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      'project_id': _projectId == 0 ? null : _projectId,
      'status_id': _statusId == 0 ? null : _statusId,
      'priority': _priority,
      'due_at': due?.toIso8601String(),
      'assignee_user_ids':
          _assigneeUserId == 0 ? <int>[] : <int>[_assigneeUserId],
    };

    try {
      if (widget.task == null) {
        await widget.taskService.createTask(
          businessId: widget.businessId,
          data: data,
        );
      } else {
        await widget.taskService.updateTask(
          businessId: widget.businessId,
          taskId: widget.task!.id,
          data: data,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = ErrorExtractor.forContext(e, context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.task != null;

    return AlertDialog(
      title: Text(editing ? 'ویرایش کار' : 'کار جدید'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _titleController,
                  autofocus: !editing,
                  decoration: const InputDecoration(
                    labelText: 'عنوان',
                    prefixIcon: Icon(Icons.task_alt_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'عنوان الزامی است';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'توضیحات',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _projectId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'پروژه'),
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('بدون پروژه'),
                    ),
                    ...widget.projects.map(
                      (project) => DropdownMenuItem(
                        value: project.id,
                        child: Text('${project.code} · ${project.name}'),
                      ),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _projectId = value ?? 0),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _statusId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'وضعیت'),
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
                      : (value) => setState(() => _statusId = value ?? 0),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _priority,
                  decoration: const InputDecoration(labelText: 'اولویت'),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('کم')),
                    DropdownMenuItem(value: 'normal', child: Text('معمولی')),
                    DropdownMenuItem(value: 'high', child: Text('زیاد')),
                    DropdownMenuItem(value: 'urgent', child: Text('فوری')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) =>
                          setState(() => _priority = value ?? 'normal'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _assigneeUserId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'مسئول'),
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('بدون مسئول'),
                    ),
                    ...widget.assignees.map(
                      (user) => DropdownMenuItem(
                        value: user.userId,
                        child: Text(user.name),
                      ),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) =>
                          setState(() => _assigneeUserId = value ?? 0),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('سررسید'),
                  subtitle: Text(
                    _dueDate == null
                        ? 'بدون سررسید'
                        : DateFormat('yyyy/MM/dd').format(_dueDate!),
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      if (_dueDate != null)
                        IconButton(
                          tooltip: 'پاک کردن',
                          onPressed: _saving
                              ? null
                              : () => setState(() => _dueDate = null),
                          icon: const Icon(Icons.clear),
                        ),
                      IconButton(
                        tooltip: 'انتخاب تاریخ',
                        onPressed: _saving ? null : _pickDueDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('انصراف'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(editing ? 'ذخیره' : 'ایجاد'),
        ),
      ],
    );
  }
}
