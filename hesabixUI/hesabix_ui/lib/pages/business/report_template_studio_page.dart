import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../constants/report_template_constants.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/business_named_route_locations.dart';
import '../../services/report_template_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/permission/permission_widgets.dart';
import '../../widgets/report_template/studio/report_template_studio_customize_panel.dart';
import '../../widgets/report_template/studio/report_template_studio_gallery.dart';
import '../../widgets/report_template/studio/report_template_media_settings.dart';
import '../../widgets/report_template/studio/report_template_studio_preview_panel.dart';
import '../../widgets/report_template/studio/report_template_studio_v3_builder.dart';
import '../../widgets/report_template/studio/report_template_studio_v4_adapter.dart';
import '../../core/hesabix_back.dart';
import 'report_template_html_editor_page.dart';

enum _StudioStep { gallery, customize }

enum _StudioToolbarAction { changeTemplate, advancedHtml, pageSettings }

class ReportTemplateStudioPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final Map<String, dynamic>? template;
  final int? templateId;
  final String? moduleKey;
  final String? subtype;

  const ReportTemplateStudioPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.template,
    this.templateId,
    this.moduleKey,
    this.subtype,
  });

  bool get isNew => template == null && templateId == null;

  @override
  State<ReportTemplateStudioPage> createState() =>
      _ReportTemplateStudioPageState();
}

class _ReportTemplateStudioPageState extends State<ReportTemplateStudioPage> {
  late final ReportTemplateService _service;
  final _previewDebouncer = ReportTemplatePreviewDebouncer();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _marginTopCtrl = TextEditingController(text: '10');
  final _marginRightCtrl = TextEditingController(text: '10');
  final _marginBottomCtrl = TextEditingController(text: '10');
  final _marginLeftCtrl = TextEditingController(text: '10');
  final _paperCustomCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _previewLoading = false;
  _StudioStep _step = _StudioStep.gallery;

  String? _moduleKey;
  String? _subtype;
  int? _templateId;
  bool _legacyTemplateCopied = false;
  String _lastSavedFingerprint = '';

  List<Map<String, dynamic>> _galleryItems = const [];
  List<Map<String, dynamic>> _scopeCatalog = const [];
  List<Map<String, dynamic>> _blockCatalog = const [];
  Map<String, dynamic>? _design;
  Map<String, dynamic> _assets = {'images': <String, String>{}};
  Map<String, dynamic> _sampleContext = const {};

  String? _paperSize = 'A4';
  String? _orientation = 'portrait';
  String? _previewHtml;
  Uint8List? _previewPdfBytes;
  bool _showPdfPreview = false;
  int _previewRevision = 0;
  int _previewRequestId = 0;
  List<String> _validationErrors = const [];
  List<String> _validationWarnings = const [];

  @override
  void initState() {
    super.initState();
    _service = ReportTemplateService(ApiClient());
    _moduleKey = widget.moduleKey ?? 'invoices';
    _subtype = widget.subtype ?? 'detail';
    _applyReceiptPageDefaultsIfNeeded();
    _bootstrap();
  }

