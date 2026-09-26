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
  final Map<int, TextEditingController> _quickControllers = {};
  final Set<int> _creatingStatusIds = {};

  @override
  void dispose() {
    _horizontal.dispose();
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

  List<TaskModel> _tasksFor(TaskStatusModel status) {
    final items = widget.tasks
        .where((task) => task.statusId == status.id)
        .toList();
    items.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
    });
    return items;
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

  int _normalizedTargetIndex(
    TaskModel dragged,
    TaskStatusModel targetStatus,
    List<TaskModel> currentColumn,
    int zoneIndex,
  ) {
    if (dragged.statusId != targetStatus.id) return zoneIndex;
    final originalIndex =
        currentColumn.indexWhere((task) => task.id == dragged.id);
    if (originalIndex >= 0 && originalIndex < zoneIndex) {
      return zoneIndex - 1;
    }
    return zoneIndex;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.statuses.isEmpty) {
      return const Center(child: Text('وضعیتی برای برد تعریف نشده است.'));
    }

    return LayoutBuilder(
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
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.statuses.map((status) {
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12),
                  child: SizedBox(
                    width: 310,
                    height: height > 360 ? height - 28 : 360,
                    child: _column(context, status),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
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
            _normalizedTargetIndex(task, status, items, zoneIndex);
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
