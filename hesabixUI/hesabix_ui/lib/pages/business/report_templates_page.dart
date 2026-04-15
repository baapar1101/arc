import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../constants/report_template_constants.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../l10n/app_localizations.dart';
import '../../services/report_template_service.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/web/web_utils.dart' as web_utils;
import '../../widgets/data_table/helpers/file_saver.dart';
import '../../widgets/report_template/embedded_pdf_iframe.dart';
import 'report_template_visual_editor_page.dart';

class ReportTemplatesPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  const ReportTemplatesPage({super.key, required this.businessId, required this.authStore});

  @override
  State<ReportTemplatesPage> createState() => _ReportTemplatesPageState();
}

class _ReportTemplatesPageState extends State<ReportTemplatesPage> {
  late final ReportTemplateService _service;
  final _moduleCtrl = TextEditingController(text: 'invoices');
  final _subtypeCtrl = TextEditingController(text: 'list');
  String? _statusFilter; // draft/published/null

  bool _loading = false;
  List<Map<String, dynamic>> _items = const [];

  // Create/Edit form
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _htmlCtrl = TextEditingController(text: "<html><head></head><body><h3>{{ title_text }}</h3></body></html>");
  final _cssCtrl = TextEditingController(text: "body { font-family: Tahoma, Arial; }");
  final _headerCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();
  // Page settings
  String? _paperSize = 'A4'; // A4, Letter, ...
  String? _orientation = 'portrait'; // portrait, landscape
  final _marginTopCtrl = TextEditingController(text: '10');
  final _marginRightCtrl = TextEditingController(text: '10');
  final _marginBottomCtrl = TextEditingController(text: '10');
  final _marginLeftCtrl = TextEditingController(text: '10');
  /// اگر پر باشد، به‌جای مقدار کشوی «سایز صفحه» برای API استفاده می‌شود.
  final _paperCustomCtrl = TextEditingController();

  bool get _canWrite => widget.authStore.hasBusinessPermission('report_templates', 'write');

  /// فیلتر از پیش: all، انواع گزارش، یا custom برای ورود دستی module/subtype
  String _filterPresetId = 'invoices_list';

  void _applyScopePreset(String presetId) {
    setState(() {
      _filterPresetId = presetId;
      switch (presetId) {
        case 'all':
          _moduleCtrl.clear();
          _subtypeCtrl.clear();
          break;
        case 'invoices_list':
          _moduleCtrl.text = 'invoices';
          _subtypeCtrl.text = 'list';
          break;
        case 'invoices_detail':
          _moduleCtrl.text = 'invoices';
          _subtypeCtrl.text = 'detail';
          break;
        case 'receipts_payments_list':
          _moduleCtrl.text = 'receipts_payments';
          _subtypeCtrl.text = 'list';
          break;
        case 'receipts_payments_detail':
          _moduleCtrl.text = 'receipts_payments';
          _subtypeCtrl.text = 'detail';
          break;
        case 'expense_income_list':
          _moduleCtrl.text = 'expense_income';
          _subtypeCtrl.text = 'list';
          break;
        case 'documents_list':
          _moduleCtrl.text = 'documents';
          _subtypeCtrl.text = 'list';
          break;
        case 'documents_detail':
          _moduleCtrl.text = 'documents';
          _subtypeCtrl.text = 'detail';
          break;
        case 'transfers_list':
          _moduleCtrl.text = 'transfers';
          _subtypeCtrl.text = 'list';
          break;
        case 'transfers_detail':
          _moduleCtrl.text = 'transfers';
          _subtypeCtrl.text = 'detail';
          break;
        case 'custom':
          break;
      }
    });
    _fetch();
  }

  List<DropdownMenuItem<String>> _scopeDropdownItems(AppLocalizations t) {
    return [
      DropdownMenuItem(value: 'all', child: Text(t.reportTemplatesScopeAll)),
      DropdownMenuItem(value: 'invoices_list', child: Text(t.presetInvoicesList)),
      DropdownMenuItem(value: 'invoices_detail', child: Text(t.presetInvoicesDetail)),
      DropdownMenuItem(value: 'receipts_payments_list', child: Text(t.presetReceiptsPaymentsList)),
      DropdownMenuItem(value: 'receipts_payments_detail', child: Text(t.presetReceiptsPaymentsDetail)),
      DropdownMenuItem(value: 'expense_income_list', child: Text(t.presetExpenseIncomeList)),
      DropdownMenuItem(value: 'documents_list', child: Text(t.presetDocumentsList)),
      DropdownMenuItem(value: 'documents_detail', child: Text(t.presetDocumentsDetail)),
      DropdownMenuItem(value: 'transfers_list', child: Text(t.presetTransfersList)),
      DropdownMenuItem(value: 'transfers_detail', child: Text(t.presetTransfersDetail)),
      DropdownMenuItem(value: 'custom', child: Text(t.reportTemplatesScopeCustom)),
    ];
  }

