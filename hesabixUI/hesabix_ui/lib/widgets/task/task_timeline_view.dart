import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/project_model.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:intl/intl.dart';

enum TaskTimelineZoom { day, week, month }

class TaskTimelineView extends StatefulWidget {
  final List<TaskModel> tasks;
  final List<Map<String, dynamic>> dependencies;
  final List<ProjectMilestoneModel> milestones;
  final ValueChanged<TaskModel> onOpen;

  const TaskTimelineView({
    super.key,
    required this.tasks,
    required this.dependencies,
    this.milestones = const [],
    required this.onOpen,
  });

  @override
  State<TaskTimelineView> createState() => _TaskTimelineViewState();
}

class _TaskTimelineViewState extends State<TaskTimelineView> {
  TaskTimelineZoom _zoom = TaskTimelineZoom.week;
  final ScrollController _horizontal = ScrollController();

  static const double _labelWidth = 250;
  static const double _headerHeight = 48;
  static const double _rowHeight = 58;

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  DateTime _day(DateTime value) => DateUtils.dateOnly(value.toLocal());

  List<TaskModel> get _scheduled {
    final items = widget.tasks
        .where((task) => task.startAt != null || task.dueAt != null)
        .toList();
    items.sort((a, b) {
      final as = _day(a.startAt ?? a.dueAt!);
      final bs = _day(b.startAt ?? b.dueAt!);
      final byStart = as.compareTo(bs);
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });
    return items;
  }

  double get _pixelsPerDay {
    switch (_zoom) {
      case TaskTimelineZoom.day:
        return 38;
      case TaskTimelineZoom.week:
        return 11;
      case TaskTimelineZoom.month:
        return 4;
    }
  }

  ({DateTime start, DateTime end}) _range(List<TaskModel> tasks) {
    if (tasks.isEmpty) {
      final today = DateUtils.dateOnly(DateTime.now());
      return (
        start: today.subtract(const Duration(days: 7)),
        end: today.add(const Duration(days: 35)),
      );
    }
    DateTime? minDate;
    DateTime? maxDate;
    for (final task in tasks) {
      final start = _day(task.startAt ?? task.dueAt!);
      final end = _day(task.dueAt ?? task.startAt!);
      if (minDate == null || start.isBefore(minDate)) minDate = start;
      if (maxDate == null || end.isAfter(maxDate)) maxDate = end;
    }
    final pad = _zoom == TaskTimelineZoom.day
        ? 3
        : _zoom == TaskTimelineZoom.week
            ? 14
            : 35;
    return (
      start: minDate!.subtract(Duration(days: pad)),
      end: maxDate!.add(Duration(days: pad)),
    );
  }

  double _x(DateTime date, DateTime rangeStart) {
    final minutes = _day(date).difference(rangeStart).inMinutes;
    return (minutes / 1440) * _pixelsPerDay;
  }

  ({DateTime start, DateTime end}) _taskRange(TaskModel task) {
    var start = _day(task.startAt ?? task.dueAt!);
    var end = _day(task.dueAt ?? task.startAt!);
    if (end.isBefore(start)) {
      final tmp = start;
      start = end;
      end = tmp;
    }
    return (start: start, end: end);
  }

  List<DateTime> _markers(DateTime start, DateTime end) {
    final result = <DateTime>[];
    switch (_zoom) {
      case TaskTimelineZoom.day:
        for (var d = start;
            !d.isAfter(end);
            d = d.add(const Duration(days: 1))) {
          result.add(d);
        }
        break;
      case TaskTimelineZoom.week:
        var d = start.subtract(Duration(days: start.weekday % 7));
        while (!d.isAfter(end)) {
          result.add(d);
          d = d.add(const Duration(days: 7));
        }
        break;
      case TaskTimelineZoom.month:
        var d = DateTime(start.year, start.month, 1);
        while (!d.isAfter(end)) {
          result.add(d);
          d = DateTime(d.year, d.month + 1, 1);
        }
        break;
    }
    return result;
  }

