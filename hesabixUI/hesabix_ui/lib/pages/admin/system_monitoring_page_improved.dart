import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../services/monitoring_service.dart';
import '../../services/monitoring_ws_client.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/monitoring/metric_line_chart.dart';
import '../../widgets/monitoring/metric_gauge.dart';
import '../../widgets/monitoring/area_chart_widget.dart';
import '../../utils/error_extractor.dart';

class SystemMonitoringPage extends StatefulWidget {
  const SystemMonitoringPage({super.key});

  @override
  State<SystemMonitoringPage> createState() => _SystemMonitoringPageState();
}

class _SystemMonitoringPageState extends State<SystemMonitoringPage> with SingleTickerProviderStateMixin {
  final _service = MonitoringService(ApiClient());
  Timer? _refreshTimer;
  bool _isLoading = true;
  bool _autoRefresh = true;
  int _refreshInterval = 5;
  bool _useWebSocket = true;
  
  Map<String, dynamic>? _hardwareMetrics;
  Map<String, dynamic>? _servicesStatus;
  List<Map<String, dynamic>> _alerts = [];
  String? _error;
  
  // Historical data برای نمودارها
  List<double> _cpuHistory = [];
  List<double> _memoryHistory = [];
  final int _maxHistoryPoints = 60; // آخرین 60 نقطه (5 دقیقه با 5 ثانیه interval)
  
  // WebSocket
  MonitoringWebSocketClient? _wsClient;
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
    _connectWebSocket();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _wsSubscription?.cancel();
    _wsClient?.disconnect();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _connectWebSocket() async {
    if (!_useWebSocket) return;
    
    try {
      _wsClient = createMonitoringWebSocketClient();
      await _wsClient!.connect();
      
      _wsSubscription = _wsClient!.stream?.listen((data) {
        final channel = data['channel'] as String?;
        final messageData = data['data'] as Map<String, dynamic>?;
        
        if (channel == 'hardware:metrics' && messageData != null) {
          _updateHardwareMetrics(messageData);
        } else if (channel == 'services:status' && messageData != null) {
          setState(() {
            _servicesStatus = messageData;
          });
        } else if (channel == 'alerts:new' && messageData != null) {
          _loadAlerts();
        }
      });
    } catch (e) {
      print('WebSocket connection error: $e');
      // Fallback to polling
      _useWebSocket = false;
      _startAutoRefresh();
    }
  }

  void _updateHardwareMetrics(Map<String, dynamic> metrics) {
    setState(() {
      _hardwareMetrics = metrics;
      
      // به‌روزرسانی تاریخچه برای نمودارها
      if (metrics['cpu'] != null) {
        final cpuPercent = (metrics['cpu'] as Map)['percent'] as double? ?? 0.0;
        _cpuHistory.add(cpuPercent);
        if (_cpuHistory.length > _maxHistoryPoints) {
          _cpuHistory.removeAt(0);
        }
      }
      
      if (metrics['memory'] != null) {
        final memoryPercent = (metrics['memory'] as Map)['percent'] as double? ?? 0.0;
        _memoryHistory.add(memoryPercent);
        if (_memoryHistory.length > _maxHistoryPoints) {
          _memoryHistory.removeAt(0);
        }
      }
    });
  }

