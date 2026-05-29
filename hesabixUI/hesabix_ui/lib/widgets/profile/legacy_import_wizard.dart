import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/services/business_api_service.dart';
import 'package:hesabix_ui/services/job_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

enum _LegacyImportStep {
  intro,
  credentials,
  preview,
  options,
  confirm,
  progress,
  result,
}

/// ویزارد انتقال کسب‌وکار از نسخه قدیم حسابیکس.
class LegacyImportWizard extends StatefulWidget {
  const LegacyImportWizard({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const LegacyImportWizard(),
    );
  }

  @override
  State<LegacyImportWizard> createState() => _LegacyImportWizardState();
}

class _LegacyImportWizardState extends State<LegacyImportWizard> {
  static const _defaultServer = 'https://app.hesabix.ir';

  final _serverController = TextEditingController(text: _defaultServer);
  final _apiKeyController = TextEditingController();
  final _nameController = TextEditingController();
  final _jobService = JobService();

  _LegacyImportStep _step = _LegacyImportStep.intro;
  bool _busy = false;
  Map<String, dynamic>? _preview;
  String? _jobId;
  int _progress = 0;
  String? _progressMessage;
  Map<String, dynamic>? _importResult;
  String? _errorMessage;

  bool _importPersons = true;
  bool _importProducts = true;
  bool _importBanks = true;
  bool _importWarehouses = true;
  bool _importDocuments = true;
  bool _importFiles = true;