  String _markerLabel(DateTime date) {
    switch (_zoom) {
      case TaskTimelineZoom.day:
        return DateFormat('d MMM').format(date);
      case TaskTimelineZoom.week:
        return DateFormat('d MMM').format(date);
      case TaskTimelineZoom.month:
        return DateFormat('MMM yyyy').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _scheduled;
    final unscheduled = widget.tasks.length - tasks.length;
    final range = _range(tasks);
    final totalDays = range.end.difference(range.start).inDays + 1;
    final timelineWidth = math.max(820.0, totalDays * _pixelsPerDay + 80);
    final contentHeight =
        _headerHeight + math.max(1, tasks.length) * _rowHeight;
    final markers = _markers(range.start, range.end);
    final rowIndex = <int, int>{
      for (var i = 0; i < tasks.length; i++) tasks[i].id: i,
    };
    final taskById = <int, TaskModel>{
      for (final task in tasks) task.id: task,
    };

    return Column(
      children: [
        GlassSurface(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          borderRadius: BorderRadius.zero,
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Timeline / Gantt',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              if (unscheduled > 0)
                Chip(
                  avatar: const Icon(Icons.event_busy_outlined, size: 17),
                  label: Text('$unscheduled بدون تاریخ'),
                ),
              SizedBox(
                width: 165,
                child: DropdownButtonFormField<TaskTimelineZoom>(
                  value: _zoom,
                  decoration: const InputDecoration(
                    labelText: 'مقیاس',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: TaskTimelineZoom.day,
                      child: Text('روز'),
                    ),
                    DropdownMenuItem(
                      value: TaskTimelineZoom.week,
                      child: Text('هفته'),
                    ),
                    DropdownMenuItem(
                      value: TaskTimelineZoom.month,
                      child: Text('ماه'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _zoom = value);
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: tasks.isEmpty
              ? const Center(
                  child: Text(
                    'برای نمایش Timeline حداقل یک کار با تاریخ شروع یا سررسید لازم است.',
                    textAlign: TextAlign.center,
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final timelineViewport =
                        math.max(120.0, constraints.maxWidth - _labelWidth);
                    return SingleChildScrollView(
                      child: SizedBox(
                        height: contentHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: _labelWidth,
                              height: contentHeight,
                              child: _labelsColumn(tasks),
                            ),
                            SizedBox(
                              width: timelineViewport,
                              height: contentHeight,
                              child: Scrollbar(
                                controller: _horizontal,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  controller: _horizontal,
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: timelineWidth,
                                    height: contentHeight,
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: _TimelinePainter(
                                              rangeStart: range.start,
                                              pixelsPerDay: _pixelsPerDay,
                                              headerHeight: _headerHeight,
                                              rowHeight: _rowHeight,
                                              markers: markers,
                                              today:
                                                  DateUtils.dateOnly(DateTime.now()),
                                              rowIndex: rowIndex,
                                              taskById: taskById,
                                              dependencies: widget.dependencies,
                                              gridColor: Theme.of(context)
                                                  .colorScheme
                                                  .outlineVariant
                                                  .withValues(alpha: .35),
                                              dependencyColor: Theme.of(context)
                                                  .colorScheme
                                                  .outline
                                                  .withValues(alpha: .7),
                                              todayColor:
                                                  Theme.of(context).colorScheme.error,
                                            ),
                                          ),
                                        ),
                                        ...markers.map(
                                          (date) => Positioned(
                                            left: _x(date, range.start) + 4,
                                            top: 7,
                                            child: Text(
                                              _markerLabel(date),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall,
                                            ),
                                          ),
                                        ),
                                        ...widget.milestones
                                            .where((m) => m.targetAt != null)
                                            .map(
                                              (milestone) => _milestoneMarker(
                                                context,
                                                milestone,
                                                range.start,
                                                contentHeight,
                                              ),
                                            ),
                                        ...tasks.asMap().entries.map(
                                              (entry) => _taskBar(
                                                context,
                                                entry.value,
                                                entry.key,
                                                range.start,
                                              ),
                                            ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _labelsColumn(List<TaskModel> tasks) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          height: _headerHeight,
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: .28),
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .45),
              ),
            ),
          ),
          child: const Text(
            'کار',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        ...tasks.map(
          (task) => InkWell(
            onTap: () => widget.onOpen(task),
            child: Container(
              height: _rowHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: .28),
                  ),
                ),
              ),
              child: Row(
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: task.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _milestoneMarker(
    BuildContext context,
    ProjectMilestoneModel milestone,
    DateTime rangeStart,
    double contentHeight,
  ) {
    final target = milestone.targetAt!.toLocal();
    final left = _x(target, rangeStart);
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: left - 6,
      top: _headerHeight - 2,
      width: 160,
      height: contentHeight - _headerHeight + 2,
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 6,
              top: 0,
              bottom: 0,
              child: Container(
                width: 1,
                color: scheme.tertiary.withValues(alpha: .55),
              ),
            ),
            Positioned(
              left: 0,
              top: -7,
              child: Tooltip(
                message:
                    '${milestone.title} · ${DateFormat('yyyy/MM/dd').format(target)}',
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 13,
                    height: 13,
                    color: scheme.tertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskBar(
    BuildContext context,
    TaskModel task,
    int row,
    DateTime rangeStart,
  ) {
    final range = _taskRange(task);
    final left = _x(range.start, rangeStart);
    final endX = _x(range.end.add(const Duration(days: 1)), rangeStart);
    final width = math.max(24.0, endX - left);
    final scheme = Theme.of(context).colorScheme;

    return Positioned(
      left: left,
      top: _headerHeight + row * _rowHeight + 11,
      width: width,
      height: 35,
      child: Tooltip(
        message:
            '${task.title}\\n${DateFormat('yyyy/MM/dd').format(range.start)} → ${DateFormat('yyyy/MM/dd').format(range.end)}',
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => widget.onOpen(task),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(
                alpha: task.isCompleted ? .10 : .18,
              ),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: scheme.primary.withValues(alpha: .48),
              ),
            ),
            child: Text(
              task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final DateTime rangeStart;
  final double pixelsPerDay;
  final double headerHeight;
  final double rowHeight;
  final List<DateTime> markers;
  final DateTime today;
  final Map<int, int> rowIndex;
  final Map<int, TaskModel> taskById;
  final List<Map<String, dynamic>> dependencies;
  final Color gridColor;
  final Color dependencyColor;
  final Color todayColor;

  _TimelinePainter({
    required this.rangeStart,
    required this.pixelsPerDay,
    required this.headerHeight,
    required this.rowHeight,
    required this.markers,
    required this.today,
    required this.rowIndex,
    required this.taskById,
    required this.dependencies,
    required this.gridColor,
    required this.dependencyColor,
    required this.todayColor,
  });

  DateTime _day(DateTime value) => DateUtils.dateOnly(value.toLocal());

  double _x(DateTime date) {
    return _day(date).difference(rangeStart).inDays * pixelsPerDay;
  }

  ({DateTime start, DateTime end}) _range(TaskModel task) {
    var start = _day(task.startAt ?? task.dueAt!);
    var end = _day(task.dueAt ?? task.startAt!);
    if (end.isBefore(start)) {
      final t = start;
      start = end;
      end = t;
    }
    return (start: start, end: end);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final marker in markers) {
      final x = _x(marker);
      canvas.drawLine(
        Offset(x, headerHeight),
        Offset(x, size.height),
        gridPaint,
      );
    }
    for (var i = 0; i <= rowIndex.length; i++) {
      final y = headerHeight + i * rowHeight;
      canvas.drawLine(Offset.zero.translate(0, y), Offset(size.width, y), gridPaint);
    }

    final todayX = _x(today);
    if (todayX >= 0 && todayX <= size.width) {
      final todayPaint = Paint()
        ..color = todayColor.withValues(alpha: .72)
        ..strokeWidth = 1.5;
      canvas.drawLine(
        Offset(todayX, headerHeight),
        Offset(todayX, size.height),
        todayPaint,
      );
    }

    final depPaint = Paint()
      ..color = dependencyColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    for (final raw in dependencies) {
      final fromId = (raw['from_task_id'] as num?)?.toInt();
      final toId = (raw['to_task_id'] as num?)?.toInt();
      if (fromId == null || toId == null) continue;
      final fromTask = taskById[fromId];
      final toTask = taskById[toId];
      final fromRow = rowIndex[fromId];
      final toRow = rowIndex[toId];
      if (fromTask == null ||
          toTask == null ||
          fromRow == null ||
          toRow == null) {
        continue;
      }

      final fromRange = _range(fromTask);
      final toRange = _range(toTask);
      final start = Offset(
        _x(fromRange.end.add(const Duration(days: 1))) + 3,
        headerHeight + fromRow * rowHeight + rowHeight / 2,
      );
      final end = Offset(
        _x(toRange.start) - 3,
        headerHeight + toRow * rowHeight + rowHeight / 2,
      );
      final bendX = end.dx >= start.dx
          ? (start.dx + end.dx) / 2
          : math.max(start.dx, end.dx) + 18;

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(bendX, start.dy)
        ..lineTo(bendX, end.dy)
        ..lineTo(end.dx, end.dy);
      canvas.drawPath(path, depPaint);

      final arrow = Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(end.dx - 6, end.dy - 4)
        ..moveTo(end.dx, end.dy)
        ..lineTo(end.dx - 6, end.dy + 4);
      canvas.drawPath(arrow, depPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.pixelsPerDay != pixelsPerDay ||
        oldDelegate.rangeStart != rangeStart ||
        oldDelegate.rowIndex.length != rowIndex.length ||
        oldDelegate.dependencies.length != dependencies.length ||
        oldDelegate.today != today;
  }
}
