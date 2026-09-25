import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../constants/report_template_constants.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../l10n/app_localizations.dart';
import '../../services/report_template_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/permission/permission_widgets.dart';
import '../../widgets/report_template/embedded_pdf_iframe.dart';

/// Pre-filled content when opening the HTML editor from Studio (advanced mode).
class ReportTemplateHtmlEditorSeed {
  final String? name;
  final String? description;
  final String? moduleKey;
  final String? subtype;
  final String? contentHtml;
  final String? contentCss;
  final String? headerHtml;
  final String? footerHtml;
  final String? paperSize;
  final String? orientation;
  final Map<String, dynamic>? margins;
  final bool convertFromStudio;

  const ReportTemplateHtmlEditorSeed({
    this.name,
    this.description,
    this.moduleKey,
    this.subtype,
    this.contentHtml,
    this.contentCss,
    this.headerHtml,
    this.footerHtml,
    this.paperSize,
    this.orientation,
    this.margins,
    this.convertFromStudio = false,
  });
}

class ReportTemplateHtmlEditorPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final int? templateId;
  final String? moduleKey;
  final String? subtype;
  final ReportTemplateHtmlEditorSeed? seed;

  const ReportTemplateHtmlEditorPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.templateId,
    this.moduleKey,
    this.subtype,
    this.seed,
  });

  bool get isNew => templateId == null;

  @override
  State<ReportTemplateHtmlEditorPage> createState() => _ReportTemplateHtmlEditorPageState();
}

class _ReportTemplateHtmlEditorPageState extends State<ReportTemplateHtmlEditorPage> {
  late final ReportTemplateService _service;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _htmlCtrl = TextEditingController(
    text: '<html><head></head><body><h3>{{ title_text }}</h3></body></html>',
  );
  final _cssCtrl = TextEditingController(text: 'body { font-family: Tahoma, Arial; }');
  final _headerCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();
  final _marginTopCtrl = TextEditingController(text: '10');
  final _marginRightCtrl = TextEditingController(text: '10');
  final _marginBottomCtrl = TextEditingController(text: '10');
  final _marginLeftCtrl = TextEditingController(text: '10');
  final _paperCustomCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _previewLoading = false;
  String? _moduleKey;
  String? _subtype;
  String? _paperSize = 'A4';
  String? _orientation = 'portrait';
  String _lastSavedFingerprint = '';
  bool _convertFromStudio = false;

  @override
  void initState() {
    super.initState();
    _service = ReportTemplateService(ApiClient());
    _moduleKey = widget.moduleKey ?? widget.seed?.moduleKey ?? 'invoices';
    _subtype = widget.subtype ?? widget.seed?.subtype ?? 'list';
    _convertFromStudio = widget.seed?.convertFromStudio ?? false;
    _bootstrap();
  }

