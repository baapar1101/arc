import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../person/file_picker_bridge.dart';
import '../../core/api_client.dart';
import '../../services/bytes_export/bytes_export_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../common/excel_import_dialog_shell.dart';

class ProductImportDialog extends StatefulWidget {
  final int businessId;

  const ProductImportDialog({super.key, required this.businessId});

  @override
  State<ProductImportDialog> createState() => _ProductImportDialogState();
}

class _ProductImportDialogState extends State<ProductImportDialog> {
  bool _dryRun = true;
  String _matchBy = 'code';
  String _conflictPolicy = 'upsert';
  String _onMissingCategory = 'error';
  String _onMissingAttributes = 'error';
  bool _loading = false;
  Map<String, dynamic>? _result;
  PickedFileData? _selectedFile;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    });
  }

  Future<void> _pickFile() async {
    if (!_isInitialized) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(context, message: t.loading);
      }
      return;
    }

    try {
      final picked = await FilePickerBridge.pickExcel();
      if (picked != null) {
        setState(() {
          _selectedFile = picked;
        });
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(
          context,
          message: '${t.pickFileError}: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    }
  }

  Future<void> _downloadTemplate() async {
    try {
      setState(() => _loading = true);
      final api = ApiClient();
      final res = await api.post(
        '/products/business/${widget.businessId}/import/template',
        responseType: ResponseType.bytes,
      );
      String filename = 'products_import_template.xlsx';
      final cd = res.headers.value('content-disposition');
      if (cd != null) {
        try {
          final parts = cd.split(';').map((e) => e.trim());
          for (final p in parts) {
            if (p.toLowerCase().startsWith('filename=')) {
              var name = p.substring('filename='.length).trim();
              if (name.startsWith('"') && name.endsWith('"') && name.length >= 2) {
                name = name.substring(1, name.length - 1);
              }
              if (name.isNotEmpty) filename = name;
              break;
            }
          }
        } catch (_) {}
      }
      final result = await BytesExportService.export(
        bytes: res.data as List<int>,
        filename: filename,
      );
      if (mounted) {
        final t = AppLocalizations.of(context);
        BytesExportService.showFeedback(
          context,
          result,
          successOverride: '${t.templateDownloaded}: $filename',
        );
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(
          context,
          message: '${t.templateDownloadError}: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runImport({required bool dryRun}) async {
    if (_selectedFile == null) {
      await _pickFile();
      if (_selectedFile == null) return;
    }
    final filename = _selectedFile!.name;
    final bytes = _selectedFile!.bytes;

    try {
      setState(() {
        _loading = true;
        _result = null;
      });
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
        'dry_run': dryRun.toString(),
        'match_by': _matchBy,
        'conflict_policy': _conflictPolicy,
        'on_missing_category': _onMissingCategory,
        'on_missing_attributes': _onMissingAttributes,
      });
      final api = ApiClient();
      final res = await api.post<Map<String, dynamic>>(
        '/products/business/${widget.businessId}/import/excel',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      setState(() {
        _result = res.data;
      });
      if (!dryRun) {
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(
          context,
          message: '${t.importError}: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isFa = Localizations.localeOf(context).languageCode == 'fa';

    return ExcelImportDialogShell(
      title: t.importFromExcel,
      onClose: _loading ? null : () => Navigator.of(context).pop(false),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: Text(t.close),
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : _downloadTemplate,
          icon: const Icon(Icons.download),
          label: Text(t.downloadTemplate),
        ),
        FilledButton.icon(
          onPressed: _loading ? null : () => _runImport(dryRun: _dryRun),
          icon: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.play_arrow),
          label: Text(_dryRun ? t.reviewDryRun : t.import),
        ),
        if (_dryRun)
          FilledButton.tonalIcon(
            onPressed: _loading
                ? null
                : () async {
                    setState(() => _dryRun = false);
                    await _runImport(dryRun: false);
                  },
            icon: const Icon(Icons.cloud_upload),
            label: Text(t.importReal),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcelImportFilePicker(
            fileName: _selectedFile?.name,
            emptyHint: t.noFileSelected,
            chooseLabel: t.chooseFile,
            onPick: _pickFile,
            enabled: !_loading && _isInitialized,
          ),
          const SizedBox(height: 16),
          ExcelImportResponsiveGroup(
            children: [
              ExcelImportDropdownField(
                label: t.matchBy,
                value: _matchBy,
                items: [
                  DropdownMenuItem(value: 'code', child: Text(t.code)),
                  DropdownMenuItem(value: 'name', child: Text(t.title)),
                ],
                onChanged: _loading ? null : (v) => setState(() => _matchBy = v ?? 'code'),
              ),
              ExcelImportDropdownField(
                label: t.conflictPolicy,
                value: _conflictPolicy,
                items: [
                  DropdownMenuItem(value: 'insert', child: Text(t.policyInsertOnly)),
                  DropdownMenuItem(value: 'update', child: Text(t.policyUpdateExisting)),
                  DropdownMenuItem(value: 'upsert', child: Text(t.policyUpsert)),
                ],
                onChanged: _loading ? null : (v) => setState(() => _conflictPolicy = v ?? 'upsert'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ExcelImportResponsiveGroup(
            children: [
              ExcelImportDropdownField(
                label: isFa ? 'دسته‌بندی ناموجود' : 'Missing category',
                value: _onMissingCategory,
                items: [
                  DropdownMenuItem(
                    value: 'error',
                    child: Text(isFa ? 'خطا' : 'Error'),
                  ),
                  DropdownMenuItem(
                    value: 'create',
                    child: Text(isFa ? 'ایجاد خودکار' : 'Auto-create'),
                  ),
                ],
                onChanged: _loading ? null : (v) => setState(() => _onMissingCategory = v ?? 'error'),
              ),
              ExcelImportDropdownField(
                label: isFa ? 'ویژگی ناموجود' : 'Missing attribute',
                value: _onMissingAttributes,
                items: [
                  DropdownMenuItem(
                    value: 'error',
                    child: Text(isFa ? 'خطا' : 'Error'),
                  ),
                  DropdownMenuItem(
                    value: 'create',
                    child: Text(isFa ? 'ایجاد خودکار' : 'Auto-create'),
                  ),
                ],
                onChanged: _loading ? null : (v) => setState(() => _onMissingAttributes = v ?? 'error'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ExcelImportInfoBanner(
            message: isFa
                ? 'برای دسته‌بندی می‌توانید «مسیر دسته‌بندی» مثل «مواد اولیه > پلاستیک» وارد کنید. '
                    'تعداد اولیه و بهای تمام‌شده فقط برای کالا با کنترل موجودی فعال و در سند تراز افتتاحیه ثبت می‌شوند؛ '
                    'انبار را با شناسه، کد یا نام مشخص کنید.'
                : 'Tip: Use Category Path like "Raw materials > Plastics". '
                    'Opening balance qty/cost apply only to tracked products and are stored in the opening balance document; '
                    'specify warehouse by ID, code, or name.',
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.dryRunValidateOnly),
            value: _dryRun,
            onChanged: _loading ? null : (v) => setState(() => _dryRun = v),
          ),
          if (_result != null) ...[
            const SizedBox(height: 16),
            Text(
              '${t.result}:',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _ResultSummary(result: _result!),
          ],
        ],
      ),
    );
  }
}

class _ResultSummary extends StatelessWidget {
  final Map<String, dynamic> result;
  const _ResultSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    return _ResultSummaryBody(result: result);
  }
}

class _ResultSummaryBody extends StatefulWidget {
  final Map<String, dynamic> result;
  const _ResultSummaryBody({required this.result});

  @override
  State<_ResultSummaryBody> createState() => _ResultSummaryBodyState();
}

class _ResultSummaryBodyState extends State<_ResultSummaryBody> {
  String _previewFilter = 'all';
  int _previewLimit = 50;

  String _fmtMap(Object? v) {
    if (v is Map) {
      if (v.isEmpty) return '';
      return v.entries.map((e) => '${e.key}: ${e.value}').join(' | ');
    }
    if (v is List) {
      return v.join(', ');
    }
    return v?.toString() ?? '';
  }

  bool _hasAnyInfo(Map<String, dynamic> row) {
    final resolved = row['resolved'];
    final wouldCreate = row['would_create'];
    final warnings = row['warnings'];
    final openingBalance = row['opening_balance'];
    return (resolved is Map && resolved.isNotEmpty) ||
        (wouldCreate is Map && wouldCreate.isNotEmpty) ||
        (warnings is List && warnings.isNotEmpty) ||
        (openingBalance is Map && openingBalance.isNotEmpty);
  }

  bool _matchFilter(Map<String, dynamic> row) {
    final resolved = row['resolved'];
    final wouldCreate = row['would_create'];
    final warnings = row['warnings'];
    switch (_previewFilter) {
      case 'warnings':
        return warnings is List && warnings.isNotEmpty;
      case 'would_create':
        return wouldCreate is Map && wouldCreate.isNotEmpty;
      case 'resolved':
        return resolved is Map && resolved.isNotEmpty;
      case 'all':
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    final data = widget.result['data'] as Map<String, dynamic>?;
    final summary = (data?['summary'] as Map<String, dynamic>?) ?? {};
    final errors = (data?['errors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final refSummary = data?['reference_summary'] as Map<String, dynamic>?;
    final previewRaw = (data?['preview'] as List?)?.cast<dynamic>() ?? const [];
    final preview = previewRaw
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .where(_hasAnyInfo)
        .toList();
    final filteredPreview = preview.where(_matchFilter).toList();
    final shownCount = filteredPreview.length > _previewLimit ? _previewLimit : filteredPreview.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _chip(t.total, summary['total']),
            _chip(t.valid, summary['valid']),
            _chip(t.invalid, summary['invalid']),
            _chip(t.inserted, summary['inserted']),
            _chip(t.updated, summary['updated']),
            _chip(t.skipped, summary['skipped']),
            _chip(t.dryRun, summary['dry_run'] == true ? t.yes : t.no),
          ],
        ),
        if (refSummary != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _chip(isFa ? 'Resolve دسته‌بندی' : 'Resolved category', (refSummary['resolved'] as Map?)?['category']),
              _chip(isFa ? 'Resolve انبار' : 'Resolved warehouse', (refSummary['resolved'] as Map?)?['warehouse']),
              _chip(isFa ? 'Resolve نوع مالیات' : 'Resolved tax type', (refSummary['resolved'] as Map?)?['tax_type']),
              _chip(isFa ? 'Resolve واحد مالیاتی' : 'Resolved tax unit', (refSummary['resolved'] as Map?)?['tax_unit']),
              _chip(isFa ? 'Resolve ویژگی‌ها' : 'Resolved attributes', (refSummary['resolved'] as Map?)?['attributes']),
              _chip(isFa ? 'ایجادشدنی دسته‌بندی' : 'Would create categories', (refSummary['would_create'] as Map?)?['categories']),
              _chip(isFa ? 'ایجادشدنی ویژگی' : 'Would create attributes', (refSummary['would_create'] as Map?)?['attributes']),
              _chip(isFa ? 'ردیف با تعداد اولیه' : 'Rows with opening balance', (refSummary['opening_balance'] as Map?)?['rows_with_opening_balance']),
              _chip(isFa ? 'حذف تعداد اولیه' : 'Opening balance cleared', (refSummary['opening_balance'] as Map?)?['rows_cleared']),
            ],
          ),
        ],
        if (preview.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(
              isFa ? 'جزئیات بررسی (Dry-run)' : 'Dry-run details',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            subtitle: Text(
              isFa
                  ? 'نمایش $shownCount ردیف (از ${filteredPreview.length})'
                  : 'Showing $shownCount rows (of ${filteredPreview.length})',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            children: [
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(isFa ? 'همه' : 'All'),
                    selected: _previewFilter == 'all',
                    onSelected: (_) => setState(() => _previewFilter = 'all'),
                  ),
                  ChoiceChip(
                    label: Text(isFa ? 'هشدارها' : 'Warnings'),
                    selected: _previewFilter == 'warnings',
                    onSelected: (_) => setState(() => _previewFilter = 'warnings'),
                  ),
                  ChoiceChip(
                    label: Text(isFa ? 'ایجادشدنی‌ها' : 'Would create'),
                    selected: _previewFilter == 'would_create',
                    onSelected: (_) => setState(() => _previewFilter = 'would_create'),
                  ),
                  ChoiceChip(
                    label: Text(isFa ? 'Resolve شده‌ها' : 'Resolved'),
                    selected: _previewFilter == 'resolved',
                    onSelected: (_) => setState(() => _previewFilter = 'resolved'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: shownCount,
                itemBuilder: (context, i) {
                  final row = filteredPreview[i];
                  final rowNo = row['row'];
                  final resolved = row['resolved'];
                  final wouldCreate = row['would_create'];
                  final warnings = row['warnings'];
                  final openingBalance = row['opening_balance'];
                  final resolvedText = _fmtMap(resolved);
                  final wouldCreateText = _fmtMap(wouldCreate);
                  final warningsText = _fmtMap(warnings);
                  final openingBalanceText = _fmtMap(openingBalance);

                  final lines = <String>[];
                  if (resolvedText.isNotEmpty) {
                    lines.add((isFa ? 'Resolve: ' : 'Resolved: ') + resolvedText);
                  }
                  if (wouldCreateText.isNotEmpty) {
                    lines.add((isFa ? 'ایجادشدنی: ' : 'Would create: ') + wouldCreateText);
                  }
                  if (openingBalanceText.isNotEmpty) {
                    lines.add((isFa ? 'تعداد اولیه: ' : 'Opening balance: ') + openingBalanceText);
                  }
                  if (warningsText.isNotEmpty) {
                    lines.add((isFa ? 'هشدار: ' : 'Warnings: ') + warningsText);
                  }

                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info_outline, size: 20),
                    title: Text('${t.row} ${rowNo ?? '-'}'),
                    subtitle: Text(lines.join('\n')),
                  );
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (_previewLimit < filteredPreview.length)
                    TextButton(
                      onPressed: () => setState(() => _previewLimit = _previewLimit + 50),
                      child: Text(isFa ? 'نمایش بیشتر' : 'Show more'),
                    ),
                  if (_previewLimit > 50)
                    TextButton(
                      onPressed: () => setState(() => _previewLimit = 50),
                      child: Text(isFa ? 'نمایش کمتر' : 'Show less'),
                    ),
                ],
              ),
            ],
          ),
        ],
        if (errors.isNotEmpty)
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: errors.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = errors[i];
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                leading: const Icon(Icons.error_outline, color: Colors.red, size: 20),
                title: Text('${t.row} ${e['row']}'),
                subtitle: Text(((e['errors'] as List?)?.join(', ')) ?? ''),
              );
            },
          ),
      ],
    );
  }

  Widget _chip(String label, Object? value) {
    return Chip(
      label: Text('$label: ${value ?? '-'}'),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
