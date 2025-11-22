import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/backup_service.dart';
import 'package:hesabix_ui/services/errors/api_error.dart';

enum _RestoreSource { stored, file }

class BusinessRestorePage extends StatefulWidget {
  final int businessId;
  const BusinessRestorePage({super.key, required this.businessId});

  @override
  State<BusinessRestorePage> createState() => _BusinessRestorePageState();
}

class _BusinessRestorePageState extends State<BusinessRestorePage> {
  final BackupService _service = BackupService();
  bool _loading = true;
  String? _error;
  String? _selectedBackupId;
  List<Map<String, dynamic>> _items = const [];
  bool _restoring = false;
  String _mode = 'new_business';
  String? _currentJobId;
  int _jobProgress = 0;
  String? _jobMessage;
  bool _jobRunning = false;
  Timer? _pollTimer;
  String? _selectedFilePath;
  String? _selectedFileName;
  Uint8List? _selectedFileBytes;
  _RestoreSource _source = _RestoreSource.stored;

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
    } on DioException catch (e) {
      final errorMessage = _extractErrorMessage(e);
      setState(() {
        _error = errorMessage;
      });
    } catch (e) {
      setState(() {
        _error = _getUserFriendlyError('$e');
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _restore() async {
    final t = AppLocalizations.of(context);
    
    // نمایش دیالوگ تایید
    final confirmed = await _showConfirmDialog();
    if (confirmed != true) {
      return;
    }
    
    if (!_canSubmit) {
      _showSnackBar(t.error);
      return;
    }
    
    setState(() {
      _restoring = true;
    });
    try {
      late final String jobId;
      if (_source == _RestoreSource.file && (_selectedFilePath != null || _selectedFileBytes != null)) {
        jobId = await _service.startRestoreFromFileAsync(
          widget.businessId,
          filePath: _selectedFilePath,
          fileBytes: _selectedFileBytes,
          filename: _selectedFileName,
          mode: _mode,
        );
        _startJob(jobId, t.inProgress);
      } else if (_selectedBackupId != null) {
        jobId = await _service.startRestoreAsync(
          widget.businessId,
          _selectedBackupId!,
          mode: _mode,
        );
        _startJob(jobId, t.inProgress);
      } else {
        throw Exception(t.error);
      }
      _startPollingJob();
      _showSnackBar(t.inProgress);
    } on DioException catch (e) {
      final errorMessage = _extractErrorMessage(e);
      _showSnackBar(errorMessage);
    } catch (e) {
      final errorMessage = _getUserFriendlyError('$e');
      _showSnackBar(errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _restoring = false;
        });
      }
    }
  }

  Future<bool?> _showConfirmDialog() async {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    String title;
    String message;
    Color? iconColor;
    IconData icon;
    
    if (_mode == 'replace') {
      title = t.restoreConfirmReplace;
      message = t.restoreConfirmReplaceMessage;
      iconColor = colorScheme.error;
      icon = Icons.warning_amber_rounded;
    } else {
      title = t.restoreConfirmNewBusiness;
      message = t.restoreConfirmNewBusinessMessage;
      iconColor = colorScheme.primary;
      icon = Icons.info_outline;
    }
    
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(icon, color: iconColor, size: 48),
        title: Text(title, style: theme.textTheme.titleLarge),
        content: SingleChildScrollView(
          child: Text(message, style: theme.textTheme.bodyMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.dialogClose),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: _mode == 'replace' 
              ? FilledButton.styleFrom(backgroundColor: colorScheme.error)
              : null,
            child: Text(t.restore),
          ),
        ],
      ),
    );
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
          if (!ctx.mounted) return;
          _showSnackBar(AppLocalizations.of(ctx).operationSuccessful);
        } else if (state == 'failed') {
          timer.cancel();
          setState(() {
            _jobRunning = false;
          });
          if (!ctx.mounted) return;
          final err = (st['error'] as String?) ?? AppLocalizations.of(ctx).error;
          final errorMessage = _parseJobError(err);
          _showSnackBar(errorMessage);
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.dataRestore),
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
          onPressed: _restoring || !_canSubmit || _jobRunning ? null : _restore,
          icon: _restoring ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.restore),
          label: Text(t.restore),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  bool get _canSubmit {
    if (_jobRunning) return false;
    if (_source == _RestoreSource.file) {
      return (_selectedFilePath != null && _selectedFilePath!.isNotEmpty) || 
             (_selectedFileBytes != null && _selectedFileBytes!.isNotEmpty);
    }
    return _selectedBackupId != null && _selectedBackupId!.isNotEmpty;
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
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildBody(AppLocalizations t) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(t.retry),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          // وضعیت job
          if (_jobRunning || _jobMessage != null) ...[
            _buildJobStatusCard(t),
            const SizedBox(height: 16),
          ],
          
          // انتخاب منبع
          _buildSourceSelector(t),
          const SizedBox(height: 16),
          
          // انتخاب فایل یا بکاپ ذخیره شده
          if (_source == _RestoreSource.stored) 
            _buildStoredBackupsCard(t) 
          else 
            _buildFilePickerCard(t),
          const SizedBox(height: 16),
          
          // انتخاب حالت بازیابی
          _buildModeSelectorCard(t),
          const SizedBox(height: 16),
          
          // نکات امنیتی
          _buildSecurityNotesCard(t),
        ],
      ),
    );
  }

  Widget _buildSecurityNotesCard(AppLocalizations t) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  t.restoreSecurityNote,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildSecurityNoteItem(t.restoreSecurityNote1, Icons.backup),
            _buildSecurityNoteItem(t.restoreSecurityNote2, Icons.verified),
            _buildSecurityNoteItem(t.restoreSecurityNote3, Icons.timer),
            _buildSecurityNoteItem(t.restoreSecurityNote4, Icons.support_agent),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityNoteItem(String text, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobStatusCard(AppLocalizations t) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final message = _jobMessage ?? t.inProgress;
    return Card(
      color: colorScheme.surfaceContainerHighest,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _jobRunning ? Icons.sync : Icons.check_circle,
                  color: _jobRunning ? colorScheme.primary : colorScheme.secondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _jobProgress > 0 ? _jobProgress / 100.0 : null,
              minHeight: 6,
            ),
            if (_jobProgress > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${_jobProgress}%',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.end,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSourceSelector(AppLocalizations t) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.restoreSourceTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<_RestoreSource>(
              segments: [
                ButtonSegment<_RestoreSource>(
                  value: _RestoreSource.stored,
                  label: Text(t.dataBackup),
                  icon: const Icon(Icons.cloud),
                ),
                ButtonSegment<_RestoreSource>(
                  value: _RestoreSource.file,
                  label: Text(t.restoreFile),
                  icon: const Icon(Icons.upload_file),
                ),
              ],
              selected: {_source},
              onSelectionChanged: _jobRunning
                  ? null
                  : (value) {
                      if (value.isEmpty) return;
                      setState(() {
                        _source = value.first;
                        _selectedBackupId = null;
                        _selectedFilePath = null;
                        _selectedFileName = null;
                        _selectedFileBytes = null;
                      });
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoredBackupsCard(AppLocalizations t) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedBackupId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: t.dataBackup,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.backup),
              ),
              items: _items
                  .map(
                    (e) => DropdownMenuItem<String>(
                      value: e['id'] as String,
                      child: Text(
                        (e['filename'] as String?) ?? AppLocalizations.of(context).defaultBackupFilename,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _jobRunning
                  ? null
                  : (v) {
                      setState(() {
                        _selectedBackupId = v;
                        _selectedFilePath = null;
                        _selectedFileName = null;
                        _selectedFileBytes = null;
                      });
                    },
            ),
            if (_items.isEmpty) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  t.noDataFound,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilePickerCard(AppLocalizations t) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: Text(_selectedFileName ?? t.selectBackupFile),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: _jobRunning
                  ? null
                  : () async {
                      try {
                        final res = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: const ['hbx', 'zip'],
                          withData: true,
                        );
                        if (res != null && res.files.isNotEmpty) {
                          final f = res.files.first;
                          setState(() {
                            _selectedFilePath = f.path;
                            _selectedFileName = f.name;
                            _selectedFileBytes = f.bytes;
                            _selectedBackupId = null;
                            _source = _RestoreSource.file;
                          });
                        }
                      } on DioException catch (e) {
                        final errorMessage = _extractErrorMessage(e);
                        _showSnackBar(errorMessage);
                      } catch (e) {
                        final errorMessage = _getUserFriendlyError('$e');
                        _showSnackBar(errorMessage);
                      }
                    },
            ),
            if (_selectedFileName != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.insert_drive_file,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedFileName!,
                        style: Theme.of(context).textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: t.clear,
                      onPressed: _jobRunning
                          ? null
                          : () {
                              setState(() {
                                _selectedFilePath = null;
                                _selectedFileName = null;
                                _selectedFileBytes = null;
                              });
                            },
                      icon: const Icon(Icons.clear),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelectorCard(AppLocalizations t) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.restoreModeTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            RadioListTile<String>(
              value: 'new_business',
              groupValue: _mode,
              onChanged: _jobRunning
                  ? null
                  : (v) => setState(() => _mode = v ?? 'new_business'),
              title: Text(
                t.restoreModeNewBusiness,
                style: theme.textTheme.bodyLarge,
              ),
              subtitle: Text(
                t.restoreWarningNewBusiness,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              activeColor: colorScheme.primary,
            ),
            const Divider(),
            RadioListTile<String>(
              value: 'replace',
              groupValue: _mode,
              onChanged: _jobRunning
                  ? null
                  : (v) => setState(() => _mode = v ?? 'replace'),
              title: Text(
                t.restoreModeReplace,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                t.restoreWarningReplace,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              ),
              activeColor: colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }

  /// استخراج پیام خطا از DioException
  String _extractErrorMessage(DioException e) {
    final t = AppLocalizations.of(context);
    if (e.error is ApiErrorDetails) {
      final apiError = e.error as ApiErrorDetails;
      return apiError.message ?? t.errorUnknown;
    }
    
    if (e.response != null) {
      final data = e.response!.data;
      if (data is Map<String, dynamic>) {
        if (data['error'] is Map<String, dynamic>) {
          final errorObj = data['error'];
          final message = errorObj['message'] as String?;
          if (message != null && message.isNotEmpty) {
            return message;
          }
        }
        final message = data['message'] as String?;
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
    }
    
    if (e.type == DioExceptionType.connectionTimeout) {
      return t.errorConnectionTimeout;
    } else if (e.type == DioExceptionType.receiveTimeout) {
      return t.errorReceiveTimeout;
    } else if (e.type == DioExceptionType.connectionError) {
      return t.errorConnectionError;
    } else if (e.type == DioExceptionType.sendTimeout) {
      return t.errorSendTimeout;
    }
    
    return _getUserFriendlyError(e.message ?? t.errorUnknownServer);
  }

  /// تبدیل پیام‌های خطای فنی به پیام‌های قابل فهم برای کاربر
  String _getUserFriendlyError(String error) {
    final t = AppLocalizations.of(context);
    final lowerError = error.toLowerCase();
    
    if (lowerError.contains('network') || lowerError.contains('connection')) {
      return t.errorConnectionError;
    }
    if (lowerError.contains('timeout')) {
      return t.errorRequestTimeout;
    }
    if (lowerError.contains('invalid_input') || lowerError.contains('validation')) {
      return t.errorInvalidInput;
    }
    if (lowerError.contains('not_found')) {
      return t.errorBackupNotFound;
    }
    if (lowerError.contains('business_mismatch')) {
      return t.errorBusinessMismatch;
    }
    if (lowerError.contains('not_supported')) {
      return t.errorNotSupported;
    }
    if (lowerError.contains('rate_limit')) {
      return t.errorRateLimit;
    }
    if (lowerError.contains('invalid_backup')) {
      return t.errorInvalidBackup;
    }
    if (lowerError.contains('business_creation_failed')) {
      return t.errorBusinessCreationFailed;
    }
    
    final httpCodeMatch = RegExp(r'\d{3}:\s*').firstMatch(error);
    if (httpCodeMatch != null) {
      return error.substring(httpCodeMatch.end).trim();
    }
    
    return error;
  }

  /// پارس کردن خطای job و تبدیل به پیام قابل فهم
  String _parseJobError(String? error) {
    final t = AppLocalizations.of(context);
    if (error == null || error.isEmpty) {
      return t.errorRestoreFailed;
    }
    
    final httpCodeMatch = RegExp(r'(\d{3}):\s*(.+)').firstMatch(error);
    if (httpCodeMatch != null) {
      final jsonStr = httpCodeMatch.group(2);
      if (jsonStr != null) {
        try {
          final jsonMatch = RegExp(r"\{.*\}").firstMatch(jsonStr);
          if (jsonMatch != null) {
            // در اینجا می‌توانیم JSON را parse کنیم اگر نیاز باشد
          }
        } catch (_) {
          // ignore
        }
      }
    }
    
    return _getUserFriendlyError(error);
  }

  /// تبدیل پیام‌های job از انگلیسی به پیام‌های چندزبانه
  String? _translateJobMessage(String? message) {
    if (message == null || message.isEmpty) {
      return message;
    }
    final t = AppLocalizations.of(context);
    final lowerMessage = message.toLowerCase().trim();
    
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
    
    return message;
  }
}
