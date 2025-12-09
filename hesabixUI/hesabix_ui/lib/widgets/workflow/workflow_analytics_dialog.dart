import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/workflow_service.dart';

/// دیالوگ نمایش آمار و تحلیل workflow
class WorkflowAnalyticsDialog extends StatefulWidget {
  final int businessId;
  final int? workflowId;
  final String? workflowName;

  const WorkflowAnalyticsDialog({
    super.key,
    required this.businessId,
    this.workflowId,
    this.workflowName,
  });

  @override
  State<WorkflowAnalyticsDialog> createState() => _WorkflowAnalyticsDialogState();
}

class _WorkflowAnalyticsDialogState extends State<WorkflowAnalyticsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final WorkflowService _workflowService = WorkflowService();
  
  bool _loadingPerformance = false;
  bool _loadingErrors = false;
  
  Map<String, dynamic>? _performanceData;
  Map<String, dynamic>? _errorsData;
  
  int _performanceDays = 30;
  int _errorsDays = 7;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadPerformanceAnalytics(),
      _loadErrorsAnalytics(),
    ]);
  }

  Future<void> _loadPerformanceAnalytics() async {
    setState(() => _loadingPerformance = true);
    try {
      final data = await _workflowService.getWorkflowPerformanceAnalytics(
        businessId: widget.businessId,
        workflowId: widget.workflowId,
        days: _performanceDays,
      );
      if (mounted) {
        setState(() {
          _performanceData = data;
          _loadingPerformance = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingPerformance = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری آمار عملکرد: $e')),
        );
      }
    }
  }

  Future<void> _loadErrorsAnalytics() async {
    setState(() => _loadingErrors = true);
    try {
      final data = await _workflowService.getWorkflowErrorsAnalytics(
        businessId: widget.businessId,
        workflowId: widget.workflowId,
        days: _errorsDays,
      );
      if (mounted) {
        setState(() {
          _errorsData = data;
          _loadingErrors = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingErrors = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری آمار خطاها: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.analytics_outlined, size: 32, color: theme.primaryColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'آمار و تحلیل',
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
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Tabs
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(
                  icon: Icon(Icons.speed),
                  text: 'عملکرد',
                ),
                Tab(
                  icon: Icon(Icons.error_outline),
                  text: 'خطاها',
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPerformanceTab(),
                  _buildErrorsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceTab() {
    if (_loadingPerformance) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_performanceData == null) {
      return const Center(child: Text('داده‌ای موجود نیست'));
    }

    final workflows = (_performanceData!['workflows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    
    if (workflows.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'هنوز اجرایی ثبت نشده است',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period Selector
          _buildPeriodSelector(
            value: _performanceDays,
            onChanged: (value) {
              setState(() => _performanceDays = value);
              _loadPerformanceAnalytics();
            },
          ),
          const SizedBox(height: 24),
          
          // Workflows List
          ...workflows.map((workflow) => _buildPerformanceCard(workflow)).toList(),
        ],
      ),
    );
  }

  Widget _buildPerformanceCard(Map<String, dynamic> workflow) {
    final theme = Theme.of(context);
    final totalExecutions = workflow['total_executions'] as int? ?? 0;
    final successful = workflow['successful'] as int? ?? 0;
    final failed = workflow['failed'] as int? ?? 0;
    final successRate = workflow['success_rate'] as num? ?? 0;
    final avgDuration = workflow['avg_duration_seconds'] as num? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // عنوان
            if (widget.workflowId == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  workflow['workflow_name'] as String? ?? '',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            
            // متریک‌ها
            Row(
              children: [
                Expanded(
                  child: _buildMetricItem(
                    icon: Icons.play_circle_outline,
                    label: 'کل اجراها',
                    value: totalExecutions.toString(),
                    color: Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildMetricItem(
                    icon: Icons.check_circle_outline,
                    label: 'موفق',
                    value: successful.toString(),
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildMetricItem(
                    icon: Icons.error_outline,
                    label: 'ناموفق',
                    value: failed.toString(),
                    color: Colors.red,
                  ),
                ),
                Expanded(
                  child: _buildMetricItem(
                    icon: Icons.timer_outlined,
                    label: 'میانگین زمان',
                    value: '${avgDuration.toStringAsFixed(2)}s',
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Success Rate Progress
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'نرخ موفقیت',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      '${successRate.toStringAsFixed(1)}%',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _getSuccessRateColor(successRate.toDouble()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: successRate / 100,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getSuccessRateColor(successRate.toDouble()),
                  ),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorsTab() {
    if (_loadingErrors) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorsData == null) {
      return const Center(child: Text('داده‌ای موجود نیست'));
    }

    final totalErrors = _errorsData!['total_errors'] as int? ?? 0;
    final uniqueErrorTypes = _errorsData!['unique_error_types'] as int? ?? 0;
    final errorsByType = (_errorsData!['errors_by_type'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (totalErrors == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green[400]),
            const SizedBox(height: 16),
            Text(
              'خطایی ثبت نشده است! 🎉',
              style: TextStyle(
                color: Colors.green[700],
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period Selector
          _buildPeriodSelector(
            value: _errorsDays,
            onChanged: (value) {
              setState(() => _errorsDays = value);
              _loadErrorsAnalytics();
            },
            options: const [7, 14, 30, 60, 90],
          ),
          const SizedBox(height: 24),
          
          // Summary Cards
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.error,
                  title: 'کل خطاها',
                  value: totalErrors.toString(),
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.category,
                  title: 'انواع خطا',
                  value: uniqueErrorTypes.toString(),
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Errors Chart (Pie Chart)
          if (errorsByType.isNotEmpty) ...[
            Text(
              'توزیع خطاها',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: _buildErrorsPieChart(errorsByType),
            ),
            const SizedBox(height: 24),
          ],
          
          // Errors List
          Text(
            'جزئیات خطاها',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...errorsByType.map((error) => _buildErrorCard(error)).toList(),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector({
    required int value,
    required Function(int) onChanged,
    List<int> options = const [7, 14, 30, 60, 90],
  }) {
    return Row(
      children: [
        Text('بازه زمانی:', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: 12),
        SegmentedButton<int>(
          segments: options.map((days) {
            return ButtonSegment<int>(
              value: days,
              label: Text('$days روز'),
            );
          }).toList(),
          selected: {value},
          onSelectionChanged: (Set<int> newSelection) {
            onChanged(newSelection.first);
          },
        ),
      ],
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(Map<String, dynamic> error) {
    final theme = Theme.of(context);
    final errorType = error['error_type'] as String? ?? 'Unknown';
    final count = error['count'] as int? ?? 0;
    final percentage = error['percentage'] as num? ?? 0;
    final lastOccurrence = error['last_occurrence'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.red[100],
          child: Text(
            count.toString(),
            style: TextStyle(
              color: Colors.red[900],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          errorType,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: lastOccurrence != null
            ? Text('آخرین رخداد: ${_formatDateTime(lastOccurrence)}')
            : null,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${percentage.toStringAsFixed(1)}%',
            style: TextStyle(
              color: Colors.red[900],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorsPieChart(List<Map<String, dynamic>> errors) {
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.amber,
      Colors.yellow,
      Colors.lime,
      Colors.purple,
      Colors.pink,
      Colors.indigo,
    ];

    return PieChart(
      PieChartData(
        sections: errors.asMap().entries.map((entry) {
          final index = entry.key;
          final error = entry.value;
          final percentage = error['percentage'] as num? ?? 0;
          
          return PieChartSectionData(
            color: colors[index % colors.length],
            value: percentage.toDouble(),
            title: '${percentage.toStringAsFixed(1)}%',
            radius: 100,
            titleStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          );
        }).toList(),
        sectionsSpace: 2,
        centerSpaceRadius: 0,
      ),
    );
  }

  Color _getSuccessRateColor(double rate) {
    if (rate >= 95) return Colors.green;
    if (rate >= 80) return Colors.orange;
    return Colors.red;
  }

  String _formatDateTime(String dateTime) {
    try {
      final date = DateTime.parse(dateTime);
      final formatter = DateFormat('yyyy/MM/dd HH:mm');
      return formatter.format(date.toLocal());
    } catch (e) {
      return dateTime;
    }
  }
}

