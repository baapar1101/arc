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

  Map<String, dynamic>? _outboxSummary;
  bool _outboxLoading = false;
  late final VoidCallback _outboxTabListener;
  final _abandonConfirmController = TextEditingController();
  final _abandonEventKeyController = TextEditingController();
  final _abandonUserIdController = TextEditingController();
  final _abandonMaxRowsController = TextEditingController(text: '50000');
  final _abandonNoteController = TextEditingController();
  String _abandonChannel = 'sms';
  bool _abandonOnlyScheduled = true;
  
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
    _tabController = TabController(length: 5, vsync: this);
    _outboxTabListener = () {
      if (!mounted) return;
      if (_tabController.index == 4) {
        _loadOutboxSummary();
      }
    };
    _tabController.addListener(_outboxTabListener);
    _loadData();
    _connectWebSocket();
  }

  @override
  void dispose() {
    _tabController.removeListener(_outboxTabListener);
    _refreshTimer?.cancel();
    _wsSubscription?.cancel();
    _wsClient?.disconnect();
    _abandonConfirmController.dispose();
    _abandonEventKeyController.dispose();
    _abandonUserIdController.dispose();
    _abandonMaxRowsController.dispose();
    _abandonNoteController.dispose();
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
          _error = e.toString();
          _isLoading = false;
        });
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطا در بارگذاری داده‌ها: $e'),
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

  Future<void> _loadOutboxSummary({bool silent = false}) async {
    if (!silent) {
      setState(() => _outboxLoading = true);
    }
    try {
      final data = await _service.getNotificationOutboxSummary();
      if (mounted) {
        setState(() {
          _outboxSummary = data;
          _outboxLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _outboxLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در بارگذاری صف اعلان: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
            Tab(text: 'اعلان / پیامک', icon: Icon(Icons.sms_outlined)),
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
                    _buildOutboxNotificationsTab(theme),
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

  Widget _buildOutboxNotificationsTab(ThemeData theme) {
    if (_outboxLoading && _outboxSummary == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_outboxSummary == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('برای بارگذاری این تب را باز کنید یا دکمه زیر را بزنید'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadOutboxSummary,
              icon: const Icon(Icons.refresh),
              label: const Text('بارگذاری'),
            ),
          ],
        ),
      );
    }

    final rq = _outboxSummary!['retry_queue'] as Map? ?? {};
    final pending = _outboxSummary!['pending'] as Map? ?? {};
    final c24 = _outboxSummary!['created_last_24h'] as Map? ?? {};
    final smsRate = _outboxSummary!['sms_destination_rate'] as Map? ?? {};
    final thresholds = _outboxSummary!['thresholds'] as Map? ?? {};
    final warnings = (_outboxSummary!['warnings'] as List?) ?? [];
    final topEvents = (_outboxSummary!['top_failed_sms_events_7d'] as List?) ?? [];
    final byStatus = (c24['by_status'] as Map?) ?? {};
    final confirmPhrase = _outboxSummary!['abandon_confirm_phrase'] as String? ?? '';
    final dueNow = (rq['failed_due_now'] as num?)?.toInt() ?? 0;
    final dueWarn = (thresholds['due_retry_warn'] as num?)?.toInt() ?? 500;
    final pendSms = (pending['sms'] as num?)?.toInt() ?? 0;
    final pendWarn = (thresholds['sms_pending_warn'] as num?)?.toInt() ?? 50;

    return RefreshIndicator(
      onRefresh: () => _loadOutboxSummary(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _buildSectionTitle(theme, 'صف اعلان و پیامک (outbox)')),
                IconButton(
                  onPressed: () => _loadOutboxSummary(),
                  icon: const Icon(Icons.refresh),
                  tooltip: 'بروزرسانی',
                ),
              ],
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...warnings.map((w) {
                final m = w as Map;
                return Card(
                  color: Colors.orange.shade50,
                  child: ListTile(
                    leading: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                    title: Text(m['message'] as String? ?? ''),
                    subtitle: Text(m['code'] as String? ?? ''),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatItem(
                  theme,
                  'آماده retry (اکنون)',
                  '$dueNow',
                  Icons.schedule,
                  dueNow >= dueWarn ? Colors.red : Colors.blue,
                ),
                _buildStatItem(
                  theme,
                  'retry زمان‌بندی‌شده',
                  '${rq['failed_scheduled_future'] ?? 0}',
                  Icons.timer_outlined,
                  Colors.indigo,
                ),
                _buildStatItem(
                  theme,
                  'pending پیامک',
                  '$pendSms',
                  Icons.sms,
                  pendSms >= pendWarn ? Colors.red : Colors.teal,
                ),
                _buildStatItem(
                  theme,
                  'Redis کش',
                  (_outboxSummary!['redis_cache_enabled'] == true) ? 'فعال' : 'غیرفعال',
                  Icons.storage,
                  (_outboxSummary!['redis_cache_enabled'] == true) ? Colors.green : Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('سقف پیامک به هر مقصد: ${smsRate['enabled'] == true ? "فعال" : "غیرفعال"} — '
                '${smsRate['max_sends_per_window'] ?? "-"} / ${smsRate['window_minutes'] ?? "-"} دقیقه',
                style: theme.textTheme.bodyMedium),
            Text(
              'حداکثر تلاش retry هر ردیف: ${_outboxSummary!['outbox_max_retry_per_row'] ?? "-"}',
              style: theme.textTheme.bodySmall,
            ),
            if (rq['oldest_due_at_utc'] != null)
              Text('قدیمی‌ترین due: ${rq['oldest_due_at_utc']}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            _buildSectionTitle(theme, 'ایجاد در ۲۴ ساعت (همه کانال‌ها) — به تفکیک وضعیت'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: byStatus.entries.map((e) {
                return Chip(label: Text('${e.key}: ${e.value}'));
              }).toList(),
            ),
            Text('مجموع پیامک ایجادشده در ۲۴ ساعت: ${c24['sms_total'] ?? 0}'),
            const SizedBox(height: 16),
            _buildSectionTitle(theme, 'بیشترین رویدادهای ناموفق پیامک (۷ روز)'),
            const SizedBox(height: 8),
            ...topEvents.map((raw) {
              final e = raw as Map;
              return ListTile(
                dense: true,
                title: Text(e['event_key'] as String? ?? ''),
                trailing: Text('${e['count']}'),
              );
            }),
            const SizedBox(height: 24),
            _buildSectionTitle(theme, 'مدیریت صف (خالی کردن دسته‌ای)'),
            const SizedBox(height: 8),
            SelectableText(
              'عبارت تأیید: $confirmPhrase',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showAbandonOutboxDialog(theme, confirmPhrase),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('رها کردن ردیف‌ها (abandon)…'),
            ),
            const SizedBox(height: 24),
            Text(
              'آستانه هشدار را می‌توان با متغیرهای محیطی '
              'MONITORING_OUTBOX_DUE_RETRY_WARN و MONITORING_OUTBOX_SMS_PENDING_WARN تنظیم کرد.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAbandonOutboxDialog(ThemeData theme, String expectedPhrase) async {
    _abandonConfirmController.clear();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('رها کردن ردیف‌های outbox'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'این عمل ردیف‌های مطابق فیلتر را به وضعیت abandoned می‌برد. عبارت تأیید را دقیق وارد کنید.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _abandonConfirmController,
                  decoration: const InputDecoration(
                    labelText: 'عبارت تأیید',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'کانال',
                    border: OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _abandonChannel,
                      items: const [
                        DropdownMenuItem(value: 'sms', child: Text('فقط SMS')),
                        DropdownMenuItem(value: '__all__', child: Text('همه کانال‌ها')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _abandonChannel = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _abandonEventKeyController,
                  decoration: const InputDecoration(
                    labelText: 'event_key (اختیاری، مثلاً auth.password_reset)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _abandonUserIdController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'شناسه کاربر (اختیاری)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _abandonMaxRowsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'حداکثر تعداد ردیف',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _abandonNoteController,
                  decoration: const InputDecoration(
                    labelText: 'یادداشت کوتاه (اختیاری)',
                    border: OutlineInputBorder(),
                  ),
                ),
                CheckboxListTile(
                  value: _abandonOnlyScheduled,
                  onChanged: (v) {
                    setState(() => _abandonOnlyScheduled = v ?? true);
                  },
                  title: const Text('فقط ردیف‌های دارای زمان retry (next_attempt_at)'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
            ElevatedButton(
              onPressed: () async {
                final maxRows = int.tryParse(_abandonMaxRowsController.text.trim()) ?? 50000;
                final uid = int.tryParse(_abandonUserIdController.text.trim());
                final ev = _abandonEventKeyController.text.trim();
                final channel = _abandonChannel == '__all__' ? null : _abandonChannel;
                final nav = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final r = await _service.abandonNotificationOutbox(
                    confirmPhrase: _abandonConfirmController.text.trim(),
                    statuses: const ['failed'],
                    channel: channel,
                    eventKey: ev.isEmpty ? null : ev,
                    userId: uid,
                    onlyRetryScheduled: _abandonOnlyScheduled,
                    maxRows: maxRows,
                    adminNote: _abandonNoteController.text.trim().isEmpty
                        ? null
                        : _abandonNoteController.text.trim(),
                  );
                  if (!ctx.mounted) return;
                  nav.pop();
                  if (!context.mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('انجام شد: ${r['abandoned_count'] ?? r['message'] ?? r}'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  await _loadOutboxSummary();
                } catch (e) {
                  if (!context.mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text('خطا: $e'), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('اجرای abandon'),
            ),
          ],
        );
      },
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
            content: Text('خطا در restart: $e'),
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

