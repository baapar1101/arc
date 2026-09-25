import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'file_picker_bridge.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../services/bytes_export/bytes_export_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../common/excel_import_dialog_shell.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

class PersonImportDialog extends StatefulWidget {
  final int businessId;

  const PersonImportDialog({super.key, required this.businessId});

  @override
  State<PersonImportDialog> createState() => _PersonImportDialogState();
}

class _PersonImportDialogState extends State<PersonImportDialog> {
  bool _dryRun = true;
  String _matchBy = 'code';
  String _conflictPolicy = 'upsert';
  bool _loading = false;
  Map<String, dynamic>? _result;
  PickedFileData? _selectedFile;
  bool _isInitialized = false;
  /// پس از ایمپورت واقعی موفق، با بستن دیالوگ جدول والد رفرش شود.
  bool _shouldRefreshParent = false;

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
        '/persons/businesses/${widget.businessId}/persons/import/template',
        responseType: ResponseType.bytes,
      );
      String filename = 'persons_import_template.xlsx';
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
      });
      final api = ApiClient();
      final res = await api.post<Map<String, dynamic>>(
        '/persons/businesses/${widget.businessId}/persons/import/excel',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      setState(() {
        _result = res.data;
        if (!dryRun) {
          _shouldRefreshParent = true;
        }
      });
      if (!dryRun && mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(context, message: t.personImportSuccess);
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

    return ExcelImportDialogShell(
      title: t.importPersonsFromExcel,
      onClose: _loading ? null : () => Navigator.of(context).pop(_shouldRefreshParent),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(_shouldRefreshParent),
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
                  DropdownMenuItem(value: 'national_id', child: Text(t.personNationalId)),
                  DropdownMenuItem(value: 'email', child: Text(t.personEmail)),
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
    final t = AppLocalizations.of(context);
    final data = result['data'] as Map<String, dynamic>?;
    final summary = (data?['summary'] as Map<String, dynamic>?) ?? {};
    final errors = (data?['errors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final warnings =
        (data?['warnings'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final isDry = summary['dry_run'] == true;
    final skipApply = summary['skipped_apply'];

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
            if (skipApply != null && skipApply is num && skipApply.toInt() > 0)
              _chip(t.importSkippedApply, skipApply),
            _chip(t.dryRun, isDry ? t.yes : t.no),
            if (isDry) ...[
              _chip(t.importPreviewInsert, summary['would_insert']),
              _chip(t.importPreviewUpdate, summary['would_update']),
              _chip(t.importPreviewSkipConflict, summary['would_skip_conflict']),
            ],
          ],
        ),
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            t.importWarningsTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: warnings.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final w = warnings[i];
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                leading: Icon(
                  Icons.warning_amber_outlined,
                  color: Theme.of(context).colorScheme.tertiary,
                  size: 20,
                ),
                title: Text('${t.row} ${w['row']}'),
                subtitle: Text(w['message']?.toString() ?? ''),
              );
            },
          ),
        ],
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 8),
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
                leading: Icon(Icons.error_outline, color: SemanticColorResolver.negative(context), size: 20),
                title: Text('${t.row} ${e['row']}'),
                subtitle: Text(((e['errors'] as List?)?.join(', ')) ?? ''),
              );
            },
          ),
        ],
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
