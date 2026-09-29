import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/project_model.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/project_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:intl/intl.dart';

class ProjectCyclesView extends StatefulWidget {
  final int businessId;
  final int projectId;
  final List<ProjectCycleModel> cycles;
  final List<TaskModel> tasks;
  final Set<int> backlogTaskIds;
  final ProjectService service;
  final ValueChanged<TaskModel> onOpenTask;
  final void Function(List<ProjectCycleModel>, Set<int>) onChanged;

  const ProjectCyclesView({
    super.key,
    required this.businessId,
    required this.projectId,
    required this.cycles,
    required this.tasks,
    required this.backlogTaskIds,
    required this.service,
    required this.onOpenTask,
    required this.onChanged,
  });

  @override
  State<ProjectCyclesView> createState() => _ProjectCyclesViewState();
}

class _ProjectCyclesViewState extends State<ProjectCyclesView> {
  late List<ProjectCycleModel> _items;
  late Set<int> _backlogTaskIds;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _items = List<ProjectCycleModel>.from(widget.cycles);
    _backlogTaskIds = Set<int>.from(widget.backlogTaskIds);
  }

  @override
  void didUpdateWidget(covariant ProjectCyclesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.cycles, widget.cycles)) {
      _items = List<ProjectCycleModel>.from(widget.cycles);
    }
    if (!identical(oldWidget.backlogTaskIds, widget.backlogTaskIds)) {
      _backlogTaskIds = Set<int>.from(widget.backlogTaskIds);
    }
  }

  void _emit(List<ProjectCycleModel> items, Set<int> backlogTaskIds) {
    setState(() {
      _items = items;
      _backlogTaskIds = backlogTaskIds;
    });
    widget.onChanged(items, backlogTaskIds);
  }

  Future<void> _reload() async {
    final workflow = await widget.service.getCycleWorkflow(
      businessId: widget.businessId,
      projectId: widget.projectId,
    );
    if (mounted) {
      _emit(workflow.cycles, workflow.backlogTaskIds);
    }
  }

  Future<void> _edit([ProjectCycleModel? cycle]) async {
    if (_busy) return;
    final data = await showGlassDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CycleEditorDialog(cycle: cycle),
    );
    if (data == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = cycle == null
          ? await widget.service.createCycle(
              businessId: widget.businessId,
              projectId: widget.projectId,
              data: data,
            )
          : await widget.service.updateCycle(
              businessId: widget.businessId,
              projectId: widget.projectId,
              cycleId: cycle.id,
              data: data,
            );
      await _reload();
    } catch (e) {
      if (mounted) {
        setState(() => _error = ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ProjectCycleModel cycle) async {
    if (_busy) return;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف Cycle'),
        content: Text('«${cycle.name}» حذف شود؟'),
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

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.deleteCycle(
        businessId: widget.businessId,
        projectId: widget.projectId,
        cycleId: cycle.id,
      );
      await _reload();
    } catch (e) {
      if (mounted) {
        setState(() => _error = ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Planned';
    }
  }

  List<ProjectCycleModel> get _currentCycles =>
      _items.where((cycle) => cycle.status == 'active').toList();

  List<ProjectCycleModel> get _futureCycles =>
      _items.where((cycle) => cycle.status == 'planned').toList();

  List<ProjectCycleModel> get _completedCycles => _items
      .where(
        (cycle) =>
            cycle.status == 'completed' || cycle.status == 'cancelled',
      )
      .toList();

  List<ProjectCycleModel> get _planningTargets => _items
      .where(
        (cycle) => cycle.status == 'active' || cycle.status == 'planned',
      )
      .toList();

  List<TaskModel> get _backlogTasks {
    final items = widget.tasks
        .where(
          (task) =>
              _backlogTaskIds.contains(task.id) && !task.isCompleted,
        )
        .toList();
    items.sort((a, b) {
      final ad = a.dueAt;
      final bd = b.dueAt;
      if (ad == null && bd == null) return a.id.compareTo(b.id);
      if (ad == null) return 1;
      if (bd == null) return -1;
      final byDue = ad.compareTo(bd);
      return byDue != 0 ? byDue : a.id.compareTo(b.id);
    });
    return items;
  }

  Future<void> _assignBacklogTask(
    TaskModel task,
    ProjectCycleModel cycle,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.addTaskToCycle(
        businessId: widget.businessId,
        projectId: widget.projectId,
        cycleId: cycle.id,
        taskId: task.id,
      );
      await _reload();
    } catch (e) {
      if (mounted) {
        setState(() => _error = ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _carryOver(ProjectCycleModel source) async {
    if (_busy || source.incompleteTaskIds.isEmpty) return;
    final targets = _planningTargets
        .where((cycle) => cycle.id != source.id)
        .toList();
    if (targets.isEmpty) {
      setState(
        () => _error =
            'برای Carry-over ابتدا یک Cycle فعال یا برنامه‌ریزی‌شده دیگر بسازید.',
      );
      return;
    }

    var targetId = targets.first.id;
    final selected = await showGlassDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('Carry-over کارهای ناتمام'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${source.incompleteTaskIds.length} کار ناتمام به Cycle بعدی اضافه می‌شود. عضویت در Cycle مبدا برای تاریخچه حفظ خواهد شد.',
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  value: targetId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Cycle مقصد',
                  ),
                  items: targets
                      .map(
                        (cycle) => DropdownMenuItem<int>(
                          value: cycle.id,
                          child: Text(
                            cycle.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setInner(() => targetId = value);
                  },
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
              onPressed: () => Navigator.pop(ctx, targetId),
              child: const Text('Carry-over'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.carryOverCycle(
        businessId: widget.businessId,
        projectId: widget.projectId,
        sourceCycleId: source.id,
        targetCycleId: selected,
      );
      await _reload();
    } catch (e) {
      if (mounted) {
        setState(() => _error = ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _sectionHeader(String title, int count, IconData icon) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Chip(label: Text('$count')),
          ],
        ),
      );

  Widget _emptySection(String text) => GlassSurface(
        padding: const EdgeInsets.all(18),
        child: Text(text),
      );

  Widget _backlogSection() {
    final tasks = _backlogTasks;
    final targets = _planningTargets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('Backlog', tasks.length, Icons.inbox_outlined),
        if (tasks.isEmpty)
          _emptySection('کار ناتمام بدون Cycle فعال/آینده وجود ندارد.')
        else
          ...tasks.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassSurface(
                padding: const EdgeInsets.all(6),
                child: ListTile(
                  leading: const Icon(Icons.task_alt_outlined),
                  title: Text(
                    task.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    [
                      task.priority,
                      if (task.dueAt != null)
                        DateFormat('yyyy/MM/dd').format(task.dueAt!.toLocal()),
                    ].join(' · '),
                  ),
                  onTap: () => widget.onOpenTask(task),
                  trailing: targets.isEmpty
                      ? const Tooltip(
                          message: 'ابتدا Cycle فعال/آینده بسازید',
                          child: Icon(Icons.add_circle_outline),
                        )
                      : PopupMenuButton<int>(
                          enabled: !_busy,
                          tooltip: 'افزودن به Cycle',
                          onSelected: (cycleId) {
                            final cycle = targets.firstWhere(
                              (item) => item.id == cycleId,
                            );
                            _assignBacklogTask(task, cycle);
                          },
                          itemBuilder: (_) => targets
                              .map(
                                (cycle) => PopupMenuItem<int>(
                                  value: cycle.id,
                                  child: Text('افزودن به ${cycle.name}'),
                                ),
                              )
                              .toList(),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _cycleSection(
    String title,
    List<ProjectCycleModel> cycles,
    IconData icon,
    String emptyText,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          _sectionHeader(title, cycles.length, icon),
          if (cycles.isEmpty)
            _emptySection(emptyText)
          else
            ...cycles.map(_cycleCard),
        ],
      );

  Widget _cycleCard(ProjectCycleModel cycle) {
    final scheme = Theme.of(context).colorScheme;
    final carryTargets = _planningTargets
        .where((item) => item.id != cycle.id)
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: GlassSurface(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.autorenew_rounded),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    cycle.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(label: Text(_statusLabel(cycle.status))),
                PopupMenuButton<String>(
                  enabled: !_busy,
                  onSelected: (value) {
                    if (value == 'edit') _edit(cycle);
                    if (value == 'delete') _delete(cycle);
                    if (value == 'carry') _carryOver(cycle);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('ویرایش'),
                    ),
                    if ((cycle.status == 'active' ||
                            cycle.status == 'completed') &&
                        cycle.incompleteTaskIds.isNotEmpty &&
                        carryTargets.isNotEmpty)
                      const PopupMenuItem(
                        value: 'carry',
                        child: Text('Carry-over کارهای ناتمام'),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('حذف'),
                    ),
                  ],
                ),
              ],
            ),
            if (cycle.goal?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(cycle.goal!),
            ],
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (cycle.startAt != null)
                  Chip(
                    label: Text(
                      'شروع ${DateFormat('yyyy/MM/dd').format(cycle.startAt!.toLocal())}',
                    ),
                  ),
                if (cycle.endAt != null)
                  Chip(
                    label: Text(
                      'پایان ${DateFormat('yyyy/MM/dd').format(cycle.endAt!.toLocal())}',
                    ),
                  ),
                Chip(
                  avatar: const Icon(Icons.task_alt, size: 17),
                  label: Text(
                    '${cycle.taskCompleted}/${cycle.taskTotal} کار',
                  ),
                ),
                if (cycle.incompleteTaskIds.isNotEmpty)
                  Chip(
                    avatar: Icon(
                      Icons.pending_actions_outlined,
                      size: 17,
                      color: scheme.outline,
                    ),
                    label: Text(
                      '${cycle.incompleteTaskIds.length} ناتمام',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            LinearProgressIndicator(
              value: (cycle.progressPercent / 100).clamp(0.0, 1.0),
              minHeight: 7,
              borderRadius: BorderRadius.circular(99),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          GlassSurface(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cycles / Sprints',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text('Backlog → Current → Future → Completed'),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _edit(),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Cycle جدید'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _backlogSection(),
          _cycleSection(
            'Current cycle',
            _currentCycles,
            Icons.play_circle_outline,
            'Cycle فعالی وجود ندارد.',
          ),
          _cycleSection(
            'Future cycles',
            _futureCycles,
            Icons.upcoming_outlined,
            'Cycle برنامه‌ریزی‌شده‌ای وجود ندارد.',
          ),
          _cycleSection(
            'Completed cycles',
            _completedCycles,
            Icons.history_rounded,
            'Cycle تکمیل یا لغوشده‌ای وجود ندارد.',
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
    );
  }
}

class _CycleEditorDialog extends StatefulWidget {
  final ProjectCycleModel? cycle;
  const _CycleEditorDialog({this.cycle});

  @override
  State<_CycleEditorDialog> createState() => _CycleEditorDialogState();
}

class _CycleEditorDialogState extends State<_CycleEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _goal;
  late String _status;
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.cycle?.name ?? '');
    _goal = TextEditingController(text: widget.cycle?.goal ?? '');
    _status = widget.cycle?.status ?? 'planned';
    _start = widget.cycle?.startAt?.toLocal();
    _end = widget.cycle?.endAt?.toLocal();
  }

  @override
  void dispose() {
    _name.dispose();
    _goal.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? value) => showDatePicker(
        context: context,
        initialDate: value ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 3650)),
      );

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, {
      'name': name,
      'goal': _goal.text.trim().isEmpty ? null : _goal.text.trim(),
      'status': _status,
      'start_at': _start == null
          ? null
          : DateTime(_start!.year, _start!.month, _start!.day, 9)
              .toUtc()
              .toIso8601String(),
      'end_at': _end == null
          ? null
          : DateTime(_end!.year, _end!.month, _end!.day, 17)
              .toUtc()
              .toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.cycle == null ? 'Cycle جدید' : 'ویرایش Cycle'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'نام'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _goal,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'هدف',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(labelText: 'وضعیت'),
                  items: const [
                    DropdownMenuItem(value: 'planned', child: Text('Planned')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'completed', child: Text('Completed')),
                    DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                  ],
                  onChanged: (value) =>
                      setState(() => _status = value ?? 'planned'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final value = await _pick(_start);
                          if (value != null) setState(() => _start = value);
                        },
                        child: Text(
                          _start == null
                              ? 'شروع'
                              : DateFormat('yyyy/MM/dd').format(_start!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final value = await _pick(_end);
                          if (value != null) setState(() => _end = value);
                        },
                        child: Text(
                          _end == null
                              ? 'پایان'
                              : DateFormat('yyyy/MM/dd').format(_end!),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(onPressed: _submit, child: const Text('ذخیره')),
        ],
      );
}