  String _statusLabel(AppLocalizations t, String status) {
    if (status == 'published') return t.reportTemplateStatusPublished;
    if (status == 'draft') return t.reportTemplateStatusDraft;
    return status;
  }

  Map<String, dynamic>? _marginsFromFull(Map<String, dynamic> full) {
    final m = (full['margins'] as Map?)?.cast<String, dynamic>();
    if (m == null || m.isEmpty) return null;
    double? p(String k) {
      final v = m[k];
      if (v == null) return null;
      return double.tryParse(v.toString());
    }
    final map = <String, dynamic>{
      if (p('top') != null) 'top': p('top'),
      if (p('right') != null) 'right': p('right'),
      if (p('bottom') != null) 'bottom': p('bottom'),
      if (p('left') != null) 'left': p('left'),
    };
    return map.isEmpty ? null : map;
  }

  List<DropdownMenuItem<String>> _paperSizeDropdownItems(String? current) {
    return [
      ...kReportTemplatePaperSizeOptions.map(
        (e) => DropdownMenuItem<String>(value: e, child: Text(e)),
      ),
      if (current != null &&
          current.isNotEmpty &&
          !kReportTemplatePaperSizeOptions.contains(current))
        DropdownMenuItem<String>(value: current, child: Text(current)),
    ];
  }

  String _effectivePaperSize() {
    final c = _paperCustomCtrl.text.trim();
    if (c.isEmpty) return _paperSize ?? 'A4';
    return c.length > kReportTemplatePaperSizeMaxLength
        ? c.substring(0, kReportTemplatePaperSizeMaxLength)
        : c;
  }

