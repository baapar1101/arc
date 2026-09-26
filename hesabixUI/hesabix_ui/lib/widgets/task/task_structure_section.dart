import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

class TaskStructureSection extends StatefulWidget {
  final int businessId;
  final TaskModel task;
  final List<TaskModel> relationCandidates;
  final ValueChanged<TaskModel> onTaskCreated;

  const TaskStructureSection({
    super.key,
    required this.businessId,
    required this.task,
    required this.relationCandidates,
    required this.onTaskCreated,
  });

  @override
  State<TaskStructureSection> createState() => _TaskStructureSectionState();
}

class _TaskStructureSectionState extends State<TaskStructureSection> {
  late final TaskService _service;
  final TextEditingController _subtaskController = TextEditingController();
  TaskStructureModel? _structure;
  bool _loading = true;
  bool _creatingSubtask = false;
  bool _savingRelation = false;
  int _relatedTaskId = 0;
  String _relationType = 'blocks';
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = TaskService(ApiClient());
    _load();
  }

  @override
  void didUpdateWidget(covariant TaskStructureSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _relatedTaskId = 0;
      _load();
    }
  }

  @override
  void dispose() {
    _subtaskController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final structure = await _service.getTaskStructure(
        businessId: widget.businessId,
        taskId: widget.task.id,
      );
      if (!mounted) return;
      setState(() {
        _structure = structure;
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

  Future<void> _createSubtask() async {
    final title = _subtaskController.text.trim();
    if (title.isEmpty || _creatingSubtask) return;
    setState(() {
      _creatingSubtask = true;
      _error = null;
    });
    try {
      final task = await _service.createSubtask(
        businessId: widget.businessId,
        parentTaskId: widget.task.id,
        title: title,
      );
      if (!mounted) return;
      _subtaskController.clear();
      widget.onTaskCreated(task);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
      });
    } finally {
      if (mounted) setState(() => _creatingSubtask = false);
    }
  }

  Future<void> _addRelation() async {
    if (_relatedTaskId <= 0 || _savingRelation) return;
    setState(() {
      _savingRelation = true;
      _error = null;
    });
    try {
      await _service.addTaskRelation(
        businessId: widget.businessId,
        taskId: widget.task.id,
        relatedTaskId: _relatedTaskId,
        relationType: _relationType,
      );
      if (!mounted) return;
      setState(() => _relatedTaskId = 0);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
      });
    } finally {
      if (mounted) setState(() => _savingRelation = false);
    }
  }

  Future<void> _removeRelation(TaskRelationModel relation) async {
    if (_savingRelation) return;
    setState(() {
      _savingRelation = true;
      _error = null;
    });
    try {
      await _service.deleteTaskRelation(
        businessId: widget.businessId,
        taskId: widget.task.id,
        relationId: relation.id,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
      });
    } finally {
      if (mounted) setState(() => _savingRelation = false);
    }
  }

  String _relationLabel(TaskRelationModel relation) {
    switch (relation.relationType) {
      case 'blocks':
        return relation.direction == 'outgoing'
            ? 'مسدود می‌کند'
            : 'مسدود شده توسط';
      case 'duplicates':
        return relation.direction == 'outgoing'
            ? 'تکراریِ'
            : 'تکراری توسط';
      default:
        return 'مرتبط با';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final structure = _structure;
    final candidates = widget.relationCandidates
        .where((task) => task.id != widget.task.id)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Subtasks & Dependencies',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'بروزرسانی روابط',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 19),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else ...[
          if (structure?.parent != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: .18),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_tree_outlined, size: 19),
                  const SizedBox(width: 8),
                  const Text('والد: '),
                  Expanded(
                    child: Text(
                      '#${structure!.parent!.id} · ${structure.parent!.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _subtaskController,
                  enabled: !_creatingSubtask,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _createSubtask(),
                  decoration: const InputDecoration(
                    labelText: 'زیرکار جدید',
                    isDense: true,
                    prefixIcon: Icon(Icons.subdirectory_arrow_left),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'ایجاد زیرکار',
                onPressed: _creatingSubtask ? null : _createSubtask,
                icon: _creatingSubtask
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (structure == null || structure.subtasks.isEmpty)
            Text(
              'زیرکاری ثبت نشده است.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ...structure.subtasks.map(
              (subtask) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  subtask.isCompleted
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: subtask.isCompleted
                      ? scheme.primary
                      : scheme.outline,
                ),
                title: Text(
                  subtask.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: subtask.statusName == null
                    ? null
                    : Text(subtask.statusName!),
                trailing: Text('#${subtask.id}'),
              ),
            ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Dependencies / Relations',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          if (candidates.isEmpty)
            Text(
              'کار دیگری در نمای فعلی برای ایجاد رابطه وجود ندارد.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Column(
              children: [
                DropdownButtonFormField<int>(
                  value: _relatedTaskId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'کار مرتبط',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('انتخاب کار'),
                    ),
                    ...candidates.map(
                      (task) => DropdownMenuItem(
                        value: task.id,
                        child: Text(
                          '#${task.id} · ${task.title}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: _savingRelation
                      ? null
                      : (value) =>
                          setState(() => _relatedTaskId = value ?? 0),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _relationType,
                        decoration: const InputDecoration(
                          labelText: 'نوع رابطه',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'blocks',
                            child: Text('Blocks'),
                          ),
                          DropdownMenuItem(
                            value: 'related',
                            child: Text('Related'),
                          ),
                          DropdownMenuItem(
                            value: 'duplicates',
                            child: Text('Duplicates'),
                          ),
                        ],
                        onChanged: _savingRelation
                            ? null
                            : (value) => setState(
                                  () => _relationType = value ?? 'blocks',
                                ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: _savingRelation || _relatedTaskId == 0
                          ? null
                          : _addRelation,
                      icon: _savingRelation
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link_rounded),
                      label: const Text('افزودن'),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 8),
          if (structure == null || structure.relations.isEmpty)
            Text(
              'رابطه‌ای ثبت نشده است.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ...structure.relations.map(
              (relation) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link_rounded, size: 20),
                title: Text(
                  relation.task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_relationLabel(relation)} · #${relation.task.id}',
                ),
                trailing: IconButton(
                  tooltip: 'حذف رابطه',
                  onPressed: _savingRelation
                      ? null
                      : () => _removeRelation(relation),
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
              ),
            ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          GlassSurface(
            padding: const EdgeInsets.all(10),
            borderRadius: BorderRadius.circular(10),
            child: Text(
              _error!,
              style: TextStyle(color: scheme.error),
            ),
          ),
        ],
      ],
    );
  }
}
