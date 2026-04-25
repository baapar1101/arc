import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../constants/report_template_constants.dart';
import '../../core/api_client.dart';
import '../../l10n/app_localizations.dart';
import '../../services/report_template_service.dart';
import '../../services/warehouse_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/web/web_utils.dart' as web_utils;

/// دیالوگ انتخاب سایز کاغذ، جهت، قالب و فیلدهای برگه مرسوله پستی حواله انبار.
Future<void> showWarehousePostalLabelPrintDialog({
  required BuildContext context,
  required int businessId,
  required int documentId,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _WarehousePostalLabelPrintDialog(
      businessId: businessId,
      documentId: documentId,
    ),
  );
}

class _WarehousePostalLabelPrintDialog extends StatefulWidget {
  final int businessId;
  final int documentId;

  const _WarehousePostalLabelPrintDialog({
    required this.businessId,
    required this.documentId,
  });

  @override
  State<_WarehousePostalLabelPrintDialog> createState() => _WarehousePostalLabelPrintDialogState();
}

class _WarehousePostalLabelPrintDialogState extends State<_WarehousePostalLabelPrintDialog> {
  final _templateService = ReportTemplateService(ApiClient());
  final _warehouseService = WarehouseService();
  final _customPaperCtrl = TextEditingController();

  bool _loadingTemplates = true;
  List<Map<String, dynamic>> _templates = const [];
  int? _selectedTemplateId;

  String _paperChoice = kWarehousePostalLabelPaperOptions.first;
  String _orientation = 'portrait';

  bool _showSender = true;
  bool _showReceiver = true;
  bool _showWarehouse = true;
  bool _showLines = true;
  bool _showDelivery = true;
  bool _showTracking = true;
  bool _showSource = true;

  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _customPaperCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() => _loadingTemplates = true);
    try {
      final list = await _templateService.listTemplates(
        businessId: widget.businessId,
        moduleKey: 'warehouse_documents',
        subtype: 'postal_label',
        status: 'published',
      );
      if (mounted) {
        setState(() {
          _templates = list;
          _loadingTemplates = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _templates = const [];
          _loadingTemplates = false;
        });
      }
    }
  }

  String _effectivePaperSize() {
    final c = _customPaperCtrl.text.trim();
    if (c.isNotEmpty) {
      return c.length > kReportTemplatePaperSizeMaxLength
          ? c.substring(0, kReportTemplatePaperSizeMaxLength)
          : c;
    }
    return _paperChoice;
  }

  Future<void> _download() async {
    final t = AppLocalizations.of(context);
    setState(() => _downloading = true);
    try {
      final query = <String, dynamic>{
        'paper_size': _effectivePaperSize(),
        'orientation': _orientation,
        'show_sender': _showSender ? 1 : 0,
        'show_receiver': _showReceiver ? 1 : 0,
        'show_warehouse': _showWarehouse ? 1 : 0,
        'show_lines': _showLines ? 1 : 0,
        'show_delivery': _showDelivery ? 1 : 0,
        'show_tracking': _showTracking ? 1 : 0,
        'show_source': _showSource ? 1 : 0,
      };
      if (_selectedTemplateId != null) {
        query['template_id'] = _selectedTemplateId;
      }
      final bytes = await _warehouseService.downloadPostalLabelPdf(
        businessId: widget.businessId,
        docId: widget.documentId,
        query: query,
      );
      if (!mounted) return;
      if (kIsWeb) {
        await web_utils.saveBytesAsFileWeb(
          bytes,
          'postal_label_${widget.documentId}.pdf',
          mimeType: 'application/pdf',
        );
        if (!mounted) return;
        SnackBarHelper.showSuccess(context, message: t.warehousePostalLabelDownload);
        Navigator.of(context).pop();
      } else {
        if (!mounted) return;
        SnackBarHelper.show(context, message: 'دانلود PDF در این پلتفرم پشتیبانی نشده است');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(t.warehousePostalLabelDialogTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.warehousePostalLabelPaperSize, style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _paperChoice,
                items: kWarehousePostalLabelPaperOptions
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _paperChoice = v);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _customPaperCtrl,
                decoration: InputDecoration(
                  labelText: t.warehousePostalLabelCustomPaperHint,
                  border: const OutlineInputBorder(),
                ),
                maxLength: kReportTemplatePaperSizeMaxLength,
                buildCounter: (ctx, {required currentLength, required isFocused, maxLength}) => null,
              ),
              const SizedBox(height: 12),
              Text(t.warehousePostalLabelOrientation, style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'portrait', label: Text(t.warehousePostalLabelPortrait)),
                  ButtonSegment(value: 'landscape', label: Text(t.warehousePostalLabelLandscape)),
                ],
                selected: {_orientation},
                onSelectionChanged: (s) {
                  setState(() => _orientation = s.first);
                },
              ),
              const SizedBox(height: 16),
              Text(t.warehousePostalLabelTemplate, style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              if (_loadingTemplates)
                const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
              else
                DropdownButtonFormField<int?>(
                  value: _selectedTemplateId,
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(t.warehousePostalLabelNoTemplate),
                    ),
                    ..._templates.map((tpl) {
                      final id = (tpl['id'] as num?)?.toInt();
                      final name = (tpl['name'] ?? '').toString();
                      return DropdownMenuItem<int?>(
                        value: id,
                        child: Text(name.isEmpty ? '#$id' : name),
                      );
                    }),
                  ],
                  onChanged: (v) => setState(() => _selectedTemplateId = v),
                ),
              const SizedBox(height: 16),
              Text(t.warehousePostalLabelFieldsSection, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              SwitchListTile(
                title: Text(t.warehousePostalLabelShowSender),
                value: _showSender,
                onChanged: (v) => setState(() => _showSender = v),
              ),
              SwitchListTile(
                title: Text(t.warehousePostalLabelShowReceiver),
                value: _showReceiver,
                onChanged: (v) => setState(() => _showReceiver = v),
              ),
              SwitchListTile(
                title: Text(t.warehousePostalLabelShowWarehouse),
                value: _showWarehouse,
                onChanged: (v) => setState(() => _showWarehouse = v),
              ),
              SwitchListTile(
                title: Text(t.warehousePostalLabelShowLines),
                value: _showLines,
                onChanged: (v) => setState(() => _showLines = v),
              ),
              SwitchListTile(
                title: Text(t.warehousePostalLabelShowDelivery),
                value: _showDelivery,
                onChanged: (v) => setState(() => _showDelivery = v),
              ),
              SwitchListTile(
                title: Text(t.warehousePostalLabelShowTracking),
                value: _showTracking,
                onChanged: (v) => setState(() => _showTracking = v),
              ),
              SwitchListTile(
                title: Text(t.warehousePostalLabelShowSource),
                value: _showSource,
                onChanged: (v) => setState(() => _showSource = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        FilledButton.icon(
          onPressed: _downloading ? null : _download,
          icon: _downloading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined),
          label: Text(t.warehousePostalLabelDownload),
        ),
      ],
    );
  }
}
