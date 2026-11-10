import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/admin_legacy_import_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'admin_compact_scaffold.dart';
import 'package:hesabix_ui/theme/tokens/extensions.dart';

class LegacyDatabaseImportPage extends StatefulWidget {
  const LegacyDatabaseImportPage({super.key});

  @override
  State<LegacyDatabaseImportPage> createState() => _LegacyDatabaseImportPageState();
}

class _LegacyDatabaseImportPageState extends State<LegacyDatabaseImportPage> {
  final _service = AdminLegacyImportService(ApiClient());
  final _targetBusinessIdController = TextEditingController();
  final _ownerUserIdController = TextEditingController();
  final _rewriteConfirmationController = TextEditingController();

  List<int>? _fileBytes;
  String? _filename;
  Map<String, dynamic>? _analysis;
  String? _jobId;
  Map<String, dynamic>? _jobStatus;
  Timer? _jobTimer;

  bool _loading = false;
  String? _loadingAction;

  String _importMode = 'new_business';
  bool _dryRun = true;
  bool _importUsers = true;
  bool _importMaster = true;
  bool _importInvoices = true;
  bool _importReceipts = true;
  bool _importExpenseIncome = true;
  bool _importWarehouses = true;
  bool _importTransfers = true;
  bool _importOpeningBalance = true;
  bool _importChecks = true;

