import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../services/payroll_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/data_table/helpers/file_saver.dart';
import '../../../widgets/person/file_picker_bridge.dart';

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
      await FileSaver.saveBytes(bytes, 'payroll_employees_template.xlsx');
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
    return AlertDialog(
      title: Text(t.importFromExcel),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.payrollImportEmployeesHint),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading ? null : _downloadTemplate,
              icon: const Icon(Icons.download_outlined),
              label: Text(t.downloadTemplate),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loading ? null : _pickFile,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(_file?.name ?? t.chooseFile),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.dryRun),
              value: _dryRun,
              onChanged: _loading ? null : (v) => setState(() => _dryRun = v),
            ),
            if (_result != null) ...[
              const Divider(),
              Text('${t.payrollImportCreated}: ${_result!['created'] ?? 0}'),
              Text('${t.payrollImportUpdated}: ${_result!['updated'] ?? 0}'),
              Text('${t.payrollImportErrorCount}: ${_result!['error_count'] ?? 0}'),
            ],
          ],
        ),
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
