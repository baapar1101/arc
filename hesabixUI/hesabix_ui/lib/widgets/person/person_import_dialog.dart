import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'file_picker_bridge.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../data_table/helpers/file_saver.dart';
import '../../utils/snackbar_helper.dart';

class PersonImportDialog extends StatefulWidget {
  final int businessId;

  const PersonImportDialog({super.key, required this.businessId});

  @override
  State<PersonImportDialog> createState() => _PersonImportDialogState();
}

class _PersonImportDialogState extends State<PersonImportDialog> {
  final TextEditingController _pathCtrl = TextEditingController();
  bool _dryRun = true;
  String _matchBy = 'code';
  String _conflictPolicy = 'upsert';
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

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    if (!_isInitialized) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.loading)),
        );
      }
      return;
    }
    
    try {
      final picked = await FilePickerBridge.pickExcel();
      if (picked != null) {
        setState(() {
          _selectedFile = picked;
          _pathCtrl.text = picked.name;
        });
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.pickFileError}: $e')),
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
      await FileSaver.saveBytes((res.data as List<int>), filename);
      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.templateDownloaded}: $filename')),
        );
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.templateDownloadError}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runImport({required bool dryRun}) async {
    // Ensure file is selected
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
      });
      if (!dryRun) {
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.importError}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.importPersonsFromExcel),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _pathCtrl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: t.selectedFile,
                    hintText: t.noFileSelected,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: (_loading || !_isInitialized) ? null : _pickFile,
                icon: const Icon(Icons.attach_file),
                label: Text(t.chooseFile),
              ),
            ]),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _matchBy,
                    isDense: true,
                    items: [
                      DropdownMenuItem(value: 'code', child: Text('${t.matchBy}: ${t.code}')),
                      DropdownMenuItem(value: 'national_id', child: Text('${t.matchBy}: ${t.personNationalId}')),
                      DropdownMenuItem(value: 'email', child: Text('${t.matchBy}: ${t.personEmail}')),
                    ],
                    onChanged: (v) => setState(() => _matchBy = v ?? 'code'),
                    decoration: const InputDecoration(isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _conflictPolicy,
                    isDense: true,
                    items: [
                      DropdownMenuItem(value: 'insert', child: Text('${t.conflictPolicy}: ${t.policyInsertOnly}')),
                      DropdownMenuItem(value: 'update', child: Text('${t.conflictPolicy}: ${t.policyUpdateExisting}')),
                      DropdownMenuItem(value: 'upsert', child: Text('${t.conflictPolicy}: ${t.policyUpsert}')), 
                    ],
                    onChanged: (v) => setState(() => _conflictPolicy = v ?? 'upsert'),
                    decoration: const InputDecoration(isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _dryRun,
                  onChanged: (v) => setState(() => _dryRun = v ?? true),
                ),
                Text(t.dryRunValidateOnly)
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _downloadTemplate,
                  icon: const Icon(Icons.download),
                  label: Text(t.downloadTemplate),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : () => _runImport(dryRun: _dryRun),
                  icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
                  label: Text(_dryRun ? t.reviewDryRun : t.import),
                ),
                const SizedBox(width: 8),
                if (_dryRun)
                  FilledButton.tonalIcon(
                    onPressed: _loading ? null : () async {
                      // اجرای ایمپورت واقعی
                      setState(() => _dryRun = false);
                      await _runImport(dryRun: false);
                    },
                    icon: const Icon(Icons.cloud_upload),
                    label: Text(t.importReal),
                  )
              ],
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text('${t.result}:', style: Theme.of(context).textTheme.titleSmall),
              ),
              const SizedBox(height: 8),
              _ResultSummary(result: _result!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: Text(t.close),
        ),
      ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
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
        const SizedBox(height: 8),
        if (errors.isNotEmpty)
          SizedBox(
            height: 160,
            child: ListView.builder(
              itemCount: errors.length,
              itemBuilder: (context, i) {
                final e = errors[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: Text('${t.row} ${e['row']}'),
                  subtitle: Text(((e['errors'] as List?)?.join(', ')) ?? ''),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _chip(String label, Object? value) {
    return Chip(label: Text('$label: ${value ?? '-'}'));
  }
}