  @override
  void dispose() {
    _serverController.dispose();
    _apiKeyController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _go(_LegacyImportStep step) => setState(() => _step = step);

  Future<void> _testConnection() async {
    final key = _apiKeyController.text.trim();
    if (key.length < 8) {
      SnackBarHelper.showError(context, message: 'کلید API را وارد کنید');
      return;
    }
    setState(() => _busy = true);
    try {
      final data = await BusinessApiService.previewLegacyImport(
        serverUrl: _serverController.text.trim(),
        apiKey: key,
      );
      if (!mounted) return;
      setState(() {
        _preview = data;
        final name = data['business_name'] as String?;
        if (name != null &&
            name.isNotEmpty &&
            _nameController.text.isEmpty) {
          _nameController.text = name;
        }
      });
      _go(_LegacyImportStep.preview);
    } on DioException catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startImport() async {
    final key = _apiKeyController.text.trim();
    setState(() {
      _busy = true;
      _errorMessage = null;
      _importResult = null;
      _progress = 0;
      _progressMessage = 'در صف انتظار...';
    });
    _go(_LegacyImportStep.progress);

    try {
      final start = await BusinessApiService.importBusinessFromLegacyApi(
        serverUrl: _serverController.text.trim(),
        apiKey: key,
        businessNameOverride: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        importPersons: _importPersons,
        importProducts: _importProducts,
        importBanks: _importBanks,
        importWarehouses: _importWarehouses,
        importDocuments: _importDocuments,
        importFiles: _importFiles,
      );
      final jobId = start['job_id'] as String?;
      if (jobId == null) {
        throw Exception('شناسه کار پس‌زمینه دریافت نشد');
      }
      setState(() => _jobId = jobId);

      final poll = await _jobService.pollUntilComplete(
        jobId,
        onProgress: (p, m) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            if (m != null && m.isNotEmpty) _progressMessage = m;
          });
        },
      );

      if (!mounted) return;
      if (poll.isSuccess) {
        setState(() {
          _importResult = poll.result;
          _progress = 100;
          _progressMessage = poll.message ?? 'انتقال تکمیل شد';
        });
        _go(_LegacyImportStep.result);
      } else {
        setState(() {
          _errorMessage = poll.errorMessage ?? 'خطا در انتقال';
        });
        _go(_LegacyImportStep.result);
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ErrorExtractor.forContext(e, context);
        });
        _go(_LegacyImportStep.result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
        _go(_LegacyImportStep.result);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelJob() async {
    final id = _jobId;
    if (id != null) {
      try {
        await _jobService.cancelJob(id);
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.cloud_sync, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'انتقال از حسابیکس قبلی',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  if (_step != _LegacyImportStep.progress)
                    IconButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
            if (_step != _LegacyImportStep.intro &&
                _step != _LegacyImportStep.result)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: LinearProgressIndicator(
                  value: _stepIndex / (_totalSteps - 1),
                  minHeight: 4,
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildStepContent(theme),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _buildActions(theme),
            ),
          ],
        ),
      ),
    );
  }

  int get _stepIndex {
    switch (_step) {
      case _LegacyImportStep.intro:
        return 0;
      case _LegacyImportStep.credentials:
        return 1;
      case _LegacyImportStep.preview:
        return 2;
      case _LegacyImportStep.options:
        return 3;
      case _LegacyImportStep.confirm:
        return 4;
      case _LegacyImportStep.progress:
        return 5;
      case _LegacyImportStep.result:
        return 6;
    }
  }

  int get _totalSteps => 7;

  Widget _buildStepContent(ThemeData theme) {
    switch (_step) {
      case _LegacyImportStep.intro:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'با کلید API از نسخه قدیم حسابیکس، کسب‌وکار جدیدی در این حساب کاربری ساخته می‌شود.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _infoTile(
              Icons.schedule,
              'زمان تقریبی: ۵ تا ۱۵ دقیقه',
              'بسته به حجم آرشیو و تعداد اسناد',
            ),
            _infoTile(
              Icons.wifi,
              'اتصال پایدار',
              'تا پایان انتقال این پنجره را نبندید',
            ),
            _infoTile(
              Icons.warning_amber,
              'برخی اسناد ممکن است منتقل نشوند',
              'گزارش کامل در پایان نمایش داده می‌شود',
            ),
          ],
        );
      case _LegacyImportStep.credentials:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'کلید API را از تنظیمات کسب‌وکار در نسخه قدیم (بخش API) دریافت کنید.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _serverController,
              decoration: const InputDecoration(
                labelText: 'آدرس سرور نسخه قدیم',
                border: OutlineInputBorder(),
              ),
              enabled: !_busy,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'کلید API *',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              enabled: !_busy,
            ),
          ],
        );
      case _LegacyImportStep.preview:
        return _PreviewStepBody(preview: _preview ?? {});
      case _LegacyImportStep.options:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'نام کسب‌وکار جدید (اختیاری)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('موارد قابل انتقال:', style: TextStyle(fontWeight: FontWeight.w600)),
            CheckboxListTile(
              value: _importPersons,
              onChanged: _busy ? null : (v) => setState(() => _importPersons = v ?? true),
              title: const Text('اشخاص'),
              dense: true,
            ),
            CheckboxListTile(
              value: _importProducts,
              onChanged: _busy ? null : (v) => setState(() => _importProducts = v ?? true),
              title: const Text('کالا و خدمات'),
              dense: true,
            ),
            CheckboxListTile(
              value: _importBanks,
              onChanged: _busy ? null : (v) => setState(() => _importBanks = v ?? true),
              title: const Text('حساب‌های بانکی'),
              dense: true,
            ),
            CheckboxListTile(
              value: _importWarehouses,
              onChanged: _busy ? null : (v) => setState(() => _importWarehouses = v ?? true),
              title: const Text('انبارها'),
              dense: true,
            ),
            CheckboxListTile(
              value: _importDocuments,
              onChanged: _busy ? null : (v) => setState(() => _importDocuments = v ?? true),
              title: const Text('اسناد حسابداری'),
              dense: true,
            ),
            CheckboxListTile(
              value: _importFiles,
              onChanged: _busy ? null : (v) => setState(() => _importFiles = v ?? true),
              title: const Text('لوگو و مهر'),
              dense: true,
            ),
          ],
        );
      case _LegacyImportStep.confirm:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'کسب‌وکار «${_preview?['business_name'] ?? '—'}» از سرور قدیم منتقل می‌شود.',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (_preview != null) _PreviewStepBody(preview: _preview!, compact: true),
            const SizedBox(height: 12),
            Text(
              'با زدن «شروع انتقال» فرایند در پس‌زمینه اجرا می‌شود و پیشرفت را می‌بینید.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
      case _LegacyImportStep.progress:
        return Column(
          children: [
            const SizedBox(height: 24),
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                value: _progress > 0 ? _progress / 100 : null,
                strokeWidth: 5,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _progressMessage ?? 'در حال انتقال...',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _progress > 0 ? _progress / 100 : null,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text('$_progress%', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 24),
            Text(
              'لطفاً این پنجره را نبندید.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        );
      case _LegacyImportStep.result:
        return _ResultStepBody(
          result: _importResult,
          errorMessage: _errorMessage,
        );
    }
  }

  Widget _infoTile(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(ThemeData theme) {
    switch (_step) {
      case _LegacyImportStep.intro:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => _go(_LegacyImportStep.credentials),
              child: const Text('ادامه'),
            ),
          ],
        );
      case _LegacyImportStep.credentials:
        return Row(
          children: [
            TextButton(
              onPressed: _busy ? null : () => _go(_LegacyImportStep.intro),
              child: const Text('بازگشت'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _testConnection,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('تست اتصال و پیش‌نمایش'),
            ),
          ],
        );
      case _LegacyImportStep.preview:
        return Row(
          children: [
            TextButton(
              onPressed: _busy ? null : () => _go(_LegacyImportStep.credentials),
              child: const Text('بازگشت'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _preview == null ? null : () => _go(_LegacyImportStep.options),
              child: const Text('ادامه'),
            ),
          ],
        );
      case _LegacyImportStep.options:
        return Row(
          children: [
            TextButton(
              onPressed: () => _go(_LegacyImportStep.preview),
              child: const Text('بازگشت'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => _go(_LegacyImportStep.confirm),
              child: const Text('ادامه'),
            ),
          ],
        );
      case _LegacyImportStep.confirm:
        return Row(
          children: [
            TextButton(
              onPressed: _busy ? null : () => _go(_LegacyImportStep.options),
              child: const Text('بازگشت'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _busy ? null : _startImport,
              icon: const Icon(Icons.play_arrow),
              label: const Text('شروع انتقال'),
            ),
          ],
        );
      case _LegacyImportStep.progress:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: _cancelJob,
              child: const Text('لغو و بستن'),
            ),
          ],
        );
      case _LegacyImportStep.result:
        final success = _errorMessage == null && _importResult != null;
        final businessId = _importResult?['business_id'];
        return Row(
          children: [
            if (!success)
              TextButton(
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                    _importResult = null;
                  });
                  _go(_LegacyImportStep.confirm);
                },
                child: const Text('تلاش مجدد'),
              ),
            const Spacer(),
            if (success && businessId != null)
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.goNamed('profile_businesses');
                },
                child: const Text('رفتن به فهرست کسب‌وکارها'),
              )
            else
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('بستن'),
              ),
          ],
        );
    }
  }
}

