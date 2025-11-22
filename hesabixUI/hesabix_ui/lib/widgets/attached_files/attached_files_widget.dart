import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hesabix_ui/services/business_storage_service.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;
import '../../utils/snackbar_helper.dart';

/// کلید برای دسترسی به state از خارج (برای refresh)
class AttachedFilesWidgetKey {
  VoidCallback? _refreshCallback;

  void attach(VoidCallback refreshCallback) {
    _refreshCallback = refreshCallback;
  }

  void detach() {
    _refreshCallback = null;
  }

  void refresh() {
    _refreshCallback?.call();
  }
}

/// ویجت ماژولار برای نمایش و دانلود فایل‌های الصاق شده
class AttachedFilesWidget extends StatefulWidget {
  /// کلید برای دسترسی به state از خارج (برای refresh)
  final AttachedFilesWidgetKey? refreshKey;
  /// شناسه کسب‌وکار
  final int businessId;
  
  /// نوع ماژول (مثلاً 'accounting', 'tickets', ...)
  final String moduleContext;
  
  /// شناسه context (مثلاً ID سند)
  final String contextId;
  
  /// عنوان بخش (اختیاری)
  final String? title;
  
  /// آیا باید فایل‌ها را به صورت خودکار بارگذاری کند؟
  final bool autoLoad;
  
  /// Callback برای زمانی که فایل‌ها بارگذاری شدند
  final void Function(List<Map<String, dynamic>>)? onFilesLoaded;
  
  /// Callback برای زمانی که فایلی حذف شد
  final void Function(String fileId)? onFileDeleted;
  
  /// آیا امکان حذف فایل وجود دارد؟
  final bool allowDelete;

  const AttachedFilesWidget({
    super.key,
    required this.businessId,
    required this.moduleContext,
    required this.contextId,
    this.title,
    this.autoLoad = true,
    this.onFilesLoaded,
    this.onFileDeleted,
    this.allowDelete = false,
    this.refreshKey,
  });

  @override
  State<AttachedFilesWidget> createState() => _AttachedFilesWidgetState();
}

class _AttachedFilesWidgetState extends State<AttachedFilesWidget> {
  late final BusinessStorageService _storageService;
  List<Map<String, dynamic>> _files = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _storageService = BusinessStorageService(ApiClient());
    widget.refreshKey?.attach(refresh);
    if (widget.autoLoad) {
      _loadFiles();
    }
  }
  
  @override
  void dispose() {
    widget.refreshKey?.detach();
    super.dispose();
  }

  /// متد عمومی برای refresh کردن فایل‌ها از خارج
  void refresh() {
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final files = await _storageService.listFilesByContext(
        businessId: widget.businessId,
        moduleContext: widget.moduleContext,
        contextId: widget.contextId,
      );

      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
        
        widget.onFilesLoaded?.call(files);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'خطا در بارگذاری فایل‌ها: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _downloadFile(Map<String, dynamic> file) async {
    try {
      final fileId = file['id'] as String;
      final filename = file['original_name'] as String? ?? 'file';
      
      final bytes = await _storageService.downloadFile(
        businessId: widget.businessId,
        fileId: fileId,
      );

      if (bytes.isNotEmpty) {
        if (kIsWeb) {
          await web_utils.saveBytesAsFileWeb(
            bytes,
            filename,
            mimeType: 'application/octet-stream',
          );
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('دانلود فایل فقط در نسخه وب پشتیبانی می‌شود')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در دانلود فایل: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    final confirmed = await _showDeleteConfirmation(file);
    if (confirmed != true) return;

    try {
      final fileId = file['id'] as String;
      await _storageService.deleteFile(
        businessId: widget.businessId,
        fileId: fileId,
      );
      
      if (mounted) {
        setState(() {
          _files.removeWhere((f) => f['id'] == fileId);
        });
        
        widget.onFileDeleted?.call(fileId);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فایل با موفقیت حذف شد'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در حذف فایل: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool?> _showDeleteConfirmation(Map<String, dynamic> file) async {
    List<Map<String, dynamic>> dependencies = <Map<String, dynamic>>[];
    String? usageError;
    try {
      final usage = await _storageService.getFileUsage(
        businessId: widget.businessId,
        fileId: file['id'] as String,
      );
      dependencies = (usage['dependencies'] as List?)
              ?.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[];
    } catch (e) {
      usageError = '$e';
    }

    if (!mounted) return false;

    final theme = Theme.of(context);

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف فایل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'آیا از حذف فایل "${file['original_name']}" اطمینان دارید؟',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (usageError != null)
              Text(
                'خطا در دریافت وابستگی‌ها: $usageError',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
              )
            else if (dependencies.isEmpty)
              Text(
                'این فایل در هیچ بخش دیگری استفاده نشده است.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              Text(
                'این فایل در بخش‌های زیر استفاده شده است:',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  itemCount: dependencies.length,
                  itemBuilder: (context, index) {
                    final dep = dependencies[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.link, color: theme.colorScheme.primary, size: 20),
                      title: Text(dep['description'] as String? ?? '-', style: theme.textTheme.bodyMedium),
                      subtitle: Text(
                        '${dep['module'] ?? ''} • ${dep['entity_type'] ?? ''} • ${dep['entity_id'] ?? ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'با حذف فایل، لینک‌های مرتبط نیز پاک می‌شوند.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  IconData _getFileIcon(String? mimeType) {
    if (mimeType == null) return Icons.insert_drive_file;
    
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.video_file;
    if (mimeType.startsWith('audio/')) return Icons.audio_file;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word') || mimeType.contains('document')) return Icons.description;
    if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) return Icons.table_chart;
    if (mimeType.contains('zip') || mimeType.contains('archive')) return Icons.folder_zip;
    
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.title != null) ...[
          Row(
            children: [
              Icon(Icons.attach_file, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                widget.title!,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (!widget.autoLoad)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadFiles,
                  tooltip: 'بروزرسانی',
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_error != null)
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade900),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadFiles,
                    child: const Text('تلاش مجدد'),
                  ),
                ],
              ),
            ),
          )
        else if (_files.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'هیچ فایلی الصاق نشده است',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
          )
        else
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8),
              itemCount: _files.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final file = _files[index];
                final filename = file['original_name'] as String? ?? 'نامشخص';
                final fileSize = file['file_size'] as int? ?? 0;
                final mimeType = file['mime_type'] as String?;

                return ListTile(
                  dense: true,
                  leading: Icon(
                    _getFileIcon(mimeType),
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(
                    filename,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _formatFileSize(fileSize),
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.download),
                        onPressed: () => _downloadFile(file),
                        tooltip: 'دانلود',
                        color: theme.colorScheme.primary,
                      ),
                      if (widget.allowDelete)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteFile(file),
                          tooltip: 'حذف',
                          color: Colors.red,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

