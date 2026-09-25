import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../services/bytes_export/bytes_export_service.dart';
import '../../../services/payroll_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/person/file_picker_bridge.dart';
import 'payroll_ui.dart';

/// دیالوگ ورود گروهی پرسنل از Excel.
class PayrollEmployeeImportDialog extends StatefulWidget {
  final int businessId;

  const PayrollEmployeeImportDialog({super.key, required this.businessId});

  static Future<bool?> show(BuildContext context, {required int businessId}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => PayrollEmployeeImportDialog(businessId: businessId),
    );
  }

  @override
  State<PayrollEmployeeImportDialog> createState() => _PayrollEmployeeImportDialogState();
}

class _PayrollEmployeeImportDialogState extends State<PayrollEmployeeImportDialog> {
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
      final bytes = await _svc.downloadEmployeesTemplate(businessId: widget.businessId);
      const filename = 'payroll_employees_template.xlsx';
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
      final data = await _svc.importEmployeesExcel(
        businessId: widget.businessId,
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
      title: t.importFromExcel,
      icon: Icons.upload_file_outlined,
      maxWidth: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PayrollUi.infoBanner(context: context, message: t.payrollImportEmployeesHint),
          const SizedBox(height: 16),
          PayrollUi.importStepCard(
            context: context,
            icon: Icons.download_outlined,
            title: t.downloadTemplate,
            subtitle: t.payrollImportEmployeesHint,
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
                  Text('${t.payrollImportCreated}: ${PayrollUi.formatCount(_result!['created'] ?? 0)}'),
                  Text('${t.payrollImportUpdated}: ${PayrollUi.formatCount(_result!['updated'] ?? 0)}'),
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
