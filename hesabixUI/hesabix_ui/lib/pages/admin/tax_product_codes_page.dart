import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../services/tax_product_code_service.dart';
import 'admin_compact_scaffold.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/person/file_picker_bridge.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

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
          'message': adminTx(context, 'در انتظار شروع کار پس‌زمینه', 'Waiting for the background job'),
        };
      });
      SnackBarHelper.show(context, message: adminTx(context, 'ایمپورت آغاز شد. وضعیت در نوار بالا دیده می‌شود.', 'Import started. Status is shown in the banner.'));
      _startJobPolling();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
        context,
        message: '${adminTx(context, 'ارسال فایل ناموفق بود', 'Could not upload the file')}: ${ErrorExtractor.forContext(e, context)}',
      );
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
          SnackBarHelper.show(context, message: adminTx(context, 'ایمپورت تمام شد', 'Import finished'));
          setState(() {
            _tableRefreshToken++;
          });
        } else {
          final err = status['error'] ?? status['message'] ?? adminTx(context, 'ایمپورت ناموفق بود', 'Import failed');
          SnackBarHelper.showError(context, message: err.toString());
        }
      }
    } catch (e) {
      _jobTimer?.cancel();
      _jobTimer = null;
      if (mounted) {
        SnackBarHelper.showError(
        context,
        message:
            '${adminTx(context, 'وضعیت کار خوانده نشد', 'Could not read the job status')}: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    return AdminCompactScaffold(
      title: adminTx(context, 'کدهای مالیاتی کالا', 'Tax product codes'),
      subtitle: adminTx(context, 'فهرست کدهای سازمان امور مالیاتی', 'Tax authority product codes'),
      actions: [
        IconButton(
          tooltip: adminTx(context, 'ورود XML یا ZIP', 'Import XML or ZIP'),
          onPressed: _importing ? null : _pickAndImportFile,
          icon: _importing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file_outlined, size: 20),
        ),
      ],
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
        color = SemanticColorResolver.positive(context);
        icon = Icons.check_circle_outline;
        break;
      case 'failed':
        color = SemanticColorResolver.negative(context);
        icon = Icons.error_outline;
        break;
      case 'running':
        color = SemanticColorResolver.warning(context);
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
                Text('${adminTx(context, 'وضعیت ایمپورت', 'Import status')}: ${_jobStateLabel(state)}', style: theme.textTheme.titleSmall?.copyWith(color: color, fontSize: 13)),
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
              tooltip: adminTx(context, 'جزئیات خطا', 'Error details'),
              onPressed: () {
                final err = _jobStatus?['error'] ?? adminTx(context, 'نامشخص', 'Unknown');
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(adminTx(ctx, 'جزئیات خطا', 'Error details'), style: const TextStyle(fontSize: 16)),
                    content: Text(err.toString()),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(adminTx(ctx, 'بستن', 'Close'))),
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
          adminTx(context, 'وضعیت مالیاتی', 'Tax status'),
          width: ColumnWidth.medium,
          formatter: (item) => item['taxable_status']?.toString(),
        ),
        TextColumn(
          'run_date',
          adminTx(context, 'تاریخ اجرا', 'Effective date'),
          width: ColumnWidth.small,
          formatter: (item) => item['run_date']?.toString(),
        ),
        TextColumn(
          'last_edit_date',
          adminTx(context, 'آخرین ویرایش', 'Last edit'),
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
    
        expandBodyHeightToFitRows: true,);

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
                  adminTx(context, 'در حال بارگذاری فایل', 'Uploading file'),
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

  String _jobStateLabel(String state) {
    return switch (state) {
      'succeeded' => adminTx(context, 'موفق', 'Succeeded'),
      'failed' => adminTx(context, 'ناموفق', 'Failed'),
      'running' => adminTx(context, 'در حال اجرا', 'Running'),
      'queued' => adminTx(context, 'در صف', 'Queued'),
      _ => state,
    };
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

