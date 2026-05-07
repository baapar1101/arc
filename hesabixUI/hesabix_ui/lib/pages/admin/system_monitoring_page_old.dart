import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../services/monitoring_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../utils/error_extractor.dart';

class SystemMonitoringPage extends StatefulWidget {
  const SystemMonitoringPage({super.key});

  @override
  State<SystemMonitoringPage> createState() => _SystemMonitoringPageState();
}

class _SystemMonitoringPageState extends State<SystemMonitoringPage> {
  final _service = MonitoringService(ApiClient());
  Timer? _refreshTimer;
  bool _isLoading = true;
  bool _autoRefresh = true;
  int _refreshInterval = 5; // seconds
  
  Map<String, dynamic>? _hardwareMetrics;
  Map<String, dynamic>? _servicesStatus;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    if (_autoRefresh) {
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
      ]);

      if (mounted) {
        setState(() {
          _hardwareMetrics = results[0] as Map<String, dynamic>;
          _servicesStatus = results[1] as Map<String, dynamic>;
          _isLoading = false;
          _error = null;
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

  void _toggleAutoRefresh() {
    setState(() {
      _autoRefresh = !_autoRefresh;
    });
    
    if (_autoRefresh) {
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
        actions: [
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
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Hardware Metrics Cards
                      if (_hardwareMetrics != null) ...[
                        _buildSectionTitle(theme, 'منابع سخت‌افزاری'),
                        const SizedBox(height: 12),
                        _buildHardwareMetrics(theme),
                        const SizedBox(height: 24),
                      ],

                      // Services Status Cards
                      if (_servicesStatus != null) ...[
                        _buildSectionTitle(theme, 'وضعیت سرویس‌ها'),
                        const SizedBox(height: 12),
                        _buildServicesStatus(theme),
                      ],
                    ],
                  ),
                ),
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

  Widget _buildHardwareMetrics(ThemeData theme) {
    final cpu = _hardwareMetrics!['cpu'] as Map? ?? {};
    final memory = _hardwareMetrics!['memory'] as Map? ?? {};
    final disk = _hardwareMetrics!['disk'] as Map? ?? {};
    final network = _hardwareMetrics!['network'] as Map? ?? {};

    return Column(
      children: [
        Row(
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
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                theme,
                'دیسک',
                '${disk['percent']?.toStringAsFixed(1) ?? '0'}%',
                _getStatusColor(disk['percent'] as double? ?? 0),
                Icons.dns,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                theme,
                'شبکه',
                '${_formatBytes(network['bytes_recv'] as int? ?? 0)}/s',
                Colors.blue,
                Icons.network_check,
              ),
            ),
          ],
        ),
      ],
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

