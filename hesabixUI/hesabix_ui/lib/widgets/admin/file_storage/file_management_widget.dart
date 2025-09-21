import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../../core/api_client.dart';

class FileManagementWidget extends StatefulWidget {
  const FileManagementWidget({super.key});

  @override
  State<FileManagementWidget> createState() => _FileManagementWidgetState();
}

class _FileManagementWidgetState extends State<FileManagementWidget>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _allFiles = [];
  List<Map<String, dynamic>> _unverifiedFiles = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ApiClient();
      
      // Call API to load files
      final response = await api.get('/api/v1/admin/files/');
      final unverifiedResponse = await api.get('/api/v1/admin/files/unverified');
      
      if (response.data != null && response.data['success'] == true) {
        final files = response.data['data']['files'] as List<dynamic>;
        final unverifiedFiles = unverifiedResponse.data != null && unverifiedResponse.data['success'] == true 
            ? unverifiedResponse.data['data']['unverified_files'] as List<dynamic>
            : <dynamic>[];
        
        setState(() {
          _allFiles = files.cast<Map<String, dynamic>>();
          _unverifiedFiles = unverifiedFiles.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      } else {
        throw Exception(response.data?['message'] ?? 'خطا در دریافت فایل‌ها');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }


  Future<void> _forceDeleteFile(String fileId) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteConfirm),
        content: Text(l10n.deleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.forceDelete),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final api = ApiClient();
        final response = await api.delete('/api/v1/admin/files/$fileId');
        
        if (response.data != null && response.data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.fileDeleted),
              backgroundColor: Colors.green,
            ),
          );
          
          _loadFiles();
        } else {
          throw Exception(response.data?['message'] ?? 'خطا در حذف فایل');
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorDeletingFile),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _restoreFile(String fileId) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.restoreConfirm),
        content: Text(l10n.restoreConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.restoreFile),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final api = ApiClient();
        final response = await api.put('/api/v1/admin/files/$fileId/restore');
        
        if (response.data != null && response.data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.fileRestored),
              backgroundColor: Colors.green,
            ),
          );
          
          _loadFiles();
        } else {
          throw Exception(response.data?['message'] ?? 'خطا در بازیابی فایل');
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorRestoringFile),
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

  String _formatDate(String dateString) {
    final date = DateTime.parse(dateString);
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.folder),
              text: l10n.allFiles,
            ),
            Tab(
              icon: const Icon(Icons.warning),
              text: l10n.unverifiedFilesList,
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildFilesList(_allFiles),
              _buildFilesList(_unverifiedFiles),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilesList(List<Map<String, dynamic>> files) {
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
              onPressed: _loadFiles,
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }

    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noFilesFound,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              _getFileIcon(file['mime_type']),
              color: theme.colorScheme.primary,
            ),
            title: Text(
              file['original_name'],
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${l10n.fileSize}: ${_formatFileSize(file['file_size'])}'),
                Text('${l10n.moduleContext}: ${file['module_context']}'),
                Text('${l10n.createdAt}: ${_formatDate(file['created_at'])}'),
                if (file['is_temporary'] == true)
                  Text(
                    '${l10n.isTemporary}: ${file['expires_at'] != null ? _formatDate(file['expires_at']) : 'N/A'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                if (file['is_verified'] == false)
                  Text(
                    l10n.isVerified,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'delete':
                    _forceDeleteFile(file['id']);
                    break;
                  case 'restore':
                    _restoreFile(file['id']);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Text(AppLocalizations.of(context).forceDelete),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'restore',
                  child: Row(
                    children: [
                      Icon(Icons.restore, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(AppLocalizations.of(context).restoreFile),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getFileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.video_file;
    if (mimeType.startsWith('audio/')) return Icons.audio_file;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word')) return Icons.description;
    if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) return Icons.table_chart;
    if (mimeType.contains('zip') || mimeType.contains('rar')) return Icons.archive;
    return Icons.insert_drive_file;
  }
}
