import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../services/bytes_export/bytes_export_service.dart';
import '../../../services/payroll_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/person/file_picker_bridge.dart';
import 'payroll_ui.dart';

/// دیالوگ ورود مقادیر سند حقوق از Excel.
class PayrollRunImportDialog extends StatefulWidget {
  final int businessId;
  final int runId;

  const PayrollRunImportDialog({
    super.key,
    required this.businessId,
    required this.runId,
  });

  static Future<bool?> show(
    BuildContext context, {
    required int businessId,
    required int runId,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => PayrollRunImportDialog(businessId: businessId, runId: runId),
    );
  }

  @override
  State<PayrollRunImportDialog> createState() => _PayrollRunImportDialogState();
}

class _PayrollRunImportDialogState extends State<PayrollRunImportDialog> {
  final PayrollService _svc = PayrollService();
  bool _loading = false;
  bool _dryRun = true;
  PickedFileData? _file;
  Map<String, dynamic>? _result;

  Future<void> _pickFile() async {
    final picked = await FilePickerBridge.pickExcel();
    if (picked != null) setState(() => _file = picked);
  }

  Future<void> _downloadTemplate() async {
    setState(() => _loading = true);
    try {
      final bytes = await _svc.downloadRunLinesTemplate(
        businessId: widget.businessId,
        runId: widget.runId,
      );
      const filename = 'payroll_run_template.xlsx';
      final result = await BytesExportService.export(
        bytes: bytes,
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
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runImport({required bool dryRun}) async {
    if (_file == null) {
      await _pickFile();
      if (_file == null) return;
    }
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final data = await _svc.importRunLinesExcel(
        businessId: widget.businessId,
        runId: widget.runId,
        fileBytes: _file!.bytes,
        filename: _file!.name,
        dryRun: dryRun,
      );
      setState(() => _result = data);
      if (!dryRun && mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return PayrollUi.dialogShell(
      context: context,
      title: t.payrollImportRunLines,
      icon: Icons.table_view_outlined,
      maxWidth: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PayrollUi.infoBanner(context: context, message: t.payrollImportRunLinesHint),
          const SizedBox(height: 16),
          PayrollUi.importStepCard(
            context: context,
            icon: Icons.download_outlined,
            title: t.downloadTemplate,
            subtitle: t.payrollImportRunLinesHint,
            onPressed: _loading ? null : _downloadTemplate,
            buttonLabel: t.downloadTemplate,
          ),
          const SizedBox(height: 10),
          PayrollUi.importStepCard(
            context: context,
            icon: Icons.insert_drive_file_outlined,
            title: _file?.name ?? t.chooseFile,
            subtitle: t.chooseFile,
            selected: _file != null,
            onPressed: _loading ? null : _pickFile,
            buttonLabel: t.chooseFile,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.dryRun),
            value: _dryRun,
            onChanged: _loading ? null : (v) => setState(() => _dryRun = v),
          ),
          if (_result != null) ...[
            const SizedBox(height: 8),
            PayrollUi.sectionCard(
              context: context,
              title: t.preview,
              icon: Icons.fact_check_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t.payrollImportUpdatedLines}: ${PayrollUi.formatCount(_result!['updated_lines'] ?? _result!['would_update_lines'] ?? 0)}',
                  ),
                  Text('${t.payrollImportErrorCount}: ${PayrollUi.formatCount(_result!['error_count'] ?? 0)}'),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          onPressed: _loading ? null : () => _runImport(dryRun: _dryRun),
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_dryRun ? t.preview : t.import),
        ),
      ],
    );
  }
}
