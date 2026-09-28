import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';
import 'package:intl/intl.dart';

class TaskDashboardView extends StatefulWidget {
  final int businessId;
  final ValueChanged<int> onOpenTask;
  final ValueChanged<int> onOpenProject;

  const TaskDashboardView({
    super.key,
    required this.businessId,
    required this.onOpenTask,
    required this.onOpenProject,
  });

  @override
  State<TaskDashboardView> createState() => _TaskDashboardViewState();
}

class _TaskDashboardViewState extends State<TaskDashboardView> {
  late final TaskService _service;
  Map<String, dynamic> _data = const {};
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
      final data = await _service.getDashboard(widget.businessId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _list(String key) {
    return ((_data[key] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, dynamic> _map(String key) =>
      Map<String, dynamic>.from((_data[key] as Map?) ?? const {});

  String _duration(dynamic raw) {
    final seconds = (raw as num?)?.toInt() ?? 0;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }

  String _date(dynamic value) {
    if (value == null) return '—';
    final raw = value.toString();
    final dt = DateTime.tryParse(raw);
    return dt == null ? raw : DateFormat('yyyy/MM/dd').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveHelper.getPadding(context);
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: EdgeInsets.all(padding),
        children: [
          GlassSurface(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Icon(Icons.analytics_outlined, size: 46, color: scheme.error),
                const SizedBox(height: 10),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('تلاش مجدد'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final summary = _map('summary');
    final scope = _map('scope');
    final time = _map('time_7d');
    final projects = _list('project_progress');
    final workload = _list('workload');
    final myTasks = _list('my_tasks');
    final recent = _list('recent_completed');
    final milestones = _list('milestones');
    final cycles = _list('cycles');
    final statuses = _list('status_breakdown');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(padding, 16, padding, 30),
        children: [
          GlassSurface(
            padding: const EdgeInsets.all(18),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.analytics_outlined, color: scheme.primary),
                const Text(
                  'Task & Project Analytics',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                Chip(
                  avatar: const Icon(Icons.visibility_outlined, size: 17),
                  label: Text(
                    scope['project_visibility'] == 'all'
                        ? 'همه پروژه‌های مجاز'
                        : 'پروژه‌های عضو',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.timer_outlined, size: 17),
                  label: Text(
                    scope['time_visibility'] == 'team'
                        ? 'زمان تیم'
                        : 'زمان شخصی',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Metric(
                label: 'کارهای باز',
                value: '${summary['open'] ?? 0}',
                icon: Icons.pending_actions_outlined,
              ),
              _Metric(
                label: 'سررسید امروز',
                value: '${summary['due_today'] ?? 0}',
                icon: Icons.today_outlined,
              ),
              _Metric(
                label: 'گذشته از سررسید',
                value: '${summary['overdue'] ?? 0}',
                icon: Icons.warning_amber_rounded,
                danger: ((summary['overdue'] as num?)?.toInt() ?? 0) > 0,
              ),
              _Metric(
                label: 'تکمیل ۷ روز',
                value: '${summary['completed_7d'] ?? 0}',
                icon: Icons.task_alt_rounded,
              ),
              _Metric(
                label: 'بدون مسئول',
                value: '${summary['unassigned'] ?? 0}',
                icon: Icons.person_off_outlined,
              ),
              _Metric(
                label: 'زمان ۷ روز',
                value: _duration(summary['time_seconds_7d']),
                icon: Icons.timer_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _twoColumn(
            _Section(
              title: 'کارهای من',
              icon: Icons.person_outline,
              child: myTasks.isEmpty
                  ? const _Empty('کار بازی برای شما نیست.')
                  : Column(
                      children: myTasks
                          .map(
                            (task) => _TaskRow(
                              task: task,
                              onTap: () => widget.onOpenTask(
                                (task['id'] as num).toInt(),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
            _Section(
              title: 'ترکیب وضعیت‌ها',
              icon: Icons.donut_small_outlined,
              child: statuses.isEmpty
                  ? const _Empty('داده وضعیت وجود ندارد.')
                  : Column(
                      children: statuses
                          .map(
                            (status) => _CountBar(
                              label: status['name']?.toString() ?? 'Status',
                              value: (status['count'] as num?)?.toInt() ?? 0,
                              max: statuses.fold<int>(
                                1,
                                (m, e) => ((e['count'] as num?)?.toInt() ?? 0) > m
                                    ? ((e['count'] as num?)?.toInt() ?? 0)
                                    : m,
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'پیشرفت پروژه‌ها',
            icon: Icons.folder_copy_outlined,
            child: projects.isEmpty
                ? const _Empty('پروژه قابل مشاهده‌ای وجود ندارد.')
                : Column(
                    children: projects
                        .map(
                          (project) => _ProgressRow(
                            title:
                                '${project['code'] ?? ''} · ${project['name'] ?? ''}',
                            subtitle:
                                '${project['completed'] ?? 0}/${project['total'] ?? 0} تکمیل · ${project['overdue'] ?? 0} سررسید گذشته',
                            progress:
                                ((project['progress_percent'] as num?)?.toDouble() ??
                                        0) /
                                    100,
                            onTap: () => widget.onOpenProject(
                              (project['project_id'] as num).toInt(),
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 14),
          _twoColumn(
            _Section(
              title: 'بار کاری تیم',
              icon: Icons.groups_outlined,
              child: workload.isEmpty
                  ? const _Empty('کار تخصیص‌یافته‌ای وجود ندارد.')
                  : Column(
                      children: workload
                          .map(
                            (row) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                radius: 17,
                                child: Icon(Icons.person_outline, size: 18),
                              ),
                              title: Text(row['name']?.toString() ?? 'User'),
                              subtitle: Text(
                                '${row['open'] ?? 0} باز · ${row['overdue'] ?? 0} سررسید گذشته',
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
            _Section(
              title: 'زمان ثبت‌شده · ۷ روز',
              icon: Icons.timer_outlined,
              child: Column(
                children: [
                  _ValueLine(
                    label: scope['time_visibility'] == 'team'
                        ? 'کل زمان تیم'
                        : 'زمان شخصی من',
                    value: _duration(time['total_seconds']),
                  ),
                  _ValueLine(
                    label: 'زمان Billable',
                    value: _duration(time['billable_seconds']),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _twoColumn(
            _Section(
              title: 'Milestones فعال',
              icon: Icons.flag_outlined,
              child: milestones.isEmpty
                  ? const _Empty('Milestone فعالی وجود ندارد.')
                  : Column(
                      children: milestones
                          .map(
                            (item) => _ProgressRow(
                              title: item['title']?.toString() ?? 'Milestone',
                              subtitle:
                                  'هدف ${_date(item['target_at_raw'] ?? item['target_at'])} · ${item['completed'] ?? 0}/${item['total'] ?? 0}',
                              progress:
                                  ((item['progress_percent'] as num?)?.toDouble() ??
                                          0) /
                                      100,
                            ),
                          )
                          .toList(),
                    ),
            ),
            _Section(
              title: 'Cycles فعال',
              icon: Icons.autorenew_rounded,
              child: cycles.isEmpty
                  ? const _Empty('Cycle فعالی وجود ندارد.')
                  : Column(
                      children: cycles
                          .map(
                            (item) => _ProgressRow(
                              title: item['name']?.toString() ?? 'Cycle',
                              subtitle:
                                  '${item['completed'] ?? 0}/${item['total'] ?? 0} · ${item['status'] ?? ''}',
                              progress:
                                  ((item['progress_percent'] as num?)?.toDouble() ??
                                          0) /
                                      100,
                            ),
                          )
                          .toList(),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'تکمیل‌های اخیر',
            icon: Icons.history_rounded,
            child: recent.isEmpty
                ? const _Empty('در ۷ روز اخیر کاری تکمیل نشده است.')
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: recent
                        .map(
                          (task) => ActionChip(
                            avatar: const Icon(Icons.check_circle_outline, size: 17),
                            label: Text(
                              task['title']?.toString() ?? 'Task',
                              overflow: TextOverflow.ellipsis,
                            ),
                            onPressed: () => widget.onOpenTask(
                              (task['id'] as num).toInt(),
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _twoColumn(Widget a, Widget b) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 850) {
          return Column(
            children: [a, const SizedBox(height: 12), b],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b),
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool danger;

  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger ? scheme.error : scheme.primary;
    return SizedBox(
      width: 182,
      child: GlassSurface(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: danger ? color : null,
                    ),
                  ),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback onTap;

  const _TaskRow({
    required this.task,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final due = task['due_at_raw'] ?? task['due_at'];
    final dt = due == null ? null : DateTime.tryParse(due.toString());
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.radio_button_unchecked, size: 19),
      title: Text(
        task['title']?.toString() ?? 'Task',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (task['project_name'] != null) task['project_name'].toString(),
          if (dt != null) 'سررسید ${DateFormat('yyyy/MM/dd').format(dt.toLocal())}',
        ].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final double progress;
  final VoidCallback? onTap;

  const _ProgressRow({
    required this.title,
    required this.subtitle,
    required this.progress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text('${(value * 100).toStringAsFixed(0)}%'),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: value,
              minHeight: 7,
              borderRadius: BorderRadius.circular(20),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBar extends StatelessWidget {
  final String label;
  final int value;
  final int max;

  const _CountBar({
    required this.label,
    required this.value,
    required this.max,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 30, child: Text('$value')),
        ],
      ),
    );
  }
}

class _ValueLine extends StatelessWidget {
  final String label;
  final String value;

  const _ValueLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}