class _PreviewStepBody extends StatelessWidget {
  const _PreviewStepBody({required this.preview, this.compact = false});

  final Map<String, dynamic> preview;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = (preview['counts'] as Map?)?.cast<String, dynamic>() ?? {};
    final risks = preview['import_risks'] as List? ?? [];
    final size = preview['archive_size_bytes'];
    final warnings = preview['warnings'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          preview['business_name']?.toString() ?? '—',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip('اشخاص', counts['persons']),
            _chip('کالا', counts['commodities'] ?? counts['products']),
            _chip('اسناد', counts['documents'] ?? counts['hesabdari_docs']),
            _chip('بانک', counts['bank_accounts']),
            if (size is int)
              _chip(
                'حجم',
                '${(size / (1024 * 1024)).toStringAsFixed(1)} MB',
              ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 16),
          if (risks.isNotEmpty) ...[
            Text('ریسک‌های احتمالی', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            ...risks.map((r) {
              final map = r is Map ? r.cast<String, dynamic>() : <String, dynamic>{};
              final severity = map['severity'] as String? ?? 'info';
              Color? color;
              if (severity == 'high') {
                color = theme.colorScheme.errorContainer;
              } else if (severity == 'medium') {
                color = theme.colorScheme.tertiaryContainer;
              } else {
                color = theme.colorScheme.surfaceContainerHighest;
              }
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(map['message']?.toString() ?? ''),
              );
            }),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...warnings.take(3).map(
                  (w) => Text('• $w', style: theme.textTheme.bodySmall),
                ),
          ],
        ],
      ],
    );
  }

  Widget _chip(String label, dynamic value) {
    return Chip(label: Text('$label: ${value ?? 0}'));
  }
}

class _ResultStepBody extends StatelessWidget {
  const _ResultStepBody({this.result, this.errorMessage});

  final Map<String, dynamic>? result;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (errorMessage != null) {
      return Column(
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
      );
    }

    final stats = (result?['stats'] as Map?)?.cast<String, dynamic>() ?? {};
    final warnings = stats['warnings'] as List? ?? [];
    final warningsCount = stats['warnings_count'] as int? ?? warnings.length;
    final docsImported = stats['documents_imported'] ?? 0;
    final docsSkipped = stats['documents_skipped'] ?? 0;
    final hasManyWarnings = docsSkipped > 0 || warningsCount > 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              hasManyWarnings ? Icons.warning_amber : Icons.check_circle,
              color: hasManyWarnings
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.primary,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasManyWarnings
                    ? 'انتقال انجام شد؛ برخی موارد منتقل نشدند'
                    : 'انتقال با موفقیت انجام شد',
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (result?['business_id'] != null)
          Text('شناسه کسب‌وکار جدید: ${result!['business_id']}'),
        if (result?['source_business_name'] != null)
          Text('منبع: ${result!['source_business_name']}'),
        const SizedBox(height: 12),
        _statRow('اشخاص', stats['persons_imported'], stats['persons_skipped']),
        _statRow('کالا', stats['products_imported'], stats['products_skipped']),
        _statRow('بانک', stats['bank_accounts_imported'], null),
        _statRow('اسناد', docsImported, docsSkipped),
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'نمونه هشدارها (${warningsCount} مورد)',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: warnings.length.clamp(0, 30),
              itemBuilder: (_, i) {
                return ListTile(
                  dense: true,
                  title: Text(
                    warnings[i].toString(),
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _statRow(String label, dynamic ok, dynamic skip) {
    final skipText = skip != null ? ' (رد: $skip)' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('$label: $ok$skipText'),
    );
  }
}