  @override
  void dispose() {
    _previewDebouncer.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _marginTopCtrl.dispose();
    _marginRightCtrl.dispose();
    _marginBottomCtrl.dispose();
    _marginLeftCtrl.dispose();
    _paperCustomCtrl.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges {
    if (_lastSavedFingerprint.isEmpty) return false;
    return _fingerprint() != _lastSavedFingerprint;
  }

  String _fingerprint() => jsonEncode({
    'name': _nameCtrl.text.trim(),
    'desc': _descCtrl.text.trim(),
    'module': _moduleKey,
    'subtype': _subtype,
    'design': _design,
    'paperSize': _paperSize,
    'orientation': _orientation,
    'margins': {
      'top': _marginTopCtrl.text.trim(),
      'right': _marginRightCtrl.text.trim(),
      'bottom': _marginBottomCtrl.text.trim(),
      'left': _marginLeftCtrl.text.trim(),
    },
  });

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _loadScopeCatalog(),
        _loadGallery(),
        _loadSampleContext(),
        _loadBlockCatalog(),
      ]);
      if (widget.template != null) {
        await _loadExistingTemplate();
      } else if (widget.templateId != null) {
        await _loadExistingTemplateById(widget.templateId!);
      }
      if (_design != null) {
        _step = _StudioStep.customize;
        _schedulePreview();
      }
      if (_lastSavedFingerprint.isEmpty) {
        _lastSavedFingerprint = _fingerprint();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadScopeCatalog() async {
    final items = await _service.scopeCatalog(businessId: widget.businessId);
    if (mounted) setState(() => _scopeCatalog = items);
  }

  Future<void> _loadGallery() async {
    final items = await _service.templateGallery(
      businessId: widget.businessId,
      moduleKey: _moduleKey,
      subtype: _subtype,
    );
    if (mounted) setState(() => _galleryItems = items);
  }

  Future<void> _loadSampleContext() async {
    final schema = await _service.schema(
      businessId: widget.businessId,
      moduleKey: _moduleKey ?? 'invoices',
      subtype: _subtype,
    );
    final sample = (schema['sample_context'] as Map?)?.cast<String, dynamic>();
    if (mounted) setState(() => _sampleContext = sample ?? const {});
  }

  Future<void> _loadBlockCatalog() async {
    final items = await _service.studioBlocks(
      businessId: widget.businessId,
      moduleKey: _moduleKey ?? 'invoices',
      subtype: _subtype,
    );
    if (mounted) setState(() => _blockCatalog = items);
  }

  Future<void> _loadExistingTemplateById(int templateId) async {
    final full = await _service.getTemplate(
      businessId: widget.businessId,
      templateId: templateId,
    );
    _templateId = templateId;
    await _applyLoadedTemplate(full);
  }

  Future<void> _loadExistingTemplate() async {
    final tid = (widget.template!['id'] as num?)?.toInt();
    if (tid == null) return;
    final full = await _service.getTemplate(
      businessId: widget.businessId,
      templateId: tid,
    );
    _templateId = tid;
    await _applyLoadedTemplate(full);
  }

  Future<void> _applyLoadedTemplate(Map<String, dynamic> full) async {
    _moduleKey = full['module_key']?.toString() ?? _moduleKey;
    _subtype = full['subtype']?.toString();
    _nameCtrl.text = (full['name'] ?? '').toString();
    _descCtrl.text = (full['description'] ?? '').toString();
    _paperSize = (full['paper_size'] ?? _paperSize)?.toString();
    _orientation = (full['orientation'] ?? _orientation)?.toString();
    final margins =
        (full['margins'] as Map?)?.cast<String, dynamic>() ?? const {};
    _marginTopCtrl.text = margins['top']?.toString() ?? _marginTopCtrl.text;
    _marginRightCtrl.text =
        margins['right']?.toString() ?? _marginRightCtrl.text;
    _marginBottomCtrl.text =
        margins['bottom']?.toString() ?? _marginBottomCtrl.text;
    _marginLeftCtrl.text = margins['left']?.toString() ?? _marginLeftCtrl.text;

    final engine = (full['engine'] ?? '').toString().toLowerCase();
    final assets = (full['assets'] as Map?)?.cast<String, dynamic>() ?? {};
    _assets = assets.isNotEmpty ? assets : _assets;

    if (engine == 'template_v2') {
      _design = (assets['template_design'] as Map?)?.cast<String, dynamic>();
    } else if (engine == 'builder') {
      final builderDesign =
          (assets['builder_design'] as Map?)?.cast<String, dynamic>() ??
          const {};
      if (mounted && builderDesign.isNotEmpty) {
        final migrate = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('ارتقا به استودیو قالب'),
            content: const Text(
              'این قالب با سازنده قدیمی ساخته شده است. برای ادامه، به استودیو جدید منتقل می‌شود. '
              'برخی جزئیات ممکن است نیاز به بازبینی داشته باشند.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('انتقال'),
              ),
            ],
          ),
        );
        if (migrate != true) {
          if (mounted) context.pop();
          return;
        }
        final out = await _service.migrateBuilderToV2(
          businessId: widget.businessId,
          moduleKey: _moduleKey ?? 'invoices',
          subtype: _subtype,
          builderDesign: builderDesign,
        );
        _design = (out['design'] as Map?)?.cast<String, dynamic>();
      }
    }

    final hadStoredMedia = _design?['media'] is Map;
    await _upgradeDesignToV4IfSupported();
    if (hadStoredMedia) {
      _applyMediaToLegacyFields(
        normalizedReportTemplateMedia(_design!, preferRoll: _isReceiptScope),
      );
    } else {
      _syncDesignMediaFromLegacy();
    }

    await Future.wait([_loadGallery(), _loadBlockCatalog()]);
    _lastSavedFingerprint = _fingerprint();
  }

  Future<void> _upgradeDesignToV4IfSupported() async {
    var design = _design;
    if (design == null) return;
    if (_moduleKey != 'invoices' ||
        !const {'detail', 'receipt'}.contains(_subtype)) {
      return;
    }
    final originalSchema = (design['schema_version'] as num?)?.toInt();
    if (originalSchema == 2) {
      final out = await _service.migrateV2ToV3(
        businessId: widget.businessId,
        design: design,
      );
      design = (out['design'] as Map?)?.cast<String, dynamic>() ?? design;
    }
    if ((design['schema_version'] as num?)?.toInt() == 3) {
      final out = await _service.migrateV3ToV4(
        businessId: widget.businessId,
        design: design,
      );
      design = (out['design'] as Map?)?.cast<String, dynamic>() ?? design;
    }
    _design = design;
    if (originalSchema != 4 && _templateId != null) {
      // Copy-on-write: saving a migrated legacy design must never overwrite v3.
      _templateId = null;
      _legacyTemplateCopied = true;
      final currentName = _nameCtrl.text.trim();
      if (currentName.isNotEmpty && !currentName.endsWith('(نسخه جدید)')) {
        _nameCtrl.text = '$currentName (نسخه جدید)';
      }
    }
  }

  void _onScopeChanged(String? scopeId) {
    if (scopeId == null) return;
    final idx = scopeId.indexOf(':');
    if (idx <= 0) return;
    setState(() {
      _moduleKey = scopeId.substring(0, idx);
      _subtype = scopeId.substring(idx + 1);
      _step = _StudioStep.gallery;
      _design = null;
      _legacyTemplateCopied = false;
      _previewHtml = null;
      _previewPdfBytes = null;
      _showPdfPreview = false;
      _previewLoading = false;
      _previewRequestId++;
      _blockCatalog = const [];
      if (_moduleKey == 'invoices' && _subtype == 'receipt') {
        _applyReceiptPageDefaultsIfNeeded();
      } else if (kInvoiceReceiptPaperSizeOptions.contains(_paperSize)) {
        _paperSize = 'A4';
        _orientation = 'portrait';
        _marginTopCtrl.text = '10';
        _marginRightCtrl.text = '10';
        _marginBottomCtrl.text = '10';
        _marginLeftCtrl.text = '10';
      }
    });
    Future.wait([_loadGallery(), _loadSampleContext(), _loadBlockCatalog()]);
  }

  void _selectGalleryItem(Map<String, dynamic> item) {
    final design = ((item['studio_design'] ?? item['default_design']) as Map?)
        ?.cast<String, dynamic>();
    if (design == null) return;
    final nextDesign = Map<String, dynamic>.from(design);
    nextDesign['media'] = normalizedReportTemplateMedia(
      nextDesign,
      preferRoll: _isReceiptScope,
    );
    _applyMediaToLegacyFields(
      (nextDesign['media'] as Map).cast<String, dynamic>(),
    );
    setState(() {
      _design = nextDesign;
      _legacyTemplateCopied = false;
      _step = _StudioStep.customize;
      _previewHtml = null;
      _previewPdfBytes = null;
      _showPdfPreview = false;
      _applyReceiptPageDefaultsIfNeeded();
    });
    _schedulePreview();
  }

  void _onDesignChanged(Map<String, dynamic> design) {
    final media = normalizedReportTemplateMedia(
      design,
      preferRoll: _isReceiptScope,
    );
    design['media'] = media;
    _applyMediaToLegacyFields(media);
    setState(() {
      _design = design;
      _previewPdfBytes = null;
      _showPdfPreview = false;
    });
    _schedulePreview();
  }

  void _schedulePreview() {
    if (mounted && (_showPdfPreview || _previewPdfBytes != null)) {
      setState(() {
        _showPdfPreview = false;
        _previewPdfBytes = null;
      });
    }
    _previewDebouncer.schedule(_refreshPreview);
  }

  Future<void> _refreshPreview() async {
    final design = _design;
    if (design == null || !mounted) return;
    final requestId = ++_previewRequestId;
    setState(() {
      _previewLoading = true;
      _validationErrors = const [];
      _validationWarnings = const [];
    });
    try {
      final validation = await _service.validateStudioDesign(
        businessId: widget.businessId,
        moduleKey: _moduleKey ?? 'invoices',
        subtype: _subtype,
        design: design,
      );
      final errors = ((validation['errors'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
      final warnings = ((validation['warnings'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
      if (!mounted || requestId != _previewRequestId) return;
      if (errors.isNotEmpty) {
        if (mounted) {
          setState(() {
            _validationErrors = errors;
            _validationWarnings = warnings;
            _previewLoading = false;
            _previewHtml = null;
            _previewPdfBytes = null;
          });
        }
        return;
      }

      final html = await _service.previewHtml(
        businessId: widget.businessId,
        engine: 'template_v2',
        design: design,
        assets: {..._assets, 'template_design': design},
        context: _sampleContext,
        paperSize: _effectivePaperSize(),
        orientation: _orientation,
        margins: _parseMargins(),
      );
      if (mounted && requestId == _previewRequestId) {
        setState(() {
          _previewHtml = html;
          _previewRevision++;
          _validationWarnings = warnings;
          _previewLoading = false;
        });
      }
    } catch (e) {
      if (mounted && requestId == _previewRequestId) {
        setState(() {
          _previewLoading = false;
          _validationErrors = [ErrorExtractor.forContext(e, context)];
        });
      }
    }
  }

  Future<void> _refreshPdfPreview() async {
    if (_design == null || !mounted) return;
    final requestId = ++_previewRequestId;
    setState(() => _previewLoading = true);
    try {
      final pdfBytes = await _service.previewPdf(
        businessId: widget.businessId,
        engine: 'template_v2',
        design: _design,
        assets: {..._assets, 'template_design': _design},
        context: _sampleContext,
        paperSize: _effectivePaperSize(),
        orientation: _orientation,
        margins: _parseMargins(),
      );
      if (!mounted || requestId != _previewRequestId) return;
      setState(() {
        _previewPdfBytes = Uint8List.fromList(pdfBytes);
        _previewRevision++;
        _showPdfPreview = true;
        _previewLoading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _previewRequestId) return;
      setState(() {
        _previewLoading = false;
        _validationErrors = [ErrorExtractor.forContext(e, context)];
      });
    }
  }

  Map<String, dynamic>? _parseMargins() {
    final design = _design;
    if (design != null && design['media'] is Map) {
      final media = normalizedReportTemplateMedia(
        design,
        preferRoll: _isReceiptScope,
      );
      final margins = (media['margins_mm'] as Map?)?.cast<String, dynamic>();
      if (margins != null) return Map<String, dynamic>.from(margins);
    }
    double? parse(String s) {
      try {
        if (s.trim().isEmpty) return null;
        return double.parse(s.trim());
      } catch (_) {
        return null;
      }
    }

    final mt = parse(_marginTopCtrl.text);
    final mr = parse(_marginRightCtrl.text);
    final mb = parse(_marginBottomCtrl.text);
    final ml = parse(_marginLeftCtrl.text);
    final margins = <String, dynamic>{
      if (mt != null) 'top': mt,
      if (mr != null) 'right': mr,
      if (mb != null) 'bottom': mb,
      if (ml != null) 'left': ml,
    };
    return margins.isEmpty ? null : margins;
  }

  String _effectivePaperSize() {
    final design = _design;
    if (design != null && design['media'] is Map) {
      return reportTemplatePaperSizeFromMedia(
        normalizedReportTemplateMedia(design, preferRoll: _isReceiptScope),
      );
    }
    final c = _paperCustomCtrl.text.trim();
    if (c.isEmpty) return _paperSize ?? 'A4';
    return c.length > kReportTemplatePaperSizeMaxLength
        ? c.substring(0, kReportTemplatePaperSizeMaxLength)
        : c;
  }

  void _syncDesignMediaFromLegacy() {
    final design = _design;
    if (design == null) return;
    final media = reportTemplateMediaFromLegacy(
      paperSize: _paperSize,
      orientation: _orientation,
      margins: _parseLegacyMargins(),
      preferRoll: _isReceiptScope,
    );
    _design = Map<String, dynamic>.from(design)..['media'] = media;
    syncReportTemplateV4ActiveMedia(_design!);
    _applyMediaToLegacyFields(media);
  }

  Map<String, dynamic>? _parseLegacyMargins() {
    double? parse(String value) => double.tryParse(value.trim());
    final values = <String, dynamic>{
      if (parse(_marginTopCtrl.text) != null) 'top': parse(_marginTopCtrl.text),
      if (parse(_marginRightCtrl.text) != null)
        'right': parse(_marginRightCtrl.text),
      if (parse(_marginBottomCtrl.text) != null)
        'bottom': parse(_marginBottomCtrl.text),
      if (parse(_marginLeftCtrl.text) != null)
        'left': parse(_marginLeftCtrl.text),
    };
    return values.isEmpty ? null : values;
  }

  void _applyMediaToLegacyFields(Map<String, dynamic> media) {
    _paperSize = reportTemplatePaperSizeFromMedia(media);
    _paperCustomCtrl.clear();
    _orientation = media['type'] == 'roll'
        ? 'portrait'
        : (media['orientation'] == 'landscape' ? 'landscape' : 'portrait');
    final margins =
        (media['margins_mm'] as Map?)?.cast<String, dynamic>() ?? const {};
    String textFor(String side, String fallback) {
      final value = margins[side];
      if (value == null) return fallback;
      final number = value is num
          ? value.toDouble()
          : double.tryParse('$value');
      if (number == null) return fallback;
      return number == number.roundToDouble()
          ? number.toInt().toString()
          : number.toString();
    }

    _marginTopCtrl.text = textFor('top', _marginTopCtrl.text);
    _marginRightCtrl.text = textFor('right', _marginRightCtrl.text);
    _marginBottomCtrl.text = textFor('bottom', _marginBottomCtrl.text);
    _marginLeftCtrl.text = textFor('left', _marginLeftCtrl.text);
  }

  void _navigateBackAfterSave() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop(true);
      return;
    }
    BusinessNamedRoutes.goNamed(
      context,
      businessId: widget.businessId,
      routeName: 'business_report_templates',
    );
  }

  Future<void> _save() async {
    if (_design == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      SnackBarHelper.showError(context, message: 'نام قالب الزامی است');
      return;
    }

    setState(() => _saving = true);
    try {
      final validation = await _service.validateStudioDesign(
        businessId: widget.businessId,
        moduleKey: _moduleKey ?? 'invoices',
        subtype: _subtype,
        design: _design!,
      );
      final errors = ((validation['errors'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
      if (errors.isNotEmpty) {
        SnackBarHelper.showError(context, message: errors.join(' | '));
        return;
      }

      final assets = {
        'template_design': _design,
        'images': (_assets['images'] as Map?) ?? <String, String>{},
      };
      final margins = _parseMargins();

      if (_templateId == null) {
        final id = await _service.createTemplate(
          businessId: widget.businessId,
          moduleKey: _moduleKey ?? 'invoices',
          subtype: _subtype,
          name: name,
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          contentHtml: '<html><body></body></html>',
          paperSize: _effectivePaperSize(),
          orientation: _orientation,
          margins: margins,
          assets: assets,
          engine: 'template_v2',
        );
        _templateId = id;
      } else {
        await _service.updateTemplate(
          businessId: widget.businessId,
          templateId: _templateId!,
          changes: {
            'name': name,
            'description': _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
            'module_key': _moduleKey,
            'subtype': _subtype,
            'engine': 'template_v2',
            'assets': assets,
            'paper_size': _effectivePaperSize(),
            'orientation': _orientation,
            'margins': margins,
          },
        );
      }

      _lastSavedFingerprint = _fingerprint();
      if (mounted) {
        SnackBarHelper.show(context, message: 'قالب ذخیره شد');
        _navigateBackAfterSave();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('خروج بدون ذخیره؟'),
        content: const Text('تغییرات ذخیره نشده از بین می‌رود.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ماندن'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _openAdvancedHtml() async {
    if (_design == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حالت پیشرفته — HTML'),
        content: const Text(
          'طراحی استودیو به HTML/CSS تبدیل می‌شود و دیگر از ویزارد استودیو قابل ویرایش نیست. '
          'می‌توانید کد را در ادیتور پیشرفته ویرایش کنید.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ادامه'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final fragments = await _service.compileStudioDesign(
        businessId: widget.businessId,
        design: _design!,
      );
      if (!mounted) return;

      final seed = ReportTemplateHtmlEditorSeed(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        moduleKey: _moduleKey,
        subtype: _subtype,
        contentHtml: fragments['content_html']?.toString(),
        contentCss: fragments['content_css']?.toString(),
        headerHtml: fragments['header_html']?.toString(),
        footerHtml: fragments['footer_html']?.toString(),
        paperSize: _effectivePaperSize(),
        orientation: _orientation,
        margins: _parseMargins(),
        convertFromStudio: true,
      );

      if (_templateId != null) {
        await BusinessNamedRoutes.pushNamed<bool>(
          context,
          businessId: widget.businessId,
          routeName: 'business_report_template_html_edit',
          pathParameters: {'template_id': _templateId.toString()},
          extra: seed,
        );
      } else {
        await BusinessNamedRoutes.pushNamed<bool>(
          context,
          businessId: widget.businessId,
          routeName: 'business_report_template_html_new',
          queryParameters: {
            if (_moduleKey != null) 'module_key': _moduleKey!,
            if (_subtype != null) 'subtype': _subtype!,
          },
          extra: seed,
        );
      }
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    }
  }

  String _currentScopeId() => '${_moduleKey ?? ''}:${_subtype ?? ''}';

  bool get _isReceiptScope => _moduleKey == 'invoices' && _subtype == 'receipt';

  List<String> get _paperChoices {
    if (_isReceiptScope) return kInvoiceReceiptPaperSizeOptions;
    return kReportTemplatePaperSizeOptions;
  }

  void _applyReceiptPageDefaultsIfNeeded() {
    if (!_isReceiptScope) return;
    if (_paperSize == null || !_paperChoices.contains(_paperSize)) {
      _paperSize = '80mm';
    }
    _orientation = 'portrait';
    if (_marginTopCtrl.text.trim() == '10' &&
        _marginRightCtrl.text.trim() == '10' &&
        _marginBottomCtrl.text.trim() == '10' &&
        _marginLeftCtrl.text.trim() == '10') {
      _marginTopCtrl.text = '3';
      _marginRightCtrl.text = '2';
      _marginBottomCtrl.text = '4';
      _marginLeftCtrl.text = '2';
    }
  }

  String _scopeLabel() {
    for (final s in _scopeCatalog) {
      final id =
          '${(s['module_key'] ?? '').toString()}:${(s['subtype'] ?? '').toString()}';
      if (id == _currentScopeId()) return (s['label_fa'] ?? id).toString();
    }
    return _currentScopeId();
  }

  Future<void> _showPageSettings() async {
    final design = _design;
    var media = design == null
        ? reportTemplateMediaFromLegacy(
            paperSize: _paperSize,
            orientation: _orientation,
            margins: _parseLegacyMargins(),
            preferRoll: _isReceiptScope,
          )
        : normalizedReportTemplateMedia(design, preferRoll: _isReceiptScope);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('صفحه و چاپ'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: ReportTemplateMediaSettings(
                media: media,
                onChanged: (next) => setDialogState(() => media = next),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.pop(ctx);
                if (design != null) {
                  _onDesignChanged(
                    Map<String, dynamic>.from(design)..['media'] = media,
                  );
                } else {
                  _applyMediaToLegacyFields(media);
                  setState(() {});
                  _schedulePreview();
                }
              },
              child: const Text('اعمال'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleToolbarAction(_StudioToolbarAction action) async {
    switch (action) {
      case _StudioToolbarAction.changeTemplate:
        setState(() => _step = _StudioStep.gallery);
        return;
      case _StudioToolbarAction.advancedHtml:
        await _openAdvancedHtml();
        return;
      case _StudioToolbarAction.pageSettings:
        await _showPageSettings();
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.hasBusinessPermission('report_templates', 'write')) {
      return const AccessDeniedPage(
        message: 'شما دسترسی لازم برای ویرایش قالب‌ها را ندارید',
      );
    }

    final isNew = widget.isNew;
    final title = isNew ? 'استودیو قالب — جدید' : 'استودیو قالب — ویرایش';
    final compactToolbar = MediaQuery.sizeOf(context).width < 900;

    return HesabixBackInterceptor(
      onWillPop: _confirmDiscard,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: hesabixBackAppBarLeading(
            context,
            businessId: widget.businessId,
          ),
          actions: [
            if (!compactToolbar && _step == _StudioStep.customize && isNew)
              TextButton.icon(
                onPressed: () => setState(() => _step = _StudioStep.gallery),
                icon: const Icon(Icons.grid_view),
                label: const Text('تغییر قالب'),
              ),
            if (!compactToolbar &&
                _step == _StudioStep.customize &&
                _design != null)
              TextButton.icon(
                onPressed: _openAdvancedHtml,
                icon: const Icon(Icons.code),
                label: const Text('حالت پیشرفته'),
              ),
            if (!compactToolbar)
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'تنظیمات صفحه',
                onPressed: _showPageSettings,
              ),
            if (compactToolbar)
              PopupMenuButton<_StudioToolbarAction>(
                tooltip: 'گزینه‌های استودیو',
                onSelected: _handleToolbarAction,
                itemBuilder: (context) => [
                  if (_step == _StudioStep.customize && isNew)
                    const PopupMenuItem(
                      value: _StudioToolbarAction.changeTemplate,
                      child: ListTile(
                        leading: Icon(Icons.grid_view),
                        title: Text('تغییر قالب'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (_step == _StudioStep.customize && _design != null)
                    const PopupMenuItem(
                      value: _StudioToolbarAction.advancedHtml,
                      child: ListTile(
                        leading: Icon(Icons.code),
                        title: Text('حالت پیشرفته'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuItem(
                    value: _StudioToolbarAction.pageSettings,
                    child: ListTile(
                      leading: Icon(Icons.settings),
                      title: Text('تنظیمات صفحه'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            if (_hasUnsavedChanges && !compactToolbar)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Chip(
                  label: Text('ذخیره نشده'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compactToolbar ? 2 : 8,
                vertical: 8,
              ),
              child: compactToolbar
                  ? IconButton(
                      tooltip: _saving ? 'در حال ذخیره...' : 'ذخیره',
                      onPressed: _saving || _loading || _design == null
                          ? null
                          : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                    )
                  : FilledButton.icon(
                      onPressed: _saving || _loading || _design == null
                          ? null
                          : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(_saving ? 'در حال ذخیره...' : 'ذخیره'),
                    ),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: LoadingIndicator())
            : _step == _StudioStep.gallery
            ? _buildGalleryStep(context)
            : _buildCustomizeStep(context),
      ),
    );
  }

  Widget _buildGalleryStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'انتخاب قالب',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'یک قالب حرفه‌ای انتخاب کنید؛ سپس آن را سفارشی کنید.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value:
                          _scopeCatalog.any(
                            (s) =>
                                '${(s['module_key'] ?? '').toString()}:${(s['subtype'] ?? '').toString()}' ==
                                _currentScopeId(),
                          )
                          ? _currentScopeId()
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'کاربرد قالب',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _scopeCatalog
                          .map(
                            (s) => DropdownMenuItem<String>(
                              value:
                                  '${(s['module_key'] ?? '').toString()}:${(s['subtype'] ?? '').toString()}',
                              child: Text((s['label_fa'] ?? '').toString()),
                            ),
                          )
                          .toList(),
                      onChanged: _onScopeChanged,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Chip(label: Text(_scopeLabel())),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ReportTemplateStudioGallery(
            items: _galleryItems,
            selectedFamilyId: (_design?['family_id'] ?? '').toString(),
            onSelect: _selectGalleryItem,
          ),
        ),
      ],
    );
  }

  Widget _buildCustomizeStep(BuildContext context) {
    final design = _design;
    if (design == null) {
      return const Center(child: Text('قالبی انتخاب نشده است.'));
    }

    if (const {3, 4}.contains((design['schema_version'] as num?)?.toInt())) {
      return ReportTemplateStudioV3Builder(
        design: design,
        blockCatalog: _blockCatalog,
        onDesignChanged: _onDesignChanged,
        editorHeader: _buildTemplateIdentityFields(),
        previewPane: _buildPreviewPane(),
      );
    }

    final settingsPane = _buildCustomizeSettings(design);
    final previewPane = _buildPreviewPane();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            children: [
              SizedBox(width: 520, child: settingsPane),
              VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
              Expanded(flex: 3, child: previewPane),
            ],
          );
        }

        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const Material(
                child: TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.tune), text: 'تنظیمات'),
                    Tab(
                      icon: Icon(Icons.picture_as_pdf_outlined),
                      text: 'پیش‌نمایش',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(children: [settingsPane, previewPane]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCustomizeSettings(Map<String, dynamic> design) {
    return Column(
      children: [
        _buildTemplateIdentityFields(),
        const Divider(height: 16),
        Expanded(
          child: ReportTemplateStudioCustomizePanel(
            design: design,
            moduleKey: _moduleKey ?? 'invoices',
            subtype: _subtype,
            blockCatalog: _blockCatalog,
            onDesignChanged: _onDesignChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateIdentityFields() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          if (_legacyTemplateCopied) ...[
            MaterialBanner(
              padding: const EdgeInsets.all(10),
              leading: const Icon(Icons.copy_all_outlined),
              content: const Text(
                'این طراحی از قالب قدیمی به v4 منتقل شده است. ذخیره، یک قالب جدید می‌سازد و نسخه قبلی را تغییر نمی‌دهد.',
              ),
              actions: const [SizedBox.shrink()],
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'نام قالب',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'توضیحات (اختیاری)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPane() {
    return ReportTemplateStudioPreviewPanel(
      loading: _previewLoading,
      pdfBytes: _previewPdfBytes,
      html: _previewHtml,
      previewRevision: _previewRevision,
      paperSize: _effectivePaperSize(),
      orientation: _orientation,
      media: _design == null
          ? null
          : normalizedReportTemplateMedia(
              _design!,
              preferRoll: _isReceiptScope,
            ),
      errors: _validationErrors,
      warnings: _validationWarnings,
      onRefresh: _refreshPreview,
      onGeneratePdf: () {
        if (_previewPdfBytes != null && _previewPdfBytes!.isNotEmpty) {
          setState(() => _showPdfPreview = true);
        } else {
          _refreshPdfPreview();
        }
      },
      onShowHtml: () => setState(() => _showPdfPreview = false),
      showPdf: _showPdfPreview,
    );
  }
}
