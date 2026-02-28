import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import '../../models/workflow_editor_models.dart';
import '../../services/workflow_service.dart';
import 'workflow_analytics_dialog.dart';
import 'workflow_timeline_dialog.dart';
import '../../utils/snackbar_helper.dart';


/// Panel برای نمایش تاریخچه اجرای workflow
class WorkflowExecutionHistoryPanel extends StatefulWidget {
  final int businessId;
  final int workflowId;
  final List<WorkflowNodeModel>? nodes; // برای highlight کردن نودهای اجرا شده
  final Function(String nodeId)? onNodeHighlight;

  const WorkflowExecutionHistoryPanel({
    super.key,
    required this.businessId,
    required this.workflowId,
    this.nodes,
    this.onNodeHighlight,
  });

  @override
  State<WorkflowExecutionHistoryPanel> createState() => _WorkflowExecutionHistoryPanelState();
}

class _WorkflowExecutionHistoryPanelState extends State<WorkflowExecutionHistoryPanel> {
  final WorkflowService _workflowService = WorkflowService();
  bool _loading = false;
  List<Map<String, dynamic>> _executions = [];
  Map<String, dynamic>? _selectedExecution;
  List<Map<String, dynamic>> _logs = [];
  int _page = 1;
  final int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loadExecutions();
  }

  Future<void> _loadExecutions() async {
    setState(() => _loading = true);
    try {
      final result = await _workflowService.listExecutions(
        businessId: widget.businessId,
        workflowId: widget.workflowId,
        page: _page,
        pageSize: _pageSize,
      );
      setState(() {
        _executions = (result['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        SnackBarHelper.show(context, message: '${AppLocalizations.of(context).workflowErrorLoadHistory}: $e');
      }
    }
  }

  Future<void> _loadLogs(int executionId) async {
    try {
      final logs = await _workflowService.getExecutionLogs(
        businessId: widget.businessId,
        workflowId: widget.workflowId,
        executionId: executionId,
      );
      setState(() {
        _logs = logs;
      });
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: '${AppLocalizations.of(context).workflowErrorLoadLogs}: $e');
      }
    }
  }

  void _selectExecution(Map<String, dynamic> execution) {
    setState(() {
      _selectedExecution = execution;
    });
    final executionId = execution['id'] as int?;
    if (executionId != null) {
      _loadLogs(executionId);
      
      // Highlight کردن نودهای اجرا شده
      final executionData = execution['execution_data'] as Map<String, dynamic>?;
      final executedNodes = executionData?['executed_nodes'] as List<dynamic>?;
      if (executedNodes != null && widget.onNodeHighlight != null) {
        for (final nodeId in executedNodes) {
          widget.onNodeHighlight?.call(nodeId.toString());
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant,
              border: Border(
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.history, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'تاریخچه اجرا',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.analytics_outlined),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => WorkflowAnalyticsDialog(
                        businessId: widget.businessId,
                        workflowId: widget.workflowId,
                      ),
                    );
                  },
                  tooltip: 'آمار و تحلیل',
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadExecutions,
                  tooltip: 'به‌روزرسانی',
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _executions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history,
                              size: 48,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'هیچ اجرایی یافت نشد',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Row(
                        children: [
                          // لیست اجراها
                          Expanded(
                            flex: 1,
                            child: ListView.builder(
                              itemCount: _executions.length,
                              itemBuilder: (context, index) {
                                final execution = _executions[index];
                                final isSelected = _selectedExecution?['id'] == execution['id'];
                                return _buildExecutionItem(execution, isSelected);
                              },
                            ),
                          ),
                          // جزئیات و لاگ‌ها
                          if (_selectedExecution != null)
                            Container(
                              width: 1,
                              color: theme.dividerColor,
                            ),
                          if (_selectedExecution != null)
                            Expanded(
                              flex: 1,
                              child: _buildExecutionDetails(),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildExecutionItem(Map<String, dynamic> execution, bool isSelected) {
    final theme = Theme.of(context);
    final status = execution['status']?.toString() ?? '';
    final startedAt = execution['started_at']?.toString();
    final completedAt = execution['completed_at']?.toString();
    
    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'تکمیل شده':
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'ناموفق':
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case 'در حال اجرا':
      case 'running':
        statusColor = Colors.blue;
        statusIcon = Icons.sync;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.pending;
    }

    DateTime? startDate;
    if (startedAt != null) {
      try {
        startDate = DateTime.parse(startedAt);
      } catch (e) {
        // ignore
      }
    }

    return InkWell(
      onTap: () => _selectExecution(execution),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected 
              ? theme.colorScheme.primaryContainer.withOpacity(0.3)
              : null,
          border: Border(
            left: BorderSide(
              color: isSelected ? theme.colorScheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, size: 16, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if (startDate != null) ...[
              const SizedBox(height: 4),
              Text(
                DateFormat('yyyy/MM/dd HH:mm').format(startDate),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (execution['error_message'] != null) ...[
              const SizedBox(height: 4),
              Text(
                execution['error_message'].toString(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.red,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExecutionDetails() {
    final theme = Theme.of(context);
    if (_selectedExecution == null) return const SizedBox();

    return Column(
      children: [
        // Header جزئیات
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              Text(
                'جزئیات اجرا',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.timeline, size: 18),
                onPressed: () {
                  final executionId = _selectedExecution!['id'] as int?;
                  if (executionId != null) {
                    showDialog(
                      context: context,
                      builder: (context) => WorkflowTimelineDialog(
                        businessId: widget.businessId,
                        workflowId: widget.workflowId,
                        executionId: executionId,
                      ),
                    );
                  }
                },
                tooltip: 'مشاهده Timeline',
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  setState(() {
                    _selectedExecution = null;
                    _logs = [];
                  });
                },
                tooltip: 'بستن',
              ),
            ],
          ),
        ),
        // محتوای جزئیات
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('وضعیت', _selectedExecution!['status']?.toString() ?? ''),
                const SizedBox(height: 8),
                if (_selectedExecution!['started_at'] != null)
                  _buildDetailRow(
                    'شروع',
                    _formatDate(_selectedExecution!['started_at']?.toString()),
                  ),
                if (_selectedExecution!['completed_at'] != null) ...[
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    'پایان',
                    _formatDate(_selectedExecution!['completed_at']?.toString()),
                  ),
                ],
                if (_selectedExecution!['error_message'] != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error, size: 16, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedExecution!['error_message'].toString(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'لاگ‌های اجرا',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (_logs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'لاگی یافت نشد',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ..._logs.map((log) => _buildLogItem(log)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    final theme = Theme.of(context);
    final level = log['level']?.toString() ?? 'info';
    final message = log['message']?.toString() ?? '';
    final createdAt = log['created_at']?.toString();

    Color levelColor;
    IconData levelIcon;
    switch (level.toLowerCase()) {
      case 'error':
        levelColor = Colors.red;
        levelIcon = Icons.error;
        break;
      case 'warning':
        levelColor = Colors.orange;
        levelIcon = Icons.warning;
        break;
      case 'info':
        levelColor = Colors.blue;
        levelIcon = Icons.info;
        break;
      default:
        levelColor = Colors.grey;
        levelIcon = Icons.circle;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: levelColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: levelColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(levelIcon, size: 14, color: levelColor),
              const SizedBox(width: 4),
              Text(
                level.toUpperCase(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: levelColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (createdAt != null) ...[
                const Spacer(),
                Text(
                  _formatDate(createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('yyyy/MM/dd HH:mm:ss').format(date);
    } catch (e) {
      return dateStr;
    }
  }
}

