import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/project_model.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/widgets/task/task_structure_section.dart';
import 'package:hesabix_ui/widgets/task/task_conversation_section.dart';
import 'package:intl/intl.dart';

typedef TaskUpdateCallback = Future<TaskModel?> Function(Map<String, dynamic> data);
typedef TaskToggleCallback = Future<TaskModel?> Function();
typedef TaskDeleteCallback = Future<bool> Function();

/// Plane-inspired task detail surface.
///
/// On desktop this is rendered as a persistent side drawer next to the list.
/// On mobile the same surface is hosted by a glass modal bottom sheet.
class TaskDetailDrawer extends StatefulWidget {
  final int businessId;
  final TaskModel task;
  final List<TaskModel> relationCandidates;
  final ValueChanged<TaskModel> onTaskCreated;
  final List<TaskStatusModel> statuses;
  final List<ProjectModel> projects;
  final List<TaskAssigneeOption> assignees;
  final TaskUpdateCallback onUpdate;
  final TaskToggleCallback onToggleComplete;
  final TaskDeleteCallback onDelete;
  final VoidCallback onClose;

  const TaskDetailDrawer({
    super.key,
    required this.businessId,
    required this.task,
    required this.relationCandidates,
    required this.onTaskCreated,
    required this.statuses,
    required this.projects,
    required this.assignees,
    required this.onUpdate,
    required this.onToggleComplete,
    required this.onDelete,
    required this.onClose,
  });

  @override
  State<TaskDetailDrawer> createState() => _TaskDetailDrawerState();
}

