import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../services/workflow_service.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/permission/permission_widgets.dart';
import '../../widgets/workflow/workflow_analytics_dialog.dart';

class WorkflowsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const WorkflowsPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<WorkflowsPage> createState() => _WorkflowsPageState();
}

class _WorkflowsPageState extends State<WorkflowsPage> {
  final WorkflowService _workflowService = WorkflowService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  bool _loading = true;
  bool _busy = false;
  String _statusFilter = 'all';
  List<Map<String, dynamic>> _workflows = const [];
  bool _isFirstLoad = true;

  static const Map<String, String> _statusApiValues = {
    'active': 'فعال',
    'inactive': 'غیرفعال',
    'draft': 'پیش‌نویس',
  };

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    widget.calendarController.addListener(_onCalendarChanged);
    _loadAll(showSpinner: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // هر بار که صفحه visible می‌شود، لیست را به‌روزرسانی می‌کنیم
    // (به جز بار اول که در initState بارگذاری شده است)
    if (!_isFirstLoad && mounted) {
      _loadAll(showSpinner: false);
    }
    _isFirstLoad = false;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    widget.calendarController.removeListener(_onCalendarChanged);
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onCalendarChanged() {
    // وقتی نوع تقویم تغییر کند، صفحه را به‌روزرسانی می‌کنیم
    if (mounted) {
      setState(() {
        // فقط برای rebuild کردن UI
      });
    }
  }

  void _onSearchChanged() {
    // لغو تایمر قبلی اگر وجود داشته باشد
    _debounceTimer?.cancel();
    
    // ایجاد تایمر جدید با تاخیر 500 میلی‌ثانیه
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_busy && mounted) {
        _loadAll(showSpinner: false);
      }
    });
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
      final workflowsMap = await _workflowService.listWorkflows(
        businessId: widget.businessId,
        queryInfo: query,
      );
      if (!mounted) return;
      setState(() {
        _workflows = (workflowsMap['items'] as List<Map<String, dynamic>>?) ?? const [];
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
            tooltip: 'آمار و تحلیل',
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => WorkflowAnalyticsDialog(
                  businessId: widget.businessId,
                ),
              );
            },
          ),
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
                              },
                            ),
                    ),
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

  Widget _buildWorkflowCard(Map<String, dynamic> workflow, AppLocalizations t) {
    final statusValue = workflow['status']?.toString() ?? _statusApiValues['draft']!;
    final isActive = statusValue == _statusApiValues['active'];
    final statusLabel = _executionStatusLabel(t, statusValue, statuses: true);
    final updatedAt = workflow['updated_at']?.toString() ?? workflow['created_at']?.toString();
    // استفاده از HesabixDateUtils برای فرمت کردن تاریخ بر اساس نوع تقویم انتخابی کاربر
    final parsedDate = updatedAt == null ? null : DateTime.tryParse(updatedAt)?.toLocal();
    final updatedText = parsedDate == null 
        ? '-' 
        : HesabixDateUtils.formatDateTime(parsedDate, widget.calendarController.isJalali);
    final nodeSummary = _buildNodeSummary(workflow, t);
    final description = (workflow['description'] as String?)?.trim();

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
          width: 1,
        ),
      ),
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
                  backgroundColor: isActive 
                      ? Colors.green.withOpacity(0.15) 
                      : statusValue == _statusApiValues['draft']!
                          ? Colors.orange.withOpacity(0.15)
                          : Theme.of(context).colorScheme.surfaceVariant,
                  label: Text(
                    statusLabel,
                    style: TextStyle(
                      color: isActive 
                          ? Colors.green.shade700 
                          : statusValue == _statusApiValues['draft']!
                              ? Colors.orange.shade700
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  side: BorderSide(
                    color: isActive 
                        ? Colors.green.shade300 
                        : statusValue == _statusApiValues['draft']!
                            ? Colors.orange.shade300
                            : Colors.transparent,
                    width: 1,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: t.workflowRunNow,
                  icon: const Icon(Icons.play_arrow_rounded),
                  color: Colors.blue.shade600,
                  onPressed: () => _runWorkflow(workflow),
                ),
                IconButton(
                  tooltip: t.workflowExecutionHistory,
                  icon: const Icon(Icons.history_rounded),
                  onPressed: () => _showExecutions(workflow, t),
                ),
                IconButton(
                  tooltip: t.workflowEdit,
                  icon: const Icon(Icons.edit_rounded),
                  onPressed: () => _openWorkflowEditor(t, workflow: workflow),
                ),
                IconButton(
                  tooltip: 'حذف ورک‌فلو',
                  icon: const Icon(Icons.delete_rounded),
                  color: Colors.red.shade600,
                  onPressed: () => _deleteWorkflow(workflow, t),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (description != null && description.isNotEmpty) ...[
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Icon(
                  isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded, 
                  color: isActive ? Colors.green.shade600 : Colors.grey.shade400, 
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${t.workflowLastUpdate}: $updatedText',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                Switch.adaptive(
                  value: isActive,
                  onChanged: (value) => _toggleWorkflowStatus(workflow, value),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nodeSummary,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
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

  Future<void> _deleteWorkflow(Map<String, dynamic> workflow, AppLocalizations t) async {
    // نمایش دیالوگ تایید
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف ورک‌فلو'),
        content: Text('آیا از حذف ورک‌فلو "${workflow['name']}" اطمینان دارید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.workflowClose),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _workflowService.deleteWorkflow(
        businessId: widget.businessId,
        workflowId: workflow['id'] as int,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ورک‌فلو با موفقیت حذف شد')),
      );
      _loadAll(showSpinner: false);
    } catch (e, stackTrace) {
      debugPrint('خطا در حذف workflow: $e');
      debugPrint('StackTrace: $stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('خطا در حذف ورک‌فلو')),
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
      context.goNamed(
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
      context.goNamed(
        'business_edit_workflow',
        pathParameters: {
          'business_id': widget.businessId.toString(),
          'workflow_id': workflowId.toString(),
        },
        extra: workflow,
      );
    }
  }

  Future<void> _showExecutions(Map<String, dynamic> workflow, AppLocalizations t) async {
    final workflowId = workflow['id'] as int;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
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
                  return Column(
                    children: [
                      // Handle برای کشیدن bottom sheet
                      Container(
                        margin: const EdgeInsets.only(top: 8, bottom: 4),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          t.workflowExecutionHistory,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          controller: controller,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                onPressed: () => _showExecutionLogs(
                                  bottomSheetContext,
                                  workflowId,
                                  execution['id'] as int,
                                  t,
                                ),
                              ),
                            );
                          },
                          separatorBuilder: (_, __) => const Divider(),
                          itemCount: executions.length,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showExecutionLogs(
    BuildContext bottomSheetContext,
    int workflowId,
    int executionId,
    AppLocalizations t,
  ) async {
    try {
      final logs = await _workflowService.getExecutionLogs(
        businessId: widget.businessId,
        workflowId: workflowId,
        executionId: executionId,
      );
      if (!mounted) return;
      
      await showDialog<void>(
        context: bottomSheetContext,
        builder: (dialogContext) {
          // محاسبه عرض و ارتفاع بر اساس اندازه صفحه
          final size = MediaQuery.of(dialogContext).size;
          final dialogWidth = size.width > 800 ? 800.0 : size.width * 0.9;
          final dialogHeight = size.height * 0.8;
          
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: dialogWidth,
              height: dialogHeight,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(
                        Icons.terminal_rounded,
                        color: Theme.of(dialogContext).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          t.workflowExecutionLogs,
                          style: Theme.of(dialogContext).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        tooltip: t.workflowClose,
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  // محتوای لاگ‌ها
                  Expanded(
                    child: logs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 48,
                                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  t.workflowNoLogs,
                                  style: Theme.of(dialogContext).textTheme.bodyLarge,
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: logs.length,
                            separatorBuilder: (_, __) => const Divider(height: 24),
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
                                      Text(
                                        timestamp,
                                        style: Theme.of(dialogContext).textTheme.labelSmall?.copyWith(
                                              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                      const Spacer(),
                                      Chip(
                                        label: Text(level.toUpperCase()),
                                        backgroundColor: _logColor(level).withOpacity(0.15),
                                        labelStyle: TextStyle(
                                          color: _logColor(level),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    message,
                                    style: Theme.of(dialogContext).textTheme.bodyMedium,
                                  ),
                                  if (data != null) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Theme.of(dialogContext).colorScheme.surfaceVariant,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Text(
                                          const JsonEncoder.withIndent('  ').convert(data),
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
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
    // استفاده از HesabixDateUtils برای فرمت کردن تاریخ بر اساس نوع تقویم انتخابی کاربر
    return HesabixDateUtils.formatDateTime(date.toLocal(), widget.calendarController.isJalali);
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
    
    // اگر هیچ نودی تعریف نشده باشد
    if (nodes.isEmpty) {
      return 'هیچ گره‌ای تعریف نشده است';
    }
    
    // شمارش انواع مختلف نودها
    final triggerCount = nodes.where((n) => n['type'] == 'trigger').length;
    final actionCount = nodes.where((n) => n['type'] == 'action').length;
    final conditionCount = nodes.where((n) => n['type'] == 'condition').length;
    
    // ساخت خلاصه کوتاه و واضح
    final parts = <String>[];
    if (triggerCount > 0) {
      parts.add('$triggerCount تریگر');
    }
    if (actionCount > 0) {
      parts.add('$actionCount اکشن');
    }
    if (conditionCount > 0) {
      parts.add('$conditionCount شرط');
    }
    
    return parts.isEmpty ? 'این ورک‌فلو خالی است' : parts.join(' • ');
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


