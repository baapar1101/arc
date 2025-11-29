import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../services/system_services_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/loading_indicator.dart';

class ServiceLogsPage extends StatefulWidget {
  const ServiceLogsPage({super.key});

  @override
  State<ServiceLogsPage> createState() => _ServiceLogsPageState();
}

class _ServiceLogsPageState extends State<ServiceLogsPage> {
  final _service = SystemServicesService(ApiClient());
  
  String _selectedService = 'hesabix-api';
  List<Map<String, dynamic>> _logs = [];
  Map<String, dynamic>? _serviceStatus;
  bool _isLoading = false;
  bool _autoRefresh = true;
  int _lines = 100;
  String? _error;
  
  Timer? _refreshTimer;
  final ScrollController _scrollController = ScrollController();

  final List<String> _availableServices = ['hesabix-api', 'hesabix-rq-worker'];

  @override
  void initState() {
    super.initState();
    _loadData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    if (_autoRefresh) {
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _loadLogs(silent: true);
      });
    }
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadLogs(),
      _loadServiceStatus(),
    ]);
  }

  Future<void> _loadLogs({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final data = await _service.getServiceLogs(
        serviceName: _selectedService,
        lines: _lines,
      );
      
      if (mounted) {
        setState(() {
          _logs = List<Map<String, dynamic>>.from(data['logs'] as List? ?? []);
          _isLoading = false;
          _error = null;
        });
        
        // Scroll to bottom برای نمایش جدیدترین لاگ‌ها
        if (_scrollController.hasClients && _logs.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
        if (!silent) {
          SnackBarHelper.showError(context, message: 'خطا در دریافت لاگ‌ها: $e');
        }
      }
    }
  }

  Future<void> _loadServiceStatus() async {
    try {
      final status = await _service.getServiceStatus(serviceName: _selectedService);
      if (mounted) {
        setState(() {
          _serviceStatus = status;
        });
      }
    } catch (e) {
      print('Error loading service status: $e');
    }
  }

  Future<void> _restartService() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تایید Restart'),
        content: Text('آیا مطمئن هستید که می‌خواهید سرویس $_selectedService را restart کنید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('لغو'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Restart'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      setState(() {
        _isLoading = true;
      });

      final result = await _service.restartService(serviceName: _selectedService);
      
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: result['message'] as String? ?? 'سرویس با موفقیت restart شد');
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در restart کردن سرویس: $e');
        setState(() {
          _isLoading = false;
        });
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

  Color _getLogLevelColor(String level) {
    final levelNum = int.tryParse(level) ?? 6;
    switch (levelNum) {
      case 0: // emerg
      case 1: // alert
      case 2: // crit
      case 3: // err
        return Colors.red;
      case 4: // warning
        return Colors.orange;
      case 5: // notice
      case 6: // info
        return Colors.blue;
      case 7: // debug
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      // timestamp از journalctl به میکروثانیه است
      final ms = int.tryParse(timestamp) ?? 0;
      final date = DateTime.fromMicrosecondsSinceEpoch(ms ~/ 1000);
      return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('لاگ‌های سرویس‌های سیستم'),
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
      body: Column(
        children: [
          // انتخاب سرویس و وضعیت
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedService,
                    isExpanded: true,
                    items: _availableServices.map((service) {
                      return DropdownMenuItem(
                        value: service,
                        child: Text(service),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedService = value;
                        });
                        _loadData();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                if (_serviceStatus != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: (_serviceStatus!['is_active'] as bool? ?? false)
                          ? Colors.green
                          : Colors.red,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      (_serviceStatus!['is_active'] as bool? ?? false) ? 'فعال' : 'غیرفعال',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _restartService,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Restart'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          
          // لاگ‌ها
          Expanded(
            child: _isLoading && _logs.isEmpty
                ? const Center(child: LoadingIndicator())
                : _error != null && _logs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 64, color: Colors.red),
                            const SizedBox(height: 16),
                            Text(
                              'خطا در دریافت لاگ‌ها',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => _loadData(),
                              child: const Text('تلاش مجدد'),
                            ),
                          ],
                        ),
                      )
                    : _logs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.info_outline, size: 64, color: Colors.grey),
                                const SizedBox(height: 16),
                                Text(
                                  'لاگی یافت نشد',
                                  style: theme.textTheme.titleLarge,
                                ),
                              ],
                            ),
                          )
                        : Container(
                            color: Colors.black87,
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(8),
                              itemCount: _logs.length,
                              itemBuilder: (context, index) {
                                final log = _logs[index];
                                final message = log['message'] as String? ?? '';
                                final level = log['level'] as String? ?? '6';
                                final timestamp = log['timestamp'] as String? ?? '';
                                
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    border: Border(
                                      left: BorderSide(
                                        color: _getLogLevelColor(level),
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 140,
                                        child: Text(
                                          _formatTimestamp(timestamp),
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 60,
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _getLogLevelColor(level).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          level == '3' ? 'ERR' : 
                                          level == '4' ? 'WARN' :
                                          level == '6' ? 'INFO' :
                                          level == '7' ? 'DEBUG' : 'LOG',
                                          style: TextStyle(
                                            color: _getLogLevelColor(level),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          message,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
          
          // Footer info
          if (_logs.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'تعداد لاگ‌ها: ${_logs.length}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text('ERROR', style: theme.textTheme.bodySmall),
                      const SizedBox(width: 12),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text('WARN', style: theme.textTheme.bodySmall),
                      const SizedBox(width: 12),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text('INFO', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

