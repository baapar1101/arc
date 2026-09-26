import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:intl/intl.dart';

class TaskRecurrenceReminderSection extends StatefulWidget {
  final int businessId;
  final TaskModel task;
  final Future<TaskModel?> Function(Map<String, dynamic> data) onUpdate;

  const TaskRecurrenceReminderSection({
    super.key,
    required this.businessId,
    required this.task,
    required this.onUpdate,
  });

  @override
  State<TaskRecurrenceReminderSection> createState() =>
      _TaskRecurrenceReminderSectionState();
}

class _TaskRecurrenceReminderSectionState
    extends State<TaskRecurrenceReminderSection> {
  late final TaskService _service;
  List<TaskReminderModel> _reminders = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  static const Map<String, String?> _rules = {
    'بدون تکرار': null,
    'روزانه': 'FREQ=DAILY;INTERVAL=1',
    'روزهای کاری': 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
    'هفتگی': 'FREQ=WEEKLY;INTERVAL=1',
    'ماهانه': 'FREQ=MONTHLY;INTERVAL=1',
    'سالانه': 'FREQ=YEARLY;INTERVAL=1',
  };

  @override
  void initState() {
    super.initState();
    _service = TaskService(ApiClient());
    _load();
  }

  @override
  void didUpdateWidget(covariant TaskRecurrenceReminderSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.listReminders(
        businessId: widget.businessId,
        taskId: widget.task.id,
      );
      if (!mounted) return;
      setState(() {
        _reminders = items;
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

  String _ruleLabel(String? rule) {
    for (final entry in _rules.entries) {
      if (entry.value == rule) return entry.key;
    }
    return rule == null || rule.isEmpty ? 'بدون تکرار' : 'سفارشی';
  }

  Future<void> _setRecurrence(String? rule) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onUpdate({
        'recurrence_rule': rule,
        if (rule == null) 'recurrence_timezone': null,
        if (rule == null) 'recurrence_end_at': null,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickRecurrenceEnd() async {
    var selected = widget.task.recurrenceEndAt?.toLocal() ??
        DateTime.now().add(const Duration(days: 90));
    final result = await showGlassDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInnerState) => AlertDialog(
          title: const Text('پایان تکرار'),
          content: SizedBox(
            width: 360,
            height: 330,
            child: CalendarDatePicker(
              initialDate: selected,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 3650)),
              onDateChanged: (value) =>
                  setInnerState(() => selected = value),
            ),
          ),
          actions: [
            if (widget.task.recurrenceEndAt != null)
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, DateTime.fromMillisecondsSinceEpoch(0)),
                child: const Text('بدون تاریخ پایان'),
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
    await widget.onUpdate({
      'recurrence_end_at': result.millisecondsSinceEpoch == 0
          ? null
          : DateTime(result.year, result.month, result.day, 23, 59)
              .toUtc()
              .toIso8601String(),
    });
  }

  Future<void> _addReminder(String relativeTo, int offsetMinutes) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.createReminder(
        businessId: widget.businessId,
        taskId: widget.task.id,
        relativeTo: relativeTo,
        offsetMinutes: offsetMinutes,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteReminder(TaskReminderModel reminder) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.deleteReminder(
        businessId: widget.businessId,
        taskId: widget.task.id,
        reminderId: reminder.id,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _reminderLabel(TaskReminderModel reminder) {
    final base = reminder.relativeTo == 'start' ? 'شروع' : 'سررسید';
    final offset = reminder.offsetMinutes ?? 0;
    if (reminder.relativeTo == null) {
      return DateFormat('yyyy/MM/dd HH:mm')
          .format(reminder.remindAt.toLocal());
    }
    if (offset == 0) return 'در زمان $base';
    if (offset % 1440 == 0) {
      return '${offset ~/ 1440} روز قبل از $base';
    }
    if (offset % 60 == 0) {
      return '${offset ~/ 60} ساعت قبل از $base';
    }
    return '$offset دقیقه قبل از $base';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedRule = _rules.values.contains(widget.task.recurrenceRule)
        ? widget.task.recurrenceRule
        : '__custom__';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Recurrence & Reminders',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 9),
        DropdownButtonFormField<String?>(
          value: selectedRule,
          decoration: const InputDecoration(
            labelText: 'تکرار',
            isDense: true,
          ),
          items: [
            ..._rules.entries.map(
              (entry) => DropdownMenuItem<String?>(
                value: entry.value,
                child: Text(entry.key),
              ),
            ),
            if (selectedRule == '__custom__')
              DropdownMenuItem<String?>(
                value: '__custom__',
                child: Text(_ruleLabel(widget.task.recurrenceRule)),
              ),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value != '__custom__') _setRecurrence(value);
                },
        ),
        if (widget.task.recurrenceRule != null) ...[
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.public_rounded),
            title: Text(widget.task.recurrenceTimezone ?? 'Timezone کسب‌وکار'),
            subtitle: Text(
              widget.task.recurrenceEndAt == null
                  ? 'بدون تاریخ پایان'
                  : 'تا ${DateFormat('yyyy/MM/dd').format(widget.task.recurrenceEndAt!.toLocal())}',
            ),
            trailing: IconButton(
              tooltip: 'تاریخ پایان',
              onPressed: _busy ? null : _pickRecurrenceEnd,
              icon: const Icon(Icons.event_outlined),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
              child: Text(
                'یادآورها',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'یادآور جدید',
              enabled: !_busy,
              onSelected: (value) {
                switch (value) {
                  case 'due0':
                    _addReminder('due', 0);
                    break;
                  case 'due15':
                    _addReminder('due', 15);
                    break;
                  case 'due60':
                    _addReminder('due', 60);
                    break;
                  case 'due1440':
                    _addReminder('due', 1440);
                    break;
                  case 'start15':
                    _addReminder('start', 15);
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'due0', child: Text('در زمان سررسید')),
                PopupMenuItem(value: 'due15', child: Text('۱۵ دقیقه قبل از سررسید')),
                PopupMenuItem(value: 'due60', child: Text('۱ ساعت قبل از سررسید')),
                PopupMenuItem(value: 'due1440', child: Text('۱ روز قبل از سررسید')),
                PopupMenuItem(value: 'start15', child: Text('۱۵ دقیقه قبل از شروع')),
              ],
              child: const Chip(
                avatar: Icon(Icons.add_alert_outlined, size: 17),
                label: Text('افزودن'),
              ),
            ),
          ],
        ),
        if (_loading)
          const Center(child: CircularProgressIndicator(strokeWidth: 2))
        else if (_reminders.isEmpty)
          Text(
            'یادآوری ثبت نشده است.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          ..._reminders.map(
            (reminder) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                reminder.sentAt == null
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none_rounded,
              ),
              title: Text(_reminderLabel(reminder)),
              subtitle: Text(
                DateFormat('yyyy/MM/dd HH:mm')
                    .format(reminder.remindAt.toLocal()),
              ),
              trailing: IconButton(
                tooltip: 'حذف یادآور',
                onPressed: _busy ? null : () => _deleteReminder(reminder),
                icon: const Icon(Icons.close_rounded, size: 19),
              ),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          GlassSurface(
            padding: const EdgeInsets.all(9),
            borderRadius: BorderRadius.circular(9),
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
