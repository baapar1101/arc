import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/backup_service.dart';
import 'package:file_saver/file_saver.dart';
import 'package:dio/dio.dart';
import '../../../utils/snackbar_helper.dart';


class BusinessBackupPage extends StatefulWidget {
  final int businessId;
  const BusinessBackupPage({super.key, required this.businessId});

  @override
  State<BusinessBackupPage> createState() => _BusinessBackupPageState();
}

class _BusinessBackupPageState extends State<BusinessBackupPage> {
  final BackupService _service = BackupService();
  bool _loading = true;
  bool _creating = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  String? _currentJobId;
  int _jobProgress = 0;
  String? _jobMessage;
  bool _jobRunning = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.listBackups(widget.businessId);
      setState(() {
        _items = items;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _createBackup() async {
    setState(() {
      _creating = true;
    });
    if (!context.mounted) return;
    final ctx = context;
    try {
      final jobId = await _service.startBackupAsync(widget.businessId);
      if (!ctx.mounted) return;
      _startJob(jobId, AppLocalizations.of(ctx).inProgress);
      _startPollingJob();
      if (ctx.mounted) {
        _showSnackBar(AppLocalizations.of(ctx).inProgress);
      }
    } catch (e) {
      if (e is DioException) {
        await _handleBackupError(e);
      } else {
        _showSnackBar('$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _creating = false;
        });
      }
    }
  }

  void _startPollingJob() {
    _pollTimer?.cancel();
    if (_currentJobId == null || _currentJobId!.isEmpty) return;
    if (!context.mounted) return;
    final ctx = context;
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final st = await _service.getJobStatus(_currentJobId!);
        if (!ctx.mounted) return;
        setState(() {
          _jobProgress = (st['progress'] as int?) ?? _jobProgress;
          final rawMessage = (st['message'] as String?) ?? _jobMessage;
          _jobMessage = _translateJobMessage(rawMessage);
        });
        final state = (st['state'] as String?) ?? '';
        if (state == 'succeeded') {
          timer.cancel();
          setState(() {
            _jobRunning = false;
          });
          await _load();
          if (ctx.mounted) {
            _showSnackBar(AppLocalizations.of(ctx).operationSuccessful);
          }
        } else if (state == 'failed') {
          timer.cancel();
          setState(() {
            _jobRunning = false;
          });
          if (!ctx.mounted) return;
          final err = (st['error'] as String?) ?? AppLocalizations.of(ctx).error;
          // بررسی اینکه آیا خطا مربوط به فضای ذخیره‌سازی است
          final errorData = st['error_data'];
          if (errorData is Map) {
            final errorCode = errorData['error'] as String?;
            if (errorCode == 'STORAGE_LIMIT_EXCEEDED' || errorCode == 'NO_ACTIVE_STORAGE_PLAN') {
              await _showStorageLimitDialog(Map<String, dynamic>.from(errorData));
              return;
            }
          }
          _showSnackBar(err);
        }
      } catch (_) {}
    });
  }

  Future<void> _download(String id, String filename) async {
    try {
      final bytes = await _service.downloadBackup(widget.businessId, id);
      await FileSaver.instance.saveFile(
        name: filename,
        bytes: bytes,
        ext: 'hbx',
        mimeType: MimeType.other,
      );
    } catch (e) {
      _showSnackBar('$e');
    }
  }

  Future<void> _delete(String id) async {
    final t = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.delete),
        content: Text(t.deleteConfirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.dialogClose)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.delete)),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _service.deleteBackup(widget.businessId, id);
      await _load();
    } catch (e) {
      _showSnackBar('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.dataBackup),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/business/${widget.businessId}/dashboard');
            }
          },
        ),
      ),
      body: _buildBody(t),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: FilledButton.icon(
          onPressed: _creating || _jobRunning ? null : _createBackup,
          icon: _creating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.backup),
          label: Text(t.backup),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startJob(String jobId, String message) {
    setState(() {
      _currentJobId = jobId;
      _jobRunning = true;
      _jobProgress = 0;
      _jobMessage = message;
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    SnackBarHelper.show(context, message: message);
  }

  Widget _buildBody(AppLocalizations t) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          Text(t.dataBackupDescription, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (_jobRunning || _jobMessage != null) _buildJobStatusCard(t),
          if (_items.isEmpty)
            _buildEmptyState(t)
          else ..._items.map((it) => _buildBackupCard(t, it)).toList(),
        ],
      ),
    );
  }

  Widget _buildJobStatusCard(AppLocalizations t) {
    final theme = Theme.of(context);
    final isActive = _jobRunning;
    final colorScheme = theme.colorScheme;
    final message = _jobMessage ?? t.inProgress;
    return Card(
      color: isActive ? colorScheme.surfaceContainerHighest : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isActive ? Icons.sync : Icons.check_circle, color: isActive ? colorScheme.primary : colorScheme.secondary),
                const SizedBox(width: 12),
                Expanded(child: Text(message, style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _jobProgress > 0 ? _jobProgress / 100.0 : null),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.archive_outlined, size: 48),
            const SizedBox(height: 12),
            Text(t.noDataFound, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              t.dataBackupDialogContent,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupCard(AppLocalizations t, Map<String, dynamic> data) {
    final id = data['id'] as String? ?? '';
    final name = (data['filename'] as String?) ?? t.defaultBackupFilename;
    final size = (data['size'] as int?) ?? 0;
    final createdAt = (data['created_at'] as String?) ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.archive),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('$createdAt • ${_formatBytes(size)}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _download(id, name),
                  icon: const Icon(Icons.download),
                  label: Text(t.downloadTemplate),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _delete(id),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(t.delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    final t = AppLocalizations.of(context);
    if (bytes <= 0) {
      return '0 ${t.byteUnitB}';
    }
    final units = [t.byteUnitB, t.byteUnitKB, t.byteUnitMB, t.byteUnitGB, t.byteUnitTB];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(value < 10 && unitIndex > 0 ? 1 : 0)} ${units[unitIndex]}';
  }

  /// تبدیل پیام‌های job از انگلیسی به پیام‌های چندزبانه
  String? _translateJobMessage(String? message) {
    if (message == null || message.isEmpty) {
      return message;
    }
    final t = AppLocalizations.of(context);
    final lowerMessage = message.toLowerCase().trim();
    
    // تبدیل پیام‌های رایج
    if (lowerMessage == 'backup completed') {
      return t.backupCompleted;
    }
    if (lowerMessage == 'restore completed') {
      return t.restoreCompleted;
    }
    if (lowerMessage == 'backup failed') {
      return t.backupFailed;
    }
    if (lowerMessage == 'restore failed') {
      return t.restoreFailed;
    }
    if (lowerMessage == 'starting backup') {
      return t.jobStartingBackup;
    }
    if (lowerMessage == 'collecting data') {
      return t.jobCollectingData;
    }
    if (lowerMessage == 'packaging archive') {
      return t.jobPackagingArchive;
    }
    if (lowerMessage == 'saving file') {
      return t.jobSavingFile;
    }
    if (lowerMessage == 'finalizing') {
      return t.jobFinalizing;
    }
    if (lowerMessage == 'uploading file') {
      return t.jobUploadingFile;
    }
    if (lowerMessage == 'starting restore') {
      return t.jobStartingRestore;
    }
    if (lowerMessage == 'loading backup') {
      return t.jobLoadingBackup;
    }
    if (lowerMessage == 'creating new business') {
      return t.jobCreatingNewBusiness;
    }
    if (lowerMessage.startsWith('new business created')) {
      // استخراج ID از پیام (اگر وجود داشته باشد)
      final idMatch = RegExp(r'\(id:\s*(\d+)\)', caseSensitive: false).firstMatch(message);
      if (idMatch != null) {
        final id = idMatch.group(1);
        return '${t.jobNewBusinessCreated} (ID: $id)';
      }
      return t.jobNewBusinessCreated;
    }
    if (lowerMessage == 'cleaning current data') {
      return t.jobCleaningCurrentData;
    }
    if (lowerMessage == 'preparing to restore data') {
      return t.jobPreparingToRestoreData;
    }
    if (lowerMessage == 'updating business info') {
      return t.jobUpdatingBusinessInfo;
    }
    if (lowerMessage == 'preparing business data') {
      return t.jobPreparingBusinessData;
    }
    if (lowerMessage == 'restoring data') {
      return t.jobRestoringData;
    }
    
    // اگر پیام ترجمه نشده، همان پیام اصلی را برمی‌گردانیم
    return message;
  }

  Future<void> _handleBackupError(DioException e) async {
    final response = e.response;
    if (response != null && response.data is Map) {
      final data = response.data as Map<String, dynamic>;
      final error = data['error'] ?? data['detail'];
      
      if (error is Map) {
        final errorCode = error['error'] as String?;
        if (errorCode == 'STORAGE_LIMIT_EXCEEDED' || errorCode == 'NO_ACTIVE_STORAGE_PLAN') {
          await _showStorageLimitDialog(Map<String, dynamic>.from(error));
          return;
        }
      }
    }
    
    String errorMessage = 'خطا در ایجاد پشتیبان';
    if (response?.data is Map) {
      final data = response!.data as Map<String, dynamic>;
      if (data.containsKey('message')) {
        errorMessage = data['message'] as String;
      } else if (data.containsKey('error')) {
        final errorMap = data['error'];
        if (errorMap is Map && errorMap.containsKey('message')) {
          errorMessage = errorMap['message'] as String;
        } else if (errorMap is String) {
          errorMessage = errorMap;
        }
      } else if (data.containsKey('detail')) {
        final detail = data['detail'];
        if (detail is Map && detail.containsKey('message')) {
          errorMessage = detail['message'] as String;
        } else if (detail is String) {
          errorMessage = detail;
        }
      }
    }
    
    _showSnackBar(errorMessage);
  }

  Future<void> _showStorageLimitDialog(Map<String, dynamic> error) async {
    final errorCode = error['error'] as String?;
    final totalLimit = (error['total_limit_gb'] as num?)?.toDouble() ?? 0.0;
    final currentUsage = (error['current_usage_gb'] as num?)?.toDouble() ?? 0.0;
    final available = (error['available_gb'] as num?)?.toDouble() ?? 0.0;
    final overUsage = (error['over_usage_gb'] as num?)?.toDouble() ?? 0.0;
    final required = (error['required_gb'] as num?)?.toDouble() ?? 0.0;
    
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final isNoPlan = errorCode == 'NO_ACTIVE_STORAGE_PLAN';
    
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isNoPlan ? Icons.info_outline : Icons.warning_amber_rounded,
              color: isNoPlan ? Colors.blue : Colors.orange,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isNoPlan ? 'پکیج ذخیره‌سازی فعال نیست' : 'محدودیت ذخیره‌سازی',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error['message'] as String? ?? 
                (isNoPlan 
                  ? 'هیچ پکیج ذخیره‌سازی فعالی برای این کسب‌وکار وجود ندارد. لطفاً ابتدا یک پکیج ذخیره‌سازی فعال کنید.'
                  : 'حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند'),
                style: theme.textTheme.bodyLarge,
              ),
              if (!isNoPlan) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStorageInfoRow('محدودیت کل:', '${totalLimit.toStringAsFixed(3)} GB', theme),
                      _buildStorageInfoRow('استفاده شده:', '${currentUsage.toStringAsFixed(3)} GB', theme),
                      _buildStorageInfoRow('موجود:', '${available.toStringAsFixed(3)} GB', theme),
                      const Divider(height: 24),
                      _buildStorageInfoRow('حجم مورد نیاز:', '${required.toStringAsFixed(3)} GB', theme, isHighlight: true),
                      _buildStorageInfoRow('حجم اضافی:', '${overUsage.toStringAsFixed(3)} GB', theme, isHighlight: true, isError: true),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'برای ایجاد پشتیبان، لطفاً پلن ذخیره‌سازی خود را ارتقا دهید.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.dialogClose),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              // رفتن به صفحه مدیریت پلن‌های ذخیره‌سازی
              context.go('/business/${widget.businessId}/storage-files');
            },
            icon: const Icon(Icons.storage_outlined),
            label: const Text('مشاهده پلن‌ها'),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageInfoRow(String label, String value, ThemeData theme, {bool isHighlight = false, bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
              color: isError 
                  ? Colors.red 
                  : isHighlight 
                      ? theme.colorScheme.primary 
                      : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}


