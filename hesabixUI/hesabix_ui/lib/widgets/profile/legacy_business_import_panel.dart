import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/services/business_api_service.dart';
import 'package:hesabix_ui/services/job_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

/// پنل انتقال کسب‌وکار از نسخه قدیم حسابیکس با کلید API.
class LegacyBusinessImportPanel extends StatefulWidget {
  final bool isLoading;
  final ValueChanged<bool>? onLoadingChanged;

  const LegacyBusinessImportPanel({
    super.key,
    this.isLoading = false,
    this.onLoadingChanged,
  });

  @override
  State<LegacyBusinessImportPanel> createState() => _LegacyBusinessImportPanelState();
}

class _LegacyBusinessImportPanelState extends State<LegacyBusinessImportPanel> {
  static const _defaultServer = 'https://app.hesabix.ir';

  final _serverController = TextEditingController(text: _defaultServer);
  final _apiKeyController = TextEditingController();
  final _nameOverrideController = TextEditingController();

  Map<String, dynamic>? _preview;
  String? _importJobId;
  int _importProgress = 0;
  String? _importMessage;
  bool _busy = false;

  @override
  void dispose() {
    _serverController.dispose();
    _apiKeyController.dispose();
    _nameOverrideController.dispose();
    super.dispose();
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    setState(() => _busy = value);
    widget.onLoadingChanged?.call(value);
  }

  Future<void> _preview() async {
    final key = _apiKeyController.text.trim();
    if (key.length < 8) {
      SnackBarHelper.showError(context, message: 'کلید API را وارد کنید');
      return;
    }
    _setBusy(true);
    try {
      final data = await BusinessApiService.previewLegacyImport(
        serverUrl: _serverController.text.trim(),
        apiKey: key,
      );
      if (!mounted) return;
      setState(() {
        _preview = data;
        final name = data['business_name'] as String?;
        if (name != null && name.isNotEmpty && _nameOverrideController.text.isEmpty) {
          _nameOverrideController.text = name;
        }
      });
      SnackBarHelper.showSuccess(context, message: 'اتصال برقرار شد');
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
      if (mounted) _setBusy(false);
    }
  }

  Future<void> _startImport() async {
    final key = _apiKeyController.text.trim();
    if (key.length < 8) {
      SnackBarHelper.showError(context, message: 'کلید API را وارد کنید');
      return;
    }
    _setBusy(true);
    setState(() {
      _importJobId = null;
      _importProgress = 0;
      _importMessage = null;
    });
    try {
      final result = await BusinessApiService.importBusinessFromLegacyApi(
        serverUrl: _serverController.text.trim(),
        apiKey: key,
        businessNameOverride: _nameOverrideController.text.trim().isEmpty
            ? null
            : _nameOverrideController.text.trim(),
      );
      final jobId = result['job_id'] as String?;
      if (jobId != null) {
        setState(() {
          _importJobId = jobId;
          _importMessage = 'در حال انتقال...';
        });
        await _pollJob(jobId);
      }
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
      if (mounted) {
        _setBusy(false);
        setState(() => _importJobId = null);
      }
    }
  }

  Future<void> _pollJob(String jobId) async {
    final jobService = JobService();
    while (mounted && _importJobId == jobId) {
      await Future.delayed(const Duration(seconds: 1));
      try {
        final status = await jobService.getJobStatus(jobId);
        final progress = status['progress'] as int? ?? 0;
        final message = status['message'] as String? ?? '';
        final state = status['state'] as String? ?? '';
        if (mounted) {
          setState(() {
            _importProgress = progress;
            _importMessage = message;
          });
        }
        if (state == 'completed') {
          if (mounted) {
            SnackBarHelper.showSuccess(
              context,
              message: 'کسب‌وکار با موفقیت از نسخه قدیم منتقل شد',
            );
            context.goNamed('profile_businesses');
          }
          break;
        }
        if (state == 'failed') {
          final error = status['error'] as String? ?? 'خطا در انتقال';
          if (mounted) SnackBarHelper.showError(context, message: error);
          break;
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showError(
            context,
            message: ErrorExtractor.forContext(e, context),
          );
        }
        break;
      }
    }
  }

  void _openDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: !_busy,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('انتقال از حسابیکس قبلی'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'کلید API را از تنظیمات کسب‌وکار در نسخه قدیم (بخش API) دریافت کنید. '
                    'هر کلید فقط به یک کسب‌وکار متصل است.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _serverController,
                    decoration: const InputDecoration(
                      labelText: 'آدرس سرور نسخه قدیم',
                      hintText: 'https://app.hesabix.ir',
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameOverrideController,
                    decoration: const InputDecoration(
                      labelText: 'نام کسب‌وکار جدید (اختیاری)',
                      border: OutlineInputBorder(),
                    ),
                    enabled: !_busy,
                  ),
                  if (_preview != null) ...[
                    const SizedBox(height: 16),
                    _PreviewSummary(preview: _preview!),
                  ],
                  if (_importMessage != null) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _importJobId != null ? _importProgress / 100 : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _importMessage!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(ctx),
              child: const Text('بستن'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _preview,
              child: const Text('تست اتصال'),
            ),
            FilledButton(
              onPressed: _busy ? null : _startImport,
              child: _busy && _importJobId != null
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: _importProgress > 0 ? _importProgress / 100 : null,
                      ),
                    )
                  : const Text('شروع انتقال'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.isLoading || _busy;
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: disabled ? null : _openDialog,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.cloud_sync,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'انتقال از حسابیکس قبلی',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'با کلید API از نسخه قدیم (ابری یا اختصاصی)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
              ),
              if (_busy && _importJobId != null)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: _importProgress / 100,
                  ),
                )
              else if (_busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewSummary extends StatelessWidget {
  final Map<String, dynamic> preview;

  const _PreviewSummary({required this.preview});

  @override
  Widget build(BuildContext context) {
    final counts = (preview['counts'] as Map?)?.cast<String, dynamic>() ?? {};
    final size = preview['archive_size_bytes'];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            preview['business_name']?.toString() ?? '—',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text('اشخاص: ${counts['persons'] ?? 0}'),
          Text('کالا/خدمت: ${counts['commodities'] ?? 0}'),
          Text('اسناد: ${counts['documents'] ?? 0}'),
          Text('انبار: ${counts['storerooms'] ?? 0}'),
          if (size != null)
            Text(
              'حجم آرشیو: ${(size is int ? size / 1024 : 0).toStringAsFixed(0)} KB',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
