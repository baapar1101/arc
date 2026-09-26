import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:intl/intl.dart';

enum TaskCalendarMode { month, week, day, agenda }

class TaskCalendarView extends StatefulWidget {
  final List<TaskModel> tasks;
  final ValueChanged<TaskModel> onOpen;
  final Future<TaskModel?> Function(TaskModel task, DateTime targetDate)
      onReschedule;

  const TaskCalendarView({
    super.key,
    required this.tasks,
    required this.onOpen,
    required this.onReschedule,
  });

  @override
  State<TaskCalendarView> createState() => _TaskCalendarViewState();
}

class _TaskCalendarViewState extends State<TaskCalendarView> {
  TaskCalendarMode _mode = TaskCalendarMode.month;
  DateTime _anchor = DateUtils.dateOnly(DateTime.now());
  DateTime _selected = DateUtils.dateOnly(DateTime.now());
  final Set<int> _moving = {};

  DateTime _day(DateTime value) => DateUtils.dateOnly(value.toLocal());

  bool _occursOn(TaskModel task, DateTime day) {
    final start = task.startAt == null ? null : _day(task.startAt!);
    final due = task.dueAt == null ? null : _day(task.dueAt!);
    final target = DateUtils.dateOnly(day);
    if (start != null && due != null) {
      return !target.isBefore(start) && !target.isAfter(due);
    }
    if (due != null) return DateUtils.isSameDay(due, target);
    if (start != null) return DateUtils.isSameDay(start, target);
    return false;
  }

  List<TaskModel> _tasksOn(DateTime day) {
    final items = widget.tasks.where((task) => _occursOn(task, day)).toList();
    items.sort((a, b) {
      final ad = (a.dueAt ?? a.startAt)?.toLocal();
      final bd = (b.dueAt ?? b.startAt)?.toLocal();
      if (ad == null && bd == null) return a.id.compareTo(b.id);
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });
    return items;
  }

  Future<void> _drop(TaskModel task, DateTime day) async {
    if (_moving.contains(task.id)) return;
    setState(() => _moving.add(task.id));
    try {
      await widget.onReschedule(task, DateUtils.dateOnly(day));
    } finally {
      if (mounted) setState(() => _moving.remove(task.id));
    }
  }

  void _goToday() {
    final now = DateUtils.dateOnly(DateTime.now());
    setState(() {
      _anchor = now;
      _selected = now;
    });
  }

  void _shift(int delta) {
    setState(() {
      switch (_mode) {
        case TaskCalendarMode.month:
          _anchor = DateTime(_anchor.year, _anchor.month + delta, 1);
          break;
        case TaskCalendarMode.week:
          _anchor = _anchor.add(Duration(days: 7 * delta));
          _selected = _anchor;
          break;
        case TaskCalendarMode.day:
          _anchor = _anchor.add(Duration(days: delta));
          _selected = _anchor;
          break;
        case TaskCalendarMode.agenda:
          _anchor = _anchor.add(Duration(days: 30 * delta));
          _selected = _anchor;
          break;
      }
    });
  }

