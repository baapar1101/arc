import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/project_model.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';
import 'package:intl/intl.dart';

Future<bool?> showTaskDetailDrawer({
  required BuildContext context,
  required int businessId,
  required TaskService taskService,
  required TaskModel task,
  required List<TaskStatusModel> statuses,
  required List<ProjectModel> projects,
  required List<TaskAssigneeOption> assignees,
}) {
  final mobile = ResponsiveHelper.isMobile(context);
  final editor = _TaskDetailEditor(
    businessId: businessId,
    taskService: taskService,
    task: task,
    statuses: statuses,
    projects: projects,
    assignees: assignees,
  );

  if (mobile) {
    return showGlassModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.92,
        child: editor,
      ),
    );
  }

  return showGlassDialog<bool>(
    context: context,
    useSafeArea: false,
    barrierDismissible: true,
    builder: (dialogContext) {
      final width = math.min(
        720.0,
        math.max(540.0, MediaQuery.sizeOf(dialogContext).width * 0.48),
      );
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: width,
            height: MediaQuery.sizeOf(dialogContext).height,
            child: GlassSurface(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(24),
              ),
              blur: GlassStyle.strongModalBlur,
              opacity: Theme.of(dialogContext).brightness == Brightness.dark
                  ? 0.22
                  : 0.64,
              child: editor,
            ),
          ),
        ),
      );
    },
  );
}

class _TaskDetailEditor extends StatefulWidget {
  final int businessId;
  final TaskService taskService;
  final TaskModel task;
  final List<TaskStatusModel> statuses;
  final List<ProjectModel> projects;
  final List<TaskAssigneeOption> assignees;

  const _TaskDetailEditor({
    required this.businessId,
    required this.taskService,
    required this.task,
    required this.statuses,
    required this.projects,
    required this.assignees,
  });

  @override
  State<_TaskDetailEditor> createState() => _TaskDetailEditorState();
}

class _TaskDetailEditorState extends State<_TaskDetailEditor> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late int _projectId;
  late int _statusId;
  late String _priority;
  late Set<int> _assigneeIds;
  DateTime? _dueDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task.title);
    _descriptionController = TextEditingController(text: task.description ?? '');
    _projectId = task.projectId ?? 0;
    _statusId = task.statusId ??
        (widget.statuses.where((e) => e.isDefault).isNotEmpty
            ? widget.statuses.firstWhere((e) => e.isDefault).id
            : widget.statuses.first.id);
    _priority = task.priority;
    _assigneeIds = task.assignees.map((e) => e.userId).toSet();
    _dueDate = task.dueAt?.toLocal();
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
              onDateChanged: (value) => setDialogState(() => selected = value),
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

  DateTime? _normalizedDueDate() {
    if (_dueDate == null) return null;
    return DateTime(
      _dueDate!.year,
      _dueDate!.month,
      _dueDate!.day,
      17,
    ).toUtc();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'عنوان الزامی است');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.taskService.updateTask(
        businessId: widget.businessId,
        taskId: widget.task.id,
        data: {
          'title': title,
          'description': _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          'project_id': _projectId == 0 ? null : _projectId,
          'status_id': _statusId,
          'priority': _priority,
          'due_at': _normalizedDueDate()?.toIso8601String(),
          'assignee_user_ids': _assigneeIds.toList()..sort(),
        },
      );
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

  Future<void> _toggleCompletion() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.task.isCompleted) {
        await widget.taskService.reopenTask(
          businessId: widget.businessId,
          taskId: widget.task.id,
        );
      } else {
        await widget.taskService.completeTask(
          businessId: widget.businessId,
          taskId: widget.task.id,
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

  String _priorityLabel(String value) {
    switch (value) {
      case 'low':
        return 'کم';
      case 'high':
        return 'زیاد';
      case 'urgent':
        return 'فوری';
      default:
        return 'معمولی';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = ResponsiveHelper.isMobile(context);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.task_alt_outlined,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Task #${widget.task.id}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'بستن',
                  onPressed: _saving ? null : () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 16 : 22,
                18,
                isMobile ? 16 : 22,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _titleController,
                    enabled: !_saving,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                    decoration: const InputDecoration(
                      labelText: 'عنوان',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Section(
                    icon: Icons.notes_outlined,
                    title: 'توضیحات',
                    child: TextField(
                      controller: _descriptionController,
                      enabled: !_saving,
                      minLines: 4,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        hintText: 'شرح کار، نتیجه مورد انتظار یا جزئیات اجرا...',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    icon: Icons.tune_outlined,
                    title: 'مشخصات',
                    child: Column(
                      children: [
                        DropdownButtonFormField<int>(
                          value: _statusId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'وضعیت',
                            prefixIcon: Icon(Icons.radio_button_checked_outlined),
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
                              : (value) {
                                  if (value != null) {
                                    setState(() => _statusId = value);
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _priority,
                          decoration: const InputDecoration(
                            labelText: 'اولویت',
                            prefixIcon: Icon(Icons.flag_outlined),
                          ),
                          items: const ['low', 'normal', 'high', 'urgent']
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_priorityLabel(value)),
                                ),
                              )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _priority = value);
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: _projectId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'پروژه',
                            prefixIcon: Icon(Icons.folder_open_outlined),
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
                              : (value) => setState(
                                    () => _projectId = value ?? 0,
                                  ),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _saving ? null : _pickDueDate,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'سررسید',
                              prefixIcon: Icon(Icons.event_outlined),
                            ),
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
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    icon: Icons.group_outlined,
                    title: 'مسئولان',
                    subtitle: 'می‌توانید چند کاربر را به یک کار اختصاص دهید.',
                    child: widget.assignees.isEmpty
                        ? Text(
                            'کاربر فعالی برای این کسب‌وکار وجود ندارد.',
                            style: TextStyle(color: scheme.outline),
                          )
                        : Wrap(
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
                                    style: const TextStyle(fontSize: 10),
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
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    'ایجاد شده: ${widget.task.createdAt == null ? '—' : DateFormat('yyyy/MM/dd HH:mm').format(widget.task.createdAt!.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.outline,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _toggleCompletion,
                  icon: Icon(
                    widget.task.isCompleted
                        ? Icons.restart_alt
                        : Icons.check_circle_outline,
                  ),
                  label: Text(
                    widget.task.isCompleted ? 'بازگشایی' : 'تکمیل',
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('ذخیره تغییرات'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  const _Section({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.48),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.outline,
                  ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