  @override
  void dispose() {
    _targetBusinessIdController.dispose();
    _ownerUserIdController.dispose();
    _rewriteConfirmationController.dispose();
    _jobTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sql', 'gz', 'zip', 'hs60'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    final bytes = f.bytes;
    final name = f.name;
    if (bytes == null || bytes.isEmpty || name == null) {
      if (mounted) SnackBarHelper.showError(context, message: adminTx(context, 'خواندن فایل ناموفق بود', 'Could not read the file'));
      return;
    }
    final lower = name.toLowerCase();
    if (!lower.endsWith('.sql') &&
        !lower.endsWith('.sql.gz') &&
        !lower.endsWith('.gz') &&
        !lower.endsWith('.zip') &&
        !lower.endsWith('.hs60')) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: adminTx(context, 'فرمت فایل باید .sql، .sql.gz، .zip یا .hs60 باشد', 'File must be .sql, .sql.gz, .zip, or .hs60'),
        );
      }
      return;
    }
    setState(() {
      _fileBytes = bytes;
      _filename = name;
      _analysis = null;
      _jobId = null;
      _jobStatus = null;
    });
  }

  int? _parseOptionalInt(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  LegacyImportRunParams _buildParams({required bool dryRun}) {
    return LegacyImportRunParams(
      importMode: _importMode,
      targetBusinessId: _parseOptionalInt(_targetBusinessIdController.text),
      ownerUserId: _parseOptionalInt(_ownerUserIdController.text),
      dryRun: dryRun,
      importUsers: _importUsers,
      importMasterData: _importMaster,
      importInvoices: _importInvoices,
      importReceiptsPayments: _importReceipts,
      importExpenseIncome: _importExpenseIncome,
      importWarehouses: _importWarehouses,
      importTransfers: _importTransfers,
      importOpeningBalance: _importOpeningBalance,
      importChecks: _importChecks,
      rewriteConfirmation: _importMode == 'rewrite_business'
          ? _rewriteConfirmationController.text.trim()
          : null,
      runConfirmation: dryRun ? null : 'IMPORT',
    );
  }

  Future<void> _analyze() async {
    final bytes = _fileBytes;
    final name = _filename;
    if (bytes == null || name == null) {
      SnackBarHelper.showError(context, message: adminTx(context, 'ابتدا فایل SQL را انتخاب کنید', 'Choose an SQL file first'));
      return;
    }
    setState(() {
      _loading = true;
      _loadingAction = 'analyze';
    });
    try {
      final report = await _service.analyzeLegacySql(fileBytes: bytes, filename: name);
      if (mounted) setState(() => _analysis = report);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.extractErrorMessage(e, null));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingAction = null;
        });
      }
    }
  }

  void _pollJob() {
    final id = _jobId;
    if (id == null) return;
    _service.getJobStatus(id).then((status) {
      if (!mounted) return;
      setState(() => _jobStatus = status);
      final state = status['state'] as String?;
      if (state == 'succeeded' || state == 'failed') {
        _jobTimer?.cancel();
        _jobTimer = null;
        if (state == 'succeeded') {
          SnackBarHelper.showSuccess(context, message: adminTx(context, 'ایمپورت انجام شد', 'Import completed'));
        } else {
          final err = status['error'];
          final msg = err is Map ? (err['message'] as String?) : err?.toString();
          SnackBarHelper.showError(context, message: '${adminTx(context, 'ایمپورت ناموفق', 'Import failed')}: ${msg ?? adminTx(context, 'خطا', 'Error')}');
        }
      }
    }).catchError((_) {
      _jobTimer?.cancel();
    });
  }

  Future<bool> _confirmRealImport() async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var phraseError = '';
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(adminTx(context, 'تأیید ایمپورت واقعی', 'Confirm a real import')),
              content: TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: adminTx(context, 'عبارت IMPORT یا ایمپورت', 'Type IMPORT or ایمپورت'),
                  errorText: phraseError.isEmpty ? null : phraseError,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(adminTx(context, 'انصراف', 'Cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    final text = controller.text.trim();
                    if (text != 'IMPORT' && text != 'ایمپورت') {
                      setLocal(() => phraseError = adminTx(context, 'عبارت باید IMPORT یا ایمپورت باشد', 'Type IMPORT or ایمپورت'));
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  child: Text(adminTx(context, 'ادامه', 'Continue')),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return accepted == true;
  }

  Future<void> _startImport() async {
    final bytes = _fileBytes;
    final name = _filename;
    if (bytes == null || name == null) {
      SnackBarHelper.showError(context, message: adminTx(context, 'ابتدا فایل SQL را انتخاب کنید', 'Choose an SQL file first'));
      return;
    }
    if (_importMode != 'new_business') {
      if (_parseOptionalInt(_targetBusinessIdController.text) == null) {
        SnackBarHelper.showError(context, message: adminTx(context, 'شناسه کسب‌وکار هدف را وارد کنید', 'Enter the target business ID'));
        return;
      }
    }
    if (_importMode == 'rewrite_business') {
      final c = _rewriteConfirmationController.text.trim();
      if (c != 'بازنویسی' && c != 'REWRITE') {
        SnackBarHelper.showError(context, message: adminTx(context, 'برای بازنویسی عبارت «بازنویسی» یا REWRITE را وارد کنید', 'Type بازنویسی or REWRITE to rewrite'));
        return;
      }
    }
    if (!_dryRun) {
      final confirmed = await _confirmRealImport();
      if (!confirmed || !mounted) return;
    }

    setState(() {
      _loading = true;
      _loadingAction = 'import';
      _jobId = null;
      _jobStatus = null;
    });
    try {
      final jobId = await _service.startLegacyImport(
        fileBytes: bytes,
        filename: name,
        params: _buildParams(dryRun: _dryRun),
      );
      if (!mounted) return;
      setState(() => _jobId = jobId);
      _jobTimer?.cancel();
      _jobTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollJob());
      _pollJob();
      SnackBarHelper.showSuccess(
        context,
        message: _dryRun
            ? adminTx(context, 'شبیه‌سازی در صف قرار گرفت', 'Dry run queued')
            : adminTx(context, 'ایمپورت در پس‌زمینه شروع شد', 'Import started in the background'),
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.extractErrorMessage(e, null));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingAction = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hub = context.settingsHub;
    return AdminCompactScaffold(
      title: adminTx(context, 'ایمپورت دیتابیس قدیمی', 'Legacy database import'),
      body: SingleChildScrollView(
        padding: hub.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _infoCard(theme),
            const SizedBox(height: 8),
            _fileCard(theme),
            const SizedBox(height: 8),
            _optionsCard(theme),
            if (_analysis != null) ...[
              const SizedBox(height: 8),
              _analysisCard(theme, _analysis!),
            ],
            if (_jobStatus != null) ...[
              const SizedBox(height: 8),
              _jobCard(theme, _jobStatus!),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _analyze,
                    icon: _loadingAction == 'analyze'
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.analytics_outlined),
                    label: Text(adminTx(context, 'تحلیل فایل', 'Analyze file')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _startImport,
                    icon: _loadingAction == 'import'
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(_dryRun
                        ? adminTx(context, 'اجرای آزمایشی', 'Run dry-run')
                        : adminTx(context, 'شروع ایمپورت', 'Start import')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          adminTx(
            context,
            'دامپ MySQL نسخه قدیمی حسابیکس یا فایل .hs60 / .zip حاوی SQL را بارگذاری کنید. داده‌ها از مسیر سرویس‌های استاندارد ثبت می‌شوند.',
            'Upload an old Hesabix MySQL dump or an .hs60 / .zip file that contains SQL. Data is written through the standard services.',
          ),
          style: context.settingsHub.cardSubtitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }

  Widget _fileCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              adminTx(context, 'فایل SQL', 'SQL file'),
              style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: Text(_filename ?? adminTx(context, 'انتخاب فایل .sql / .hs60 / .zip', 'Choose .sql / .hs60 / .zip')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              adminTx(context, 'تنظیمات ایمپورت', 'Import options'),
              style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _importMode,
              decoration: InputDecoration(
                isDense: true,
                labelText: adminTx(context, 'حالت ایمپورت', 'Import mode'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 'new_business', child: Text(adminTx(context, 'کسب‌وکار جدید', 'New business'))),
                DropdownMenuItem(value: 'merge_into_business', child: Text(adminTx(context, 'ادغام در کسب‌وکار موجود', 'Merge into an existing business'))),
                DropdownMenuItem(value: 'rewrite_business', child: Text(adminTx(context, 'بازنویسی کسب‌وکار موجود', 'Rewrite an existing business'))),
              ],
              onChanged: _loading ? null : (v) => setState(() => _importMode = v ?? 'new_business'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _targetBusinessIdController,
              decoration: InputDecoration(
                isDense: true,
                labelText: adminTx(context, 'شناسه کسب‌وکار هدف', 'Target business ID'),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ownerUserIdController,
              decoration: InputDecoration(
                isDense: true,
                labelText: adminTx(context, 'شناسه مالک (اختیاری)', 'Owner user ID (optional)'),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            if (_importMode == 'rewrite_business') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _rewriteConfirmationController,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: adminTx(context, 'برای بازنویسی «بازنویسی» یا REWRITE را بنویسید', 'Type بازنویسی or REWRITE'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.warning_amber),
                ),
              ),
            ],
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(adminTx(context, 'اجرای آزمایشی (بدون ذخیره)', 'Dry run (nothing is saved)')),
              value: _dryRun,
              onChanged: _loading ? null : (v) => setState(() => _dryRun = v),
            ),
            const Divider(),
            _scopeSwitch(adminTx(context, 'کاربران', 'Users'), _importUsers, (v) => _importUsers = v),
            _scopeSwitch(adminTx(context, 'مستر دیتا', 'Master data'), _importMaster, (v) => _importMaster = v),
            _scopeSwitch(adminTx(context, 'فاکتورها', 'Invoices'), _importInvoices, (v) => _importInvoices = v),
            _scopeSwitch(adminTx(context, 'دریافت و پرداخت', 'Receipts and payments'), _importReceipts, (v) => _importReceipts = v),
            _scopeSwitch(adminTx(context, 'هزینه و درآمد', 'Expenses and income'), _importExpenseIncome, (v) => _importExpenseIncome = v),
            _scopeSwitch(adminTx(context, 'انبارها و حواله‌ها', 'Warehouses and transfers'), _importWarehouses, (v) => _importWarehouses = v),
            _scopeSwitch(adminTx(context, 'انتقال وجه', 'Money transfers'), _importTransfers, (v) => _importTransfers = v),
            _scopeSwitch(adminTx(context, 'تراز افتتاحیه', 'Opening balance'), _importOpeningBalance, (v) => _importOpeningBalance = v),
            _scopeSwitch(adminTx(context, 'چک‌ها', 'Checks'), _importChecks, (v) => _importChecks = v),
          ],
        ),
      ),
    );
  }

  Widget _scopeSwitch(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      dense: true,
      onChanged: _loading ? null : onChanged,
    );
  }

  Widget _analysisCard(ThemeData theme, Map<String, dynamic> report) {
    final valid = report['valid'] == true;
    final analysis = report['analysis'] as Map<String, dynamic>? ?? {};
    final errors = (report['errors'] as List?)?.cast<String>() ?? [];
    final docTypes = analysis['document_types'] as Map<String, dynamic>? ?? {};
    return Card(
      color: valid ? null : theme.colorScheme.errorContainer.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              adminTx(context, 'نتیجه تحلیل', 'Analysis'),
              style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            if (!valid)
              ...errors.map((e) => Text('• $e', style: TextStyle(color: theme.colorScheme.error))),
            Text('${adminTx(context, 'کسب‌وکار', 'Businesses')}: ${analysis['business_count'] ?? 0}'),
            Text('${adminTx(context, 'کاربر', 'Users')}: ${analysis['user_count'] ?? 0}'),
            Text('${adminTx(context, 'اسناد', 'Documents')}: ${analysis['document_count'] ?? 0}'),
            Text('${adminTx(context, 'سطرهای سند', 'Document lines')}: ${analysis['document_row_count'] ?? 0}'),
            if (docTypes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(adminTx(context, 'انواع سند', 'Document types'), style: theme.textTheme.labelLarge),
              ...docTypes.entries.map((e) => Text('  ${e.key}: ${e.value}')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _jobCard(ThemeData theme, Map<String, dynamic> status) {
    final state = status['state'] as String?;
    final result = status['result'] as Map<String, dynamic>?;
    final meta = status['meta'] as Map<String, dynamic>?;
    final progress = (meta?['progress'] ?? status['progress']) as num? ?? 0;
    final message = (result?['message'] ?? meta?['message'] ?? status['message']) as String? ?? '';
    final stats = result?['stats'];
    String statsText = '';
    if (stats != null) {
      statsText = const JsonEncoder.withIndent('  ').convert(stats);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${adminTx(context, 'وضعیت کار', 'Job')}: ${state ?? "—"}',
              style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
            ),
            if (message.isNotEmpty) Text(message),
            if (state == 'running' || state == 'queued') ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress > 0 ? progress / 100 : null),
            ],
            if (statsText.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(statsText, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
