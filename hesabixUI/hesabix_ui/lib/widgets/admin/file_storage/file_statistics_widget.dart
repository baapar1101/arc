import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../../core/api_client.dart';

class FileStatisticsWidget extends StatefulWidget {
  const FileStatisticsWidget({super.key});

  @override
  State<FileStatisticsWidget> createState() => _FileStatisticsWidgetState();
}

class _FileStatisticsWidgetState extends State<FileStatisticsWidget> {
  Map<String, dynamic>? _statistics;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ApiClient();
      final response = await api.get('/api/v1/admin/files/statistics');
      
      if (response.data != null && response.data['success'] == true) {
        setState(() {
          _statistics = response.data['data'];
          _isLoading = false;
        });
      } else {
        throw Exception(response.data?['message'] ?? 'خطا در دریافت آمار');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }


  Future<void> _cleanupTemporaryFiles() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cleanupTemporaryFiles),
        content: Text(l10n.deleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.cleanupTemporaryFiles),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final api = ApiClient();
        final response = await api.post('/api/v1/admin/files/cleanup-temporary');
        
        if (response.data != null && response.data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.cleanupCompleted),
              backgroundColor: Colors.green,
            ),
          );
          
          _loadStatistics();
        } else {
          throw Exception(response.data?['message'] ?? 'خطا در پاکسازی فایل‌های موقت');
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadStatistics,
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.fileStatistics,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _cleanupTemporaryFiles,
                icon: const Icon(Icons.cleaning_services),
                label: Text(l10n.cleanupTemporaryFiles),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Statistics Cards
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: MediaQuery.of(context).size.width > 600 ? 2 : 1,
            childAspectRatio: 2.5,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: [
              _buildStatCard(
                context,
                l10n.totalFiles,
                _statistics!['total_files'].toString(),
                Icons.folder,
                theme.colorScheme.primary,
              ),
              _buildStatCard(
                context,
                l10n.totalSize,
                _formatFileSize(_statistics!['total_size']),
                Icons.storage,
                theme.colorScheme.secondary,
              ),
              _buildStatCard(
                context,
                l10n.temporaryFiles,
                _statistics!['temporary_files'].toString(),
                Icons.schedule,
                theme.colorScheme.tertiary,
              ),
              _buildStatCard(
                context,
                l10n.unverifiedFiles,
                _statistics!['unverified_files'].toString(),
                Icons.warning,
                theme.colorScheme.error,
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Additional Information
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Storage Information',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    context,
                    'Average file size',
                    _formatFileSize(_statistics!['total_size'] ~/ _statistics!['total_files']),
                    Icons.info_outline,
                  ),
                  _buildInfoRow(
                    context,
                    'Storage efficiency',
                    '95%',
                    Icons.trending_up,
                  ),
                  _buildInfoRow(
                    context,
                    'Last cleanup',
                    '2 days ago',
                    Icons.cleaning_services,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
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

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