  @override
  void dispose() {
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

  String _fingerprint() => [
        _nameCtrl.text.trim(),
        _descCtrl.text.trim(),
        _moduleKey,
        _subtype,
        _htmlCtrl.text,
        _cssCtrl.text,
        _headerCtrl.text,
        _footerCtrl.text,
        _paperSize,
        _orientation,
        _marginTopCtrl.text,
        _marginRightCtrl.text,
        _marginBottomCtrl.text,
        _marginLeftCtrl.text,
      ].join('\u0001');

  bool get _hasUnsavedChanges =>
      _lastSavedFingerprint.isNotEmpty && _fingerprint() != _lastSavedFingerprint;

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      if (widget.templateId != null) {
        await _loadTemplate(widget.templateId!);
      }
      _applySeed(widget.seed);
      _lastSavedFingerprint = _fingerprint();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applySeed(ReportTemplateHtmlEditorSeed? seed) {
    if (seed == null) return;
    if (seed.name != null) _nameCtrl.text = seed.name!;
    if (seed.description != null) _descCtrl.text = seed.description!;
    if (seed.moduleKey != null) _moduleKey = seed.moduleKey;
    if (seed.subtype != null) _subtype = seed.subtype;
    if (seed.contentHtml != null) _htmlCtrl.text = seed.contentHtml!;
    if (seed.contentCss != null) _cssCtrl.text = seed.contentCss!;
    if (seed.headerHtml != null) _headerCtrl.text = seed.headerHtml!;
    if (seed.footerHtml != null) _footerCtrl.text = seed.footerHtml!;
    if (seed.paperSize != null) _paperSize = seed.paperSize;
    if (seed.orientation != null) _orientation = seed.orientation;
    final margins = seed.margins;
    if (margins != null) {
      _marginTopCtrl.text = margins['top']?.toString() ?? _marginTopCtrl.text;
      _marginRightCtrl.text = margins['right']?.toString() ?? _marginRightCtrl.text;
      _marginBottomCtrl.text = margins['bottom']?.toString() ?? _marginBottomCtrl.text;
      _marginLeftCtrl.text = margins['left']?.toString() ?? _marginLeftCtrl.text;
    }
    _convertFromStudio = seed.convertFromStudio;
  }

  Future<void> _loadTemplate(int templateId) async {
    final full = await _service.getTemplate(businessId: widget.businessId, templateId: templateId);
    _moduleKey = full['module_key']?.toString() ?? _moduleKey;
    _subtype = full['subtype']?.toString();
    _nameCtrl.text = (full['name'] ?? '').toString();
    _descCtrl.text = (full['description'] ?? '').toString();
    _htmlCtrl.text = (full['content_html'] ?? '').toString();
    _cssCtrl.text = (full['content_css'] ?? '').toString();
    _headerCtrl.text = (full['header_html'] ?? '').toString();
    _footerCtrl.text = (full['footer_html'] ?? '').toString();
    _paperSize = (full['paper_size'] ?? _paperSize)?.toString();
    _orientation = (full['orientation'] ?? _orientation)?.toString();
    final margins = (full['margins'] as Map?)?.cast<String, dynamic>() ?? const {};
    _marginTopCtrl.text = margins['top']?.toString() ?? _marginTopCtrl.text;
    _marginRightCtrl.text = margins['right']?.toString() ?? _marginRightCtrl.text;
    _marginBottomCtrl.text = margins['bottom']?.toString() ?? _marginBottomCtrl.text;
    _marginLeftCtrl.text = margins['left']?.toString() ?? _marginLeftCtrl.text;
  }

  Map<String, dynamic>? _parseMargins() {
    double? parse(String s) {
      try {
        if (s.trim().isEmpty) return null;
        return double.parse(s.trim());
      } catch (_) {
        return null;
      }
    }

    final margins = <String, dynamic>{
      if (parse(_marginTopCtrl.text) != null) 'top': parse(_marginTopCtrl.text),
      if (parse(_marginRightCtrl.text) != null) 'right': parse(_marginRightCtrl.text),
      if (parse(_marginBottomCtrl.text) != null) 'bottom': parse(_marginBottomCtrl.text),
      if (parse(_marginLeftCtrl.text) != null) 'left': parse(_marginLeftCtrl.text),
    };
    return margins.isEmpty ? null : margins;
  }

  String _effectivePaperSize() {
    final c = _paperCustomCtrl.text.trim();
    if (c.isEmpty) return _paperSize ?? 'A4';
    return c.length > kReportTemplatePaperSizeMaxLength
        ? c.substring(0, kReportTemplatePaperSizeMaxLength)
        : c;
  }

  List<DropdownMenuItem<String>> _paperSizeDropdownItems(String? current) {
    final items = List<String>.from(kReportTemplatePaperSizeOptions);
    if (current != null && current.isNotEmpty && !items.contains(current)) {
      items.insert(0, current);
    }
    return items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList();
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('خروج بدون ذخیره؟'),
        content: const Text('تغییرات ذخیره نشده از بین می‌رود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ماندن')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('خروج')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      SnackBarHelper.showError(context, message: 'نام قالب الزامی است');
      return;
    }

    setState(() => _saving = true);
    try {
      final margins = _parseMargins();
      final changes = <String, dynamic>{
        'name': name,
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'content_html': _htmlCtrl.text,
        'content_css': _cssCtrl.text.trim().isEmpty ? null : _cssCtrl.text,
        'header_html': _headerCtrl.text.trim().isEmpty ? null : _headerCtrl.text,
        'footer_html': _footerCtrl.text.trim().isEmpty ? null : _footerCtrl.text,
        'paper_size': _effectivePaperSize(),
        'orientation': _orientation,
        if (margins != null) 'margins': margins,
      };

      if (_convertFromStudio) {
        changes['engine'] = 'jinja2';
        changes['assets'] = <String, dynamic>{};
      }

      if (widget.isNew) {
        await _service.createTemplate(
          businessId: widget.businessId,
          moduleKey: _moduleKey ?? 'invoices',
          subtype: _subtype,
          name: name,
          description: changes['description'] as String?,
          contentHtml: _htmlCtrl.text,
          contentCss: changes['content_css'] as String?,
          headerHtml: changes['header_html'] as String?,
          footerHtml: changes['footer_html'] as String?,
          paperSize: _effectivePaperSize(),
          orientation: _orientation,
          margins: margins,
          engine: 'jinja2',
        );
      } else {
        changes['module_key'] = _moduleKey;
        changes['subtype'] = _subtype;
        await _service.updateTemplate(
          businessId: widget.businessId,
          templateId: widget.templateId!,
          changes: changes,
        );
      }

      _lastSavedFingerprint = _fingerprint();
      if (mounted) {
        SnackBarHelper.show(context, message: t.save);
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: t.reportTemplateEditSaveError(ErrorExtractor.forContext(e, context)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _preview() async {
    final t = AppLocalizations.of(context);
    setState(() => _previewLoading = true);
    try {
      Map<String, dynamic> sampleContext = const {};
      try {
        final schema = await _service.schema(
          businessId: widget.businessId,
          moduleKey: _moduleKey ?? 'invoices',
          subtype: _subtype,
        );
        sampleContext = (schema['sample_context'] as Map?)?.cast<String, dynamic>() ?? const {};
      } catch (_) {}

      final pdfBytes = await _service.previewPdf(
        businessId: widget.businessId,
        contentHtml: _htmlCtrl.text,
        contentCss: _cssCtrl.text.trim().isEmpty ? null : _cssCtrl.text,
        headerHtml: _headerCtrl.text.trim().isEmpty ? null : _headerCtrl.text,
        footerHtml: _footerCtrl.text.trim().isEmpty ? null : _footerCtrl.text,
        context: sampleContext,
        paperSize: _effectivePaperSize(),
        orientation: _orientation,
        margins: _parseMargins(),
      );

      if (!mounted) return;
      await showGlassDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.reportTemplatePreview),
          content: SizedBox(
            width: 720,
            height: 520,
            child: ReportTemplateEmbeddedPdf(bytes: Uint8List.fromList(pdfBytes)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.close)),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  TextStyle? _codeStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium;
    return base?.copyWith(fontFamily: 'monospace', fontSize: 13, height: 1.4);
  }

  Widget _codeField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      style: _codeStyle(context),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: hint,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        contentPadding: const EdgeInsets.all(12),
      ),
      maxLines: null,
      minLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      keyboardType: TextInputType.multiline,
      onChanged: (_) => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.hasBusinessPermission('report_templates', 'write')) {
      return const AccessDeniedPage(message: 'شما دسترسی لازم برای ویرایش قالب‌ها را ندارید');
    }

    final t = AppLocalizations.of(context);
    final title = widget.isNew ? t.reportTemplateNewHtml : t.reportTemplateEdit;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () async {
              if (await _confirmDiscard() && mounted) context.pop();
            },
          ),
          actions: [
            if (_convertFromStudio)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Chip(
                  label: Text('تبدیل از استودیو'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            if (_hasUnsavedChanges)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Chip(label: Text('ذخیره نشده'), visualDensity: VisualDensity.compact),
              ),
            TextButton.icon(
              onPressed: _previewLoading ? null : _preview,
              icon: _previewLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: Text(t.reportTemplatePreview),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: FilledButton.icon(
                onPressed: _saving || _loading ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(_saving ? '...' : t.save),
              ),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: LoadingIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _nameCtrl,
                            decoration: InputDecoration(
                              labelText: t.reportTemplateFieldName,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _descCtrl,
                            decoration: InputDecoration(
                              labelText: t.reportTemplateFieldDescription,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    if (widget.isNew) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'module_key',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: Text(_moduleKey ?? ''),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'subtype',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: Text(_subtype ?? ''),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(t.reportTemplatePageSettingsSection, style: Theme.of(context).textTheme.titleSmall),
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
                                decoration: InputDecoration(labelText: t.marginTop, border: const OutlineInputBorder(), isDense: true),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [EnglishDigitsFormatter(), FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _marginRightCtrl,
                                decoration: InputDecoration(labelText: t.marginRight, border: const OutlineInputBorder(), isDense: true),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [EnglishDigitsFormatter(), FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
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
                                decoration: InputDecoration(labelText: t.marginBottom, border: const OutlineInputBorder(), isDense: true),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [EnglishDigitsFormatter(), FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _marginLeftCtrl,
                                decoration: InputDecoration(labelText: t.marginLeft, border: const OutlineInputBorder(), isDense: true),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [EnglishDigitsFormatter(), FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
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
                        const SizedBox(height: 8),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: DefaultTabController(
                        length: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TabBar(
                              isScrollable: true,
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
                                  _codeField(_htmlCtrl, t.reportTemplateHintHtmlBody),
                                  _codeField(_cssCtrl, t.reportTemplateHintCss),
                                  _codeField(_headerCtrl, t.reportTemplateHintHeaderHtml),
                                  _codeField(_footerCtrl, t.reportTemplateHintFooterHtml),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