  Future<void> _showExportPicker(AppLocalizations t) async {
    if (_items.isEmpty) {
      SnackBarHelper.show(context, message: t.reportTemplatePickExport);
      return;
    }
    int? selectedId = (_items.first['id'] as num?)?.toInt();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.reportTemplateExportJson),
          content: StatefulBuilder(
            builder: (ctx, setLocal) {
              return DropdownButtonFormField<int>(
                value: selectedId,
                decoration: InputDecoration(labelText: t.reportTemplatePickExport),
                items: _items
                    .map(
                      (it) => DropdownMenuItem<int>(
                        value: (it['id'] as num).toInt(),
                        child: Text(it['name']?.toString() ?? '-'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setLocal(() => selectedId = v),
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.reportTemplateExportJson)),
          ],
        );
      },
    );
    if (ok != true || selectedId == null || !mounted) return;
    Map<String, dynamic>? found;
    for (final e in _items) {
      if ((e['id'] as num).toInt() == selectedId) {
        found = e;
        break;
      }
    }
    if (found == null) return;
    await _exportTemplateJson(found, t);
  }

  Future<void> _exportTemplateJson(Map<String, dynamic> item, AppLocalizations t) async {
    try {
      final full = await _service.getTemplate(
        businessId: widget.businessId,
        templateId: (item['id'] as num).toInt(),
      );
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(t.reportTemplateExportThis),
            content: SizedBox(
              width: 700,
              height: 400,
              child: SingleChildScrollView(
                child: SelectableText(
                  JsonEncoder.withIndent('  ').convert({
                    'module_key': full['module_key'],
                    'subtype': full['subtype'],
                    'engine': full['engine'],
                    'name': full['name'],
                    'description': full['description'],
                    'content_html': full['content_html'],
                    'content_css': full['content_css'],
                    'header_html': full['header_html'],
                    'footer_html': full['footer_html'],
                    'paper_size': full['paper_size'],
                    'orientation': full['orientation'],
                    'margins': full['margins'],
                    'assets': full['assets'],
                  }),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.close)),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: '$e');
    }
  }

  Future<void> _importJsonFlow(AppLocalizations t) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.reportTemplateImportJson),
        content: SizedBox(
          width: 700,
          child: TextField(
            controller: ctrl,
            minLines: 10,
            maxLines: 18,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: t.reportTemplateImportJson,
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.create)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final data = jsonDecode(ctrl.text) as Map<String, dynamic>;
      setState(() {
        _filterPresetId = 'custom';
        _moduleCtrl.text = (data['module_key'] ?? _moduleCtrl.text).toString();
        _subtypeCtrl.text = (data['subtype'] ?? _subtypeCtrl.text).toString();
        _nameCtrl.text = (data['name'] ?? _nameCtrl.text).toString();
        _descCtrl.text = (data['description'] ?? _descCtrl.text).toString();
        _htmlCtrl.text = (data['content_html'] ?? _htmlCtrl.text).toString();
        _cssCtrl.text = (data['content_css'] ?? _cssCtrl.text).toString();
        _headerCtrl.text = (data['header_html'] ?? _headerCtrl.text).toString();
        _footerCtrl.text = (data['footer_html'] ?? _footerCtrl.text).toString();
        _paperSize = (data['paper_size'] ?? _paperSize)?.toString();
        _paperCustomCtrl.clear();
        _orientation = (data['orientation'] ?? _orientation)?.toString();
        final margins = (data['margins'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        _marginTopCtrl.text = (margins['top']?.toString() ?? _marginTopCtrl.text);
        _marginRightCtrl.text = (margins['right']?.toString() ?? _marginRightCtrl.text);
        _marginBottomCtrl.text = (margins['bottom']?.toString() ?? _marginBottomCtrl.text);
        _marginLeftCtrl.text = (margins['left']?.toString() ?? _marginLeftCtrl.text);
      });
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.reportTemplateImportDoneOpenHtml);
      await _createDialog();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: t.reportTemplateInvalidJsonError('$e'));
    }
  }

  @override
  void initState() {
    super.initState();
    _service = ReportTemplateService(ApiClient());
    _fetch();
  }

  @override
  void dispose() {
    _moduleCtrl.dispose();
    _subtypeCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _htmlCtrl.dispose();
    _cssCtrl.dispose();
    _headerCtrl.dispose();
    _footerCtrl.dispose();
    _marginTopCtrl.dispose();
    _marginRightCtrl.dispose();
    _marginBottomCtrl.dispose();
    _marginLeftCtrl.dispose();
    _paperCustomCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final items = await _service.listTemplates(
        businessId: widget.businessId,
        moduleKey: _moduleCtrl.text.trim().isEmpty ? null : _moduleCtrl.text.trim(),
        subtype: _subtypeCtrl.text.trim().isEmpty ? null : _subtypeCtrl.text.trim(),
        status: _statusFilter,
      );
      if (mounted) {
        setState(() => _items = items);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: AppLocalizations.of(context).reportTemplatesLoadError('$e'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createDialog() async {
    final t = AppLocalizations.of(context);
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.reportTemplateNewHtml),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(labelText: t.reportTemplateFieldName),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descCtrl,
                    decoration: InputDecoration(labelText: t.reportTemplateFieldDescription),
                  ),
                  const SizedBox(height: 12),
                  Text(t.reportTemplatePageSettingsSection, style: Theme.of(context).textTheme.titleSmall),
                  Row(
                    children: [
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<String>(
                          value: _paperSize,
                          decoration: InputDecoration(
                            labelText: t.pageSize,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          items: _paperSizeDropdownItems(_paperSize),
                          onChanged: (v) => setState(() => _paperSize = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<String>(
                          value: _orientation,
                          decoration: InputDecoration(
                            labelText: t.orientation,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(value: 'portrait', child: Text(t.portrait)),
                            DropdownMenuItem(value: 'landscape', child: Text(t.landscape)),
                          ],
                          onChanged: (v) => setState(() => _orientation = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginTopCtrl,
                                decoration: InputDecoration(
                                  labelText: t.marginTop,
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginRightCtrl,
                                decoration: InputDecoration(
                                  labelText: t.marginRight,
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginBottomCtrl,
                                decoration: InputDecoration(
                                  labelText: t.marginBottom,
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginLeftCtrl,
                                decoration: InputDecoration(
                                  labelText: t.marginLeft,
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _paperCustomCtrl,
                    maxLength: kReportTemplatePaperSizeMaxLength,
                    decoration: InputDecoration(
                      labelText: t.reportTemplatePaperCustomLabel,
                      helperText: t.reportTemplatePaperCustomHelper,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DefaultTabController(
                    length: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TabBar(
                          labelColor: Theme.of(context).colorScheme.primary,
                          tabs: [
                            Tab(text: t.reportTemplatePreviewHtmlTab),
                            Tab(text: t.reportTemplateEditorTabCss),
                            Tab(text: t.reportTemplateEditorTabHeader),
                            Tab(text: t.reportTemplateEditorTabFooter),
                          ],
                        ),
                        SizedBox(
                          height: 320,
                          child: TabBarView(
                            children: [
                              TextField(
                                controller: _htmlCtrl,
                                maxLines: 14,
                                decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  hintText: t.reportTemplateHintHtmlBody,
                                ),
                              ),
                              TextField(
                                controller: _cssCtrl,
                                maxLines: 14,
                                decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  hintText: t.reportTemplateHintCss,
                                ),
                              ),
                              TextField(
                                controller: _headerCtrl,
                                maxLines: 14,
                                decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  hintText: t.reportTemplateHintHeaderHtml,
                                ),
                              ),
                              TextField(
                                controller: _footerCtrl,
                                maxLines: 14,
                                decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  hintText: t.reportTemplateHintFooterHtml,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            FilledButton(
              onPressed: () async {
                try {
                  Map<String, dynamic>? margins;
                  double? _parse(String s) {
                    try {
                      if (s.trim().isEmpty) return null;
                      return double.parse(s.trim());
                    } catch (_) {
                      return null;
                    }
                  }
                  final mt = _parse(_marginTopCtrl.text);
                  final mr = _parse(_marginRightCtrl.text);
                  final mb = _parse(_marginBottomCtrl.text);
                  final ml = _parse(_marginLeftCtrl.text);
                  margins = {
                    if (mt != null) 'top': mt,
                    if (mr != null) 'right': mr,
                    if (mb != null) 'bottom': mb,
                    if (ml != null) 'left': ml,
                  };
                  if (margins.isEmpty) margins = null;
                  final id = await _service.createTemplate(
                    businessId: widget.businessId,
                    moduleKey: _moduleCtrl.text.trim().isEmpty ? 'invoices' : _moduleCtrl.text.trim(),
                    subtype: _subtypeCtrl.text.trim().isEmpty ? 'list' : _subtypeCtrl.text.trim(),
                    name: _nameCtrl.text.trim().isEmpty ? 'Template' : _nameCtrl.text.trim(),
                    description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
                    contentHtml: _htmlCtrl.text,
                    contentCss: _cssCtrl.text.trim().isEmpty ? null : _cssCtrl.text,
                    headerHtml: _headerCtrl.text.trim().isEmpty ? null : _headerCtrl.text,
                    footerHtml: _footerCtrl.text.trim().isEmpty ? null : _footerCtrl.text,
                    paperSize: _effectivePaperSize(),
                    orientation: _orientation,
                    margins: margins,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  SnackBarHelper.showSuccess(ctx, message: t.templateCreatedWithId(id));
                  await _fetch();
                } catch (e) {
                  if (!ctx.mounted) return;
                  SnackBarHelper.showError(ctx, message: t.createError(e.toString()));
                }
              },
              child: Text(t.create),
            ),
          ],
        );
      },
    );
  }

  Future<void> _togglePublish(Map<String, dynamic> item) async {
    final published = (item['status'] == 'published');
    final next = !published;
    await _service.publish(
      businessId: widget.businessId,
      templateId: (item['id'] as num).toInt(),
      published: next,
    );
    await _fetch();
  }

  Future<void> _previewTemplate(Map<String, dynamic> item) async {
    final t = AppLocalizations.of(context);
    var loadingOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => const AlertDialog(
        content: SizedBox(
          width: 72,
          height: 72,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );
    Map<String, dynamic>? builderDesign;
    Map<String, dynamic>? builderAssets;
    try {
      final full = await _service.getTemplate(
        businessId: widget.businessId,
        templateId: (item['id'] as num).toInt(),
      );
      final engine = (full['engine'] ?? 'jinja2').toString().toLowerCase();
      final Map<String, dynamic> res;
      if (engine == 'builder') {
        builderAssets = (full['assets'] as Map?)?.cast<String, dynamic>() ?? {};
        builderDesign = (builderAssets['builder_design'] as Map?)?.cast<String, dynamic>();
        if (builderDesign == null) {
          throw StateError(t.reportTemplateBuilderDesignEmpty);
        }
        res = await _service.preview(
          businessId: widget.businessId,
          engine: 'builder',
          design: builderDesign,
          assets: builderAssets,
          context: const <String, dynamic>{},
        );
      } else {
        res = await _service.preview(
          businessId: widget.businessId,
          contentHtml: (full['content_html'] ?? '').toString(),
          contentCss: (full['content_css'] ?? '').toString().isEmpty ? null : (full['content_css'] ?? '').toString(),
          headerHtml: (full['header_html'] ?? '').toString().isEmpty ? null : (full['header_html'] ?? '').toString(),
          footerHtml: (full['footer_html'] ?? '').toString().isEmpty ? null : (full['footer_html'] ?? '').toString(),
          context: const <String, dynamic>{},
        );
      }

      List<int>? pdfBytes;
      var pdfFetchFailed = false;
      try {
        final marginsMap = _marginsFromFull(full);
        if (engine == 'builder' && builderDesign != null) {
          pdfBytes = await _service.previewPdf(
            businessId: widget.businessId,
            engine: 'builder',
            design: builderDesign,
            assets: builderAssets,
            context: const <String, dynamic>{},
            paperSize: full['paper_size']?.toString(),
            orientation: full['orientation']?.toString(),
            margins: marginsMap,
          );
        } else {
          pdfBytes = await _service.previewPdf(
            businessId: widget.businessId,
            contentHtml: (full['content_html'] ?? '').toString(),
            contentCss: (full['content_css'] ?? '').toString().isEmpty ? null : (full['content_css'] ?? '').toString(),
            headerHtml: (full['header_html'] ?? '').toString().isEmpty ? null : (full['header_html'] ?? '').toString(),
            footerHtml: (full['footer_html'] ?? '').toString().isEmpty ? null : (full['footer_html'] ?? '').toString(),
            paperSize: full['paper_size']?.toString(),
            orientation: full['orientation']?.toString(),
            margins: marginsMap,
          );
        }
      } catch (_) {
        pdfFetchFailed = true;
        pdfBytes = null;
      }

      if (mounted && loadingOpen) {
        Navigator.of(context).pop();
        loadingOpen = false;
      }
      final html = (res['html'] ?? '').toString();
      final lenFromPreview = res['content_length'] ?? 0;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return DefaultTabController(
            length: 2,
            child: AlertDialog(
              title: Text(t.reportTemplatePreviewTitle),
              content: SizedBox(
                width: 720,
                height: 480,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TabBar(
                      tabs: [
                        Tab(text: t.reportTemplatePreviewHtmlTab),
                        Tab(text: t.reportTemplatePreviewPdfTab),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          SingleChildScrollView(
                            child: SelectableText(html.isEmpty ? '—' : html),
                          ),
                          _listPreviewPdfPane(
                            t,
                            pdfBytes,
                            lenFromPreview,
                            pdfFetchFailed,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.close)),
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        if (loadingOpen) {
          Navigator.of(context).pop();
          loadingOpen = false;
        }
        SnackBarHelper.showError(context, message: t.reportTemplatePreviewError('$e'));
      }
    }
  }

  Widget _listPreviewPdfPane(
    AppLocalizations t,
    List<int>? pdfBytes,
    int fallbackLen,
    bool pdfFetchFailed,
  ) {
    if (pdfBytes != null && pdfBytes.isNotEmpty) {
      final u8 = Uint8List.fromList(pdfBytes);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t.reportTemplatePreviewPdfBytes('${pdfBytes.length}'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    try {
                      if (kIsWeb) {
                        await web_utils.saveBytesAsFileWeb(
                          pdfBytes,
                          'report_preview.pdf',
                          mimeType: 'application/pdf',
                        );
                        if (mounted) {
                          SnackBarHelper.show(context, message: t.reportTemplatePdfDownloadStarted);
                        }
                      } else {
                        final path = await FileSaver.saveBytes(pdfBytes, 'report_preview.pdf');
                        if (mounted) {
                          SnackBarHelper.show(
                            context,
                            message: path != null ? t.reportTemplatePdfSavedToPath(path) : t.reportTemplatePdfSavedGeneric,
                          );
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        SnackBarHelper.showError(context, message: '$e');
                      }
                    }
                  },
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(t.reportTemplateDownload),
                ),
                if (kIsWeb)
                  TextButton.icon(
                    onPressed: () {
                      final url = web_utils.createObjectUrlFromBytes(
                        pdfBytes,
                        mimeType: 'application/pdf',
                      );
                      web_utils.openUrlInNewTabWeb(url);
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(t.reportTemplateOpenInNewTab),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SizedBox.expand(
              child: ReportTemplateEmbeddedPdf(bytes: u8),
            ),
          ),
        ],
      );
    }
    final msg = pdfFetchFailed
        ? '${t.reportTemplatePreviewPdfBytes('$fallbackLen')}\n${t.reportTemplatePdfInlineFailedHint}'
        : t.reportTemplatePreviewPdfBytes('$fallbackLen');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(msg, textAlign: TextAlign.center),
      ),
    );
  }

  Future<void> _editDialog(Map<String, dynamic> item) async {
    Map<String, dynamic> full = const <String, dynamic>{};
    bool isBuilder = false;
    try {
      full = await _service.getTemplate(
        businessId: widget.businessId,
        templateId: (item['id'] as num).toInt(),
      );
      isBuilder = (full['engine'] ?? '').toString() == 'builder';
      _nameCtrl.text = (full['name'] ?? '').toString();
      _descCtrl.text = (full['description'] ?? '').toString();
      _htmlCtrl.text = (full['content_html'] ?? '').toString();
      _cssCtrl.text = (full['content_css'] ?? '').toString();
      _headerCtrl.text = (full['header_html'] ?? '').toString();
      _footerCtrl.text = (full['footer_html'] ?? '').toString();
      _paperSize = (full['paper_size'] ?? _paperSize)?.toString();
      _orientation = (full['orientation'] ?? _orientation)?.toString();
      _paperCustomCtrl.clear();
      final margins = (full['margins'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      _marginTopCtrl.text = (margins['top']?.toString() ?? _marginTopCtrl.text);
      _marginRightCtrl.text = (margins['right']?.toString() ?? _marginRightCtrl.text);
      _marginBottomCtrl.text = (margins['bottom']?.toString() ?? _marginBottomCtrl.text);
      _marginLeftCtrl.text = (margins['left']?.toString() ?? _marginLeftCtrl.text);
    } catch (_) {}

    if (!mounted) return;
    if (isBuilder) {
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => ReportTemplateVisualEditorPage(
            businessId: widget.businessId,
            authStore: widget.authStore,
            template: item,
            moduleKey: full['module_key']?.toString(),
            subtype: full['subtype']?.toString(),
          ),
        ),
      );
      if (result == true && mounted) await _fetch();
      return;
    }

    final ctx = context;
    final tEdit = AppLocalizations.of(context);
    await showDialog(
      context: ctx,
      builder: (ctx) {
        return AlertDialog(
          title: Text(tEdit.reportTemplateEdit),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(labelText: tEdit.reportTemplateFieldName),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descCtrl,
                    decoration: InputDecoration(labelText: tEdit.reportTemplateFieldDescription),
                  ),
                  const SizedBox(height: 12),
                  Text(tEdit.reportTemplatePageSettingsSection, style: Theme.of(context).textTheme.titleSmall),
                  Row(
                    children: [
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<String>(
                          value: _paperSize,
                          decoration: InputDecoration(
                            labelText: tEdit.pageSize,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          items: _paperSizeDropdownItems(_paperSize),
                          onChanged: (v) => setState(() => _paperSize = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<String>(
                          value: _orientation,
                          decoration: InputDecoration(
                            labelText: tEdit.orientation,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(value: 'portrait', child: Text(tEdit.portrait)),
                            DropdownMenuItem(value: 'landscape', child: Text(tEdit.landscape)),
                          ],
                          onChanged: (v) => setState(() => _orientation = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginTopCtrl,
                                decoration: InputDecoration(
                                  labelText: tEdit.marginTop,
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginRightCtrl,
                                decoration: InputDecoration(
                                  labelText: tEdit.marginRight,
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginBottomCtrl,
                                decoration: InputDecoration(
                                  labelText: tEdit.marginBottom,
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginLeftCtrl,
                                decoration: InputDecoration(
                                  labelText: tEdit.marginLeft,
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _paperCustomCtrl,
                    maxLength: kReportTemplatePaperSizeMaxLength,
                    decoration: InputDecoration(
                      labelText: tEdit.reportTemplatePaperCustomLabel,
                      helperText: tEdit.reportTemplatePaperCustomHelper,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DefaultTabController(
                    length: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TabBar(
                          labelColor: Theme.of(context).colorScheme.primary,
                          tabs: [
                            Tab(text: tEdit.reportTemplatePreviewHtmlTab),
                            Tab(text: tEdit.reportTemplateEditorTabCss),
                            Tab(text: tEdit.reportTemplateEditorTabHeader),
                            Tab(text: tEdit.reportTemplateEditorTabFooter),
                          ],
                        ),
                        SizedBox(
                          height: 320,
                          child: TabBarView(
                            children: [
                              TextField(
                                controller: _htmlCtrl,
                                maxLines: 14,
                                decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  hintText: tEdit.reportTemplateHintHtmlBody,
                                ),
                              ),
                              TextField(
                                controller: _cssCtrl,
                                maxLines: 14,
                                decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  hintText: tEdit.reportTemplateHintCss,
                                ),
                              ),
                              TextField(
                                controller: _headerCtrl,
                                maxLines: 14,
                                decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  hintText: tEdit.reportTemplateHintHeaderHtml,
                                ),
                              ),
                              TextField(
                                controller: _footerCtrl,
                                maxLines: 14,
                                decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  hintText: tEdit.reportTemplateHintFooterHtml,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tEdit.cancel)),
            TextButton(
              onPressed: () async {
                await _previewTemplate(item);
              },
              child: Text(tEdit.reportTemplatePreview),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  Map<String, dynamic>? margins;
                  double? _parse(String s) {
                    try {
                      if (s.trim().isEmpty) return null;
                      return double.parse(s.trim());
                    } catch (_) {
                      return null;
                    }
                  }
                  final mt = _parse(_marginTopCtrl.text);
                  final mr = _parse(_marginRightCtrl.text);
                  final mb = _parse(_marginBottomCtrl.text);
                  final ml = _parse(_marginLeftCtrl.text);
                  margins = {
                    if (mt != null) 'top': mt,
                    if (mr != null) 'right': mr,
                    if (mb != null) 'bottom': mb,
                    if (ml != null) 'left': ml,
                  };
                  if (margins.isEmpty) margins = null;
                  final changes = <String, dynamic>{
                    'name': _nameCtrl.text.trim(),
                    'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
                    'content_html': _htmlCtrl.text,
                    'content_css': _cssCtrl.text.trim().isEmpty ? null : _cssCtrl.text,
                    'header_html': _headerCtrl.text.trim().isEmpty ? null : _headerCtrl.text,
                    'footer_html': _footerCtrl.text.trim().isEmpty ? null : _footerCtrl.text,
                    'paper_size': _effectivePaperSize(),
                    'orientation': _orientation,
                    if (margins != null) 'margins': margins,
                  };
                  await _service.updateTemplate(
                    businessId: widget.businessId,
                    templateId: (item['id'] as num).toInt(),
                    changes: changes,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  await _fetch();
                } catch (e) {
                  if (!ctx.mounted) return;
                  SnackBarHelper.showError(ctx, message: tEdit.reportTemplateEditSaveError('$e'));
                }
              },
              child: Text(tEdit.save),
            ),
          ],
        );
      },
    );
  }

  Future<void> _setDefault(Map<String, dynamic> item) async {
    final loc = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.reportTemplateSetDefaultTitle),
        content: Text(loc.reportTemplateSetDefaultMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(loc.confirm)),
        ],
      ),
    );
    if (ok != true) return;
    final mk = (item['module_key'] ?? '').toString().trim();
    final stRaw = item['subtype'];
    final String? st = stRaw == null ? null : stRaw.toString().trim().isEmpty ? null : stRaw.toString().trim();
    await _service.setDefault(
      businessId: widget.businessId,
      moduleKey: mk.isEmpty ? 'invoices' : mk,
      subtype: st,
      templateId: (item['id'] as num).toInt(),
    );
    await _fetch();
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final loc = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.reportTemplateDeleteConfirmTitle),
        content: Text(loc.reportTemplateDeleteConfirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(loc.reportTemplateDelete)),
        ],
      ),
    );
    if (ok != true) return;
    await _service.deleteTemplate(
      businessId: widget.businessId,
      templateId: (item['id'] as num).toInt(),
    );
    await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.templates),
        actions: [
          if (_canWrite) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: FilledButton.icon(
                onPressed: () async {
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (context) => ReportTemplateVisualEditorPage(
                        businessId: widget.businessId,
                        authStore: widget.authStore,
                        moduleKey: _moduleCtrl.text.trim().isEmpty ? null : _moduleCtrl.text.trim(),
                        subtype: _subtypeCtrl.text.trim().isEmpty ? null : _subtypeCtrl.text.trim(),
                      ),
                    ),
                  );
                  if (result == true && mounted) await _fetch();
                },
                icon: const Icon(Icons.view_quilt),
                label: Text(t.reportTemplateNewVisual),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: OutlinedButton.icon(
                onPressed: _createDialog,
                icon: const Icon(Icons.code),
                label: Text(t.reportTemplateNewHtml),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: t.reportTemplateMoreMenu,
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'export', child: Text(t.reportTemplateExportJson)),
                PopupMenuItem(value: 'import', child: Text(t.reportTemplateImportJson)),
              ],
              onSelected: (v) {
                if (v == 'export') {
                  _showExportPicker(t);
                } else if (v == 'import') {
                  _importJsonFlow(t);
                }
              },
            ),
          ],
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _filterPresetId,
                    decoration: InputDecoration(
                      labelText: t.reportTemplatesFilterScopeLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    isExpanded: true,
                    items: _scopeDropdownItems(t),
                    onChanged: (v) {
                      if (v != null) _applyScopePreset(v);
                    },
                  ),
                ),
                if (_filterPresetId == 'custom') ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 130,
                    child: Tooltip(
                      message: t.reportTemplateModuleKeyTooltip,
                      child: TextField(
                        controller: _moduleCtrl,
                        decoration: InputDecoration(
                          labelText: t.reportTemplateModuleKeyLabel,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _fetch(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: Tooltip(
                      message: t.reportTemplateSubtypeTooltip,
                      child: TextField(
                        controller: _subtypeCtrl,
                        decoration: InputDecoration(
                          labelText: t.reportTemplateSubtypeLabel,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _fetch(),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    if (!context.mounted) return;
                    final ctx = context;
                    try {
                      final data = await _service.schema(
                        businessId: widget.businessId,
                        moduleKey: _moduleCtrl.text.trim().isEmpty ? 'invoices' : _moduleCtrl.text.trim(),
                        subtype: _subtypeCtrl.text.trim().isEmpty ? null : _subtypeCtrl.text.trim(),
                      );
                      if (!ctx.mounted) return;
                      final keys = (data['keys'] as List? ?? const []).cast<Map>();
                      await showDialog(
                        context: ctx,
                        builder: (dctx) {
                          final loc = AppLocalizations.of(dctx);
                          return AlertDialog(
                            title: Text(loc.reportTemplatePlaceholdersTitle),
                            content: SizedBox(
                              width: 500,
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: keys.map((m) {
                                    final name = (m['name'] ?? '').toString();
                                    final desc = (m['desc'] ?? '').toString();
                                    return ListTile(
                                      dense: true,
                                      title: Text(name),
                                      subtitle: desc.isNotEmpty ? Text(desc) : null,
                                      trailing: IconButton(
                                        tooltip: loc.reportTemplateCopyPlaceholder,
                                        icon: const Icon(Icons.copy),
                                        onPressed: () async {
                                          await Clipboard.setData(ClipboardData(text: '{{ $name }}'));
                                          _htmlCtrl.text += '{{ $name }}';
                                          if (dctx.mounted) {
                                            SnackBarHelper.show(dctx, message: loc.reportTemplateCopied);
                                          }
                                        },
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dctx), child: Text(loc.close)),
                            ],
                          );
                        },
                      );
                    } catch (e) {
                      if (!ctx.mounted) return;
                      SnackBarHelper.showError(ctx, message: t.reportTemplatesSchemaFetchError('$e'));
                    }
                  },
                  icon: const Icon(Icons.help_outline),
                  label: Text(t.reportTemplateVariablesHelpButton),
                ),
                const SizedBox(width: 8),
                DropdownButton<String?>(
                  value: _statusFilter,
                  hint: Text(t.reportTemplateStatusFilterHint),
                  items: [
                    DropdownMenuItem(value: null, child: Text(t.all)),
                    DropdownMenuItem(value: 'published', child: Text(t.reportTemplateStatusPublished)),
                    DropdownMenuItem(value: 'draft', child: Text(t.reportTemplateStatusDraft)),
                  ],
                  onChanged: (v) {
                    setState(() => _statusFilter = v);
                    _fetch();
                  },
                ),
                const Spacer(),
                IconButton(onPressed: _fetch, icon: const Icon(Icons.refresh)),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: Text(t.presetInvoicesList),
                    onPressed: () => _applyScopePreset('invoices_list'),
                  ),
                  ActionChip(
                    label: Text(t.presetInvoicesDetail),
                    onPressed: () => _applyScopePreset('invoices_detail'),
                  ),
                  ActionChip(
                    label: Text(t.presetReceiptsPaymentsList),
                    onPressed: () => _applyScopePreset('receipts_payments_list'),
                  ),
                  ActionChip(
                    label: Text(t.presetReceiptsPaymentsDetail),
                    onPressed: () => _applyScopePreset('receipts_payments_detail'),
                  ),
                  ActionChip(
                    label: Text(t.presetExpenseIncomeList),
                    onPressed: () => _applyScopePreset('expense_income_list'),
                  ),
                  ActionChip(
                    label: Text(t.presetDocumentsList),
                    onPressed: () => _applyScopePreset('documents_list'),
                  ),
                  ActionChip(
                    label: Text(t.presetDocumentsDetail),
                    onPressed: () => _applyScopePreset('documents_detail'),
                  ),
                  ActionChip(
                    label: Text(t.presetTransfersList),
                    onPressed: () => _applyScopePreset('transfers_list'),
                  ),
                  ActionChip(
                    label: Text(t.presetTransfersDetail),
                    onPressed: () => _applyScopePreset('transfers_detail'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(child: Text(t.reportTemplatesEmptyList))
                      : Card(
                          clipBehavior: Clip.antiAlias,
                          child: ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (ctx, idx) {
                              final it = _items[idx];
                              final isDefault = it['is_default'] == true;
                              final status = (it['status'] ?? '').toString();
                              final updated = it['updated_at']?.toString() ?? '';
                              return ListTile(
                                title: Text(it['name']?.toString() ?? '-'),
                                isThreeLine: true,
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        Chip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text(_statusLabel(t, status)),
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        if (isDefault)
                                          Chip(
                                            visualDensity: VisualDensity.compact,
                                            avatar: const Icon(Icons.star, size: 16),
                                            label: Text(t.reportTemplateDefaultBadge),
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${it['module_key'] ?? '-'} / ${it['subtype'] ?? '—'} · v${it['version'] ?? '-'}'
                                      '${updated.isNotEmpty ? ' · $updated' : ''}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                                leading: Icon(isDefault ? Icons.star : Icons.description),
                                trailing: _canWrite
                                    ? PopupMenuButton<String>(
                                        tooltip: t.reportTemplateRowActions,
                                        itemBuilder: (pmCtx) => [
                                          PopupMenuItem(
                                            value: 'preview',
                                            child: ListTile(
                                              leading: const Icon(Icons.visibility),
                                              title: Text(t.reportTemplatePreview),
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: ListTile(
                                              leading: const Icon(Icons.edit),
                                              title: Text(t.reportTemplateEdit),
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'publish',
                                            child: ListTile(
                                              leading: Icon(status == 'published' ? Icons.visibility_off : Icons.publish),
                                              title: Text(status == 'published' ? t.reportTemplateUnpublish : t.reportTemplatePublish),
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'default',
                                            child: ListTile(
                                              leading: const Icon(Icons.star_outline),
                                              title: Text(t.reportTemplateSetDefault),
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'export',
                                            child: ListTile(
                                              leading: const Icon(Icons.file_download_outlined),
                                              title: Text(t.reportTemplateExportThis),
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: ListTile(
                                              leading: const Icon(Icons.delete_outline),
                                              title: Text(t.reportTemplateDelete),
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                        ],
                                        onSelected: (v) {
                                          switch (v) {
                                            case 'preview':
                                              _previewTemplate(it);
                                              break;
                                            case 'edit':
                                              _editDialog(it);
                                              break;
                                            case 'publish':
                                              _togglePublish(it);
                                              break;
                                            case 'default':
                                              _setDefault(it);
                                              break;
                                            case 'export':
                                              _exportTemplateJson(it, t);
                                              break;
                                            case 'delete':
                                              _delete(it);
                                              break;
                                          }
                                        },
                                      )
                                    : null,
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

}

