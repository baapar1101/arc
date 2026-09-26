import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/project_model.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/project_service.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/task/task_detail_drawer.dart';
import 'package:hesabix_ui/widgets/task/task_kanban_board.dart';
import 'package:hesabix_ui/widgets/task/task_calendar_view.dart';
import 'package:hesabix_ui/widgets/task/task_timeline_view.dart';
import 'package:hesabix_ui/widgets/project/project_milestones_view.dart';
import 'package:hesabix_ui/widgets/project/project_cycles_view.dart';
import 'package:hesabix_ui/widgets/task/task_quick_create.dart';
import 'package:intl/intl.dart';

class ProjectWorkspacePage extends StatefulWidget {
  final int businessId;
  final int projectId;
  const ProjectWorkspacePage({super.key, required this.businessId, required this.projectId});
  @override
  State<ProjectWorkspacePage> createState() => _ProjectWorkspacePageState();
}

class _ProjectWorkspacePageState extends State<ProjectWorkspacePage>
    with SingleTickerProviderStateMixin {
  late final ProjectService _projectsService;
  late final TaskService _tasksService;
  late final TabController _tabs;
  ProjectModel? _project;
  Map<String, dynamic> _taskStats = const {};
  Map<String, dynamic> _financialStats = const {};
  List<Map<String, dynamic>> _members = const [];
  List<Map<String, dynamic>> _timelineDependencies = const [];
  List<TaskModel> _tasks = const [];
  List<TaskStatusModel> _statuses = const [];
  List<TaskAssigneeOption> _assignees = const [];
  List<ProjectModel> _projects = const [];
  List<ProjectMilestoneModel> _milestones = const [];
  List<ProjectCycleModel> _cycles = const [];
  TaskModel? _selectedTask;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _projectsService = ProjectService(ApiClient());
    _tasksService = TaskService(ApiClient());
    _tabs = TabController(length: 7, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Future.wait<dynamic>([
        _projectsService.getWorkspace(businessId: widget.businessId, projectId: widget.projectId),
        _tasksService.listTasks(businessId: widget.businessId, projectId: widget.projectId, completed: null, limit: 200),
        _tasksService.listStatuses(widget.businessId),
        _tasksService.listAssignees(widget.businessId),
        _projectsService.listActiveProjects(widget.businessId),
        _projectsService.getTimeline(
          businessId: widget.businessId,
          projectId: widget.projectId,
        ),
        _projectsService.listMilestones(
          businessId: widget.businessId,
          projectId: widget.projectId,
        ),
        _projectsService.listCycles(
          businessId: widget.businessId,
          projectId: widget.projectId,
        ),
      ]);
      final ws = Map<String, dynamic>.from(r[0] as Map);
      final taskResult = Map<String, dynamic>.from(r[1] as Map);
      if (!mounted) return;
      setState(() {
        _project = ProjectModel.fromJson(Map<String, dynamic>.from(ws['project'] as Map));
        _taskStats = Map<String, dynamic>.from(ws['task_statistics'] as Map? ?? const {});
        _financialStats = Map<String, dynamic>.from(ws['financial_statistics'] as Map? ?? const {});
        _members = ((ws['members'] as List?) ?? const []).whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)).toList();
        _tasks = (taskResult['items'] as List<TaskModel>?) ?? const [];
        _statuses = r[2] as List<TaskStatusModel>;
        _assignees = r[3] as List<TaskAssigneeOption>;
        _projects = r[4] as List<ProjectModel>;
        final timeline = Map<String, dynamic>.from(r[5] as Map);
        _timelineDependencies =
            ((timeline['dependencies'] as List?) ?? const [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
        _milestones = r[6] as List<ProjectMilestoneModel>;
        _cycles = r[7] as List<ProjectCycleModel>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = ErrorExtractor.forContext(e, context); _loading = false; });
    }
  }

  void _upsert(TaskModel task) {
    final next = List<TaskModel>.from(_tasks);
    final i = next.indexWhere((e) => e.id == task.id);
    if (task.projectId != widget.projectId) {
      next.removeWhere((e) => e.id == task.id);
    } else if (i >= 0) {
      next[i] = task;
    } else {
      next.insert(0, task);
    }
    if (!mounted) return;
    setState(() {
      _tasks = next;
      if (_selectedTask?.id == task.id) _selectedTask = task;
    });
    _recalc();
  }

  void _recalc() {
    final total = _tasks.length;
    final completed = _tasks.where((e) => e.isCompleted).length;
    final now = DateTime.now();
    final overdue = _tasks.where((e) {
      final due = e.dueAt?.toLocal();
      return !e.isCompleted && due != null && due.isBefore(now);
    }).length;
    if (!mounted) return;
    setState(() {
      _taskStats = {
        ..._taskStats,
        'total': total, 'completed': completed, 'open': total - completed,
        'overdue': overdue,
        'progress_percent': total == 0 ? 0.0 : completed * 100 / total,
      };
    });
  }

  Future<bool> _quickCreateInStatus(
    TaskStatusModel status,
    String title,
  ) async {
    try {
      final task = await _tasksService.createTask(
        businessId: widget.businessId,
        data: {
          'title': title,
          'project_id': widget.projectId,
          'status_id': status.id,
        },
      );
      _upsert(task);
      return true;
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
      return false;
    }
  }

  Future<TaskModel?> _rescheduleTask(
    TaskModel source,
    DateTime targetDate,
  ) async {
    final reference = (source.dueAt ?? source.startAt)?.toLocal();
    final target = DateUtils.dateOnly(targetDate);
    final base = reference == null
        ? DateUtils.dateOnly(DateTime.now())
        : DateUtils.dateOnly(reference);
    final delta = target.difference(base).inDays;

    final data = <String, dynamic>{};
    if (source.startAt != null) {
      data['start_at'] = source.startAt!
          .toLocal()
          .add(Duration(days: delta))
          .toUtc()
          .toIso8601String();
    }
    if (source.dueAt != null) {
      data['due_at'] = source.dueAt!
          .toLocal()
          .add(Duration(days: delta))
          .toUtc()
          .toIso8601String();
    }
    if (source.startAt == null && source.dueAt == null) {
      data['due_at'] = DateTime(
        target.year,
        target.month,
        target.day,
        17,
      ).toUtc().toIso8601String();
    }
    return _update(source, data);
  }

  Future<TaskModel?> _moveTask(
    TaskModel source,
    int targetStatusId,
    int targetIndex,
  ) async {
    try {
      final task = await _tasksService.moveTask(
        businessId: widget.businessId,
        taskId: source.id,
        targetStatusId: targetStatusId,
        targetIndex: targetIndex,
      );
      _upsert(task);
      return task;
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
      return null;
    }
  }

  Future<bool> _quickCreate(String title) async {
    try {
      final task = await _tasksService.createTask(
        businessId: widget.businessId,
        data: {'title': title, 'project_id': widget.projectId},
      );
      _upsert(task);
      return true;
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      return false;
    }
  }

  Future<TaskModel?> _update(TaskModel source, Map<String, dynamic> data) async {
    try {
      final task = await _tasksService.updateTask(
        businessId: widget.businessId, taskId: source.id, data: data,
      );
      _upsert(task);
      return task;
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      rethrow;
    }
  }

  Future<TaskModel?> _toggle(TaskModel source) async {
    final task = source.isCompleted
        ? await _tasksService.reopenTask(businessId: widget.businessId, taskId: source.id)
        : await _tasksService.completeTask(businessId: widget.businessId, taskId: source.id);
    _upsert(task);
    return task;
  }

  Future<bool> _delete(TaskModel source) async {
    try {
      await _tasksService.deleteTask(businessId: widget.businessId, taskId: source.id);
      if (!mounted) return false;
      setState(() {
        _tasks = _tasks.where((e) => e.id != source.id).toList();
        if (_selectedTask?.id == source.id) _selectedTask = null;
      });
      _recalc();
      return true;
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      return false;
    }
  }

  Future<void> _openTask(TaskModel task) async {
    if (ResponsiveHelper.isMobile(context)) {
      var live = task;
      await showGlassModalBottomSheet<void>(
        context: context, isScrollControlled: true, useSafeArea: true,
        builder: (sheetContext) => FractionallySizedBox(
          heightFactor: .94,
          child: StatefulBuilder(
            builder: (_, setSheet) => TaskDetailDrawer(
              businessId: widget.businessId,
              task: live,
              relationCandidates: _tasks,
              onTaskCreated: _upsert,
              statuses: _statuses, projects: _projects, assignees: _assignees,
              onUpdate: (data) async {
                final u = await _update(live, data);
                if (u != null) { live = u; setSheet(() {}); }
                return u;
              },
              onToggleComplete: () async {
                final u = await _toggle(live);
                if (u != null) { live = u; setSheet(() {}); }
                return u;
              },
              onDelete: () => _delete(live),
              onClose: () => Navigator.pop(sheetContext),
            ),
          ),
        ),
      );
    } else {
      setState(() => _selectedTask = task);
    }
  }

  Future<void> _manageMembers() async {
    final changed = await showGlassDialog<bool>(
      context: context,
      builder: (_) => _MembersDialog(
        businessId: widget.businessId, projectId: widget.projectId,
        members: _members, users: _assignees, service: _projectsService,
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ResponsiveHelper.isMobile(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_project?.name ?? 'فضای کاری پروژه'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/business/${widget.businessId}/projects'),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.group_outlined), tooltip: 'اعضای پروژه', onPressed: _loading ? null : _manageMembers),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'بروزرسانی', onPressed: _loading ? null : _load),
        ],
        bottom: TabBar(controller: _tabs, tabs: const [
          Tab(icon: Icon(Icons.dashboard_outlined), text: 'نمای کلی'),
          Tab(icon: Icon(Icons.task_alt_outlined), text: 'کارها'),
          Tab(icon: Icon(Icons.view_kanban_outlined), text: 'برد'),
          Tab(icon: Icon(Icons.calendar_month_outlined), text: 'تقویم'),
          Tab(icon: Icon(Icons.timeline_outlined), text: 'Timeline'),
          Tab(icon: Icon(Icons.flag_outlined), text: 'Milestones'),
          Tab(icon: Icon(Icons.autorenew_rounded), text: 'Cycles'),
        ]),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: GlassSurface(padding: const EdgeInsets.all(24), child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 44),
                      const SizedBox(height: 10), Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 10), FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('تلاش مجدد')),
                    ],
                  )))
                : mobile
                    ? TabBarView(
                        controller: _tabs,
                        children: [_overview(), _taskList(), _board(), _calendar(), _timeline(), _milestonesView(), _cyclesView()],
                      )
                    : Row(children: [
                        Expanded(
                          child: TabBarView(
                            controller: _tabs,
                            children: [_overview(), _taskList(), _board(), _calendar(), _timeline(), _milestonesView(), _cyclesView()],
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: _selectedTask == null ? 0 : 440,
                          child: _selectedTask == null ? const SizedBox.shrink() : TaskDetailDrawer(
                            key: ValueKey(_selectedTask!.id),
                            businessId: widget.businessId,
                            task: _selectedTask!,
                            relationCandidates: _tasks,
                            onTaskCreated: _upsert,
                            statuses: _statuses, projects: _projects, assignees: _assignees,
                            onUpdate: (d) => _update(_selectedTask!, d),
                            onToggleComplete: () => _toggle(_selectedTask!),
                            onDelete: () => _delete(_selectedTask!),
                            onClose: () => setState(() => _selectedTask = null),
                          ),
                        ),
                      ]),
      ),
    );
  }

  Widget _overview() {
    final p = _project!;
    final pad = ResponsiveHelper.getPadding(context);
    final progress = (_taskStats['progress_percent'] as num?)?.toDouble() ?? 0;
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 18, pad, 30),
      children: [
        GlassSurface(padding: const EdgeInsets.all(20), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(p.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Chip(label: Text(p.code)), Chip(label: Text(p.statusName)),
            ]),
            if (p.description?.trim().isNotEmpty == true) ...[const SizedBox(height: 10), Text(p.description!)],
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: LinearProgressIndicator(
                value: (progress / 100).clamp(0.0, 1.0), minHeight: 8, borderRadius: BorderRadius.circular(99),
              )),
              const SizedBox(width: 12),
              Text('${progress.toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ],
        )),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _metric('کل کارها', _taskStats['total'] ?? 0, Icons.list_alt),
          _metric('باز', _taskStats['open'] ?? 0, Icons.pending_actions),
          _metric('تکمیل', _taskStats['completed'] ?? 0, Icons.task_alt),
          _metric('سررسید گذشته', _taskStats['overdue'] ?? 0, Icons.warning_amber_rounded),
        ]),
        const SizedBox(height: 12),
        GlassSurface(padding: const EdgeInsets.all(18), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('تیم پروژه', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (_members.isEmpty) const Text('عضوی برای این پروژه تعریف نشده است.')
            else Wrap(spacing: 7, runSpacing: 7, children: _members.map((m) =>
              Chip(avatar: const Icon(Icons.person_outline, size: 18), label: Text('${m['name'] ?? 'User'} · ${m['role'] ?? 'member'}'))
            ).toList()),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _manageMembers, icon: const Icon(Icons.manage_accounts_outlined), label: const Text('مدیریت اعضا')),
          ],
        )),
        const SizedBox(height: 12),
        GlassSurface(padding: const EdgeInsets.all(18), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('اطلاعات پروژه', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            _info('مدیر', p.managerName ?? '-'),
            _info('مشتری/تامین‌کننده', p.personName ?? '-'),
            _info('تاریخ شروع', p.startDate == null ? '-' : DateFormat('yyyy/MM/dd').format(p.startDate!)),
            _info('تاریخ پایان', p.endDate == null ? '-' : DateFormat('yyyy/MM/dd').format(p.endDate!)),
            _info('تعداد اسناد', '${_financialStats['total_documents'] ?? 0}'),
            _info('مانده مالی', '${_financialStats['balance'] ?? 0}'),
          ],
        )),
      ],
    );
  }

  Widget _metric(String label, dynamic value, IconData icon) => SizedBox(
    width: 210,
    child: GlassSurface(padding: const EdgeInsets.all(15), child: Row(children: [
      Icon(icon), const SizedBox(width: 9), Expanded(child: Text(label)),
      Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
    ])),
  );

  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      SizedBox(width: 135, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
      Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _cyclesView() => ProjectCyclesView(
    businessId: widget.businessId,
    projectId: widget.projectId,
    cycles: _cycles,
    service: _projectsService,
    onChanged: (items) => setState(() => _cycles = items),
  );

  Widget _milestonesView() => ProjectMilestonesView(
    businessId: widget.businessId,
    projectId: widget.projectId,
    milestones: _milestones,
    service: _projectsService,
    onChanged: (items) => setState(() => _milestones = items),
  );

  Widget _timeline() => TaskTimelineView(
    tasks: _tasks,
    dependencies: _timelineDependencies,
    onOpen: _openTask,
  );

  Widget _calendar() => TaskCalendarView(
    tasks: _tasks,
    onOpen: _openTask,
    onReschedule: _rescheduleTask,
  );

  Widget _board() => TaskKanbanBoard(
    tasks: _tasks,
    statuses: _statuses,
    onMove: _moveTask,
    onCreate: _quickCreateInStatus,
    onOpen: _openTask,
  );

  Widget _taskList() {
    final pad = ResponsiveHelper.getPadding(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, 16, pad, 30),
        children: [
          TaskQuickCreate(enabled: !_loading, onCreate: _quickCreate),
          const SizedBox(height: 12),
          if (_tasks.isEmpty)
            const GlassSurface(padding: EdgeInsets.all(40), child: Center(child: Text('هنوز کاری برای این پروژه ثبت نشده است.')))
          else ..._tasks.map((task) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassSurface(padding: const EdgeInsets.all(8), child: ListTile(
              leading: Checkbox(value: task.isCompleted, onChanged: (_) => _toggle(task)),
              title: Text(task.title, style: TextStyle(
                fontWeight: FontWeight.w700,
                decoration: task.isCompleted ? TextDecoration.lineThrough : null,
              )),
              subtitle: Text([
                task.status?.name ?? '',
                if (task.assignees.isNotEmpty) task.assignees.map((e) => e.name).join('، '),
              ].where((e) => e.isNotEmpty).join(' · ')),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () => _openTask(task),
            )),
          )),
        ],
      ),
    );
  }
}

