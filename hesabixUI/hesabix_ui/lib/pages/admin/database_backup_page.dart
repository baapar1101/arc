import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/admin_system_settings_service.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;

class DatabaseBackupPage extends StatefulWidget {
  const DatabaseBackupPage({super.key});

  @override
  State<DatabaseBackupPage> createState() => _DatabaseBackupPageState();
}

class _DatabaseBackupPageState extends State<DatabaseBackupPage> {
  final _service = AdminSystemSettingsService(ApiClient());
  final _emailController = TextEditingController();
  final _restoreConfirmationController = TextEditingController();

  bool _isLoading = false;
  String? _loadingAction;
  List<Map<String, dynamic>> _ftpConfigs = [];
  bool _loadingFtpConfigs = false;
  String? _selectedFtpConfigId;
  bool _compress = true;

  // Restore
  List<int>? _restoreFileBytes;
  String? _restoreFilename;
  String? _restoreJobId;
  Map<String, dynamic>? _restoreJobStatus;
  Timer? _restoreJobTimer;

  @override
  void initState() {
    super.initState();
    _loadFtpConfigs();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _restoreConfirmationController.dispose();
    _restoreJobTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFtpConfigs() async {
    setState(() {
      _loadingFtpConfigs = true;
    });
    try {
      final api = ApiClient();
      final response = await api.get('/api/v1/admin/files/storage-configs/');
      if (response.data != null &&
          response.data['success'] == true &&
          response.data['data'] != null) {
        final configs = (response.data['data']['configs'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        setState(() {
          _ftpConfigs = configs
              .where((c) => (c['storage_type'] as String?)?.toLowerCase() == 'ftp')
              .toList();
          if (_ftpConfigs.isNotEmpty && _selectedFtpConfigId == null) {
            _selectedFtpConfigId = _ftpConfigs.first['id'] as String?;
          }
        });
      }
    } catch (_) {
      setState(() => _ftpConfigs = []);
    } finally {
      if (mounted) {
        setState(() => _loadingFtpConfigs = false);
      }
    }
  }

  Future<void> _downloadBackup() async {
    setState(() {
      _isLoading = true;
      _loadingAction = 'download';
    });
    try {
      final bytes = await _service.createDatabaseBackupDownload(compress: _compress);
      final ext = _compress ? 'sql.gz' : 'sql';
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final filename = 'hesabix_db_backup_$ts.$ext';
      await web_utils.saveBytesAsFileWeb(
        bytes,
        filename,
        mimeType: 'application/octet-stream',
      );
      if (mounted) {
        SnackBarHelper.showSuccess(
          context,
          message: 'بکاپ با موفقیت دانلود شد',
        );
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.extractErrorMessage(e, t),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingAction = null;
        });
      }
    }
  }

  Future<void> _sendToEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      SnackBarHelper.showError(context, message: 'آدرس ایمیل را وارد کنید');
      return;
    }
    setState(() {
      _isLoading = true;
      _loadingAction = 'email';
    });
    try {
      await _service.createDatabaseBackupEmail(email: email, compress: _compress);
      if (mounted) {
        SnackBarHelper.showSuccess(
          context,
          message: 'بکاپ به ایمیل $email ارسال شد',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: 'خطا در ارسال: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingAction = null;
        });
      }
    }
  }

  Future<void> _pickRestoreFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sql', 'gz'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final f = result.files.first;
      final bytes = f.bytes;
      final name = f.name;
      if (bytes != null && bytes.isNotEmpty && name != null) {
        final lower = name.toLowerCase();
        if (lower.endsWith('.sql') || lower.endsWith('.sql.gz') || lower.endsWith('.gz')) {
          setState(() {
            _restoreFileBytes = bytes;
            _restoreFilename = name;
            _restoreJobId = null;
            _restoreJobStatus = null;
          });
        } else {
          if (mounted) {
            SnackBarHelper.showError(context, message: 'فرمت فایل باید .sql یا .sql.gz باشد');
          }
        }
      } else {
        if (mounted) {
          SnackBarHelper.showError(context, message: 'خواندن فایل ناموفق بود');
        }
      }
    }
  }

  void _pollRestoreJob() {
    if (_restoreJobId == null) return;
    _service.getJobStatus(_restoreJobId!).then((status) {
      if (!mounted) return;
      setState(() => _restoreJobStatus = status);
      final state = status['state'] as String?;
      if (state == 'succeeded' || state == 'failed') {
        _restoreJobTimer?.cancel();
        _restoreJobTimer = null;
        if (state == 'succeeded') {
          SnackBarHelper.showSuccess(context, message: 'ریستور با موفقیت انجام شد');
        } else {
          final err = status['error'] as String? ?? 'خطای نامشخص';
          SnackBarHelper.showError(context, message: 'ریستور ناموفق: $err');
        }
      }
    }).catchError((_) {
      if (mounted) _restoreJobTimer?.cancel();
    });
  }

  Future<void> _startRestore() async {
    final bytes = _restoreFileBytes;
    final filename = _restoreFilename;
    final confirmation = _restoreConfirmationController.text.trim();
    if (bytes == null || bytes.isEmpty || filename == null || filename.isEmpty) {
      SnackBarHelper.showError(context, message: 'ابتدا فایل بکاپ را انتخاب کنید');
      return;
    }
    if (confirmation != 'بازیابی' && confirmation != 'RESTORE') {
      SnackBarHelper.showError(
        context,
        message: 'برای تأیید عبارت "بازیابی" یا "RESTORE" را وارد کنید',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingAction = 'restore';
    });
    try {
      final jobId = await _service.startDatabaseRestore(
        fileBytes: bytes,
        filename: filename,
        confirmation: confirmation,
      );
      if (mounted) {
        setState(() {
          _restoreJobId = jobId;
          _restoreJobStatus = {'state': 'queued', 'message': 'در صف...'};
          _restoreJobTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollRestoreJob());
        });
        _pollRestoreJob();
        SnackBarHelper.showSuccess(context, message: 'ریستور در پس‌زمینه شروع شد');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در شروع ریستور: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingAction = null;
        });
      }
    }
  }

  Future<void> _sendToFtp() async {
    final configId = _selectedFtpConfigId;
    if (configId == null || configId.isEmpty) {
      SnackBarHelper.showError(context, message: 'یک سرور FTP انتخاب کنید');
      return;
    }
    setState(() {
      _isLoading = true;
      _loadingAction = 'ftp';
    });
    try {
      await _service.createDatabaseBackupFtp(
        storageConfigId: configId,
        compress: _compress,
      );
      if (mounted) {
        SnackBarHelper.showSuccess(
          context,
          message: 'بکاپ با موفقیت به FTP آپلود شد',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: 'خطا در آپلود FTP: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingAction = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('بکاپ دیتابیس'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoCard(theme),
              const SizedBox(height: 24),
              _buildOptionsCard(theme),
              const SizedBox(height: 24),
              _buildDownloadSection(theme),
              const SizedBox(height: 16),
              _buildEmailSection(theme),
              const SizedBox(height: 16),
              _buildFtpSection(theme),
              const SizedBox(height: 16),
              _buildRestoreSection(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.1),
              theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.storage, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'بکاپ کامل دیتابیس',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'از کل دیتابیس PostgreSQL نسخه پشتیبان تهیه کنید و آن را دانلود کنید، '
                    'به ایمیل بفرستید یا روی سرور FTP آپلود کنید.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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

  Widget _buildOptionsCard(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'تنظیمات',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _compress,
              onChanged: (v) => setState(() => _compress = v),
              title: const Text('فشرده‌سازی (gzip)'),
              subtitle: const Text('کاهش حجم فایل بکاپ'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadSection(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.download, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'دانلود مستقیم',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'فایل بکاپ مستقیماً در دستگاه شما ذخیره می‌شود.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _downloadBackup,
                icon: _loadingAction == 'download'
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.download),
                label: Text(_loadingAction == 'download' ? 'در حال ایجاد...' : 'دانلود بکاپ'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailSection(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.email_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'ارسال به ایمیل',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'بکاپ به آدرس ایمیل شما ارسال می‌شود. توجه: محدودیت حجم ایمیل معمولاً ۲۵–۵۰ مگابایت است.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: 'آدرس ایمیل',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _sendToEmail,
                icon: _loadingAction == 'email'
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(_loadingAction == 'email' ? 'در حال ارسال...' : 'ارسال به ایمیل'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFtpSection(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_upload_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'آپلود به FTP',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'بکاپ روی سرور FTP آپلود می‌شود. ابتدا در بخش ذخیره‌سازی یک پیکربندی FTP ایجاد کنید.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (_loadingFtpConfigs)
              const Center(child: CircularProgressIndicator())
            else if (_ftpConfigs.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'هیچ پیکربندی FTP یافت نشد. از بخش مدیریت ذخیره‌سازی یک پیکربندی FTP ایجاد کنید.',
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              DropdownButtonFormField<String>(
                value: _selectedFtpConfigId,
                decoration: InputDecoration(
                  labelText: 'سرور FTP',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: _ftpConfigs
                    .map((c) => DropdownMenuItem<String>(
                          value: c['id'] as String,
                          child: Text(c['name'] as String? ?? 'FTP'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedFtpConfigId = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _sendToFtp,
                  icon: _loadingAction == 'ftp'
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.cloud_upload),
                  label: Text(_loadingAction == 'ftp' ? 'در حال آپلود...' : 'آپلود به FTP'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRestoreSection(ThemeData theme) {
    final jobStatus = _restoreJobStatus;
    final state = jobStatus?['state'] as String?;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.restore, color: theme.colorScheme.error),
                const SizedBox(width: 12),
                Text(
                  'ریستور دیتابیس',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '⚠️ هشدار: ریستور کل داده‌های فعلی را حذف کرده و با محتوای فایل بکاپ جایگزین می‌کند. این عمل غیرقابل بازگشت است.',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _pickRestoreFile,
              icon: const Icon(Icons.upload_file),
              label: Text(_restoreFilename ?? 'انتخاب فایل بکاپ (.sql یا .sql.gz)'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _restoreConfirmationController,
              decoration: InputDecoration(
                labelText: 'برای تأیید عبارت "بازیابی" را وارد کنید',
                hintText: 'بازیابی',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.warning_amber),
              ),
            ),
            const SizedBox(height: 12),
            if (jobStatus != null) ...[
              _buildJobStatusWidget(theme, state, jobStatus),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading || state == 'running' || state == 'queued' ? null : _startRestore,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _loadingAction == 'restore'
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.restore),
                label: Text(_loadingAction == 'restore' ? 'در حال ارسال...' : 'شروع ریستور'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobStatusWidget(ThemeData theme, String? state, Map<String, dynamic> jobStatus) {
    final meta = jobStatus['meta'] as Map<String, dynamic>?;
    final result = jobStatus['result'] as Map<String, dynamic>?;
    final message = (result?['message'] ?? meta?['message'] ?? jobStatus['message']) as String? ?? '';
    final progress = (meta?['progress'] ?? jobStatus['progress']) as num? ?? 0;
    final errVal = jobStatus['error'];
    final error = errVal is Map
        ? (errVal['message'] as String?) ?? errVal.toString()
        : errVal as String?;

    Color color = theme.colorScheme.primary;
    IconData icon = Icons.hourglass_empty;
    if (state == 'succeeded') {
      color = theme.colorScheme.primary;
      icon = Icons.check_circle;
    } else if (state == 'failed') {
      color = theme.colorScheme.error;
      icon = Icons.error;
    } else if (state == 'running' || state == 'queued') {
      color = theme.colorScheme.secondary;
      icon = Icons.sync;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                state == 'succeeded'
                    ? 'ریستور موفق'
                    : state == 'failed'
                        ? 'ریستور ناموفق'
                        : 'در حال ریستور...',
                style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(message, style: theme.textTheme.bodySmall),
          ],
          if (state == 'running' || state == 'queued') ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress > 0 ? progress / 100 : null),
          ],
          if (error != null && error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(error, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
