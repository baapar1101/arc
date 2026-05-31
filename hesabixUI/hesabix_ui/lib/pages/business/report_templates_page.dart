import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../constants/report_template_constants.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../l10n/app_localizations.dart';
import '../../services/report_template_service.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/web/web_utils.dart' as web_utils;
import '../../widgets/data_table/helpers/file_saver.dart';
import '../../widgets/report_template/embedded_pdf_iframe.dart';
import 'report_template_visual_editor_page.dart';
import '../../widgets/business_subpage_back_leading.dart';

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
  final _searchCtrl = TextEditingController();
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
  bool get _canApprove => widget.authStore.hasBusinessPermission('report_templates', 'approve');
  bool get _canAudit =>
      widget.authStore.hasBusinessPermission('report_templates', 'approve') ||
      widget.authStore.hasBusinessPermission('report_templates', 'export');

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
        case 'warehouse_postal_label':
          _moduleCtrl.text = 'warehouse_documents';
          _subtypeCtrl.text = 'postal_label';
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
      DropdownMenuItem(value: 'warehouse_postal_label', child: Text(t.presetWarehousePostalLabel)),
      DropdownMenuItem(value: 'custom', child: Text(t.reportTemplatesScopeCustom)),
    ];
  }

  String _statusLabel(AppLocalizations t, String status) {
    if (status == 'published') return t.reportTemplateStatusPublished;
    if (status == 'draft') return t.reportTemplateStatusDraft;
    if (status == 'in_review') return 'در انتظار بررسی';
    if (status == 'approved') return 'تایید شده';
    if (status == 'deprecated') return 'منسوخ';
    return status;
  }

  String _statusFlowLabel(String? status) {
    final s = (status ?? '').trim();
    if (s == 'draft') return 'پیش‌نویس';
    if (s == 'in_review') return 'در انتظار بررسی';
    if (s == 'approved') return 'تایید شده';
    if (s == 'published') return 'منتشر شده';
    if (s == 'deprecated') return 'منسوخ';
    return s.isEmpty ? '—' : s;
  }

  String _scopeLabel(AppLocalizations t, String moduleKey, String? subtype) {
    final st = (subtype ?? '').trim();
    if (moduleKey == 'invoices' && st == 'list') return t.presetInvoicesList;
    if (moduleKey == 'invoices' && st == 'detail') return t.presetInvoicesDetail;
    if (moduleKey == 'receipts_payments' && st == 'list') return t.presetReceiptsPaymentsList;
    if (moduleKey == 'receipts_payments' && st == 'detail') return t.presetReceiptsPaymentsDetail;
    if (moduleKey == 'expense_income' && st == 'list') return t.presetExpenseIncomeList;
    if (moduleKey == 'documents' && st == 'list') return t.presetDocumentsList;
    if (moduleKey == 'documents' && st == 'detail') return t.presetDocumentsDetail;
    if (moduleKey == 'transfers' && st == 'list') return t.presetTransfersList;
    if (moduleKey == 'transfers' && st == 'detail') return t.presetTransfersDetail;
    if (moduleKey == 'warehouse_documents' && st == 'postal_label') return t.presetWarehousePostalLabel;
    return '$moduleKey / ${st.isEmpty ? '—' : st}';
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
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
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
      if (mounted) {
        SnackBarHelper.showError(
        context,
        message: t.reportTemplateInvalidJsonError(ErrorExtractor.forContext(e, context)),
      );
      }
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
    _searchCtrl.dispose();
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

  List<Map<String, dynamic>> get _filteredItems {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items.where((item) {
      final text = '${item['name'] ?? ''} ${item['description'] ?? ''} ${item['module_key'] ?? ''} ${item['subtype'] ?? ''}'.toLowerCase();
      return text.contains(query);
    }).toList();
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
          message: AppLocalizations.of(context).reportTemplatesLoadError(
            ErrorExtractor.forContext(e, context),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// موبایل: کوچک‌ترین ضلع کمتر از ۶۰۰ → ادیتور تمام‌صفحه.
  bool _reportHtmlEditorUseFullscreenLayout(BuildContext context) {
    return MediaQuery.sizeOf(context).shortestSide < 600;
  }

  TextStyle? _reportHtmlCodeStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium;
    return base?.copyWith(fontFamily: 'monospace', fontSize: 13, height: 1.4);
  }

  List<TextInputFormatter> get _reportHtmlMarginInputFormatters => [
        EnglishDigitsFormatter(),
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ];

  Widget _reportHtmlCodeEditorField({
    required BuildContext context,
    required TextEditingController controller,
    required String hintText,
  }) {
    return TextField(
      controller: controller,
      style: _reportHtmlCodeStyle(context),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: hintText,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        alignLabelWithHint: true,
        isDense: true,
        contentPadding: const EdgeInsets.all(12),
      ),
      maxLines: null,
      minLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      keyboardType: TextInputType.multiline,
    );
  }

  Widget _reportHtmlEditorPageSettingsForm(BuildContext context, AppLocalizations t) {
    const marginDec = InputDecoration(
      isDense: true,
      border: OutlineInputBorder(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
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
            Expanded(
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
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _marginTopCtrl,
                decoration: marginDec.copyWith(labelText: t.marginTop),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _reportHtmlMarginInputFormatters,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _marginRightCtrl,
                decoration: marginDec.copyWith(labelText: t.marginRight),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _reportHtmlMarginInputFormatters,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _marginBottomCtrl,
                decoration: marginDec.copyWith(labelText: t.marginBottom),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _reportHtmlMarginInputFormatters,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _marginLeftCtrl,
                decoration: marginDec.copyWith(labelText: t.marginLeft),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _reportHtmlMarginInputFormatters,
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
      ],
    );
  }

  Widget _reportHtmlEditorCodeTabs(BuildContext context, AppLocalizations t) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            isScrollable: true,
            labelColor: cs.primary,
            tabs: [
              Tab(text: t.reportTemplatePreviewHtmlTab),
              Tab(text: t.reportTemplateEditorTabCss),
              Tab(text: t.reportTemplateEditorTabHeader),
              Tab(text: t.reportTemplateEditorTabFooter),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _reportHtmlCodeEditorField(
                  context: context,
                  controller: _htmlCtrl,
                  hintText: t.reportTemplateHintHtmlBody,
                ),
                _reportHtmlCodeEditorField(
                  context: context,
                  controller: _cssCtrl,
                  hintText: t.reportTemplateHintCss,
                ),
                _reportHtmlCodeEditorField(
                  context: context,
                  controller: _headerCtrl,
                  hintText: t.reportTemplateHintHeaderHtml,
                ),
                _reportHtmlCodeEditorField(
                  context: context,
                  controller: _footerCtrl,
                  hintText: t.reportTemplateHintFooterHtml,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportHtmlEditorFormHeader(BuildContext context, AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: t.reportTemplateFieldName,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descCtrl,
          decoration: InputDecoration(
            labelText: t.reportTemplateFieldDescription,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 4),
        ExpansionTile(
          initiallyExpanded: false,
          tilePadding: EdgeInsets.zero,
          title: Text(
            t.reportTemplatePageSettingsSection,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          childrenPadding: const EdgeInsets.only(bottom: 4),
          children: [
            _reportHtmlEditorPageSettingsForm(context, t),
          ],
        ),
      ],
    );
  }

  Future<void> _openReportHtmlEditorAdaptive({
    required String title,
    required Widget Function(BuildContext dialogContext) buildBody,
    required List<Widget> Function(BuildContext dialogContext) buildActions,
  }) async {
    await showDialog<void>(
      context: context,
      useSafeArea: true,
      builder: (dialogContext) {
        final actions = buildActions(dialogContext);
        final body = buildBody(dialogContext);
        final fullscreen = _reportHtmlEditorUseFullscreenLayout(dialogContext);
        if (fullscreen) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: Text(title),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: MaterialLocalizations.of(dialogContext).closeButtonLabel,
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ),
              body: body,
              bottomNavigationBar: Material(
                elevation: 6,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: 8,
                      overflowSpacing: 8,
                      overflowAlignment: OverflowBarAlignment.end,
                      children: actions,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 960,
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.92,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(title, style: Theme.of(dialogContext).textTheme.titleLarge),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(dialogContext).closeButtonLabel,
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: body),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: OverflowBar(
                      spacing: 8,
                      overflowSpacing: 8,
                      overflowAlignment: OverflowBarAlignment.end,
                      children: actions,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _createDialog() async {
    final t = AppLocalizations.of(context);
    await _openReportHtmlEditorAdaptive(
      title: t.reportTemplateNewHtml,
      buildBody: (dctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _reportHtmlEditorFormHeader(dctx, t),
              const SizedBox(height: 8),
              Expanded(child: _reportHtmlEditorCodeTabs(dctx, t)),
            ],
          ),
        );
      },
      buildActions: (dctx) => [
        TextButton(onPressed: () => Navigator.pop(dctx), child: Text(t.cancel)),
        FilledButton(
          onPressed: () async {
            try {
              Map<String, dynamic>? margins;
              double? parseMargin(String s) {
                try {
                  if (s.trim().isEmpty) return null;
                  return double.parse(s.trim());
                } catch (_) {
                  return null;
                }
              }
              final mt = parseMargin(_marginTopCtrl.text);
              final mr = parseMargin(_marginRightCtrl.text);
              final mb = parseMargin(_marginBottomCtrl.text);
              final ml = parseMargin(_marginLeftCtrl.text);
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
              if (!dctx.mounted) return;
              Navigator.pop(dctx);
              SnackBarHelper.showSuccess(dctx, message: t.templateCreatedWithId(id));
              await _fetch();
            } catch (e) {
              if (!dctx.mounted) return;
              SnackBarHelper.showError(
              dctx,
              message: t.createError(ErrorExtractor.forContext(e, dctx)),
            );
            }
          },
          child: Text(t.create),
        ),
      ],
    );
  }

  Future<void> _togglePublish(Map<String, dynamic> item) async {
    final published = (item['status'] == 'published');
    final next = !published;
    if (next && !_canApprove) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'دسترسی تایید/انتشار قالب را ندارید');
      }
      return;
    }
    try {
      if (next) {
        final full = await _service.getTemplate(
          businessId: widget.businessId,
          templateId: (item['id'] as num).toInt(),
        );
        if ((full['engine'] ?? '').toString().toLowerCase() == 'builder') {
          final mk = (full['module_key'] ?? '').toString();
          final st = full['subtype']?.toString();
          final assets = (full['assets'] as Map?)?.cast<String, dynamic>() ?? const {};
          final design = (assets['builder_design'] as Map?)?.cast<String, dynamic>() ?? const {};
          final validation = await _service.validateBuilderDesign(
            businessId: widget.businessId,
            moduleKey: mk,
            subtype: st,
            design: design,
          );
          final errors = ((validation['errors'] as List?) ?? const [])
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList();
          final warnings = ((validation['warnings'] as List?) ?? const [])
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList();
          if (errors.isNotEmpty) {
            await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(AppLocalizations.of(ctx).reportTemplatePublish),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Text('• ${errors.join('\n• ')}'),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(ctx).close)),
                ],
              ),
            );
            return;
          }
          if (warnings.isNotEmpty) {
            final proceed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(AppLocalizations.of(ctx).reportTemplatePublish),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Text(
                      'این قالب هشدارهایی دارد:\n\n• ${warnings.join('\n• ')}\n\nبا وجود هشدار منتشر شود؟',
                    ),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(ctx).cancel)),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.of(ctx).confirm)),
                ],
              ),
            );
            if (proceed != true) return;
          }
        }
      }
      await _service.publish(
        businessId: widget.businessId,
        templateId: (item['id'] as num).toInt(),
        published: next,
      );
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      final message = ErrorExtractor.forContext(e, context);
      if (next && message.contains('Cannot publish builder template')) {
        final details = message.split(':').length > 1
            ? message.substring(message.indexOf(':') + 1).trim()
            : message;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(ctx).reportTemplatePublish),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Text(details.replaceAll('; ', '\n• ')),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(ctx).close)),
            ],
          ),
        );
      } else {
        SnackBarHelper.showError(context, message: message);
      }
    }
  }

  Future<void> _transitionStatus(Map<String, dynamic> item, String toStatus) async {
    try {
      String? reason;
      if (toStatus == 'deprecated' || toStatus == 'draft') {
        final ctrl = TextEditingController();
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(toStatus == 'deprecated' ? 'دلیل منسوخ کردن' : 'دلیل بازگشت به پیش‌نویس'),
            content: TextField(
              controller: ctrl,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'دلیل را وارد کنید',
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(ctx).cancel)),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.of(ctx).confirm)),
            ],
          ),
        );
        if (ok != true) return;
        reason = ctrl.text.trim();
        if (reason.isEmpty) {
          if (mounted) {
            SnackBarHelper.showError(context, message: 'ثبت دلیل الزامی است');
          }
          return;
        }
      }
      if ((toStatus == 'approved' || toStatus == 'published') && !_canApprove) {
        if (mounted) {
          SnackBarHelper.showError(context, message: 'دسترسی تایید قالب را ندارید');
        }
        return;
      }
      await _service.transitionStatus(
        businessId: widget.businessId,
        templateId: (item['id'] as num).toInt(),
        toStatus: toStatus,
        reason: reason,
      );
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _showStatusHistory(Map<String, dynamic> item) async {
    try {
      final events = await _service.statusEvents(
        businessId: widget.businessId,
        templateId: (item['id'] as num).toInt(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تاریخچه وضعیت قالب'),
          content: SizedBox(
            width: 620,
            height: 420,
            child: events.isEmpty
                ? const Center(child: Text('تاریخچه‌ای ثبت نشده است'))
                : ListView.separated(
                    itemCount: events.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = events[i];
                      final fromS = _statusFlowLabel(e['from_status']?.toString());
                      final toS = _statusFlowLabel(e['to_status']?.toString());
                      final at = (e['created_at'] ?? '').toString();
                      final reason = (e['reason'] ?? '').toString();
                      final actor = (e['actor_display'] ?? '').toString();
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.timeline),
                        title: Text('$fromS ← $toS'),
                        subtitle: Text(
                          '${at.isEmpty ? '—' : at}'
                          '${actor.isNotEmpty ? '\nکاربر: $actor' : ''}'
                          '${reason.isNotEmpty ? '\nدلیل: $reason' : ''}',
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(ctx).close)),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _showAuditReportDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = widget.authStore.currentUserId ?? 0;
    final prefKey = 'report_template_audit_filters_${widget.businessId}_$userId';
    final savedRaw = prefs.getString(prefKey);
    Map<String, dynamic> saved = const {};
    if (savedRaw != null && savedRaw.trim().isNotEmpty) {
      try {
        final m = jsonDecode(savedRaw);
        if (m is Map<String, dynamic>) saved = m;
      } catch (_) {}
    }
    String? status;
    final actorCtrl = TextEditingController();
    final fromCtrl = TextEditingController();
    final toCtrl = TextEditingController();
    List<Map<String, dynamic>> events = const [];
    Map<String, dynamic> summary = const {};
    bool loading = false;
    int totalCount = 0;
    int offset = 0;
    const int pageSize = 50;
    String sortBy = 'created_at';
    String sortOrder = 'desc';
    bool initialLoaded = false;
    status = saved['status']?.toString();
    actorCtrl.text = (saved['actor_user_id'] ?? '').toString();
    fromCtrl.text = (saved['from_date'] ?? '').toString();
    toCtrl.text = (saved['to_date'] ?? '').toString();
    sortBy = (saved['sort_by'] ?? 'created_at').toString();
    sortOrder = (saved['sort_order'] ?? 'desc').toString();

    Future<void> saveFilters() async {
      final payload = {
        'status': status,
        'actor_user_id': actorCtrl.text.trim(),
        'from_date': fromCtrl.text.trim(),
        'to_date': toCtrl.text.trim(),
        'sort_by': sortBy,
        'sort_order': sortOrder,
      };
      await prefs.setString(prefKey, jsonEncode(payload));
    }

    Future<void> load(StateSetter setLocal) async {
      setLocal(() => loading = true);
      try {
        final data = await _service.statusEventsReport(
          businessId: widget.businessId,
          status: status,
          actorUserId: int.tryParse(actorCtrl.text.trim()),
          fromDate: fromCtrl.text.trim().isEmpty ? null : fromCtrl.text.trim(),
          toDate: toCtrl.text.trim().isEmpty ? null : toCtrl.text.trim(),
          offset: offset,
          limit: pageSize,
          sortBy: sortBy,
          sortOrder: sortOrder,
        );
        final items = (data['items'] as List?) ?? const [];
        events = items.cast<Map<String, dynamic>>();
        totalCount = ((data['total_count'] as num?)?.toInt()) ?? events.length;
        summary = (data['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
        await saveFilters();
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
        }
      } finally {
        setLocal(() => loading = false);
      }
    }

    String isoDayStart(DateTime d) => DateTime(d.year, d.month, d.day).toIso8601String();
    String isoDayEnd(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59).toIso8601String();

    void applyDatePreset(String preset, StateSetter setLocal) {
      final now = DateTime.now();
      if (preset == 'today') {
        fromCtrl.text = isoDayStart(now);
        toCtrl.text = isoDayEnd(now);
      } else if (preset == '7d') {
        final from = now.subtract(const Duration(days: 6));
        fromCtrl.text = isoDayStart(from);
        toCtrl.text = isoDayEnd(now);
      } else if (preset == '30d') {
        final from = now.subtract(const Duration(days: 29));
        fromCtrl.text = isoDayStart(from);
        toCtrl.text = isoDayEnd(now);
      } else if (preset == 'clear') {
        fromCtrl.clear();
        toCtrl.clear();
      }
      setLocal(() {});
    }

    Future<List<Map<String, dynamic>>> loadAllFiltered() async {
      final all = <Map<String, dynamic>>[];
      var off = 0;
      const chunk = 500;
      while (true) {
        final data = await _service.statusEventsReport(
          businessId: widget.businessId,
          status: status,
          actorUserId: int.tryParse(actorCtrl.text.trim()),
          fromDate: fromCtrl.text.trim().isEmpty ? null : fromCtrl.text.trim(),
          toDate: toCtrl.text.trim().isEmpty ? null : toCtrl.text.trim(),
          offset: off,
          limit: chunk,
          sortBy: sortBy,
          sortOrder: sortOrder,
        );
        final items = ((data['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
        if (items.isEmpty) break;
        all.addAll(items);
        final total = ((data['total_count'] as num?)?.toInt()) ?? all.length;
        off += items.length;
        if (off >= total) break;
      }
      return all;
    }

    String toCsv(List<Map<String, dynamic>> rows) {
      String esc(String v) {
        final needQuote = v.contains(',') || v.contains('\n') || v.contains('"');
        final s = v.replaceAll('"', '""');
        return needQuote ? '"$s"' : s;
      }

      final buf = StringBuffer();
      buf.writeln('event_id,template_id,from_status,to_status,actor_user_id,actor_display,created_at,reason');
      for (final r in rows) {
        buf.writeln([
          esc((r['id'] ?? '').toString()),
          esc((r['report_template_id'] ?? '').toString()),
          esc((r['from_status'] ?? '').toString()),
          esc((r['to_status'] ?? '').toString()),
          esc((r['actor_user_id'] ?? '').toString()),
          esc((r['actor_display'] ?? '').toString()),
          esc((r['created_at'] ?? '').toString()),
          esc((r['reason'] ?? '').toString()),
        ].join(','));
      }
      return buf.toString();
    }

    String toExcelHtml(List<Map<String, dynamic>> rows) {
      String esc(String s) => s
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;');
      final sb = StringBuffer();
      sb.writeln('<html><head><meta charset="utf-8"></head><body>');
      sb.writeln('<table border="1"><thead><tr>');
      const headers = [
        'event_id',
        'template_id',
        'from_status',
        'to_status',
        'actor_user_id',
        'actor_display',
        'created_at',
        'reason',
      ];
      for (final h in headers) {
        sb.write('<th>${esc(h)}</th>');
      }
      sb.writeln('</tr></thead><tbody>');
      for (final r in rows) {
        final vals = [
          (r['id'] ?? '').toString(),
          (r['report_template_id'] ?? '').toString(),
          (r['from_status'] ?? '').toString(),
          (r['to_status'] ?? '').toString(),
          (r['actor_user_id'] ?? '').toString(),
          (r['actor_display'] ?? '').toString(),
          (r['created_at'] ?? '').toString(),
          (r['reason'] ?? '').toString(),
        ];
        sb.write('<tr>');
        for (final v in vals) {
          sb.write('<td>${esc(v)}</td>');
        }
        sb.writeln('</tr>');
      }
      sb.writeln('</tbody></table></body></html>');
      return sb.toString();
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            if (!initialLoaded) {
              initialLoaded = true;
              Future.microtask(() => load(setLocal));
            }
            return AlertDialog(
            title: const Text('گزارش مدیریتی تغییر وضعیت قالب‌ها'),
            content: SizedBox(
              width: 980,
              height: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: 170,
                        child: DropdownButtonFormField<String?>(
                          value: status,
                          decoration: const InputDecoration(
                            labelText: 'وضعیت',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: null, child: Text('همه')),
                            DropdownMenuItem(value: 'draft', child: Text('پیش‌نویس')),
                            DropdownMenuItem(value: 'in_review', child: Text('در انتظار بررسی')),
                            DropdownMenuItem(value: 'approved', child: Text('تایید شده')),
                            DropdownMenuItem(value: 'published', child: Text('منتشر شده')),
                            DropdownMenuItem(value: 'deprecated', child: Text('منسوخ')),
                          ],
                          onChanged: (v) => setLocal(() => status = v),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: TextField(
                          controller: actorCtrl,
                          decoration: const InputDecoration(
                            labelText: 'شناسه کاربر',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: fromCtrl,
                          decoration: const InputDecoration(
                            labelText: 'از تاریخ (ISO)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: toCtrl,
                          decoration: const InputDecoration(
                            labelText: 'تا تاریخ (ISO)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: loading
                            ? null
                            : () {
                                offset = 0;
                                load(setLocal);
                              },
                        icon: const Icon(Icons.search),
                        label: const Text('جستجو'),
                      ),
                      OutlinedButton.icon(
                        onPressed: loading ? null : () => applyDatePreset('today', setLocal),
                        icon: const Icon(Icons.today, size: 18),
                        label: const Text('امروز'),
                      ),
                      OutlinedButton.icon(
                        onPressed: loading ? null : () => applyDatePreset('7d', setLocal),
                        icon: const Icon(Icons.date_range, size: 18),
                        label: const Text('۷ روز اخیر'),
                      ),
                      OutlinedButton.icon(
                        onPressed: loading ? null : () => applyDatePreset('30d', setLocal),
                        icon: const Icon(Icons.calendar_month, size: 18),
                        label: const Text('۳۰ روز اخیر'),
                      ),
                      TextButton(
                        onPressed: loading ? null : () => applyDatePreset('clear', setLocal),
                        child: const Text('پاک‌سازی تاریخ'),
                      ),
                      SizedBox(
                        width: 170,
                        child: DropdownButtonFormField<String>(
                          value: sortBy,
                          decoration: const InputDecoration(
                            labelText: 'مرتب‌سازی',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'created_at', child: Text('تاریخ')),
                            DropdownMenuItem(value: 'to_status', child: Text('وضعیت مقصد')),
                            DropdownMenuItem(value: 'actor_user_id', child: Text('کاربر')),
                          ],
                          onChanged: (v) => setLocal(() => sortBy = v ?? 'created_at'),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: DropdownButtonFormField<String>(
                          value: sortOrder,
                          decoration: const InputDecoration(
                            labelText: 'ترتیب',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'desc', child: Text('نزولی')),
                            DropdownMenuItem(value: 'asc', child: Text('صعودی')),
                          ],
                          onChanged: (v) => setLocal(() => sortOrder = v ?? 'desc'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (summary.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: Text('کل رخدادها: $totalCount'),
                          visualDensity: VisualDensity.compact,
                        ),
                        Chip(
                          label: Text('تعداد انتشار: ${(summary['publish_count'] ?? 0)}'),
                          visualDensity: VisualDensity.compact,
                        ),
                        Chip(
                          label: Text('تعداد بازگشت/رد: ${(summary['reject_count'] ?? 0)}'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  if ((summary['top_actors'] as List?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text(
                      'بیشترین کاربران: ${(summary['top_actors'] as List).map((e) => '${e['actor_display'] ?? e['actor_user_id']} (${e['count']})').join('، ')}',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                  if ((summary['top_reasons'] as List?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      'دلایل پرتکرار: ${(summary['top_reasons'] as List).map((e) => '${e['reason']} (${e['count']})').join('، ')}',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                  if (summary.isNotEmpty) const SizedBox(height: 8),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : events.isEmpty
                            ? const Center(child: Text('داده‌ای یافت نشد'))
                            : ListView.separated(
                                itemCount: events.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final e = events[i];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.event_note),
                                    title: Text(
                                      '#${e['id'] ?? ''} · قالب ${e['report_template_id'] ?? ''} · '
                                      '${_statusFlowLabel(e['from_status']?.toString())} ← ${_statusFlowLabel(e['to_status']?.toString())}',
                                    ),
                                    subtitle: Text(
                                      '${e['created_at'] ?? ''}'
                                      '${(e['actor_display'] ?? '').toString().isNotEmpty ? '\nکاربر: ${e['actor_display']}' : ''}'
                                      '${(e['reason'] ?? '').toString().isNotEmpty ? '\nدلیل: ${e['reason']}' : ''}',
                                    ),
                                  );
                                },
                              ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('نمایش ${events.length} از $totalCount'),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: loading || offset <= 0
                            ? null
                            : () {
                                offset = (offset - pageSize).clamp(0, 1 << 30);
                                load(setLocal);
                              },
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('قبلی'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: loading || (offset + events.length) >= totalCount
                            ? null
                            : () {
                                offset += pageSize;
                                load(setLocal);
                              },
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('بعدی'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.of(ctx).close),
              ),
              TextButton.icon(
                onPressed: events.isEmpty
                    ? null
                    : () async {
                        try {
                          final rows = await loadAllFiltered();
                          final csv = toCsv(rows);
                          final bytes = utf8.encode(csv);
                          if (kIsWeb) {
                            await web_utils.saveBytesAsFileWeb(
                              bytes,
                              'report_template_status_audit.csv',
                              mimeType: 'text/csv;charset=utf-8',
                            );
                          } else {
                            await FileSaver.saveBytes(bytes, 'report_template_status_audit.csv');
                          }
                          if (ctx.mounted) {
                            SnackBarHelper.show(ctx, message: 'فایل گزارش کامل (${rows.length} ردیف) ذخیره شد');
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            SnackBarHelper.showError(ctx, message: ErrorExtractor.forContext(e, ctx));
                          }
                        }
                      },
                icon: const Icon(Icons.download),
                label: const Text('خروجی CSV'),
              ),
              TextButton.icon(
                onPressed: events.isEmpty
                    ? null
                    : () async {
                        try {
                          final rows = await loadAllFiltered();
                          final html = toExcelHtml(rows);
                          final bytes = utf8.encode(html);
                          if (kIsWeb) {
                            await web_utils.saveBytesAsFileWeb(
                              bytes,
                              'report_template_status_audit.xls',
                              mimeType: 'application/vnd.ms-excel;charset=utf-8',
                            );
                          } else {
                            await FileSaver.saveBytes(bytes, 'report_template_status_audit.xls');
                          }
                          if (ctx.mounted) {
                            SnackBarHelper.show(ctx, message: 'فایل Excel (${rows.length} ردیف) ذخیره شد');
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            SnackBarHelper.showError(ctx, message: ErrorExtractor.forContext(e, ctx));
                          }
                        }
                      },
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('خروجی Excel'),
              ),
            ],
          );
          },
        );
      },
    );
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
      Map<String, dynamic> sampleContext = const <String, dynamic>{};
      try {
        final schema = await _service.schema(
          businessId: widget.businessId,
          moduleKey: (full['module_key'] ?? 'invoices').toString(),
          subtype: full['subtype']?.toString(),
        );
        sampleContext = (schema['sample_context'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
      } catch (_) {
        sampleContext = const <String, dynamic>{};
      }
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
          context: sampleContext,
        );
      } else {
        res = await _service.preview(
          businessId: widget.businessId,
          contentHtml: (full['content_html'] ?? '').toString(),
          contentCss: (full['content_css'] ?? '').toString().isEmpty ? null : (full['content_css'] ?? '').toString(),
          headerHtml: (full['header_html'] ?? '').toString().isEmpty ? null : (full['header_html'] ?? '').toString(),
          footerHtml: (full['footer_html'] ?? '').toString().isEmpty ? null : (full['footer_html'] ?? '').toString(),
          context: sampleContext,
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
            context: sampleContext,
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
            context: sampleContext,
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
        SnackBarHelper.showError(
          context,
          message: t.reportTemplatePreviewError(ErrorExtractor.forContext(e, context)),
        );
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
                        SnackBarHelper.showError(
                        context,
                        message: ErrorExtractor.forContext(e, context),
                      );
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

    final tEdit = AppLocalizations.of(context);
    await _openReportHtmlEditorAdaptive(
      title: tEdit.reportTemplateEdit,
      buildBody: (dctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _reportHtmlEditorFormHeader(dctx, tEdit),
              const SizedBox(height: 8),
              Expanded(child: _reportHtmlEditorCodeTabs(dctx, tEdit)),
            ],
          ),
        );
      },
      buildActions: (dctx) => [
        TextButton(onPressed: () => Navigator.pop(dctx), child: Text(tEdit.cancel)),
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
              double? parseMargin(String s) {
                try {
                  if (s.trim().isEmpty) return null;
                  return double.parse(s.trim());
                } catch (_) {
                  return null;
                }
              }
              final mt = parseMargin(_marginTopCtrl.text);
              final mr = parseMargin(_marginRightCtrl.text);
              final mb = parseMargin(_marginBottomCtrl.text);
              final ml = parseMargin(_marginLeftCtrl.text);
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
              if (!dctx.mounted) return;
              Navigator.pop(dctx);
              await _fetch();
            } catch (e) {
              if (!dctx.mounted) return;
              SnackBarHelper.showError(
              dctx,
              message: tEdit.reportTemplateEditSaveError(ErrorExtractor.forContext(e, dctx)),
            );
            }
          },
          child: Text(tEdit.save),
        ),
      ],
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
        leading: businessSubpageBackLeading(context, widget.businessId),
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
          if (_canAudit)
            IconButton(
              tooltip: 'گزارش Audit قالب‌ها',
              onPressed: _showAuditReportDialog,
              icon: const Icon(Icons.analytics_outlined),
            ),
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
                      SnackBarHelper.showError(
                      ctx,
                      message: t.reportTemplatesSchemaFetchError(ErrorExtractor.forContext(e, ctx)),
                    );
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
                    const DropdownMenuItem(value: 'in_review', child: Text('در انتظار بررسی')),
                    const DropdownMenuItem(value: 'approved', child: Text('تایید شده')),
                    const DropdownMenuItem(value: 'deprecated', child: Text('منسوخ')),
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      labelText: t.search,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _searchCtrl.clear();
                                });
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
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
                  : _filteredItems.isEmpty
                      ? Center(child: Text(_searchCtrl.text.trim().isEmpty ? t.reportTemplatesEmptyList : t.reportTemplatesEmptyList))
                      : Card(
                          clipBehavior: Clip.antiAlias,
                          child: ListView.separated(
                            itemCount: _filteredItems.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (ctx, idx) {
                              final it = _filteredItems[idx];
                              final isDefault = it['is_default'] == true;
                              final status = (it['status'] ?? '').toString();
                              final updated = it['updated_at']?.toString() ?? '';
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                elevation: 1,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            isDefault ? Icons.star : Icons.description,
                                            color: isDefault ? Colors.amber : Theme.of(context).colorScheme.primary,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  it['name']?.toString() ?? '-',
                                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                                ),
                                                const SizedBox(height: 6),
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: [
                                                    Chip(
                                                      visualDensity: VisualDensity.compact,
                                                      label: Text(_statusLabel(t, status)),
                                                    ),
                                                    if (isDefault)
                                                      Chip(
                                                        visualDensity: VisualDensity.compact,
                                                        avatar: const Icon(Icons.star, size: 16),
                                                        label: Text(t.reportTemplateDefaultBadge),
                                                      ),
                                                    Chip(
                                                      visualDensity: VisualDensity.compact,
                                                      label: Text(_scopeLabel(t, (it['module_key'] ?? '-').toString(), it['subtype']?.toString())),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        it['description']?.toString() ?? '',
                                        style: Theme.of(context).textTheme.bodySmall,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'v${it['version'] ?? '-'}${updated.isNotEmpty ? ' · $updated' : ''}',
                                              style: Theme.of(context).textTheme.bodySmall,
                                            ),
                                          ),
                                          PopupMenuButton<String>(
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
                                              const PopupMenuItem(
                                                value: 'history',
                                                child: ListTile(
                                                  leading: Icon(Icons.history),
                                                  title: Text('تاریخچه وضعیت'),
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
                                              if (status == 'published' || _canApprove)
                                                PopupMenuItem(
                                                  value: 'publish',
                                                  child: ListTile(
                                                    leading: Icon(status == 'published' ? Icons.visibility_off : Icons.publish),
                                                    title: Text(status == 'published' ? t.reportTemplateUnpublish : t.reportTemplatePublish),
                                                    dense: true,
                                                    contentPadding: EdgeInsets.zero,
                                                  ),
                                                ),
                                              if (status == 'draft')
                                                const PopupMenuItem(
                                                  value: 'submit_review',
                                                  child: ListTile(
                                                    leading: Icon(Icons.rate_review_outlined),
                                                    title: Text('ارسال برای بررسی'),
                                                    dense: true,
                                                    contentPadding: EdgeInsets.zero,
                                                  ),
                                                ),
                                              if (status == 'in_review' && _canApprove)
                                                const PopupMenuItem(
                                                  value: 'approve',
                                                  child: ListTile(
                                                    leading: Icon(Icons.verified_outlined),
                                                    title: Text('تایید قالب'),
                                                    dense: true,
                                                    contentPadding: EdgeInsets.zero,
                                                  ),
                                                ),
                                              if (status != 'deprecated')
                                                const PopupMenuItem(
                                                  value: 'deprecate',
                                                  child: ListTile(
                                                    leading: Icon(Icons.archive_outlined),
                                                    title: Text('منسوخ کردن'),
                                                    dense: true,
                                                    contentPadding: EdgeInsets.zero,
                                                  ),
                                                ),
                                              if (status == 'in_review' || status == 'approved' || status == 'deprecated')
                                                const PopupMenuItem(
                                                  value: 'back_to_draft',
                                                  child: ListTile(
                                                    leading: Icon(Icons.edit_note_outlined),
                                                    title: Text('بازگشت به پیش‌نویس'),
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
                                                case 'history':
                                                  _showStatusHistory(it);
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
                                                case 'submit_review':
                                                  _transitionStatus(it, 'in_review');
                                                  break;
                                                case 'approve':
                                                  _transitionStatus(it, 'approved');
                                                  break;
                                                case 'deprecate':
                                                  _transitionStatus(it, 'deprecated');
                                                  break;
                                                case 'back_to_draft':
                                                  _transitionStatus(it, 'draft');
                                                  break;
                                                case 'export':
                                                  _exportTemplateJson(it, t);
                                                  break;
                                                case 'delete':
                                                  _delete(it);
                                                  break;
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
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