class _MembersDialog extends StatefulWidget {
  final int businessId;
  final int projectId;
  final List<Map<String, dynamic>> members;
  final List<TaskAssigneeOption> users;
  final ProjectService service;
  const _MembersDialog({
    required this.businessId, required this.projectId, required this.members,
    required this.users, required this.service,
  });
  @override
  State<_MembersDialog> createState() => _MembersDialogState();
}

class _MembersDialogState extends State<_MembersDialog> {
  late List<Map<String, dynamic>> _members;
  int _user = 0;
  String _role = 'member';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _members = widget.members.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _save() async {
    if (_user == 0 || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final member = await widget.service.saveMember(
        businessId: widget.businessId, projectId: widget.projectId, userId: _user, role: _role,
      );
      if (!mounted) return;
      final next = List<Map<String, dynamic>>.from(_members);
      final i = next.indexWhere((e) => e['user_id'] == _user);
      if (i >= 0) next[i] = member; else next.add(member);
      setState(() { _members = next; _busy = false; });
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = ErrorExtractor.forContext(e, context); });
    }
  }

  Future<void> _remove(Map<String, dynamic> m) async {
    final id = (m['user_id'] as num?)?.toInt();
    if (id == null || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.service.removeMember(businessId: widget.businessId, projectId: widget.projectId, userId: id);
      if (!mounted) return;
      setState(() { _members = _members.where((e) => e['user_id'] != id).toList(); _busy = false; });
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = ErrorExtractor.forContext(e, context); });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('اعضای پروژه'),
    content: SizedBox(width: 620, child: SingleChildScrollView(child: Column(children: [
      Row(children: [
        Expanded(flex: 2, child: DropdownButtonFormField<int>(
          value: _user, isExpanded: true, decoration: const InputDecoration(labelText: 'کاربر'),
          items: [const DropdownMenuItem(value: 0, child: Text('انتخاب کاربر')),
            ...widget.users.map((u) => DropdownMenuItem(value: u.userId, child: Text(u.name)))],
          onChanged: _busy ? null : (v) => setState(() => _user = v ?? 0),
        )),
        const SizedBox(width: 8),
        Expanded(child: DropdownButtonFormField<String>(
          value: _role, decoration: const InputDecoration(labelText: 'نقش'),
          items: const [
            DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
            DropdownMenuItem(value: 'member', child: Text('Member')),
            DropdownMenuItem(value: 'manager', child: Text('Manager')),
            DropdownMenuItem(value: 'owner', child: Text('Owner')),
          ],
          onChanged: _busy ? null : (v) => setState(() => _role = v ?? 'member'),
        )),
        const SizedBox(width: 8),
        FilledButton(onPressed: _busy || _user == 0 ? null : _save, child: const Text('افزودن')),
      ]),
      const SizedBox(height: 14),
      if (_members.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('عضوی ثبت نشده است.'))
      else ..._members.map((m) => ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(m['name']?.toString() ?? 'User'),
        subtitle: Text(m['role']?.toString() ?? 'member'),
        trailing: IconButton(onPressed: _busy ? null : () => _remove(m), icon: const Icon(Icons.remove_circle_outline)),
      )),
      if (_error != null) Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
    ]))),
    actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context, true), child: const Text('بستن'))],
  );
}
