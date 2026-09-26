import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:intl/intl.dart';

class ProjectTimeTrackingView extends StatefulWidget {
  final int businessId;
  final int projectId;

  const ProjectTimeTrackingView({
    super.key,
    required this.businessId,
    required this.projectId,
  });

  @override
  State<ProjectTimeTrackingView> createState() =>
      _ProjectTimeTrackingViewState();
}

class _ProjectTimeTrackingViewState extends State<ProjectTimeTrackingView> {
  late final TaskService _service;
  List<TaskTimeEntryModel> _entries = const [];
  int _totalSeconds = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = TaskService(ApiClient());
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.listTimeEntries(
        businessId: widget.businessId,
        projectId: widget.projectId,
        limit: 500,
      );
      if (!mounted) return;
      setState(() {
        _entries =
            (result['items'] as List<TaskTimeEntryModel>?) ?? const [];
        _totalSeconds =
            (result['total_seconds'] as num?)?.toInt() ?? 0;
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
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  Map<int, int> get _byUser {
    final totals = <int, int>{};
    for (final entry in _entries) {
      if (entry.endedAt == null) continue;
      totals.update(
        entry.userId,
        (value) => value + (entry.durationSeconds ?? 0),
        ifAbsent: () => entry.durationSeconds ?? 0,
      );
    }
    return totals;
  }

  Map<int, int> get _byTask {
    final totals = <int, int>{};
    for (final entry in _entries) {
      if (entry.endedAt == null) continue;
      totals.update(
        entry.taskId,
        (value) => value + (entry.durationSeconds ?? 0),
        ifAbsent: () => entry.durationSeconds ?? 0,
      );
    }
    return totals;
  }

  String _userName(int userId) {
    for (final entry in _entries) {
      if (entry.userId == userId && entry.userName?.isNotEmpty == true) {
        return entry.userName!;
      }
    }
    return 'User $userId';
  }

  String _taskName(int taskId) {
    for (final entry in _entries) {
      if (entry.taskId == taskId && entry.taskTitle?.isNotEmpty == true) {
        return entry.taskTitle!;
      }
    }
    return 'Task #$taskId';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: GlassSurface(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('تلاش مجدد'),
              ),
            ],
          ),
        ),
      );
    }

    final billable = _entries
        .where((e) => e.billable && e.endedAt != null)
        .fold<int>(0, (sum, e) => sum + (e.durationSeconds ?? 0));
    final active = _entries.where((e) => e.isActive).length;
    final userTotals = _byUser.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final taskTotals = _byTask.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Metric(
                icon: Icons.timer_outlined,
                label: 'کل زمان',
                value: _duration(_totalSeconds),
              ),
              _Metric(
                icon: Icons.attach_money_rounded,
                label: 'Billable',
                value: _duration(billable),
              ),
              _Metric(
                icon: Icons.people_outline,
                label: 'کاربران',
                value: '${userTotals.length}',
              ),
              _Metric(
                icon: Icons.play_circle_outline,
                label: 'Timer فعال',
                value: '$active',
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (userTotals.isNotEmpty) ...[
            Text(
              'زمان به تفکیک کاربر',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            GlassSurface(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: userTotals
                    .take(8)
                    .map(
                      (row) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: Text(_userName(row.key)),
                        trailing: Text(
                          _duration(row.value),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (taskTotals.isNotEmpty) ...[
            Text(
              'بیشترین زمان روی کارها',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            GlassSurface(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: taskTotals
                    .take(10)
                    .map(
                      (row) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.task_alt_outlined),
                        title: Text(
                          _taskName(row.key),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          _duration(row.value),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Timesheet',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'بروزرسانی',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_entries.isEmpty)
            const GlassSurface(
              padding: EdgeInsets.all(36),
              child: Center(child: Text('هنوز زمانی برای پروژه ثبت نشده است.')),
            )
          else
            ..._entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      entry.isActive
                          ? Icons.play_circle_fill_rounded
                          : entry.billable
                              ? Icons.attach_money_rounded
                              : Icons.timer_outlined,
                      color: entry.isActive ? scheme.primary : null,
                    ),
                    title: Text(
                      entry.taskTitle ?? 'Task #${entry.taskId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        entry.userName ?? 'User ${entry.userId}',
                        DateFormat('yyyy/MM/dd HH:mm')
                            .format(entry.startedAt.toLocal()),
                        if (entry.description?.trim().isNotEmpty == true)
                          entry.description!,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      entry.isActive
                          ? 'Active'
                          : _duration(entry.durationSeconds ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => GlassSurface(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      );
}
