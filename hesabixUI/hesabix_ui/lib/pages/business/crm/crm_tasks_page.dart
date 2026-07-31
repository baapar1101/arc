import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';
import 'package:intl/intl.dart';

/// صف کار فروشنده: تسک‌های باز، پیگیری‌های سررسید و نقض SLA
class CrmTasksPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const CrmTasksPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<CrmTasksPage> createState() => _CrmTasksPageState();
}

class _CrmTasksPageState extends State<CrmTasksPage> with SingleTickerProviderStateMixin {
  final CrmService _crmService = CrmService(apiClient: ApiClient());
  late TabController _tabController;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _followUpLeads = [];
  List<Map<String, dynamic>> _followUpDeals = [];
  List<Map<String, dynamic>> _slaBreachedLeads = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  static List<Map<String, dynamic>> _asMapList(dynamic v) {
    if (v is List) {
      return v.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _crmService.getMyWorkQueue(businessId: widget.businessId);
      if (!mounted) return;
      final tasks = _asMapList(data['tasks']);
      final leads = _asMapList(data['lead_follow_ups'] ?? data['follow_up_leads']);
      final deals = _asMapList(data['deal_follow_ups'] ?? data['follow_up_deals']);
      List<Map<String, dynamic>> sla = _asMapList(data['sla_breached_leads']);
      if (sla.isEmpty) {
        // در صورت نبود کلید مستقیم، از سرنخ‌های دارای SLA گذشته استخراج می‌شود
        final now = DateTime.now();
        sla = leads.where((l) {
          final due = l['sla_due_at']?.toString();
          if (due == null || due.isEmpty) return false;
          final dt = DateTime.tryParse(due);
          return dt != null && dt.isBefore(now);
        }).toList();
      }
      setState(() {
        _tasks = tasks;
        _followUpLeads = leads;
        _followUpDeals = deals;
        _slaBreachedLeads = sla;
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

  String _formatDateTime(dynamic iso) {
    final s = iso?.toString();
    if (s == null || s.isEmpty) return '';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    return DateFormat('yyyy/MM/dd HH:mm').format(dt);
  }

  bool _isOverdue(dynamic iso) {
    final s = iso?.toString();
    if (s == null || s.isEmpty) return false;
    final dt = DateTime.tryParse(s);
    return dt != null && dt.isBefore(DateTime.now());
  }

  void _navigateForEntity({int? dealId, int? leadId, int? personId}) {
    final base = '/business/${widget.businessId}/crm';
    if (dealId != null) {
      context.go('$base/deals/$dealId');
    } else if (leadId != null) {
      context.go('$base/leads/$leadId');
    } else if (personId != null) {
      context.go('$base/customer-360?personId=$personId');
    }
  }

  Future<void> _completeTask(Map<String, dynamic> task) async {
    final id = (task['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await _crmService.updateActivity(
        businessId: widget.businessId,
        activityId: id,
        status: 'done',
        completedAt: DateTime.now(),
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'تسک تکمیل شد');
      _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Future<void> _snoozeTask(Map<String, dynamic> task) async {
    final id = (task['id'] as num?)?.toInt();
    if (id == null) return;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final due = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10, 0);
    try {
      await _crmService.updateActivity(
        businessId: widget.businessId,
        activityId: id,
        dueAt: due,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'سررسید به فردا ۱۰:۰۰ موکول شد');
      _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Color _priorityColor(String? priority) {
    switch (priority) {
      case 'urgent':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'low':
        return Colors.blueGrey;
      default:
        return Colors.blue;
    }
  }

  String _priorityLabel(String? priority) {
    switch (priority) {
      case 'urgent':
        return 'فوری';
      case 'high':
        return 'زیاد';
      case 'low':
        return 'کم';
      case 'normal':
        return 'معمولی';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.canReadSection('crm')) {
      return AccessDeniedPage(message: 'شما دسترسی لازم برای مشاهده CRM را ندارید');
    }
    final canWrite = widget.authStore.hasBusinessPermission('crm', 'write');

    return Scaffold(
      appBar: AppBar(
        title: const Text('صف کار'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) context.pop();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'بروزرسانی',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'تسک‌های باز (${_tasks.length})'),
            Tab(text: 'پیگیری‌ها (${_followUpLeads.length + _followUpDeals.length})'),
            Tab(text: 'نقض SLA (${_slaBreachedLeads.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 16),
                      TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('تلاش مجدد')),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTasksTab(canWrite),
                    _buildFollowUpsTab(),
                    _buildSlaTab(),
                  ],
                ),
    );
  }

  Widget _emptyState(IconData icon, String message) {
    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(
              height: constraints.maxHeight,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(message),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksTab(bool canWrite) {
    if (_tasks.isEmpty) {
      return _emptyState(Icons.task_alt, 'تسک بازی برای شما ثبت نشده است.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tasks.length,
        itemBuilder: (context, index) {
          final task = _tasks[index];
          final subject = task['subject']?.toString() ?? task['activity_type']?.toString() ?? 'تسک';
          final due = task['due_at'];
          final overdue = _isOverdue(due);
          final priority = task['priority']?.toString();
          final personName = task['person_name']?.toString();
          final leadName = task['lead_name']?.toString();
          final dealId = (task['deal_id'] as num?)?.toInt();
          final leadId = (task['lead_id'] as num?)?.toInt();
          final personId = (task['person_id'] as num?)?.toInt();
          final subtitleParts = <String>[
            if (personName != null && personName.isNotEmpty) personName,
            if (leadName != null && leadName.isNotEmpty) 'سرنخ: $leadName',
            if (due != null && due.toString().isNotEmpty) 'سررسید: ${_formatDateTime(due)}',
          ];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: overdue ? Colors.red.shade100 : Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  overdue ? Icons.warning_amber_rounded : Icons.check_box_outlined,
                  color: overdue ? Colors.red : Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              title: Row(
                children: [
                  Expanded(child: Text(subject, overflow: TextOverflow.ellipsis)),
                  if (priority != null && priority.isNotEmpty && priority != 'normal')
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Chip(
                        label: Text(_priorityLabel(priority), style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: _priorityColor(priority).withValues(alpha: 0.15),
                        side: BorderSide(color: _priorityColor(priority).withValues(alpha: 0.4)),
                      ),
                    ),
                ],
              ),
              subtitle: subtitleParts.isEmpty
                  ? null
                  : Text(
                      subtitleParts.join(' · '),
                      style: TextStyle(color: overdue ? Colors.red : null),
                    ),
              trailing: canWrite
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.snooze_outlined),
                          tooltip: 'به فردا موکول',
                          onPressed: () => _snoozeTask(task),
                        ),
                        IconButton(
                          icon: const Icon(Icons.done),
                          tooltip: 'تکمیل تسک',
                          onPressed: () => _completeTask(task),
                        ),
                      ],
                    )
                  : null,
              onTap: () => _navigateForEntity(dealId: dealId, leadId: leadId, personId: personId),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFollowUpsTab() {
    final total = _followUpLeads.length + _followUpDeals.length;
    if (total == 0) {
      return _emptyState(Icons.notifications_off_outlined, 'پیگیری سررسیدی وجود ندارد.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ..._followUpLeads.map((l) {
            final at = l['next_follow_up_at'];
            final overdue = _isOverdue(at);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.contact_phone_outlined),
                title: Text(l['name']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  'سرنخ · ${_formatDateTime(at)}',
                  style: TextStyle(color: overdue ? Colors.red : null),
                ),
                onTap: () => _navigateForEntity(leadId: (l['id'] as num?)?.toInt()),
              ),
            );
          }),
          ..._followUpDeals.map((d) {
            final at = d['next_follow_up_at'];
            final overdue = _isOverdue(at);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.trending_up),
                title: Text(d['title']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${d['person_name'] ?? ''} · ${_formatDateTime(at)}',
                  style: TextStyle(color: overdue ? Colors.red : null),
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _navigateForEntity(dealId: (d['id'] as num?)?.toInt()),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSlaTab() {
    if (_slaBreachedLeads.isEmpty) {
      return _emptyState(Icons.verified_outlined, 'نقض SLA وجود ندارد.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _slaBreachedLeads.length,
        itemBuilder: (context, index) {
          final l = _slaBreachedLeads[index];
          final due = l['sla_due_at'];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.red.shade100,
                child: const Icon(Icons.timer_off_outlined, color: Colors.red),
              ),
              title: Text(l['name']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
              subtitle: Text(
                'مهلت SLA: ${_formatDateTime(due)}',
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () => _navigateForEntity(leadId: (l['id'] as num?)?.toInt()),
            ),
          );
        },
      ),
    );
  }
}
