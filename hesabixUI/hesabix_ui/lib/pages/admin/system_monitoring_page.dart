import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import 'admin_compact_scaffold.dart';
import '../../services/monitoring_service.dart';
import '../../services/monitoring_ws_client.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/monitoring/metric_line_chart.dart';
import '../../widgets/monitoring/metric_gauge.dart';
import '../../widgets/monitoring/area_chart_widget.dart';
import '../../utils/error_extractor.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import '../../theme/tokens/extensions.dart';

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
        setState(() {
          _error = ErrorExtractor.forContext(e, context);
          _isLoading = false;
        });
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${adminTx(context, 'خطا در بارگذاری داده‌ها', 'Could not load data')}: ${ErrorExtractor.forContext(e, context)}',
              ),
              backgroundColor: SemanticColorResolver.negative(context),
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
    final hub = context.settingsHub;

    return AdminCompactScaffold(
      title: adminTx(context, 'مانیتورینگ سیستم', 'System monitoring'),
      bottom: TabBar(
        controller: _tabController,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        tabs: [
          Tab(text: adminTx(context, 'نمای کلی', 'Overview')),
          Tab(text: adminTx(context, 'سخت‌افزار', 'Hardware')),
          Tab(text: adminTx(context, 'سرویس‌ها', 'Services')),
          Tab(text: adminTx(context, 'هشدارها', 'Alerts')),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(_useWebSocket ? Icons.wifi : Icons.wifi_off, size: 20),
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
          tooltip: _useWebSocket
              ? adminTx(context, 'WebSocket فعال', 'WebSocket on')
              : adminTx(context, 'WebSocket غیرفعال', 'WebSocket off'),
        ),
        IconButton(
          icon: Icon(_autoRefresh ? Icons.pause : Icons.play_arrow, size: 20),
          onPressed: _toggleAutoRefresh,
          tooltip: _autoRefresh
              ? adminTx(context, 'توقف بروزرسانی خودکار', 'Pause auto refresh')
              : adminTx(context, 'شروع بروزرسانی خودکار', 'Start auto refresh'),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: () => _loadData(),
          tooltip: adminTx(context, 'بروزرسانی', 'Refresh'),
        ),
      ],
      body: _isLoading && _hardwareMetrics == null
          ? const Center(child: LoadingIndicator())
          : _error != null && _hardwareMetrics == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        adminTx(context, 'خطا در بارگذاری داده‌ها', 'Could not load data'),
                        style: hub.cardSubtitleStyle(
                          theme.textTheme,
                          color: SemanticColorResolver.negative(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => _loadData(),
                        child: Text(adminTx(context, 'تلاش مجدد', 'Retry')),
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
      padding: context.settingsHub.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hardwareMetrics != null) ...[
            _buildSectionTitle(theme, adminTx(context, 'خلاصه منابع', 'Resource summary')),
            const SizedBox(height: 8),
            _buildSummaryCards(theme),
            const SizedBox(height: 16),
          ],

          if (_cpuHistory.isNotEmpty) ...[
            MetricLineChart(
              data: _cpuHistory,
              title: adminTx(context, 'استفاده CPU', 'CPU usage'),
              color: SemanticColorResolver.info(context),
              unit: '%',
              maxY: 100,
            ),
            const SizedBox(height: 12),
          ],

          if (_memoryHistory.isNotEmpty) ...[
            AreaChartWidget(
              data: _memoryHistory,
              title: adminTx(context, 'استفاده حافظه', 'Memory usage'),
              color: SemanticColorResolver.positive(context),
              unit: '%',
              maxY: 100,
            ),
            const SizedBox(height: 12),
          ],

          if (_servicesStatus != null) ...[
            _buildSectionTitle(theme, adminTx(context, 'وضعیت سرویس‌ها', 'Service status')),
            const SizedBox(height: 8),
            _buildServicesGrid(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildHardwareTab(ThemeData theme) {
    if (_hardwareMetrics == null) {
      return Center(child: Text(adminTx(context, 'داده‌ای موجود نیست', 'No data')));
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
              SizedBox(width: 12),
              Expanded(
                child: MetricGauge(
                  value: memory['percent'] as double? ?? 0.0,
                  maxValue: 100.0,
                  title: adminTx(context, 'حافظه', 'Memory'),
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
                  title: adminTx(context, 'دیسک', 'Disk'),
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
              title: adminTx(context, 'تاریخچه CPU', 'CPU history'),
              color: SemanticColorResolver.info(context),
              unit: '%',
            ),
          SizedBox(height: 16),
          if (_memoryHistory.isNotEmpty)
            AreaChartWidget(
              data: _memoryHistory,
              title: adminTx(context, 'تاریخچه حافظه', 'Memory history'),
              color: SemanticColorResolver.positive(context),
              unit: '%',
            ),
        ],
      ),
    );
  }

  Widget _buildServicesTab(ThemeData theme) {
    if (_servicesStatus == null) {
      return Center(child: Text(adminTx(context, 'داده‌ای موجود نیست', 'No data')));
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
                  Icon(Icons.check_circle, size: 64, color: SemanticColorResolver.positive(context)),
                  const SizedBox(height: 16),
                  Text(
                    adminTx(context, 'هشدار فعالی وجود ندارد', 'No active alerts'),
                    style: context.settingsHub.cardTitleStyle(
                      theme.textTheme,
                      color: theme.colorScheme.onSurface,
                    ),
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
            adminTx(context, 'حافظه', 'Memory'),
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
      style: context.settingsHub.cardTitleStyle(
        theme.textTheme,
        color: theme.colorScheme.onSurface,
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
                      '${adminTx(context, 'نسخه', 'Version')}: ${status['version']}',
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
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 20),
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
                    adminTx(context, 'در صف', 'Queued'),
                    pending.toString(),
                    Icons.hourglass_empty,
                    pending > 10 ? SemanticColorResolver.warning(context) : SemanticColorResolver.info(context),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    theme,
                    adminTx(context, 'امروز', 'Today'),
                    reviewedToday.toString(),
                    Icons.check_circle_outline,
                    SemanticColorResolver.positive(context),
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
                    '${adminTx(context, 'آخرین فعالیت', 'Last activity')}: ${_formatLastActivity(lastActivity)}',
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
      
      if (diff.inMinutes < 1) return adminTx(context, 'همین الان', 'Just now');
      if (diff.inMinutes < 60) {
        return adminTx(context, '${diff.inMinutes} دقیقه پیش', '${diff.inMinutes}m ago');
      }
      if (diff.inHours < 24) {
        return adminTx(context, '${diff.inHours} ساعت پیش', '${diff.inHours}h ago');
      }
      return adminTx(context, '${diff.inDays} روز پیش', '${diff.inDays}d ago');
    } catch (e) {
      return isoTime;
    }
  }

  Future<void> _restartNotificationModerationWorker() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(adminTx(context, 'راه‌اندازی مجدد کارگر', 'Restart worker')),
          content: Text(
            adminTx(
              context,
              'کارگر بررسی اعلان‌ها دوباره راه‌اندازی شود؟',
              'Restart the notification moderation worker?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(adminTx(context, 'لغو', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(adminTx(context, 'راه‌اندازی مجدد', 'Restart')),
            ),
          ],
        ),
      );
      
      if (confirmed != true) return;
      
      // نمایش loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminTx(context, 'در حال راه‌اندازی مجدد کارگر…', 'Restarting worker…'))),
        );
      }
      
      // فراخوانی API restart
      await ApiClient().post(
        '/api/v1/admin/system-services/restart',
        query: {'service_name': 'hesabix-notification-moderation'},
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(adminTx(context, 'کارگر دوباره راه‌اندازی شد', 'Worker restarted')),
            backgroundColor: SemanticColorResolver.positive(context),
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
              '${adminTx(context, 'خطا در راه‌اندازی مجدد', 'Restart failed')}: ${ErrorExtractor.forContext(e, context)}',
            ),
            backgroundColor: SemanticColorResolver.negative(context),
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
                      child: Text(adminTx(context, 'تأیید', 'Acknowledge')),
                      onTap: () {
                        Future.delayed(Duration.zero, () {
                          _service.acknowledgeAlert(alert['id'] as int);
                          _loadAlerts();
                        });
                      },
                    ),
                    PopupMenuItem(
                      child: Text(adminTx(context, 'حل شد', 'Resolved')),
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
    if (percent < 50) return SemanticColorResolver.positive(context);
    if (percent < 80) return SemanticColorResolver.warning(context);
    return SemanticColorResolver.negative(context);
  }

  Color _getServiceStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return SemanticColorResolver.positive(context);
      case 'offline':
        return SemanticColorResolver.negative(context);
      case 'degraded':
        return SemanticColorResolver.warning(context);
      case 'disabled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return SemanticColorResolver.negative(context);
      case 'warning':
        return SemanticColorResolver.warning(context);
      case 'info':
        return SemanticColorResolver.info(context);
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
        return adminTx(context, 'آنلاین', 'Online');
      case 'offline':
        return adminTx(context, 'آفلاین', 'Offline');
      case 'degraded':
        return adminTx(context, 'کاهش عملکرد', 'Degraded');
      case 'disabled':
        return adminTx(context, 'غیرفعال', 'Disabled');
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

