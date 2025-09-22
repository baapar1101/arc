import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class SystemLogsPage extends StatefulWidget {
  const SystemLogsPage({super.key});

  @override
  State<SystemLogsPage> createState() => _SystemLogsPageState();
}

class _SystemLogsPageState extends State<SystemLogsPage> {
  final _searchController = TextEditingController();
  String _selectedLevel = 'all';
  String _selectedDateRange = 'today';
  bool _isLoading = false;

  // Mock log data
  final List<Map<String, dynamic>> _logs = [
    {
      'id': 1,
      'timestamp': '2024-01-15 10:30:25',
      'level': 'info',
      'message': 'User login successful',
      'module': 'auth',
      'userId': 123,
      'ip': '192.168.1.100',
    },
    {
      'id': 2,
      'timestamp': '2024-01-15 10:25:10',
      'level': 'warning',
      'message': 'Failed login attempt',
      'module': 'auth',
      'userId': null,
      'ip': '192.168.1.101',
    },
    {
      'id': 3,
      'timestamp': '2024-01-15 10:20:05',
      'level': 'error',
      'message': 'Database connection timeout',
      'module': 'database',
      'userId': null,
      'ip': null,
    },
    {
      'id': 4,
      'timestamp': '2024-01-15 10:15:30',
      'level': 'info',
      'message': 'File uploaded successfully',
      'module': 'storage',
      'userId': 123,
      'ip': '192.168.1.100',
    },
    {
      'id': 5,
      'timestamp': '2024-01-15 10:10:15',
      'level': 'debug',
      'message': 'API request processed',
      'module': 'api',
      'userId': 456,
      'ip': '192.168.1.102',
    },
  ];

  List<Map<String, dynamic>> get _filteredLogs {
    return _logs.where((log) {
      final matchesSearch = log['message'].toString().toLowerCase()
          .contains(_searchController.text.toLowerCase()) ||
          log['module'].toString().toLowerCase()
          .contains(_searchController.text.toLowerCase());
      
      final matchesLevel = _selectedLevel == 'all' || log['level'] == _selectedLevel;
      
      return matchesSearch && matchesLevel;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t.systemLogs,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimary,
          ),
        ),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/user/profile/system-settings'),
        ),
        actions: [
          IconButton(
            onPressed: _refreshLogs,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _exportLogs,
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.1),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: Column(
          children: [
            _buildFilters(theme, t),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildLogsList(theme, t),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(ThemeData theme, AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search logs...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedLevel,
                  decoration: const InputDecoration(
                    labelText: 'Log Level',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Levels')),
                    DropdownMenuItem(value: 'debug', child: Text('Debug')),
                    DropdownMenuItem(value: 'info', child: Text('Info')),
                    DropdownMenuItem(value: 'warning', child: Text('Warning')),
                    DropdownMenuItem(value: 'error', child: Text('Error')),
                  ],
                  onChanged: (value) => setState(() => _selectedLevel = value!),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedDateRange,
                  decoration: const InputDecoration(
                    labelText: 'Date Range',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'today', child: Text('Today')),
                    DropdownMenuItem(value: 'yesterday', child: Text('Yesterday')),
                    DropdownMenuItem(value: 'week', child: Text('This Week')),
                    DropdownMenuItem(value: 'month', child: Text('This Month')),
                  ],
                  onChanged: (value) => setState(() => _selectedDateRange = value!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList(ThemeData theme, AppLocalizations t) {
    final logs = _filteredLogs;
    
    if (logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No logs found',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return _buildLogCard(log, theme, t);
      },
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log, ThemeData theme, AppLocalizations t) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: _buildLogLevelIcon(log['level']),
        title: Text(
          log['message'],
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${log['timestamp']} • ${log['module']}',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLogDetail('Level', log['level'].toString().toUpperCase()),
                _buildLogDetail('Module', log['module']),
                _buildLogDetail('Timestamp', log['timestamp']),
                if (log['userId'] != null)
                  _buildLogDetail('User ID', log['userId'].toString()),
                if (log['ip'] != null)
                  _buildLogDetail('IP Address', log['ip']),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    log['message'],
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogLevelIcon(String level) {
    IconData icon;
    Color color;
    
    switch (level) {
      case 'error':
        icon = Icons.error;
        color = Colors.red;
        break;
      case 'warning':
        icon = Icons.warning;
        color = Colors.orange;
        break;
      case 'info':
        icon = Icons.info;
        color = Colors.blue;
        break;
      case 'debug':
        icon = Icons.bug_report;
        color = Colors.grey;
        break;
      default:
        icon = Icons.circle;
        color = Colors.grey;
    }
    
    return Icon(icon, color: color, size: 20);
  }

  Widget _buildLogDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  void _refreshLogs() {
    setState(() => _isLoading = true);
    // Simulate API call
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  void _exportLogs() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export logs functionality would be implemented here')),
    );
  }
}
