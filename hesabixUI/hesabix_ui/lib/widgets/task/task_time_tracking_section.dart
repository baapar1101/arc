import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:intl/intl.dart';

class TaskTimeTrackingSection extends StatefulWidget {
  final int businessId;
  final TaskModel task;

  const TaskTimeTrackingSection({
    super.key,
    required this.businessId,
    required this.task,
  });

  @override
  State<TaskTimeTrackingSection> createState() =>
      _TaskTimeTrackingSectionState();
}

class _TaskTimeTrackingSectionState extends State<TaskTimeTrackingSection> {
  late final TaskService _service;
  List<TaskTimeEntryModel> _entries = const [];
  TaskTimeEntryModel? _active;
  Timer? _ticker;
  bool _loading = true;
  bool _busy = false;
  int _totalSeconds = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = TaskService(ApiClient());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _active != null) setState(() {});
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant TaskTimeTrackingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _service.listTimeEntries(
          businessId: widget.businessId,
          taskId: widget.task.id,
          limit: 50,
        ),
        _service.getActiveTimer(businessId: widget.businessId),
      ]);
      final entryData = results[0] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _entries =
            (entryData['items'] as List<TaskTimeEntryModel>?) ?? const [];
        _totalSeconds =
            (entryData['total_seconds'] as num?)?.toInt() ?? 0;
        _active = results[1] as TaskTimeEntryModel?;
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

  String _duration(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final hours = safe ~/ 3600;
    final minutes = (safe % 3600) ~/ 60;
    final secs = safe % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  int _activeSeconds(TaskTimeEntryModel entry) {
    final started = entry.startedAt.toUtc();
    return DateTime.now().toUtc().difference(started).inSeconds;
  }

  Future<void> _start() async {
    if (_busy || _active != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entry = await _service.startTimer(
        businessId: widget.businessId,
        taskId: widget.task.id,
      );
      if (!mounted) return;
      setState(() => _active = entry);
    } catch (e) {
      if (mounted) {
        setState(() => _error = ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy || _active == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.stopTimer(businessId: widget.businessId);
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manual() async {
    if (_busy) return;
    final data = await showGlassDialog<_ManualTimeData>(
      context: context,
      builder: (_) => const _ManualTimeDialog(),
    );
    if (data == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final end = DateTime(
        data.day.year,
        data.day.month,
        data.day.day,
        data.endHour,
        data.endMinute,
      );
      final start = end.subtract(Duration(minutes: data.durationMinutes));
      await _service.createTimeEntry(
        businessId: widget.businessId,
        taskId: widget.task.id,
        startedAt: start,
        endedAt: end,
        description: data.description,
        billable: data.billable,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(TaskTimeEntryModel entry) async {
    if (_busy || entry.isActive) return;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف زمان ثبت‌شده'),
        content: Text('ثبت زمان ${_duration(entry.durationSeconds ?? 0)} حذف شود؟'),
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
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _service.deleteTimeEntry(
        businessId: widget.businessId,
        entryId: entry.id,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeHere = _active?.taskId == widget.task.id;
    final activeElsewhere = _active != null && !activeHere;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Time Tracking',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              _duration(
                _totalSeconds +
                    (activeHere ? _activeSeconds(_active!) : 0),
              ),
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        if (_loading)
          const Center(child: CircularProgressIndicator(strokeWidth: 2))
        else ...[
          if (activeElsewhere)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Timer روی کار #${_active!.taskId} فعال است. ابتدا آن را متوقف کنید.',
              ),
            ),
          Row(
            children: [
              Expanded(
                child: activeHere
                    ? FilledButton.icon(
                        onPressed: _busy ? null : _stop,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: Text(
                          'توقف · ${_duration(_activeSeconds(_active!))}',
                        ),
                      )
                    : FilledButton.icon(
                        onPressed:
                            _busy || activeElsewhere ? null : _start,
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('شروع Timer'),
                      ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _manual,
                icon: const Icon(Icons.add_alarm_outlined),
                label: const Text('ثبت دستی'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_entries.isEmpty)
            Text(
              'زمانی برای این کار ثبت نشده است.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ..._entries.take(8).map(
              (entry) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  entry.billable
                      ? Icons.attach_money_rounded
                      : Icons.timer_outlined,
                  size: 20,
                ),
                title: Text(
                  entry.isActive
                      ? 'در حال اجرا'
                      : _duration(entry.durationSeconds ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  [
                    DateFormat('yyyy/MM/dd HH:mm')
                        .format(entry.startedAt.toLocal()),
                    if (entry.userName != null) entry.userName!,
                    if (entry.description?.trim().isNotEmpty == true)
                      entry.description!,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: entry.isActive
                    ? null
                    : IconButton(
                        tooltip: 'حذف',
                        onPressed: _busy ? null : () => _delete(entry),
                        icon: const Icon(Icons.delete_outline, size: 19),
                      ),
              ),
            ),
        ],
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

class _ManualTimeData {
  final DateTime day;
  final int endHour;
  final int endMinute;
  final int durationMinutes;
  final String? description;
  final bool billable;

  const _ManualTimeData({
    required this.day,
    required this.endHour,
    required this.endMinute,
    required this.durationMinutes,
    this.description,
    required this.billable,
  });
}

class _ManualTimeDialog extends StatefulWidget {
  const _ManualTimeDialog();

  @override
  State<_ManualTimeDialog> createState() => _ManualTimeDialogState();
}

class _ManualTimeDialogState extends State<_ManualTimeDialog> {
  final TextEditingController _duration =
      TextEditingController(text: '60');
  final TextEditingController _description = TextEditingController();
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  TimeOfDay _end = TimeOfDay.now();
  bool _billable = false;

  @override
  void dispose() {
    _duration.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('ثبت دستی زمان'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _duration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'مدت (دقیقه)',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final value = await showDatePicker(
                          context: context,
                          initialDate: _day,
                          firstDate: DateTime(2020),
                          lastDate:
                              DateTime.now().add(const Duration(days: 3650)),
                        );
                        if (value != null) setState(() => _day = value);
                      },
                      icon: const Icon(Icons.event_outlined),
                      label: Text(DateFormat('yyyy/MM/dd').format(_day)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final value = await showTimePicker(
                          context: context,
                          initialTime: _end,
                        );
                        if (value != null) setState(() => _end = value);
                      },
                      icon: const Icon(Icons.schedule),
                      label: Text(_end.format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'توضیح'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Billable'),
                value: _billable,
                onChanged: (value) => setState(() => _billable = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              final duration = int.tryParse(_duration.text.trim()) ?? 0;
              if (duration <= 0) return;
              Navigator.pop(
                context,
                _ManualTimeData(
                  day: _day,
                  endHour: _end.hour,
                  endMinute: _end.minute,
                  durationMinutes: duration,
                  description: _description.text.trim().isEmpty
                      ? null
                      : _description.text.trim(),
                  billable: _billable,
                ),
              );
            },
            child: const Text('ثبت'),
          ),
        ],
      );
}
