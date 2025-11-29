import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth_store.dart';
import '../../l10n/app_localizations.dart';
import '../../services/workflow_service.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/permission/permission_widgets.dart';

class WorkflowsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const WorkflowsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<WorkflowsPage> createState() => _WorkflowsPageState();
}

class _WorkflowsPageState extends State<WorkflowsPage> {
  final WorkflowService _workflowService = WorkflowService();
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  String _statusFilter = 'all';
  List<Map<String, dynamic>> _workflows = const [];
  List<Map<String, dynamic>> _triggerCatalog = const [];
  List<Map<String, dynamic>> _actionCatalog = const [];

  static const Map<String, String> _statusApiValues = {
    'active': 'فعال',
    'inactive': 'غیرفعال',
    'draft': 'پیش‌نویس',
  };

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadAll(showSpinner: true);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    // Debounce nhẹ: فقط وقتی طول متن صفر شد دوباره بارگذاری می‌کنیم
    if (_searchController.text.isEmpty && !_busy) {
      _loadAll(showSpinner: false);
    }
  }

  Future<void> _loadAll({bool showSpinner = false}) async {
    if (!mounted) return;
    if (_busy) return;
    setState(() {
      _busy = true;
      if (showSpinner) {
        _loading = true;
      }
    });
    try {
      final filters = <FilterItem>[];
      if (_statusFilter != 'all') {
        final apiValue = _statusApiValues[_statusFilter];
        if (apiValue != null) {
          filters.add(
            FilterItem(property: 'status', operator: 'eq', value: apiValue),
          );
        }
      }
      final query = QueryInfo(
        search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        filters: filters.isEmpty ? null : filters,
        take: 100,
        skip: 0,
        sortBy: 'updated_at',
        sortDesc: true,
      );
      final workflowsFuture = _workflowService.listWorkflows(
        businessId: widget.businessId,
        queryInfo: query,
      );
      final futures = <Future<dynamic>>[
        workflowsFuture,
        if (_triggerCatalog.isEmpty) _workflowService.listTriggers() else Future.value(_triggerCatalog),
        if (_actionCatalog.isEmpty) _workflowService.listActions() else Future.value(_actionCatalog),
      ];
      final results = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        final workflowsMap = results.first as Map<String, dynamic>;
        _workflows = (workflowsMap['items'] as List<Map<String, dynamic>>?) ?? const [];
        if (_triggerCatalog.isEmpty && results.length > 1) {
          _triggerCatalog = (results[1] as List<Map<String, dynamic>>);
        }
        if (_actionCatalog.isEmpty && results.length > 2) {
          _actionCatalog = (results[2] as List<Map<String, dynamic>>);
        }
      });
    } catch (e, stackTrace) {
      debugPrint('خطا در بارگذاری workflows: $e');
      debugPrint('StackTrace: $stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).workflowErrorLoading)),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final canAccess = widget.authStore.currentBusiness?.isOwner == true ||
        widget.authStore.canReadSection('settings');
    if (!canAccess) {
      return AccessDeniedPage(message: t.workflowNoAccess);
    }

    final title = t.workflows;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () {
            if (!mounted) return;
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: t.workflowRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openWorkflowEditor(t),
        icon: const Icon(Icons.add),
        label: Text(t.workflowCreate),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  _buildFilters(t),
                  const SizedBox(height: 12),
                  _buildCatalogSection(t),
                  if (_workflows.isEmpty)
                    _buildEmptyState(t)
                  else
                    ..._workflows.map((workflow) => _buildWorkflowCard(workflow, t)),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildFilters(AppLocalizations t) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.workflowFilters,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: t.workflowSearch,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _loadAll(showSpinner: false);
                              },
                            ),
                    ),
                    onSubmitted: (_) => _loadAll(showSpinner: false),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    value: _statusFilter,
                    decoration: InputDecoration(labelText: t.workflowStatus),
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(t.workflowAllStatuses),
                      ),
                      DropdownMenuItem(
                        value: 'active',
                        child: Text(t.workflowOnlyActive),
                      ),
                      DropdownMenuItem(
                        value: 'inactive',
                        child: Text(t.workflowInactive),
                      ),
                      DropdownMenuItem(
                        value: 'draft',
                        child: Text(t.workflowDraft),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _statusFilter = value);
                      _loadAll(showSpinner: false);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogSection(AppLocalizations t) {
    if (_triggerCatalog.isEmpty && _actionCatalog.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        if (_triggerCatalog.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              leading: const Icon(Icons.bolt_outlined),
              title: Text(t.workflowAvailableTriggers),
              children: _triggerCatalog
                  .map((trigger) => ListTile(
                        title: Text(trigger['name']?.toString() ?? trigger['key'] as String),
                        subtitle: Text(trigger['description']?.toString() ?? ''),
                        trailing: Tooltip(
                          message: trigger['key']?.toString() ?? '',
                          child: Text(
                            trigger['key']?.toString() ?? '',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        if (_actionCatalog.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              leading: const Icon(Icons.extension_outlined),
              title: Text(t.workflowAvailableActions),
              children: _actionCatalog
                  .map((action) => ListTile(
                        title: Text(action['name']?.toString() ?? action['key'] as String),
                        subtitle: Text(action['description']?.toString() ?? ''),
                        trailing: Tooltip(
                          message: action['key']?.toString() ?? '',
                          child: Text(
                            action['key']?.toString() ?? '',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildWorkflowCard(Map<String, dynamic> workflow, AppLocalizations t) {
    final statusValue = workflow['status']?.toString() ?? _statusApiValues['draft']!;
    final isActive = statusValue == _statusApiValues['active'];
    final statusLabel = _executionStatusLabel(t, statusValue, statuses: true);
    final updatedAt = workflow['updated_at']?.toString() ?? workflow['created_at']?.toString();
    final updatedText = updatedAt == null ? '-' : DateFormat('yyyy/MM/dd HH:mm').format(DateTime.tryParse(updatedAt)?.toLocal() ?? DateTime.now());
    final nodeSummary = _buildNodeSummary(workflow, t);
    final description = (workflow['description'] as String?)?.trim();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    workflow['name']?.toString() ?? '-',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  backgroundColor: isActive ? Colors.green.withOpacity(0.1) : Theme.of(context).colorScheme.surfaceVariant,
                  label: Text(
                    statusLabel,
                    style: TextStyle(color: isActive ? Colors.green.shade700 : Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: t.workflowRunNow,
                  icon: const Icon(Icons.play_arrow_rounded),
                  onPressed: () => _runWorkflow(workflow),
                ),
                IconButton(
                  tooltip: t.workflowExecutionHistory,
                  icon: const Icon(Icons.history),
                  onPressed: () => _showExecutions(workflow, t),
                ),
                IconButton(
                  tooltip: t.workflowEdit,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _openWorkflowEditor(t, workflow: workflow),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (description != null && description.isNotEmpty) ...[
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Icon(isActive ? Icons.check_circle : Icons.pause_circle, color: isActive ? Colors.green : Colors.grey, size: 18),
                const SizedBox(width: 6),
                Text(
                  '${t.workflowLastUpdate}: $updatedText',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Switch.adaptive(
                  value: isActive,
                  onChanged: (value) => _toggleWorkflowStatus(workflow, value),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              nodeSummary,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations t) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          const Icon(Icons.hub_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            t.workflowNoWorkflows,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            t.workflowCreateFirst,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _toggleWorkflowStatus(Map<String, dynamic> workflow, bool active) async {
    final statusValue = active ? _statusApiValues['active']! : _statusApiValues['inactive']!;
    try {
      await _workflowService.updateWorkflow(
        businessId: widget.businessId,
        workflowId: workflow['id'] as int,
        payload: {'status': statusValue},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).workflowStatusUpdated)),
      );
      _loadAll(showSpinner: false);
    } catch (e, stackTrace) {
      debugPrint('خطا در تغییر وضعیت workflow: $e');
      debugPrint('StackTrace: $stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).workflowErrorUpdatingStatus)),
      );
    }
  }

  Future<void> _runWorkflow(Map<String, dynamic> workflow) async {
    try {
      final result = await _workflowService.executeWorkflow(
        businessId: widget.businessId,
        workflowId: workflow['id'] as int,
        triggerData: const {},
      );
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      final message = result['message']?.toString() ?? t.workflowExecuted;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e, stackTrace) {
      debugPrint('خطا در اجرای workflow: $e');
      debugPrint('StackTrace: $stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).workflowErrorExecuting)),
      );
    }
  }

  Future<void> _openWorkflowEditor(
    AppLocalizations t, {
    Map<String, dynamic>? workflow,
  }) async {
    if (workflow == null) {
      // افزودن workflow جدید
      await context.pushNamed(
        'business_new_workflow',
        pathParameters: {
          'business_id': widget.businessId.toString(),
        },
        extra: null,
      );
    } else {
      // ویرایش workflow موجود
      final workflowId = workflow['id'] as int?;
      if (workflowId == null) {
        return;
      }
      await context.pushNamed(
        'business_edit_workflow',
        pathParameters: {
          'business_id': widget.businessId.toString(),
          'workflow_id': workflowId.toString(),
        },
        extra: workflow,
      );
    }
    if (mounted) {
      _loadAll(showSpinner: true);
    }
  }

  Future<void> _showExecutions(Map<String, dynamic> workflow, AppLocalizations t) async {
    final workflowId = workflow['id'] as int;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _workflowService.listExecutions(
              businessId: widget.businessId,
              workflowId: workflowId,
              page: 1,
              pageSize: 10,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) {
                return SizedBox(
                  height: 220,
                  child: Center(child: Text('خطا: ${snapshot.error}')),
                );
              }
              final data = snapshot.data ?? const <String, dynamic>{};
              final executions = (data['items'] as List<Map<String, dynamic>>?) ?? const [];
              if (executions.isEmpty) {
                return SizedBox(
                  height: 220,
                  child: Center(child: Text(t.workflowNoExecutions)),
                );
              }
              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.6,
                minChildSize: 0.4,
                maxChildSize: 0.9,
                builder: (_, controller) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: ListView.separated(
                      controller: controller,
                      itemBuilder: (_, index) {
                        final execution = executions[index];
                        final statusValue = execution['status']?.toString() ?? '';
                        final statusLabel = _executionStatusLabel(t, statusValue);
                        final startedAt = execution['started_at']?.toString();
                        final completedAt = execution['completed_at']?.toString();
                        return ListTile(
                          title: Text(statusLabel),
                          subtitle: Text(
                            '${t.workflowStarted}: ${_formatDate(startedAt)}\n'
                            '${t.workflowCompleted}: ${_formatDate(completedAt)}',
                          ),
                          trailing: TextButton.icon(
                            icon: const Icon(Icons.article_outlined),
                            label: Text(t.workflowLogs),
                            onPressed: () => _showExecutionLogs(workflowId, execution['id'] as int, t),
                          ),
                        );
                      },
                      separatorBuilder: (_, __) => const Divider(),
                      itemCount: executions.length,
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showExecutionLogs(int workflowId, int executionId, AppLocalizations t) async {
    try {
      final logs = await _workflowService.getExecutionLogs(
        businessId: widget.businessId,
        workflowId: workflowId,
        executionId: executionId,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Text(t.workflowExecutionLogs),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420, maxWidth: 640),
              child: logs.isEmpty
                  ? Text(t.workflowNoLogs)
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: logs.length,
                      separatorBuilder: (_, __) => const Divider(height: 12),
                      itemBuilder: (_, index) {
                        final log = logs[index];
                        final timestamp = _formatDate(log['timestamp']?.toString());
                        final level = log['level']?.toString() ?? 'info';
                        final message = log['message']?.toString() ?? '';
                        final data = log['data'];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(timestamp, style: Theme.of(context).textTheme.labelSmall),
                                const Spacer(),
                                Chip(
                                  label: Text(level.toUpperCase()),
                                  backgroundColor: _logColor(level).withOpacity(0.15),
                                  labelStyle: TextStyle(color: _logColor(level)),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(message, style: Theme.of(context).textTheme.bodyMedium),
                            if (data != null)
                              Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceVariant,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  const JsonEncoder.withIndent('  ').convert(data),
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t.workflowClose),
              ),
            ],
          );
        },
      );
    } catch (e, stackTrace) {
      debugPrint('خطا در دریافت لاگ‌های اجرا: $e');
      debugPrint('StackTrace: $stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).workflowErrorLoadingLogs)),
      );
    }
  }


  String _executionStatusLabel(AppLocalizations t, String value, {bool statuses = false}) {
    final isFa = t.localeName.startsWith('fa');
    final key = _statusApiValues.entries.firstWhere(
      (entry) => entry.value == value,
      orElse: () => const MapEntry('unknown', ''),
    ).key;
    if (statuses) {
      switch (key) {
        case 'active':
          return isFa ? 'فعال' : 'Active';
        case 'inactive':
          return isFa ? 'غیرفعال' : 'Inactive';
        case 'draft':
          return isFa ? 'پیش‌نویس' : 'Draft';
      }
    }
    switch (value) {
      case 'تکمیل شده':
        return isFa ? 'تکمیل شده' : 'Completed';
      case 'ناموفق':
        return isFa ? 'ناموفق' : 'Failed';
      case 'در حال اجرا':
        return isFa ? 'در حال اجرا' : 'Running';
      case 'در انتظار':
        return isFa ? 'در انتظار' : 'Pending';
      case 'لغو شده':
        return isFa ? 'لغو شده' : 'Cancelled';
      default:
        return value.isEmpty ? (isFa ? 'نامشخص' : 'Unknown') : value;
    }
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '-';
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return DateFormat('yyyy/MM/dd HH:mm').format(date.toLocal());
  }

  Map<String, dynamic> _normalizeWorkflowData(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is String && data.isNotEmpty) {
      try {
        final parsed = jsonDecode(data);
        if (parsed is Map<String, dynamic>) {
          return parsed;
        }
        if (parsed is Map) {
          return Map<String, dynamic>.from(parsed);
        }
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }

  String _buildNodeSummary(Map<String, dynamic> workflow, AppLocalizations t) {
    final data = _normalizeWorkflowData(workflow['workflow_data']);
    final nodes = (data['nodes'] as List?)
            ?.map<Map<String, dynamic>>((node) => Map<String, dynamic>.from(node as Map))
            .toList() ??
        const <Map<String, dynamic>>[];
    if (nodes.isEmpty) {
      return 'No nodes defined.'; // TODO: اضافه کردن به localization
    }
    final triggers = nodes.where((n) => n['type'] == 'trigger').map((n) => n['config']?['trigger_type'] ?? n['label']).whereType<String>().toList();
    final actions = nodes.where((n) => n['type'] == 'action').map((n) => n['config']?['action_type'] ?? n['label']).whereType<String>().toList();
    final conditions = nodes.where((n) => n['type'] == 'condition').map((n) => n['label'] ?? 'condition').whereType<String>().toList();
    final parts = <String>[];
    if (triggers.isNotEmpty) {
      parts.add('Triggers: ${triggers.join(', ')}'); // TODO: اضافه کردن به localization
    }
    if (actions.isNotEmpty) {
      parts.add('Actions: ${actions.join(', ')}'); // TODO: اضافه کردن به localization
    }
    if (conditions.isNotEmpty) {
      parts.add('Conditions: ${conditions.join(', ')}'); // TODO: اضافه کردن به localization
    }
    return parts.isEmpty ? 'This workflow definition is empty.' : parts.join(' • '); // TODO: اضافه کردن به localization
  }

  static Map<String, dynamic> _defaultWorkflowTemplate() {
    return {
      'nodes': [
        {
          'id': 'trigger-1',
          'type': 'trigger',
          'label': 'Invoice Created',
          'config': {
            'trigger_type': 'invoice.sales.created',
          },
        },
        {
          'id': 'action-1',
          'type': 'action',
          'label': 'Send Notification',
          'config': {
            'action_type': 'create_notification',
            'title': 'فاکتور جدید',
            'message': 'یک فاکتور تازه صادر شد.',
          },
        },
      ],
      'connections': [
        {'source': 'trigger-1', 'target': 'action-1'},
      ],
    };
  }

  Color _logColor(String level) {
    switch (level.toLowerCase()) {
      case 'error':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      case 'debug':
        return Colors.blueGrey;
      default:
        return Colors.blue;
    }
  }
}


