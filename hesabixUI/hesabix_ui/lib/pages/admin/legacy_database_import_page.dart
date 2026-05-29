import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/admin_legacy_import_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

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
      if (mounted) SnackBarHelper.showError(context, message: 'خواندن فایل ناموفق بود');
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
          message: 'فرمت فایل باید .sql، .sql.gz، .zip یا .hs60 باشد',
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
    );
  }

  Future<void> _analyze() async {
    final bytes = _fileBytes;
    final name = _filename;
    if (bytes == null || name == null) {
      SnackBarHelper.showError(context, message: 'ابتدا فایل SQL را انتخاب کنید');
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
          SnackBarHelper.showSuccess(context, message: 'ایمپورت با موفقیت انجام شد');
        } else {
          final err = status['error'];
          final msg = err is Map ? (err['message'] as String?) : err?.toString();
          SnackBarHelper.showError(context, message: 'ایمپورت ناموفق: ${msg ?? "خطا"}');
        }
      }
    }).catchError((_) {
      _jobTimer?.cancel();
    });
  }

  Future<void> _startImport() async {
    final bytes = _fileBytes;
    final name = _filename;
    if (bytes == null || name == null) {
      SnackBarHelper.showError(context, message: 'ابتدا فایل SQL را انتخاب کنید');
      return;
    }
    if (_importMode != 'new_business') {
      if (_parseOptionalInt(_targetBusinessIdController.text) == null) {
        SnackBarHelper.showError(context, message: 'شناسه کسب‌وکار هدف را وارد کنید');
        return;
      }
    }
    if (_importMode == 'rewrite_business') {
      final c = _rewriteConfirmationController.text.trim();
      if (c != 'بازنویسی' && c != 'REWRITE') {
        SnackBarHelper.showError(context, message: 'برای بازنویسی عبارت «بازنویسی» را وارد کنید');
        return;
      }
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
        message: _dryRun ? 'شبیه‌سازی در صف قرار گرفت' : 'ایمپورت در پس‌زمینه شروع شد',
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('ایمپورت دیتابیس قدیمی'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _infoCard(theme),
            const SizedBox(height: 16),
            _fileCard(theme),
            const SizedBox(height: 16),
            _optionsCard(theme),
            if (_analysis != null) ...[
              const SizedBox(height: 16),
              _analysisCard(theme, _analysis!),
            ],
            if (_jobStatus != null) ...[
              const SizedBox(height: 16),
              _jobCard(theme, _jobStatus!),
            ],
            const SizedBox(height: 24),
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
                    label: const Text('تحلیل فایل'),
                  ),
                ),
                const SizedBox(width: 12),
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
                    label: Text(_dryRun ? 'اجرای dry-run' : 'شروع ایمپورت'),
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
          'دامپ MySQL نسخه قدیمی Hesabix (phpMyAdmin) یا فایل .hs60 / .zip حاوی SQL را آپلود کنید. '
          'داده‌ها از مسیر سرویس‌های استاندارد (فاکتور، دریافت/پرداخت، هزینه/درآمد، حواله انبار، انتقال، تراز افتتاحیه، چک) ثبت می‌شوند.',
          style: theme.textTheme.bodyMedium,
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
            Text('فایل SQL', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: Text(_filename ?? 'انتخاب فایل .sql / .hs60 / .zip'),
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
            Text('تنظیمات ایمپورت', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _importMode,
              decoration: const InputDecoration(
                labelText: 'حالت ایمپورت',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'new_business', child: Text('کسب‌وکار جدید')),
                DropdownMenuItem(value: 'merge_into_business', child: Text('ادغام در کسب‌وکار موجود')),
                DropdownMenuItem(value: 'rewrite_business', child: Text('بازنویسی کسب‌وکار موجود')),
              ],
              onChanged: _loading ? null : (v) => setState(() => _importMode = v ?? 'new_business'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _targetBusinessIdController,
              decoration: const InputDecoration(
                labelText: 'شناسه کسب‌وکار هدف (merge/rewrite)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ownerUserIdController,
              decoration: const InputDecoration(
                labelText: 'شناسه مالک (اختیاری، حالت new)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            if (_importMode == 'rewrite_business') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _rewriteConfirmationController,
                decoration: const InputDecoration(
                  labelText: 'تأیید بازنویسی — عبارت «بازنویسی»',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.warning_amber),
                ),
              ),
            ],
            SwitchListTile(
              title: const Text('Dry-run (بدون ذخیره)'),
              value: _dryRun,
              onChanged: _loading ? null : (v) => setState(() => _dryRun = v),
            ),
            const Divider(),
            _scopeSwitch('کاربران', _importUsers, (v) => _importUsers = v),
            _scopeSwitch('مستر دیتا', _importMaster, (v) => _importMaster = v),
            _scopeSwitch('فاکتورها', _importInvoices, (v) => _importInvoices = v),
            _scopeSwitch('دریافت/پرداخت', _importReceipts, (v) => _importReceipts = v),
            _scopeSwitch('هزینه/درآمد', _importExpenseIncome, (v) => _importExpenseIncome = v),
            _scopeSwitch('انبارها و حواله‌ها', _importWarehouses, (v) => _importWarehouses = v),
            _scopeSwitch('انتقال وجه', _importTransfers, (v) => _importTransfers = v),
            _scopeSwitch('تراز افتتاحیه', _importOpeningBalance, (v) => _importOpeningBalance = v),
            _scopeSwitch('چک‌ها', _importChecks, (v) => _importChecks = v),
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
            Text('نتیجه تحلیل', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (!valid)
              ...errors.map((e) => Text('• $e', style: TextStyle(color: theme.colorScheme.error))),
            Text('کسب‌وکار: ${analysis['business_count'] ?? 0}'),
            Text('کاربر: ${analysis['user_count'] ?? 0}'),
            Text('اسناد: ${analysis['document_count'] ?? 0}'),
            Text('سطرهای سند: ${analysis['document_row_count'] ?? 0}'),
            if (docTypes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('انواع سند:', style: theme.textTheme.labelLarge),
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
            Text('وضعیت Job: ${state ?? "—"}', style: theme.textTheme.titleMedium),
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
