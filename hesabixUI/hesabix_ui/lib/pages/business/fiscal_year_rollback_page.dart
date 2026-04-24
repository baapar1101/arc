import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/widgets/business_subpage_back_leading.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/fiscal_year_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/backup_service.dart';
import 'package:hesabix_ui/services/business_ftp_backup_service.dart';
import 'package:hesabix_ui/services/fiscal_year_rollback_service.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

/// حذف سال مالی جاری و بازگشت به سال قبل (عملیات خطرناک).
class FiscalYearRollbackPage extends StatefulWidget {
  final int businessId;

  const FiscalYearRollbackPage({super.key, required this.businessId});

  @override
  State<FiscalYearRollbackPage> createState() => _FiscalYearRollbackPageState();
}

class _FiscalYearRollbackPageState extends State<FiscalYearRollbackPage> {
  late final ApiClient _api;
  late final FiscalYearRollbackService _service;
  late final BackupService _backupService;
  late final BusinessFtpBackupService _ftpService;

  bool _loading = true;
  bool _executing = false;
  String? _error;
  Map<String, dynamic>? _preview;

  /// پیشنهاد: قبل از حذف سال، پشتیبان سیستمی بگیرد.
  bool _backupBeforeRollback = true;
  bool _uploadBackupToFtp = false;
  bool? _ftpConfigured;

  String? _phaseMessage;
  int _backupProgress = 0;