  String _headerLabel() {
    switch (_mode) {
      case TaskCalendarMode.month:
        return DateFormat('MMMM yyyy').format(_anchor);
      case TaskCalendarMode.week:
        final start = _weekStart(_anchor);
        final end = start.add(const Duration(days: 6));
        return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}';
      case TaskCalendarMode.day:
        return DateFormat('EEEE, MMM d, yyyy').format(_anchor);
      case TaskCalendarMode.agenda:
        return 'Agenda · ${DateFormat('MMM yyyy').format(_anchor)}';
    }
  }

  DateTime _weekStart(DateTime value) {
    final d = DateUtils.dateOnly(value);
    return d.subtract(Duration(days: d.weekday % 7));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GlassSurface(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          borderRadius: BorderRadius.zero,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'قبلی',
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 190),
                child: Text(
                  _headerLabel(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'بعدی',
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              OutlinedButton(
                onPressed: _goToday,
                child: const Text('امروز'),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<TaskCalendarMode>(
                  value: _mode,
                  decoration: const InputDecoration(
                    labelText: 'نمای تقویم',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: TaskCalendarMode.month, child: Text('ماه')),
                    DropdownMenuItem(value: TaskCalendarMode.week, child: Text('هفته')),
                    DropdownMenuItem(value: TaskCalendarMode.day, child: Text('روز')),
                    DropdownMenuItem(value: TaskCalendarMode.agenda, child: Text('Agenda')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _mode = value);
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_mode) {
            TaskCalendarMode.month => _monthView(),
            TaskCalendarMode.week => _weekView(),
            TaskCalendarMode.day => _dayView(_anchor),
            TaskCalendarMode.agenda => _agendaView(),
          },
        ),
      ],
    );
  }

  Widget _monthView() {
    final first = DateTime(_anchor.year, _anchor.month, 1);
    final gridStart = first.subtract(Duration(days: first.weekday % 7));
    final days = List.generate(42, (i) => gridStart.add(Duration(days: i)));
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              _WeekLabel('Sun'), _WeekLabel('Mon'), _WeekLabel('Tue'),
              _WeekLabel('Wed'), _WeekLabel('Thu'), _WeekLabel('Fri'),
              _WeekLabel('Sat'),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: .92,
              crossAxisSpacing: 5,
              mainAxisSpacing: 5,
            ),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final day = days[index];
              return _dayCell(day, outside: day.month != _anchor.month, compact: true);
            },
          ),
        ),
      ],
    );
  }

  Widget _weekView() {
    final start = _weekStart(_anchor);
    final days = List.generate(7, (i) => start.add(Duration(days: i)));
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(10),
      children: days.map((day) => SizedBox(
        width: 250,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: _dayCell(day, compact: false),
        ),
      )).toList(),
    );
  }

  Widget _dayView(DateTime day) {
    final tasks = _tasksOn(day);
    return DragTarget<TaskModel>(
      onWillAccept: (task) => task != null,
      onAccept: (task) => _drop(task, day),
      builder: (context, candidates, rejected) => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (candidates.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('برای انتقال به این روز رها کنید', textAlign: TextAlign.center),
            ),
          if (tasks.isEmpty)
            const GlassSurface(
              padding: EdgeInsets.all(36),
              child: Center(child: Text('کاری در این روز نیست.')),
            )
          else
            ...tasks.map(_taskTile),
        ],
      ),
    );
  }

  Widget _agendaView() {
    final start = DateUtils.dateOnly(_anchor);
    final days = List.generate(31, (i) => start.add(Duration(days: i)));
    final nonEmpty = days.where((day) => _tasksOn(day).isNotEmpty).toList();
    if (nonEmpty.isEmpty) {
      return const Center(child: Text('کاری در این بازه ثبت نشده است.'));
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: nonEmpty.map((day) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              DateFormat('EEEE · yyyy/MM/dd').format(day),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            ..._tasksOn(day).map(_taskTile),
          ],
        ),
      )).toList(),
    );
  }

  Widget _dayCell(DateTime day, {bool outside = false, required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    final tasks = _tasksOn(day);
    final selected = DateUtils.isSameDay(day, _selected);
    final today = DateUtils.isSameDay(day, DateTime.now());
    return DragTarget<TaskModel>(
      onWillAccept: (task) => task != null,
      onAccept: (task) => _drop(task, day),
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _selected = DateUtils.dateOnly(day);
              _anchor = DateUtils.dateOnly(day);
              if (compact) _mode = TaskCalendarMode.day;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: active
                  ? scheme.primary.withValues(alpha: .11)
                  : scheme.surface.withValues(alpha: selected ? .52 : .25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active || selected
                    ? scheme.primary.withValues(alpha: .46)
                    : scheme.outlineVariant.withValues(alpha: .42),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 27, height: 27,
                      alignment: Alignment.center,
                      decoration: today
                          ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
                          : null,
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color: today ? scheme.onPrimary : outside ? scheme.outline : null,
                          fontWeight: today || selected ? FontWeight.w800 : null,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (tasks.isNotEmpty)
                      Text('${tasks.length}', style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: compact
                      ? Column(
                          children: [
                            ...tasks.take(3).map(_compactTask),
                            if (tasks.length > 3)
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  '+${tasks.length - 3}',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                          ],
                        )
                      : ListView(children: tasks.map(_compactTask).toList()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _compactTask(TaskModel task) {
    final scheme = Theme.of(context).colorScheme;
    final child = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        task.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
    return Draggable<TaskModel>(
      data: task,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 210,
          child: GlassSurface(
            padding: const EdgeInsets.all(9),
            child: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: .3, child: child),
      child: GestureDetector(onTap: () => widget.onOpen(task), child: child),
    );
  }

  Widget _taskTile(TaskModel task) {
    final due = task.dueAt?.toLocal();
    final start = task.startAt?.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Draggable<TaskModel>(
        data: task,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 300,
            child: GlassSurface(padding: const EdgeInsets.all(10), child: Text(task.title)),
          ),
        ),
        child: GlassSurface(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(task.isCompleted ? Icons.check_circle_rounded : Icons.event_note_outlined),
            title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text([
              if (start != null) 'شروع ${DateFormat('HH:mm').format(start)}',
              if (due != null) 'سررسید ${DateFormat('HH:mm').format(due)}',
            ].join(' · ')),
            trailing: _moving.contains(task.id)
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.drag_indicator_rounded),
            onTap: () => widget.onOpen(task),
          ),
        ),
      ),
    );
  }
}

class _WeekLabel extends StatelessWidget {
  final String text;
  const _WeekLabel(this.text);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}
