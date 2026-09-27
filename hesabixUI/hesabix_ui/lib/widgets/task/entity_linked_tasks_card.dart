import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:intl/intl.dart';

/// Reverse side of Phase 14 CRM-native task links.
///
/// This shows first-class Task records linked to an existing business entity.
/// It intentionally does not replace legacy CRM Activity follow-up tasks.
class EntityLinkedTasksCard extends StatefulWidget {
  final int businessId;
  final String entityType;
  final String entityId;
  final bool canWrite;
  final String title;
  final String relationshipType;

  const EntityLinkedTasksCard({
    super.key,
    required this.businessId,
    required this.entityType,
    required this.entityId,
    this.canWrite = true,
    this.title = 'کارهای مرتبط',
    this.relationshipType = 'related',
  });

  @override
  State<EntityLinkedTasksCard> createState() => _EntityLinkedTasksCardState();
}

class _EntityLinkedTasksCardState extends State<EntityLinkedTasksCard> {
  late final TaskService _service;
  final TextEditingController _titleController = TextEditingController();
  List<TaskModel> _tasks = const [];
  bool _loading = true;
  bool _creating = false;
  final Set<int> _mutatingIds = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = TaskService(ApiClient());
    _load();
  }

  @override
  void didUpdateWidget(covariant EntityLinkedTasksCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.entityType != widget.entityType ||
        oldWidget.entityId != widget.entityId) {
      _titleController.clear();
      _load();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.listTasksForEntity(
        businessId: widget.businessId,
        entityType: widget.entityType,
        entityId: widget.entityId,
      );
      if (!mounted) return;
      setState(() {
        _tasks = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorExtractor.forContext(e, context);
      });
    }
  }

  Future<void> _create() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _creating || !widget.canWrite) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final task = await _service.createTask(
        businessId: widget.businessId,
        data: {'title': title},
      );
      await _service.addEntityLink(
        businessId: widget.businessId,
        taskId: task.id,
        entityType: widget.entityType,
        entityId: widget.entityId,
        relationshipType: widget.relationshipType,
      );
      if (!mounted) return;
      _titleController.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _toggle(TaskModel task) async {
    if (_mutatingIds.contains(task.id) || !widget.canWrite) return;
    setState(() => _mutatingIds.add(task.id));
    try {
      final updated = task.isCompleted
          ? await _service.reopenTask(
              businessId: widget.businessId,
              taskId: task.id,
            )
          : await _service.completeTask(
              businessId: widget.businessId,
              taskId: task.id,
            );
      if (!mounted) return;
      setState(() {
        _tasks = [
          for (final item in _tasks)
            if (item.id == updated.id) updated else item,
        ];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _mutatingIds.remove(task.id));
    }
  }

  String _due(TaskModel task) {
    final value = task.dueAt?.toLocal();
    if (value == null) return '';
    return DateFormat('yyyy/MM/dd').format(value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GlassSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.task_alt_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'بروزرسانی',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
          Text(
            'کارهای اصلی Task Manager؛ جدا از Activity/Follow-up قدیمی CRM',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.outline,
                ),
          ),
          if (widget.canWrite) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    enabled: !_creating,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _create(),
                    decoration: const InputDecoration(
                      labelText: 'کار جدید',
                      isDense: true,
                      prefixIcon: Icon(Icons.add_task_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                IconButton.filledTonal(
                  tooltip: 'ایجاد و اتصال',
                  onPressed: _creating ? null : _create,
                  icon: _creating
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_tasks.isEmpty)
            Text(
              'کار مرتبطی ثبت نشده است.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ..._tasks.take(12).map(
              (task) {
                final due = _due(task);
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: _mutatingIds.contains(task.id)
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Checkbox(
                          value: task.isCompleted,
                          onChanged:
                              widget.canWrite ? (_) => _toggle(task) : null,
                        ),
                  title: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      decoration: task.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    [
                      if (task.status != null) task.status!.name,
                      if (task.projectName?.isNotEmpty == true)
                        task.projectName!,
                      if (due.isNotEmpty) 'سررسید $due',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text('#${task.id}'),
                );
              },
            ),
          if (_tasks.length > 12)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '+ ${_tasks.length - 12} کار دیگر',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: scheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