  @override
  void initState() {
    super.initState();
    _api = ApiClient();
    _service = FiscalYearRollbackService(_api);
    _backupService = BackupService(apiClient: _api);
    _ftpService = BusinessFtpBackupService(apiClient: _api);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  bool _canFtpAfterBackup() {
    final store = ApiClient.getAuthStore();
    if (store?.currentBusiness?.id != widget.businessId) return false;
    if (store!.currentBusiness?.isOwner == true) return true;
    return store.hasBusinessPermission('settings', 'manage_ftp');
  }

  Future<void> _loadFtpConfigured() async {
    if (!_canFtpAfterBackup()) {
      if (mounted) setState(() => _ftpConfigured = null);
      return;
    }
    try {
      final ftp = await _ftpService.getSettings(widget.businessId);
      if (mounted) setState(() => _ftpConfigured = ftp['configured'] == true);
    } catch (_) {
      if (mounted) setState(() => _ftpConfigured = false);
    }
  }

  Future<void> _load() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await _service.preview(widget.businessId, l10n);
      if (mounted) {
        setState(() {
          _preview = p;
          _loading = false;
        });
        await _loadFtpConfigured();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = FiscalYearRollbackService.formatError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _execute() async {
    final t = AppLocalizations.of(context);
    final tokenInitial = _preview?['confirmation_token'] as String?;
    if (tokenInitial == null || tokenInitial.isEmpty) {
      SnackBarHelper.showError(
        context,
        message: t.fiscalYearRollbackTokenMissing,
      );
      return;
    }

    if (_backupBeforeRollback &&
        _uploadBackupToFtp &&
        _canFtpAfterBackup() &&
        _ftpConfigured != true) {
      SnackBarHelper.showError(context, message: t.backupFtpNotConfiguredError);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final d = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(d.fiscalYearRollbackConfirmTitle),
          content: Text(
            _backupBeforeRollback
                ? d.fiscalYearRollbackConfirmWithBackupBody
                : d.fiscalYearRollbackConfirmWithoutBackupBody,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(d.fiscalYearRollbackCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: Text(d.fiscalYearRollbackConfirmDelete),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;

    setState(() {
      _executing = true;
      _phaseMessage = null;
      _backupProgress = 0;
    });

    try {
      String? token = tokenInitial;

      if (_backupBeforeRollback) {
        if (!mounted) return;
        final l10n = AppLocalizations.of(context);
        setState(() {
          _phaseMessage = l10n.fiscalYearRollbackPhaseBackupStarting;
          _backupProgress = 0;
        });
        final doFtp = _uploadBackupToFtp && _canFtpAfterBackup() && (_ftpConfigured == true);
        final String jobId;
        try {
          jobId = await _backupService.startBackupAsync(
            widget.businessId,
            uploadToFtp: doFtp,
          );
        } on DioException catch (e) {
          final msg = FiscalYearRollbackService.extractApiErrorMessage(e, l10n) ?? e.message;
          throw Exception(msg ?? l10n.fiscalYearRollbackBackupStartFailed);
        }
        if (jobId.isEmpty) {
          throw Exception(l10n.fiscalYearRollbackBackupJobIdMissing);
        }
        await _backupService.waitForJobUntilDone(
          jobId,
          l10n,
          onProgress: (p, msg) {
            if (!mounted) return;
            setState(() {
              _backupProgress = p;
              if (msg != null && msg.isNotEmpty) {
                _phaseMessage = l10n.fiscalYearRollbackBackupProgressPrefix(msg);
              }
            });
          },
        );

        if (!mounted) return;
        setState(() {
          _phaseMessage = l10n.fiscalYearRollbackPhasePreviewRefresh;
          _backupProgress = 0;
        });
        final p = await _service.preview(widget.businessId, AppLocalizations.of(context));
        if (p['can_execute'] != true) {
          throw Exception(l10n.fiscalYearRollbackAfterBackupBlocked);
        }
        token = p['confirmation_token'] as String?;
      }

      if (token == null || token.isEmpty) {
        throw Exception(
          _backupBeforeRollback
              ? t.fiscalYearRollbackTokenAfterBackupMissing
              : t.fiscalYearRollbackTokenMissingGeneric,
        );
      }

      if (!mounted) return;
      setState(() => _phaseMessage = t.fiscalYearRollbackPhaseDeleting);

      final result = await _service.execute(widget.businessId, token, AppLocalizations.of(context));
      final newId = result['current_fiscal_year_id'];
      if (newId is int && mounted) {
        final c = await FiscalYearController.load(widget.businessId);
        await c.applyAfterYearClosed(newId);
      }
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: result['message']?.toString() ?? t.fiscalYearRollbackSuccessFallback,
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: FiscalYearRollbackService.formatError(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _executing = false;
          _phaseMessage = null;
          _backupProgress = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cur = _preview?['current_fiscal_year'] as Map?;
    final prev = _preview?['previous_fiscal_year'] as Map?;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.fiscalYearRollbackTitle),
        leading: businessSubpageBackLeading(context, widget.businessId),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: Text(t.fiscalYearRollbackRetry)),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        color: Colors.orange.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(t.fiscalYearRollbackWarningCard),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_preview != null) ...[
                        Text(t.fiscalYearRollbackCurrentYearLabel, style: theme.textTheme.titleSmall),
                        Text(
                          '${cur?['title'] ?? ''} (${t.fiscalYearRollbackYearIdSuffix('${cur?['id'] ?? ''}')})',
                        ),
                        const SizedBox(height: 12),
                        Text(t.fiscalYearRollbackNextCurrentLabel, style: theme.textTheme.titleSmall),
                        Text(
                          '${prev?['title'] ?? ''} (${t.fiscalYearRollbackYearIdSuffix('${prev?['id'] ?? ''}')})',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t.fiscalYearRollbackDocCountLabel(
                            '${_preview!['documents_in_current_year_count']}',
                          ),
                        ),
                        if ((_preview!['closing_documents_on_previous_year_ids'] as List?)?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              t.fiscalYearRollbackClosingDocsToDelete(
                                '${(_preview!['closing_documents_on_previous_year_ids'] as List).length}',
                              ),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                      if (_preview?['can_execute'] == true) ...[
                        const SizedBox(height: 20),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                CheckboxListTile(
                                  value: _backupBeforeRollback,
                                  onChanged: _executing
                                      ? null
                                      : (v) => setState(() {
                                            _backupBeforeRollback = v ?? true;
                                            if (!_backupBeforeRollback) {
                                              _uploadBackupToFtp = false;
                                            }
                                          }),
                                  title: Text(t.fiscalYearRollbackBackupCheckboxTitle),
                                  subtitle: Text(t.fiscalYearRollbackBackupCheckboxSubtitle),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                ),
                                if (_backupBeforeRollback) ...[
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(start: 12, end: 12, bottom: 8),
                                    child: TextButton.icon(
                                      onPressed: _executing
                                          ? null
                                          : () => context.go('/business/${widget.businessId}/settings/backup'),
                                      icon: const Icon(Icons.open_in_new, size: 18),
                                      label: Text(t.fiscalYearRollbackOpenBackupPage),
                                    ),
                                  ),
                                  if (_canFtpAfterBackup()) ...[
                                    CheckboxListTile(
                                      value: _uploadBackupToFtp,
                                      onChanged: _executing
                                          ? null
                                          : (v) => setState(() => _uploadBackupToFtp = v ?? false),
                                      title: Text(t.ftpSendAfterBackup),
                                      subtitle: Text(t.ftpSendAfterBackupSubtitle),
                                      controlAffinity: ListTileControlAffinity.leading,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                    ),
                                    Align(
                                      alignment: AlignmentDirectional.centerStart,
                                      child: Padding(
                                        padding: const EdgeInsetsDirectional.only(start: 12, bottom: 8),
                                        child: TextButton(
                                          onPressed: _executing
                                              ? null
                                              : () => context.go(
                                                    '/business/${widget.businessId}/settings/ftp-backup',
                                                  ),
                                          child: Text(t.backupOpenFtpSettings),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (_executing && _phaseMessage != null) ...[
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: _backupProgress > 0 ? _backupProgress / 100.0 : null,
                          ),
                          const SizedBox(height: 8),
                          Text(_phaseMessage!, style: theme.textTheme.bodySmall),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _executing ? null : _execute,
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                          child: _executing
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(t.fiscalYearRollbackExecuteButton),
                        ),
                      ] else ...[
                        const SizedBox(height: 24),
                        Text(
                          t.fiscalYearRollbackBlockedTitle,
                          style: theme.textTheme.titleSmall?.copyWith(color: Colors.red.shade900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.fiscalYearRollbackBlockedHint,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        ...(((_preview?['block_reasons'] as List?) ?? const [])
                            .map((r) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('• '),
                                      Expanded(child: Text('$r')),
                                    ],
                                  ),
                                ))),
                        const SizedBox(height: 16),
                        OutlinedButton(onPressed: _load, child: Text(t.fiscalYearRollbackRefreshPreview)),
                      ],
                    ],
                  ),
                ),
    );
  }
}