  void _startAutoRefresh() {
    if (_autoRefresh && !_useWebSocket) {
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(Duration(seconds: _refreshInterval), (_) {
        _loadData(silent: true);
      });
    }
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait([
        _service.getHardwareCurrent(),
        _service.getServicesStatus(),
        _service.getActiveAlerts(),
      ]);

      if (mounted) {
        setState(() {
          _hardwareMetrics = results[0] as Map<String, dynamic>;
          _servicesStatus = results[1] as Map<String, dynamic>;
          _alerts = results[2] as List<Map<String, dynamic>>;
          _isLoading = false;
          _error = null;
          
          // به‌روزرسانی تاریخچه
          if (_hardwareMetrics != null) {
            _updateHardwareMetrics(_hardwareMetrics!);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        final err = ErrorExtractor.forContext(e, context);
        setState(() {
          _error = err;
          _isLoading = false;
        });
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطا در بارگذاری داده‌ها: $err'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _loadAlerts() async {
    try {
      final alerts = await _service.getActiveAlerts();
      if (mounted) {
        setState(() {
          _alerts = alerts;
        });
      }
    } catch (e) {
      print('Error loading alerts: $e');
    }
  }

  void _toggleAutoRefresh() {
    setState(() {
      _autoRefresh = !_autoRefresh;
    });
    
    if (_autoRefresh && !_useWebSocket) {
      _startAutoRefresh();
    } else {
      _refreshTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('مانیتورینگ سیستم'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/user/profile/system-settings'),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'نمای کلی', icon: Icon(Icons.dashboard)),
            Tab(text: 'سخت‌افزار', icon: Icon(Icons.memory)),
            Tab(text: 'سرویس‌ها', icon: Icon(Icons.cloud)),
            Tab(text: 'هشدارها', icon: Icon(Icons.warning)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_useWebSocket ? Icons.wifi : Icons.wifi_off),
            onPressed: () {
              setState(() {
                _useWebSocket = !_useWebSocket;
              });
              if (_useWebSocket) {
                _connectWebSocket();
              } else {
                _wsClient?.disconnect();
                _startAutoRefresh();
              }
            },
            tooltip: _useWebSocket ? 'WebSocket فعال' : 'WebSocket غیرفعال',
          ),
          IconButton(
            icon: Icon(_autoRefresh ? Icons.pause : Icons.play_arrow),
            onPressed: _toggleAutoRefresh,
            tooltip: _autoRefresh ? 'توقف بروزرسانی خودکار' : 'شروع بروزرسانی خودکار',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(),
            tooltip: 'بروزرسانی',
          ),
        ],
      ),
      body: _isLoading && _hardwareMetrics == null
          ? const Center(child: LoadingIndicator())
          : _error != null && _hardwareMetrics == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'خطا در بارگذاری داده‌ها',
                        style: TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _loadData(),
                        child: const Text('تلاش مجدد'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(theme),
                    _buildHardwareTab(theme),
                    _buildServicesTab(theme),
                    _buildAlertsTab(theme),
                  ],
                ),
    );
  }

  Widget _buildOverviewTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // کارت‌های خلاصه
          if (_hardwareMetrics != null) ...[
            _buildSectionTitle(theme, 'خلاصه منابع'),
            const SizedBox(height: 12),
            _buildSummaryCards(theme),
            const SizedBox(height: 24),
          ],

          // نمودار CPU
          if (_cpuHistory.isNotEmpty) ...[
            MetricLineChart(
              data: _cpuHistory,
              title: 'استفاده CPU',
              color: Colors.blue,
              unit: '%',
              maxY: 100,
            ),
            const SizedBox(height: 16),
          ],

          // نمودار Memory
          if (_memoryHistory.isNotEmpty) ...[
            AreaChartWidget(
              data: _memoryHistory,
              title: 'استفاده حافظه',
              color: Colors.green,
              unit: '%',
              maxY: 100,
            ),
            const SizedBox(height: 16),
          ],

          // وضعیت سرویس‌ها
          if (_servicesStatus != null) ...[
            _buildSectionTitle(theme, 'وضعیت سرویس‌ها'),
            const SizedBox(height: 12),
            _buildServicesGrid(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildHardwareTab(ThemeData theme) {
    if (_hardwareMetrics == null) {
      return const Center(child: Text('داده‌ای موجود نیست'));
    }

    final cpu = _hardwareMetrics!['cpu'] as Map? ?? {};
    final memory = _hardwareMetrics!['memory'] as Map? ?? {};
    final disk = _hardwareMetrics!['disk'] as Map? ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Gauge Charts
          Row(
            children: [
              Expanded(
                child: MetricGauge(
                  value: cpu['percent'] as double? ?? 0.0,
                  maxValue: 100.0,
                  title: 'CPU',
                  unit: '%',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricGauge(
                  value: memory['percent'] as double? ?? 0.0,
                  maxValue: 100.0,
                  title: 'حافظه',
                  unit: '%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: MetricGauge(
                  value: disk['percent'] as double? ?? 0.0,
                  maxValue: 100.0,
                  title: 'دیسک',
                  unit: '%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // نمودارها
          if (_cpuHistory.isNotEmpty)
            MetricLineChart(
              data: _cpuHistory,
              title: 'تاریخچه CPU',
              color: Colors.blue,
              unit: '%',
            ),
          const SizedBox(height: 16),
          if (_memoryHistory.isNotEmpty)
            AreaChartWidget(
              data: _memoryHistory,
              title: 'تاریخچه حافظه',
              color: Colors.green,
              unit: '%',
            ),
        ],
      ),
    );
  }

  Widget _buildServicesTab(ThemeData theme) {
    if (_servicesStatus == null) {
      return const Center(child: Text('داده‌ای موجود نیست'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _buildServicesStatus(theme),
    );
  }

  Widget _buildAlertsTab(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _loadAlerts,
      child: _alerts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 64, color: Colors.green),
                  const SizedBox(height: 16),
                  Text(
                    'هشدار فعالی وجود ندارد',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _alerts.length,
              itemBuilder: (context, index) {
                return _buildAlertCard(theme, _alerts[index]);
              },
            ),
    );
  }

  Widget _buildSummaryCards(ThemeData theme) {
    final cpu = _hardwareMetrics!['cpu'] as Map? ?? {};
    final memory = _hardwareMetrics!['memory'] as Map? ?? {};
    final disk = _hardwareMetrics!['disk'] as Map? ?? {};

    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            theme,
            'CPU',
            '${cpu['percent']?.toStringAsFixed(1) ?? '0'}%',
            _getStatusColor(cpu['percent'] as double? ?? 0),
            Icons.memory,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            theme,
            'حافظه',
            '${memory['percent']?.toStringAsFixed(1) ?? '0'}%',
            _getStatusColor(memory['percent'] as double? ?? 0),
            Icons.storage,
          ),
        ),
      ],
    );
  }

  Widget _buildServicesGrid(ThemeData theme) {
    final services = _servicesStatus!;
    return Column(
      children: [
        _buildServiceCard(theme, 'API Server', services['api_server'] as Map? ?? {}),
        const SizedBox(height: 12),
        _buildServiceCard(theme, 'Database', services['database'] as Map? ?? {}),
        const SizedBox(height: 12),
        _buildServiceCard(theme, 'Redis', services['redis'] as Map? ?? {}),
        const SizedBox(height: 12),
        _buildServiceCard(theme, 'Workers', services['workers'] as Map? ?? {}),
        const SizedBox(height: 12),
        _buildNotificationModerationCard(theme, services['notification_moderation'] as Map? ?? {}),
      ],
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildMetricCard(
    ThemeData theme,
    String title,
    String value,
    Color statusColor,
    IconData icon,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: statusColor),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServicesStatus(ThemeData theme) {
    final services = _servicesStatus!;
    
    return Column(
      children: [
        _buildServiceCard(theme, 'API Server', services['api_server'] as Map? ?? {}),
        const SizedBox(height: 12),
        _buildServiceCard(theme, 'Database', services['database'] as Map? ?? {}),
        const SizedBox(height: 12),
        _buildServiceCard(theme, 'Redis', services['redis'] as Map? ?? {}),
        const SizedBox(height: 12),
        _buildServiceCard(theme, 'Workers', services['workers'] as Map? ?? {}),
        const SizedBox(height: 12),
        _buildNotificationModerationCard(theme, services['notification_moderation'] as Map? ?? {}),
      ],
    );
  }

  Widget _buildServiceCard(ThemeData theme, String name, Map status) {
    final statusText = status['status'] as String? ?? 'unknown';
    final statusColor = _getServiceStatusColor(statusText);
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _translateStatus(statusText),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: statusColor,
                    ),
                  ),
                  if (status['version'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'نسخه: ${status['version']}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationModerationCard(ThemeData theme, Map status) {
    final statusText = status['status'] as String? ?? 'unknown';
    final statusColor = _getServiceStatusColor(statusText);
    final isActive = status['is_active'] as bool? ?? false;
    final queue = status['queue'] as Map? ?? {};
    final pending = queue['pending'] as int? ?? 0;
    final reviewedToday = queue['reviewed_today'] as int? ?? 0;
    final lastActivity = status['last_activity'] as String?;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'AI Moderation Worker',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _translateStatus(statusText),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Restart',
                  onPressed: isActive ? () => _restartNotificationModerationWorker() : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            // آمار صف
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    theme,
                    'در صف',
                    pending.toString(),
                    Icons.hourglass_empty,
                    pending > 10 ? Colors.orange : Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    theme,
                    'امروز',
                    reviewedToday.toString(),
                    Icons.check_circle_outline,
                    Colors.green,
                  ),
                ),
              ],
            ),
            if (lastActivity != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'آخرین فعالیت: ${_formatLastActivity(lastActivity)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[700],
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatLastActivity(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime);
      final now = DateTime.now();
      final diff = now.difference(dt);
      
      if (diff.inMinutes < 1) return 'همین الان';
      if (diff.inMinutes < 60) return '${diff.inMinutes} دقیقه پیش';
      if (diff.inHours < 24) return '${diff.inHours} ساعت پیش';
      return '${diff.inDays} روز پیش';
    } catch (e) {
      return isoTime;
    }
  }

  Future<void> _restartNotificationModerationWorker() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restart Worker'),
          content: const Text('آیا مطمئن هستید که می‌خواهید AI Moderation Worker را restart کنید؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('لغو'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restart'),
            ),
          ],
        ),
      );
      
      if (confirmed != true) return;
      
      // نمایش loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('در حال restart کردن Worker...')),
        );
      }
      
      // فراخوانی API restart
      await ApiClient().post(
        '/api/v1/admin/system-services/restart',
        query: {'service_name': 'hesabix-notification-moderation'},
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Worker با موفقیت restart شد'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      // رفرش داده‌ها بعد از 2 ثانیه
      await Future.delayed(const Duration(seconds: 2));
      _loadData();
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطا در restart: ${ErrorExtractor.forContext(e, context)}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildAlertCard(ThemeData theme, Map<String, dynamic> alert) {
    final severity = alert['severity'] as String? ?? 'info';
    final severityColor = _getSeverityColor(severity);
    final severityIcon = _getSeverityIcon(severity);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(severityIcon, color: severityColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    alert['title'] as String? ?? '',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: severityColor,
                    ),
                  ),
                ),
                PopupMenuButton(
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      child: const Text('تایید'),
                      onTap: () {
                        Future.delayed(Duration.zero, () {
                          _service.acknowledgeAlert(alert['id'] as int);
                          _loadAlerts();
                        });
                      },
                    ),
                    PopupMenuItem(
                      child: const Text('حل شد'),
                      onTap: () {
                        Future.delayed(Duration.zero, () {
                          _service.resolveAlert(alert['id'] as int);
                          _loadAlerts();
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            if (alert['message'] != null) ...[
              const SizedBox(height: 8),
              Text(
                alert['message'] as String,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _formatDateTime(alert['created_at'] as String?),
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(double percent) {
    if (percent < 50) return Colors.green;
    if (percent < 80) return Colors.orange;
    return Colors.red;
  }

  Color _getServiceStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return Colors.green;
      case 'offline':
        return Colors.red;
      case 'degraded':
        return Colors.orange;
      case 'disabled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      case 'info':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getSeverityIcon(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Icons.error;
      case 'warning':
        return Icons.warning;
      case 'info':
        return Icons.info;
      default:
        return Icons.notification_important;
    }
  }

  String _translateStatus(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return 'آنلاین';
      case 'offline':
        return 'آفلاین';
      case 'degraded':
        return 'کاهش عملکرد';
      case 'disabled':
        return 'غیرفعال';
      default:
        return status;
    }
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.year}/${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoString;
    }
  }
}