class _TaskDetailDrawerState extends State<TaskDetailDrawer> {
  late TaskModel _task;
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late Set<int> _assigneeIds;
  bool _savingText = false;
  bool _propertyBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bindTask(widget.task);
  }

  @override
  void didUpdateWidget(covariant TaskDetailDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _titleController.dispose();
      _descriptionController.dispose();
      _bindTask(widget.task);
      return;
    }
    if (oldWidget.task.updatedAt != widget.task.updatedAt ||
        oldWidget.task.completedAt != widget.task.completedAt) {
      _task = widget.task;
      _assigneeIds = widget.task.assignees.map((e) => e.userId).toSet();
      if (_titleController.text != widget.task.title) {
        _titleController.text = widget.task.title;
      }
      if (_descriptionController.text != (widget.task.description ?? '')) {
        _descriptionController.text = widget.task.description ?? '';
      }
    }
  }

  void _bindTask(TaskModel task) {
    _task = task;
    _titleController = TextEditingController(text: task.title);
    _descriptionController = TextEditingController(text: task.description ?? '');
    _assigneeIds = task.assignees.map((e) => e.userId).toSet();
    _error = null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _updateProperty(Map<String, dynamic> data) async {
    if (_propertyBusy) return;
    setState(() {
      _propertyBusy = true;
      _error = null;
    });
    try {
      final updated = await widget.onUpdate(data);
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _task = updated;
          _assigneeIds = updated.assignees.map((e) => e.userId).toSet();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _propertyBusy = false);
    }
  }

  Future<void> _saveText() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _savingText) return;
    setState(() {
      _savingText = true;
      _error = null;
    });
    try {
      final updated = await widget.onUpdate({
        'title': title,
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      });
      if (!mounted) return;
      if (updated != null) setState(() => _task = updated);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _savingText = false);
    }
  }

  Future<void> _toggleComplete() async {
    if (_propertyBusy) return;
    setState(() => _propertyBusy = true);
    try {
      final updated = await widget.onToggleComplete();
      if (!mounted) return;
      if (updated != null) setState(() => _task = updated);
    } finally {
      if (mounted) setState(() => _propertyBusy = false);
    }
  }

  Future<void> _pickDueDate() async {
    var selected = _task.dueAt?.toLocal() ?? DateTime.now();
    final result = await showGlassDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInnerState) => AlertDialog(
          title: const Text('تاریخ سررسید'),
          content: SizedBox(
            width: 360,
            height: 330,
            child: CalendarDatePicker(
              initialDate: selected,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 3650)),
              onDateChanged: (value) => setInnerState(() => selected = value),
            ),
          ),
          actions: [
            if (_task.dueAt != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, DateTime(1970)),
                child: const Text('حذف سررسید'),
              ),
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
    if (result == null) return;
    if (result.year == 1970) {
      await _updateProperty({'due_at': null});
      return;
    }
    final due = DateTime(result.year, result.month, result.day, 17).toUtc();
    await _updateProperty({'due_at': due.toIso8601String()});
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف کار'),
        content: Text('«${_task.title}» حذف شود؟'),
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
    final deleted = await widget.onDelete();
    if (deleted) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final due = _task.dueAt?.toLocal();
    final isOverdue =
        due != null && !_task.isCompleted && due.isBefore(DateTime.now());

    return GlassSurface(
      borderRadius: BorderRadius.zero,
      blur: GlassStyle.strongModalBlur,
      opacity: Theme.of(context).brightness == Brightness.dark ? 0.15 : 0.72,
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            _header(context),
            Divider(height: 1, color: GlassStyle.border(context)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                children: [
                  TextField(
                    controller: _titleController,
                    maxLines: 2,
                    minLines: 1,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          decoration:
                              _task.isCompleted ? TextDecoration.lineThrough : null,
                        ),
                    decoration: const InputDecoration(
                      labelText: 'عنوان',
                      alignLabelWithHint: true,
                    ),
                    onSubmitted: (_) => _saveText(),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _descriptionController,
                    minLines: 4,
                    maxLines: 9,
                    decoration: const InputDecoration(
                      labelText: 'توضیحات',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.tonalIcon(
                      onPressed: _savingText ? null : _saveText,
                      icon: _savingText
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('ذخیره متن'),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _sectionTitle(context, 'Properties'),
                  const SizedBox(height: 10),
                  _propertyRow(
                    icon: Icons.flag_outlined,
                    label: 'وضعیت',
                    child: DropdownButton<int>(
                      value: _task.statusId,
                      underline: const SizedBox.shrink(),
                      isExpanded: true,
                      items: widget.statuses
                          .map(
                            (status) => DropdownMenuItem(
                              value: status.id,
                              child: Text(status.name),
                            ),
                          )
                          .toList(),
                      onChanged: _propertyBusy
                          ? null
                          : (value) {
                              if (value != null) {
                                _updateProperty({'status_id': value});
                              }
                            },
                    ),
                  ),
                  _propertyRow(
                    icon: Icons.priority_high_rounded,
                    label: 'اولویت',
                    child: DropdownButton<String>(
                      value: _task.priority,
                      underline: const SizedBox.shrink(),
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('کم')),
                        DropdownMenuItem(value: 'normal', child: Text('معمولی')),
                        DropdownMenuItem(value: 'high', child: Text('زیاد')),
                        DropdownMenuItem(value: 'urgent', child: Text('فوری')),
                      ],
                      onChanged: _propertyBusy
                          ? null
                          : (value) {
                              if (value != null) {
                                _updateProperty({'priority': value});
                              }
                            },
                    ),
                  ),
                  _propertyRow(
                    icon: Icons.folder_open_outlined,
                    label: 'پروژه',
                    child: DropdownButton<int>(
                      value: _task.projectId ?? 0,
                      underline: const SizedBox.shrink(),
                      isExpanded: true,
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
                      onChanged: _propertyBusy
                          ? null
                          : (value) => _updateProperty({
                                'project_id':
                                    value == null || value == 0 ? null : value,
                              }),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _propertyBusy ? null : _pickDueDate,
                    child: _propertyRow(
                      icon: isOverdue
                          ? Icons.warning_amber_rounded
                          : Icons.event_outlined,
                      label: 'سررسید',
                      iconColor: isOverdue ? scheme.error : null,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          due == null
                              ? 'بدون سررسید'
                              : DateFormat('yyyy/MM/dd').format(due),
                          style: TextStyle(
                            color: isOverdue ? scheme.error : null,
                            fontWeight: isOverdue ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _sectionTitle(context, 'Assignees'),
                  const SizedBox(height: 10),
                  if (widget.assignees.isEmpty)
                    Text(
                      'عضوی برای تخصیص کار پیدا نشد.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: widget.assignees.map((user) {
                        final selected = _assigneeIds.contains(user.userId);
                        return FilterChip(
                          selected: selected,
                          avatar: CircleAvatar(
                            child: Text(
                              user.name.trim().isEmpty
                                  ? '?'
                                  : user.name.trim().characters.first,
                            ),
                          ),
                          label: Text(user.name),
                          onSelected: _propertyBusy
                              ? null
                              : (value) {
                                  final next = Set<int>.from(_assigneeIds);
                                  if (value) {
                                    next.add(user.userId);
                                  } else {
                                    next.remove(user.userId);
                                  }
                                  _assigneeIds = next;
                                  _updateProperty({
                                    'assignee_user_ids': next.toList(),
                                  });
                                },
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 22),
                  TaskStructureSection(
                    businessId: widget.businessId,
                    task: _task,
                    relationCandidates: widget.relationCandidates,
                    onTaskCreated: widget.onTaskCreated,
                  ),
                  const SizedBox(height: 22),
                  TaskConversationSection(
                    businessId: widget.businessId,
                    task: _task,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  OutlinedButton.icon(
                    onPressed: _propertyBusy ? null : _confirmDelete,
                    icon: Icon(Icons.delete_outline, color: scheme.error),
                    label: Text(
                      'حذف کار',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Checkbox(
            value: _task.isCompleted,
            onChanged: _propertyBusy ? null : (_) => _toggleComplete(),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${_task.id}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.outline,
                      ),
                ),
                Text(
                  _task.isCompleted ? 'Completed' : 'Task details',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          if (_propertyBusy)
            const Padding(
              padding: EdgeInsets.all(10),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: 'بستن',
            onPressed: widget.onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Widget _propertyRow({
    required IconData icon,
    required String label,
    required Widget child,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 19, color: iconColor),
          const SizedBox(width: 9),
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}
