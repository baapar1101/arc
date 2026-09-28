import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:intl/intl.dart';

class TaskKanbanBoard extends StatefulWidget {
  final List<TaskModel> tasks;
  final List<TaskStatusModel> statuses;
  final Future<TaskModel?> Function(
    TaskModel task,
    int targetStatusId,
    int targetIndex,
  ) onMove;
  final Future<bool> Function(TaskStatusModel status, String title) onCreate;
  final ValueChanged<TaskModel> onOpen;

  const TaskKanbanBoard({
    super.key,
    required this.tasks,
    required this.statuses,
    required this.onMove,
    required this.onCreate,
    required this.onOpen,
  });

  @override
  State<TaskKanbanBoard> createState() => _TaskKanbanBoardState();
}

class _TaskKanbanBoardState extends State<TaskKanbanBoard> {
  final ScrollController _horizontal = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final Map<int, TextEditingController> _quickControllers = {};
  final Set<int> _creatingStatusIds = {};
  String _priorityFilter = 'all';
  int? _assigneeFilterId;
  int? _labelFilterId;
  String _dueFilter = 'any';

  @override
  void dispose() {
    _horizontal.dispose();
    _searchController.dispose();
    for (final controller in _quickControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(int statusId) {
    return _quickControllers.putIfAbsent(
      statusId,
      TextEditingController.new,
    );
  }

  List<TaskModel> _allTasksFor(TaskStatusModel status) {
    final items = widget.tasks
        .where((task) => task.statusId == status.id)
        .toList();
    items.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
    });
    return items;
  }

