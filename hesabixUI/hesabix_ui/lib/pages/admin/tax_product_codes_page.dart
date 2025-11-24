import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../services/tax_product_code_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/person/file_picker_bridge.dart';

class TaxProductCodesPage extends StatefulWidget {
  const TaxProductCodesPage({super.key});

  @override
  State<TaxProductCodesPage> createState() => _TaxProductCodesPageState();
}

class _TaxProductCodesPageState extends State<TaxProductCodesPage> {
  final _service = TaxProductCodeService();
  bool _importing = false;
  double _uploadProgress = 0;
  String? _jobId;
  Map<String, dynamic>? _jobStatus;
  Timer? _jobTimer;
  int _tableRefreshToken = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _jobTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickAndImportFile() async {
    if (_importing) return;
    try {
      final picked = await FilePickerBridge.pickXml();
      if (picked == null) return;
      setState(() {
        _importing = true;
        _uploadProgress = 0;
      });
      final jobId = await _service.importFromXml(
        filename: picked.name,
        bytes: Uint8List.fromList(picked.bytes),
        onProgress: (sent, total) {
          if (!mounted) return;
          setState(() {
            _uploadProgress = total > 0 ? sent / total : 0;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _jobId = jobId;
        _jobStatus = {
          'state': 'queued',
          'message': 'در انتظار شروع کار پس‌زمینه',
        };
      });
      SnackBarHelper.show(context, message: 'ایمپورت آغاز شد. وضعیت در نوار بالا نمایش داده می‌شود.');
      _startJobPolling();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در ارسال فایل: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  void _startJobPolling() {
    _jobTimer?.cancel();
    if (_jobId == null) return;
    _jobTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollJobStatus());
    _pollJobStatus();
  }

  Future<void> _pollJobStatus() async {
    if (_jobId == null) return;
    try {
      final status = await _service.getJobStatus(_jobId!);
      if (!mounted) return;
      setState(() {
        _jobStatus = status;
      });
      final state = status['state'];
      if (state == 'succeeded' || state == 'failed') {
        _jobTimer?.cancel();
        _jobTimer = null;
        if (state == 'succeeded') {
          SnackBarHelper.show(context, message: 'ایمپورت با موفقیت پایان یافت.');
          setState(() {
            _tableRefreshToken++;
          });
        } else {
          final err = status['error'] ?? status['message'] ?? 'ایمپورت ناموفق بود';
          SnackBarHelper.showError(context, message: err.toString());
        }
      }
    } catch (e) {
      _jobTimer?.cancel();
      _jobTimer = null;
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در دریافت وضعیت کار: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('کدهای مالیاتی کالا'),
        actions: [
          TextButton.icon(
            onPressed: _importing ? null : _pickAndImportFile,
            icon: _importing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined),
            label: const Text('ایمپورت XML/ZIP'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_importing) _buildUploadProgressBanner(theme),
          if (_jobStatus != null) _buildJobStatusBanner(theme),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _buildTable(t),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobStatusBanner(ThemeData theme) {
    final state = (_jobStatus?['state'] ?? '').toString();
    final message = _jobStatus?['message']?.toString() ?? '';
    final progress = _jobStatus?['progress'] is num ? (_jobStatus!['progress'] as num).toInt() : null;
    Color color;
    IconData icon;
    switch (state) {
      case 'succeeded':
        color = Colors.green;
        icon = Icons.check_circle_outline;
        break;
      case 'failed':
        color = Colors.red;
        icon = Icons.error_outline;
        break;
      case 'running':
        color = Colors.orange;
        icon = Icons.work_outline;
        break;
      default:
        color = theme.colorScheme.primary;
        icon = Icons.pending;
    }
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('وضعیت ایمپورت: $state', style: theme.textTheme.titleSmall?.copyWith(color: color)),
                if (progress != null) LinearProgressIndicator(value: progress.clamp(0, 100) / 100),
                if (message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(message, style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
          if (state == 'failed' && (_jobStatus?['error'] ?? '').toString().isNotEmpty)
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'جزئیات خطا',
              onPressed: () {
                final err = _jobStatus?['error'] ?? 'نامشخص';
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('جزئیات خطا'),
                    content: Text(err.toString()),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('بستن')),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTable(AppLocalizations t) {
    final config = DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/admin/tax/product-codes/search',
      columns: [
        TextColumn(
          'code',
          t.code,
          width: ColumnWidth.small,
          formatter: (item) => item['code']?.toString(),
        ),
        TextColumn(
          'description',
          t.description,
          width: ColumnWidth.extraLarge,
          maxLines: 3,
          formatter: (item) => item['description']?.toString(),
        ),
        TextColumn(
          'vat_rate',
          t.vatColumn,
          width: ColumnWidth.small,
          formatter: (item) => _formatVatValue(item, t),
        ),
        TextColumn(
          'taxable_status',
          'وضعیت مالیاتی',
          width: ColumnWidth.medium,
          formatter: (item) => item['taxable_status']?.toString(),
        ),
        TextColumn(
          'run_date',
          'تاریخ اجرا',
          width: ColumnWidth.small,
          formatter: (item) => item['run_date']?.toString(),
        ),
        TextColumn(
          'last_edit_date',
          'آخرین ویرایش',
          width: ColumnWidth.small,
          formatter: (item) => item['last_edit_date']?.toString(),
        ),
      ],
      searchFields: const ['code', 'description', 'taxable_status'],
      defaultSortBy: 'code',
      defaultPageSize: 25,
      pageSizeOptions: const [25, 50, 100],
      showFilters: false,
      showFiltersButton: false,
      showColumnSearch: false,
      enableColumnSettings: true,
      showColumnSettingsButton: true,
      tableId: 'admin_tax_product_codes',
      showPagination: true,
      showSearch: true,
      showClearFiltersButton: true,
      customHeaderActions: const [],
    );

    return DataTableWidget<Map<String, dynamic>>(
      key: ValueKey(_tableRefreshToken),
      config: config,
      fromJson: (json) => json,
    );
  }

  Widget _buildUploadProgressBanner(ThemeData theme) {
    final percentage = (_uploadProgress * 100).clamp(0, 100);
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'در حال بارگذاری فایل...',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: _uploadProgress > 0 ? _uploadProgress.clamp(0, 1) : null,
                ),
                const SizedBox(height: 4),
                Text('${percentage.toStringAsFixed(0)}%'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatVatValue(Map<String, dynamic> item, AppLocalizations t) {
    final raw = item['vat_rate']?.toString();
    if (raw == null || raw.trim().isEmpty) {
      return t.taxVatUnknown;
    }
    final parsed = num.tryParse(raw.trim());
    final formatted = parsed != null
        ? NumberFormat.decimalPattern(t.localeName).format(parsed)
        : raw.trim();
    return t.taxVatPercent(formatted);
  }
}

