import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import '../../services/workflow_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';


/// دیالوگ نمایش Timeline اجرای workflow
class WorkflowTimelineDialog extends StatefulWidget {
  final int businessId;
  final int workflowId;
  final int executionId;
  final String? workflowName;

  const WorkflowTimelineDialog({
    super.key,
    required this.businessId,
    required this.workflowId,
    required this.executionId,
    this.workflowName,
  });

  @override
  State<WorkflowTimelineDialog> createState() => _WorkflowTimelineDialogState();
}

class _WorkflowTimelineDialogState extends State<WorkflowTimelineDialog> {
  final WorkflowService _workflowService = WorkflowService();
  bool _loading = false;
  Map<String, dynamic>? _timelineData;
  String _filterLevel = 'all'; // all, error, info
  String _filterNodeId = 'all';

  @override
  void initState() {
    super.initState();
    _loadTimeline();
  }

  Future<void> _loadTimeline() async {
    setState(() => _loading = true);
    try {
      final data = await _workflowService.getExecutionTimeline(
        businessId: widget.businessId,
        workflowId: widget.workflowId,
        executionId: widget.executionId,
      );
      if (mounted) {
        setState(() {
          _timelineData = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        SnackBarHelper.show(
        context,
        message:
            '${AppLocalizations.of(context).workflowErrorLoadTimeline}: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.timeline, size: 32, color: theme.primaryColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.workflowTimelineTitle,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.workflowName != null)
                        Text(
                          widget.workflowName!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadTimeline,
                  tooltip: t.workflowTimelineRefresh,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 32),
            
            // Loading or Content
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_timelineData == null)
              Expanded(
                child: Center(child: Text(t.workflowNoData)),
              )
            else
              Expanded(child: _buildTimelineContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineContent() {
    final execution = _timelineData!['execution'] as Map<String, dynamic>?;
    final timeline = (_timelineData!['timeline'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final nodeStats = (_timelineData!['node_statistics'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final summary = _timelineData!['summary'] as Map<String, dynamic>?;

    // Filter timeline
    final filteredTimeline = timeline.where((log) {
      if (_filterLevel != 'all' && log['level'] != _filterLevel) return false;
      if (_filterNodeId != 'all' && log['node_id'] != _filterNodeId) return false;
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Execution Info
        if (execution != null) _buildExecutionInfo(execution),
        const SizedBox(height: 16),
        
        // Summary Cards
        if (summary != null) _buildSummaryCards(context, summary),
        const SizedBox(height: 16),
        
        // Node Statistics
        if (nodeStats.isNotEmpty) _buildNodeStatistics(context, nodeStats),
        const SizedBox(height: 16),
        
        // Filters
        _buildFilters(timeline),
        const SizedBox(height: 16),
        
        // Timeline
        Expanded(
          child: Card(
            child: filteredTimeline.isEmpty
                ? Center(child: Text(AppLocalizations.of(context).workflowNoLogs))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredTimeline.length,
                    itemBuilder: (context, index) {
                      return _buildTimelineItem(filteredTimeline[index], index == filteredTimeline.length - 1);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildExecutionInfo(Map<String, dynamic> execution) {
    final theme = Theme.of(context);
    final status = execution['status'] as String?;
    final duration = execution['duration_seconds'] as num?;
    final startedAt = execution['started_at'] as String?;
    final completedAt = execution['completed_at'] as String?;
    final errorMessage = execution['error_message'] as String?;

    return Card(
      color: _getStatusColor(status).withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_getStatusIcon(status), color: _getStatusColor(status)),
                const SizedBox(width: 8),
                Text(
                  'وضعیت: $status',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(status),
                  ),
                ),
                if (duration != null) ...[
                  const Spacer(),
                  Icon(Icons.timer, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${duration.toStringAsFixed(2)}s',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
            if (startedAt != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.play_arrow, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'شروع: ${_formatDateTime(startedAt)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (completedAt != null) ...[
                    const SizedBox(width: 16),
                    Icon(Icons.stop, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'پایان: ${_formatDateTime(completedAt)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ],
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[900], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMessage,
                        style: TextStyle(
                          color: Colors.red[900],
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(BuildContext context, Map<String, dynamic> summary) {
    final t = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            icon: Icons.list,
            label: t.workflowAllLogs,
            value: (summary['total_logs'] as int? ?? 0).toString(),
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            icon: Icons.account_tree,
            label: t.workflowAllNodes,
            value: (summary['total_nodes'] as int? ?? 0).toString(),
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            icon: Icons.error,
            label: t.workflowErrors,
            value: (summary['error_count'] as int? ?? 0).toString(),
            color: Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeStatistics(BuildContext context, List<Map<String, dynamic>> nodeStats) {
    final t = AppLocalizations.of(context);
    return ExpansionTile(
      leading: const Icon(Icons.bar_chart),
      title: Text(t.workflowNodeStats),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              DataColumn(label: Text(t.workflowColumnNode)),
              DataColumn(label: Text(t.workflowColumnType), numeric: false),
              DataColumn(label: Text(t.workflowColumnExecutions), numeric: true),
              DataColumn(label: Text(t.workflowErrors), numeric: true),
              DataColumn(label: Text(t.workflowColumnAvgTime), numeric: true),
            ],
            rows: nodeStats.map((stat) {
              final nodeLabel = stat['node_label'] as String? ?? stat['node_id'] as String? ?? 'Unknown';
              final nodeType = stat['node_type'] as String? ?? '-';
              final executions = stat['executions'] as int? ?? 0;
              final errors = stat['errors'] as int? ?? 0;
              final avgDuration = stat['avg_duration_ms'] as num? ?? 0;

              return DataRow(
                cells: [
                  DataCell(Text(nodeLabel)),
                  DataCell(_buildNodeTypeBadge(nodeType)),
                  DataCell(Text(executions.toString())),
                  DataCell(
                    Text(
                      errors.toString(),
                      style: TextStyle(
                        color: errors > 0 ? Colors.red : null,
                        fontWeight: errors > 0 ? FontWeight.bold : null,
                      ),
                    ),
                  ),
                  DataCell(Text('${avgDuration.toStringAsFixed(1)}ms')),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildFilters(List<Map<String, dynamic>> timeline) {
    final uniqueNodeIds = timeline
        .where((log) => log['node_id'] != null)
        .map((log) => log['node_id'] as String)
        .toSet()
        .toList();

    return Row(
      children: [
        const Text('فیلتر:'),
        const SizedBox(width: 12),
        
        // Level Filter
        DropdownButton<String>(
          value: _filterLevel,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('همه سطوح')),
            DropdownMenuItem(value: 'info', child: Text('🔵 Info')),
            DropdownMenuItem(value: 'warning', child: Text('🟡 Warning')),
            DropdownMenuItem(value: 'error', child: Text('🔴 Error')),
            DropdownMenuItem(value: 'debug', child: Text('🟣 Debug')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _filterLevel = value);
            }
          },
        ),
        const SizedBox(width: 16),
        
        // Node Filter
        if (uniqueNodeIds.isNotEmpty)
          DropdownButton<String>(
            value: _filterNodeId,
            items: [
              const DropdownMenuItem(value: 'all', child: Text('همه نودها')),
              ...uniqueNodeIds.map((nodeId) {
                return DropdownMenuItem(value: nodeId, child: Text(nodeId));
              }),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _filterNodeId = value);
              }
            },
          ),
      ],
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> log, bool isLast) {
    final theme = Theme.of(context);
    final level = log['level'] as String? ?? 'info';
    final message = log['message'] as String? ?? '';
    final timestamp = log['timestamp'] as String?;
    final nodeId = log['node_id'] as String?;
    final data = log['data'] as Map<String, dynamic>?;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _getLevelColor(level),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(
                  _getLevelIcon(level),
                  size: 12,
                  color: Colors.white,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: Colors.grey[300],
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      if (timestamp != null) ...[
                        Text(
                          _formatTime(timestamp),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (nodeId != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            nodeId,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue[900],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  
                  // Message
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium,
                  ),
                  
                  // Data
                  if (data != null && data.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildDataSection(data),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataSection(Map<String, dynamic> data) {
    // نمایش داده‌های مهم
    final importantKeys = [
      'duration_ms',
      'node_type',
      'error_type',
      'error_message',
      'correlation_id',
    ];

    final displayData = <String, dynamic>{};
    for (final key in importantKeys) {
      if (data.containsKey(key)) {
        displayData[key] = data[key];
      }
    }

    if (displayData.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: displayData.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Text(
                  '${entry.key}: ',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.value.toString(),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNodeTypeBadge(String nodeType) {
    Color color;
    IconData icon;
    
    switch (nodeType) {
      case 'trigger':
        color = Colors.blue;
        icon = Icons.play_circle;
        break;
      case 'action':
        color = Colors.green;
        icon = Icons.play_arrow;
        break;
      case 'condition':
        color = Colors.orange;
        icon = Icons.help_outline;
        break;
      case 'loop':
        color = Colors.purple;
        icon = Icons.loop;
        break;
      default:
        color = Colors.grey;
        icon = Icons.circle;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            nodeType,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getLevelColor(String level) {
    switch (level.toLowerCase()) {
      case 'error':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      case 'debug':
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }

  IconData _getLevelIcon(String level) {
    switch (level.toLowerCase()) {
      case 'error':
        return Icons.close;
      case 'warning':
        return Icons.warning;
      case 'debug':
        return Icons.bug_report;
      default:
        return Icons.info;
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'تکمیل شده':
        return Colors.green;
      case 'ناموفق':
        return Colors.red;
      case 'در حال اجرا':
        return Colors.blue;
      case 'لغو شده':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status) {
      case 'تکمیل شده':
        return Icons.check_circle;
      case 'ناموفق':
        return Icons.error;
      case 'در حال اجرا':
        return Icons.play_circle;
      case 'لغو شده':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  String _formatDateTime(String dateTime) {
    try {
      final date = DateTime.parse(dateTime);
      final formatter = DateFormat('yyyy/MM/dd HH:mm:ss');
      return formatter.format(date.toLocal());
    } catch (e) {
      return dateTime;
    }
  }

  String _formatTime(String dateTime) {
    try {
      final date = DateTime.parse(dateTime);
      final formatter = DateFormat('HH:mm:ss.SSS');
      return formatter.format(date.toLocal());
    } catch (e) {
      return dateTime;
    }
  }
}