  bool _matchesFilters(TaskModel task) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      final haystack = [
        task.title,
        task.description ?? '',
        task.assignees.map((e) => e.name).join(' '),
        task.labels.map((e) => e.name).join(' '),
      ].join(' ').toLowerCase();
      if (!haystack.contains(query)) return false;
    }

    if (_priorityFilter != 'all' && task.priority != _priorityFilter) {
      return false;
    }
    if (_assigneeFilterId != null &&
        !task.assignees.any((e) => e.userId == _assigneeFilterId)) {
      return false;
    }
    if (_labelFilterId != null &&
        !task.labels.any((e) => e.id == _labelFilterId)) {
      return false;
    }

    final due = task.dueAt?.toLocal();
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    if (_dueFilter == 'overdue') {
      if (task.isCompleted || due == null || !due.isBefore(now)) return false;
    } else if (_dueFilter == 'today') {
      if (due == null || DateUtils.dateOnly(due) != today) return false;
    } else if (_dueFilter == 'upcoming') {
      if (due == null || !due.isAfter(now)) return false;
    } else if (_dueFilter == 'none') {
      if (due != null) return false;
    }
    return true;
  }

  List<TaskModel> _tasksFor(TaskStatusModel status) {
    return _allTasksFor(status).where(_matchesFilters).toList();
  }

  List<TaskAssigneeModel> get _assigneeOptions {
    final byId = <int, TaskAssigneeModel>{};
    for (final task in widget.tasks) {
      for (final assignee in task.assignees) {
        byId[assignee.userId] = assignee;
      }
    }
    final items = byId.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return items;
  }

  List<TaskLabelModel> get _labelOptions {
    final byId = <int, TaskLabelModel>{};
    for (final task in widget.tasks) {
      for (final label in task.labels) {
        byId[label.id] = label;
      }
    }
    final items = byId.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return items;
  }

  int get _activeFilterCount {
    var count = 0;
    if (_searchController.text.trim().isNotEmpty) count++;
    if (_priorityFilter != 'all') count++;
    if (_assigneeFilterId != null) count++;
    if (_labelFilterId != null) count++;
    if (_dueFilter != 'any') count++;
    return count;
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _priorityFilter = 'all';
      _assigneeFilterId = null;
      _labelFilterId = null;
      _dueFilter = 'any';
    });
  }

  Future<void> _quickCreate(TaskStatusModel status) async {
    final controller = _controllerFor(status.id);
    final title = controller.text.trim();
    if (title.isEmpty || _creatingStatusIds.contains(status.id)) return;

    setState(() => _creatingStatusIds.add(status.id));
    try {
      final created = await widget.onCreate(status, title);
      if (created && mounted) controller.clear();
    } finally {
      if (mounted) {
        setState(() => _creatingStatusIds.remove(status.id));
      }
    }
  }

  Color _statusColor(BuildContext context, String? raw) {
    final fallback = Theme.of(context).colorScheme.primary;
    if (raw == null || raw.trim().isEmpty) return fallback;
    var hex = raw.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return fallback;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? fallback : Color(value);
  }

  int _absoluteTargetIndex(
    TaskModel dragged,
    TaskStatusModel targetStatus,
    List<TaskModel> currentVisibleColumn,
    int zoneIndex,
  ) {
    var visibleIndex = zoneIndex;
    if (dragged.statusId == targetStatus.id) {
      final originalIndex =
          currentVisibleColumn.indexWhere((task) => task.id == dragged.id);
      if (originalIndex >= 0 && originalIndex < visibleIndex) {
        visibleIndex -= 1;
      }
    }

    final fullPeers = _allTasksFor(targetStatus)
        .where((task) => task.id != dragged.id)
        .toList();
    final visiblePeers = fullPeers.where(_matchesFilters).toList();

    if (visiblePeers.isEmpty) return fullPeers.length;
    if (visibleIndex <= 0) {
      return fullPeers.indexWhere((task) => task.id == visiblePeers.first.id);
    }
    if (visibleIndex >= visiblePeers.length) {
      final lastIndex =
          fullPeers.indexWhere((task) => task.id == visiblePeers.last.id);
      return lastIndex + 1;
    }
    return fullPeers.indexWhere(
      (task) => task.id == visiblePeers[visibleIndex].id,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.statuses.isEmpty) {
      return const Center(child: Text('وضعیتی برای برد تعریف نشده است.'));
    }

    return Column(
      children: [
        _filterBar(context),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : MediaQuery.sizeOf(context).height * .72;
              return Scrollbar(
                controller: _horizontal,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 22),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.statuses.map((status) {
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 12),
                        child: SizedBox(
                          width: 310,
                          height: height > 360 ? height - 20 : 360,
                          child: _column(context, status),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _filterBar(BuildContext context) {
    final assignees = _assigneeOptions;
    final labels = _labelOptions;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: GlassSurface(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 230,
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'جستجو در برد',
                ),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                value: _priorityFilter,
                isDense: true,
                decoration: const InputDecoration(labelText: 'اولویت'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('همه')),
                  DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                  DropdownMenuItem(value: 'normal', child: Text('Normal')),
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                ],
                onChanged: (value) =>
                    setState(() => _priorityFilter = value ?? 'all'),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<int>(
                value: _assigneeFilterId ?? 0,
                isDense: true,
                decoration: const InputDecoration(labelText: 'مسئول'),
                items: [
                  const DropdownMenuItem<int>(
                    value: 0,
                    child: Text('همه'),
                  ),
                  ...assignees.map(
                    (e) => DropdownMenuItem<int>(
                      value: e.userId,
                      child: Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(
                  () => _assigneeFilterId = value == 0 ? null : value,
                ),
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<int>(
                value: _labelFilterId ?? 0,
                isDense: true,
                decoration: const InputDecoration(labelText: 'برچسب'),
                items: [
                  const DropdownMenuItem<int>(
                    value: 0,
                    child: Text('همه'),
                  ),
                  ...labels.map(
                    (e) => DropdownMenuItem<int>(
                      value: e.id,
                      child: Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(
                  () => _labelFilterId = value == 0 ? null : value,
                ),
              ),
            ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                value: _dueFilter,
                isDense: true,
                decoration: const InputDecoration(labelText: 'سررسید'),
                items: const [
                  DropdownMenuItem(value: 'any', child: Text('همه')),
                  DropdownMenuItem(value: 'overdue', child: Text('گذشته')),
                  DropdownMenuItem(value: 'today', child: Text('امروز')),
                  DropdownMenuItem(value: 'upcoming', child: Text('آینده')),
                  DropdownMenuItem(value: 'none', child: Text('بدون تاریخ')),
                ],
                onChanged: (value) =>
                    setState(() => _dueFilter = value ?? 'any'),
              ),
            ),
            if (_activeFilterCount > 0)
              TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: Text('پاک‌کردن ($_activeFilterCount)'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _column(BuildContext context, TaskStatusModel status) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _statusColor(context, status.color);
    final items = _tasksFor(status);
    final controller = _controllerFor(status.id);
    final creating = _creatingStatusIds.contains(status.id);

    return GlassSurface(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !creating,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _quickCreate(status),
                  decoration: const InputDecoration(
                    hintText: 'افزودن کار…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'افزودن',
                onPressed: creating ? null : () => _quickCreate(status),
                icon: creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Expanded(
            child: ListView.builder(
              itemCount: items.length * 2 + 1,
              itemBuilder: (context, index) {
                if (index.isEven) {
                  final zoneIndex = index ~/ 2;
                  return _dropZone(
                    context,
                    status,
                    items,
                    zoneIndex,
                    accent,
                  );
                }
                final task = items[index ~/ 2];
                return _draggableCard(context, task, scheme);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropZone(
    BuildContext context,
    TaskStatusModel status,
    List<TaskModel> items,
    int zoneIndex,
    Color accent,
  ) {
    return DragTarget<TaskModel>(
      onWillAccept: (task) => task != null,
      onAccept: (task) {
        final targetIndex =
            _absoluteTargetIndex(task, status, items, zoneIndex);
        widget.onMove(task, status.id, targetIndex);
      },
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: active ? 34 : 10,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: .14) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: active
                ? Border.all(color: accent.withValues(alpha: .55))
                : null,
          ),
          alignment: Alignment.center,
          child: active
              ? Text(
                  'رها کنید',
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _draggableCard(
    BuildContext context,
    TaskModel task,
    ColorScheme scheme,
  ) {
    final card = _boardCard(context, task, scheme);
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Draggable<TaskModel>(
        data: task,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 286,
            child: Opacity(
              opacity: .94,
              child: _feedbackCard(context, task),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: .28, child: card),
        child: card,
      ),
    );
  }

  Widget _feedbackCard(BuildContext context, TaskModel task) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: .35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Text(
        task.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _boardCard(
    BuildContext context,
    TaskModel task,
    ColorScheme scheme,
  ) {
    final due = task.dueAt?.toLocal();
    final overdue =
        due != null && !task.isCompleted && due.isBefore(DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => widget.onOpen(task),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: .48),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .52),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    task.isCompleted
                        ? Icons.check_circle_rounded
                        : Icons.drag_indicator_rounded,
                    size: 18,
                    color: task.isCompleted
                        ? scheme.primary
                        : scheme.outline,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: task.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              if (task.assignees.isNotEmpty || due != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (task.assignees.isNotEmpty)
                      Expanded(
                        child: Text(
                          task.assignees.map((e) => e.name).join('، '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    else
                      const Spacer(),
                    if (due != null)
                      Text(
                        DateFormat('MM/dd').format(due),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color:
                                  overdue ? scheme.error : scheme.outline,
                              fontWeight:
                                  overdue ? FontWeight.w700 : null,
                            ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
