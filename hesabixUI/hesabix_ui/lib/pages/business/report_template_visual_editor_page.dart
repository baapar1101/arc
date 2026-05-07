import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, FilteringTextInputFormatter, HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey, TextInputFormatter;

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
import '../../widgets/loading_indicator.dart';
import '../../widgets/report_template/embedded_pdf_iframe.dart';
import '../../widgets/permission/permission_widgets.dart';

class ReportTemplateVisualEditorPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final Map<String, dynamic>? template;
  final String? moduleKey;
  final String? subtype;

  const ReportTemplateVisualEditorPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.template,
    this.moduleKey,
    this.subtype,
  });

  @override
  State<ReportTemplateVisualEditorPage> createState() => _ReportTemplateVisualEditorPageState();
}

class _ReportTemplateVisualEditorPageState extends State<ReportTemplateVisualEditorPage> {
  late final ReportTemplateService _service;
  final FocusNode _focusNode = FocusNode();
  
  bool _loading = false;
  bool _saving = false;
  bool _previewLoading = false;
  
  // Template data
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _moduleKey;
  String? _subtype;
  
  // Builder design
  Map<String, dynamic> _design = {
    'css': '',
    'header': <Map<String, dynamic>>[],
    'blocks': <Map<String, dynamic>>[],
    'footer': <Map<String, dynamic>>[],
  };
  
  Map<String, dynamic> _assets = {
    'images': <String, String>{},
  };
  
  // Page settings
  String? _paperSize = 'A4';
  String? _orientation = 'portrait';
  final _marginTopCtrl = TextEditingController(text: '10');
  final _marginRightCtrl = TextEditingController(text: '10');
  final _marginBottomCtrl = TextEditingController(text: '10');
  final _marginLeftCtrl = TextEditingController(text: '10');
  final _paperCustomCtrl = TextEditingController();

  // Preview
  String? _previewHtml;
  Uint8List? _previewPdfBytes;
  bool _showPreview = false;
  
  // History for undo/redo
  final List<Map<String, dynamic>> _history = [];
  int _historyIndex = -1;
  String _lastSavedFingerprint = '';
  
  // Variables schema
  List<Map<String, dynamic>> _variables = [];
  List<Map<String, dynamic>> _scopeCatalog = [];
  bool _showVariablesPanel = false;
  bool _showBlockPalette = false;
  bool _showValidationPanel = false;
  bool _validationLoading = false;
  List<String> _validationErrors = const [];
  List<String> _validationWarnings = const [];
  
  // View mode: 'list' or 'canvas'
  String _viewMode = 'list';
  
  // Canvas zoom and pan
  double _canvasZoom = 1.0;
  Offset _canvasPan = Offset.zero;

  @override
  void initState() {
    super.initState();
    _service = ReportTemplateService(ApiClient());
    _moduleKey = widget.moduleKey ?? 'invoices';
    _subtype = widget.subtype ?? 'list';
    _loadTemplate();
    _loadScopeCatalog();
    _loadVariablesSchema();
    _focusNode.requestFocus();
  }

  String _fingerprint() {
    final payload = {
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
      'paperCustom': _paperCustomCtrl.text.trim(),
    };
    return jsonEncode(payload);
  }

  bool get _hasUnsavedChanges {
    if (_lastSavedFingerprint.isEmpty) return false;
    return _fingerprint() != _lastSavedFingerprint;
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_hasUnsavedChanges) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('خروج بدون ذخیره؟'),
        content: const Text('تغییرات ذخیره‌نشده دارید. آیا مطمئن هستید که می‌خواهید خارج شوید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('خروج')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _marginTopCtrl.dispose();
    _marginRightCtrl.dispose();
    _marginBottomCtrl.dispose();
    _marginLeftCtrl.dispose();
    _paperCustomCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    if (widget.template == null) {
      _nameCtrl.text = 'قالب جدید';
      _lastSavedFingerprint = _fingerprint();
      return;
    }
    
    setState(() => _loading = true);
    try {
      final full = await _service.getTemplate(
        businessId: widget.businessId,
        templateId: (widget.template!['id'] as num).toInt(),
      );
      
      _nameCtrl.text = (full['name'] ?? '').toString();
      _descCtrl.text = (full['description'] ?? '').toString();
      _moduleKey = full['module_key']?.toString() ?? _moduleKey;
      _subtype = full['subtype']?.toString();
      _paperSize = full['paper_size']?.toString() ?? 'A4';
      _orientation = full['orientation']?.toString() ?? 'portrait';
      _paperCustomCtrl.clear();

      final margins = (full['margins'] as Map?)?.cast<String, dynamic>() ?? {};
      _marginTopCtrl.text = (margins['top']?.toString() ?? '10');
      _marginRightCtrl.text = (margins['right']?.toString() ?? '10');
      _marginBottomCtrl.text = (margins['bottom']?.toString() ?? '10');
      _marginLeftCtrl.text = (margins['left']?.toString() ?? '10');
      
      // Load builder design if engine is builder
      if ((full['engine'] ?? '').toString() == 'builder') {
        final assets = (full['assets'] as Map?)?.cast<String, dynamic>() ?? {};
        final design = (assets['builder_design'] as Map?)?.cast<String, dynamic>();
        if (design != null) {
          _design = {
            'css': (design['css'] ?? '').toString(),
            'header': List<Map<String, dynamic>>.from((design['header'] as List?) ?? const []),
            'blocks': List<Map<String, dynamic>>.from((design['blocks'] as List?) ?? const []),
            'footer': List<Map<String, dynamic>>.from((design['footer'] as List?) ?? const []),
          };
          _assets = {
            'images': Map<String, String>.from((assets['images'] as Map?)?.cast<String, String>() ?? const {}),
          };
        }
      }
      
      _pushHistory();
      _lastSavedFingerprint = _fingerprint();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
        context,
        message: 'خطا در بارگذاری قالب: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadVariablesSchema() async {
    try {
      final data = await _service.schema(
        businessId: widget.businessId,
        moduleKey: _moduleKey ?? 'invoices',
        subtype: _subtype,
      );
      final keys = (data['keys'] as List?) ?? const [];
      setState(() {
        _variables = keys.cast<Map<String, dynamic>>();
      });
    } catch (e) {
      debugPrint('خطا در بارگذاری schema: $e');
    }
  }

  Future<Map<String, dynamic>> _samplePreviewContext() async {
    try {
      final schema = await _service.schema(
        businessId: widget.businessId,
        moduleKey: _moduleKey ?? 'invoices',
        subtype: _subtype,
      );
      final sample = (schema['sample_context'] as Map?)?.cast<String, dynamic>();
      return sample ?? const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Future<bool> _validateDesignBeforeSave() async {
    try {
      final out = await _runDesignValidation(showPanel: false);
      final errors = out['errors'] ?? const <String>[];
      final warnings = out['warnings'] ?? const <String>[];
      if (errors.isNotEmpty) {
        if (mounted) {
          SnackBarHelper.showError(context, message: errors.join(' | '));
        }
        return false;
      }
      if (warnings.isNotEmpty && mounted) {
        SnackBarHelper.show(context, message: warnings.join(' | '));
      }
      return true;
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: 'خطا در اعتبارسنجی قالب: ${ErrorExtractor.forContext(e, context)}',
        );
      }
      return false;
    }
  }

  Future<Map<String, List<String>>> _runDesignValidation({bool showPanel = true}) async {
    if (showPanel) {
      setState(() {
        _validationLoading = true;
      });
    }
    try {
      final out = await _service.validateBuilderDesign(
        businessId: widget.businessId,
        moduleKey: _moduleKey ?? 'invoices',
        subtype: _subtype,
        design: _design,
      );
      final errors = ((out['errors'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      final warnings = ((out['warnings'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (mounted) {
        setState(() {
          _validationErrors = errors;
          _validationWarnings = warnings;
          if (showPanel) _showValidationPanel = true;
        });
      }
      return {'errors': errors, 'warnings': warnings};
    } finally {
      if (showPanel && mounted) {
        setState(() {
          _validationLoading = false;
        });
      }
    }
  }

  Future<void> _loadScopeCatalog() async {
    try {
      final items = await _service.scopeCatalog(businessId: widget.businessId);
      setState(() {
        _scopeCatalog = items;
      });
    } catch (e) {
      debugPrint('خطا در بارگذاری scope catalog: $e');
    }
  }

  String _currentScopeId() {
    final mk = (_moduleKey ?? '').trim();
    final st = (_subtype ?? '').trim();
    return '$mk:$st';
  }

  void _setScopeFromId(String scopeId) {
    final idx = scopeId.indexOf(':');
    if (idx <= 0) return;
    final mk = scopeId.substring(0, idx);
    final st = scopeId.substring(idx + 1);
    setState(() {
      _moduleKey = mk;
      _subtype = st.isEmpty ? null : st;
    });
    _loadVariablesSchema();
  }

  List<Map<String, dynamic>> _availableBlockTypes() {
    final mk = (_moduleKey ?? '').trim();
    final st = (_subtype ?? '').trim();
    const all = [
      {'type': 'text', 'label': 'متن', 'icon': Icons.text_fields, 'color': Colors.blue},
      {'type': 'image', 'label': 'تصویر', 'icon': Icons.image, 'color': Colors.green},
      {'type': 'table', 'label': 'جدول', 'icon': Icons.table_chart, 'color': Colors.orange},
      {'type': 'divider', 'label': 'خط جداکننده', 'icon': Icons.horizontal_rule, 'color': Colors.grey},
      {'type': 'spacer', 'label': 'فاصله', 'icon': Icons.space_bar, 'color': Colors.purple},
      {'type': 'qr', 'label': 'QR Code', 'icon': Icons.qr_code, 'color': Colors.teal},
      {'type': 'totals', 'label': 'جمع‌بندی', 'icon': Icons.summarize, 'color': Colors.red},
    ];
    if (mk == 'invoices' && st == 'detail') return all;
    if ((mk == 'invoices' && st == 'list') ||
        (mk == 'documents' && st == 'list') ||
        (mk == 'receipts_payments' && st == 'list') ||
        (mk == 'expense_income' && st == 'list') ||
        (mk == 'transfers' && st == 'list')) {
      return all.where((b) => b['type'] != 'totals' && b['type'] != 'qr').toList();
    }
    if (mk == 'warehouse_documents' && st == 'postal_label') {
      return all.where((b) => b['type'] != 'table' && b['type'] != 'totals').toList();
    }
    return all;
  }

  void _applyInvoiceDetailPreset() {
    if (!((_moduleKey ?? '') == 'invoices' && (_subtype ?? '') == 'detail')) return;
    setState(() {
      _design = {
        'css': '''
.invoice-title { font-size: 18px; font-weight: 700; margin-bottom: 8px; }
.invoice-meta { font-size: 12px; margin-bottom: 4px; }
.sig-box { border: 1px solid #333; border-radius: 8px; height: 72px; margin-top: 6px; }
.sig-label { font-size: 11px; margin-top: 4px; text-align: center; }
''',
        'header': <Map<String, dynamic>>[
          {
            'type': 'text',
            'props': {'text': '<div class="invoice-title">{{ title_text | default("فاکتور") }}</div>', 'align': 'right', 'showIf': ''},
          },
          {
            'type': 'text',
            'props': {'text': '<div class="invoice-meta">کد: {{ invoice.code | default("-") }} | تاریخ: {{ invoice.issue_date | default("-") }}</div>', 'align': 'right', 'showIf': ''},
          },
          {
            'type': 'divider',
            'props': {'thickness': 1.0, 'showIf': ''},
          },
        ],
        'blocks': <Map<String, dynamic>>[
          {
            'type': 'table',
            'props': {
              'items': 'items',
              'columns': [
                {'key': 'product_name', 'title': 'شرح', 'format': ''},
                {'key': 'quantity', 'title': 'تعداد', 'format': ''},
                {'key': 'unit_price', 'title': 'فی', 'format': 'money'},
                {'key': 'line_total', 'title': 'مبلغ', 'format': 'money'},
              ],
              'showIf': '',
            },
          },
          {
            'type': 'totals',
            'props': {
              'items': [
                {'title': 'جمع کل', 'expr': "invoice.payable_total", 'format': 'money'},
                {'title': 'مالیات', 'expr': "invoice.tax_total", 'format': 'money'},
              ],
              'showIf': '',
            },
          },
          {'type': 'spacer', 'props': {'height': 16.0, 'showIf': ''}},
          {
            'type': 'text',
            'props': {
              'text': '<div style="display:flex;gap:16px;"><div style="flex:1;"><div class="sig-box"></div><div class="sig-label">امضای فروشنده</div></div><div style="flex:1;"><div class="sig-box"></div><div class="sig-label">امضای خریدار</div></div></div>',
              'align': 'right',
              'showIf': '',
            },
          },
        ],
        'footer': <Map<String, dynamic>>[],
      };
      _pushHistory();
    });
  }

  void _pushHistory() {
    // Remove future if we're not at the end
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(_snapDesign());
    _historyIndex = _history.length - 1;
    // Limit history size
    if (_history.length > 50) {
      _history.removeAt(0);
      _historyIndex--;
    }
    // Clear future when new action is performed
  }

  Map<String, dynamic> _snapDesign() {
    return {
      'css': _design['css']?.toString() ?? '',
      'header': List<Map<String, dynamic>>.from((_design['header'] as List?) ?? const []),
      'blocks': List<Map<String, dynamic>>.from((_design['blocks'] as List?) ?? const []),
      'footer': List<Map<String, dynamic>>.from((_design['footer'] as List?) ?? const []),
    };
  }

  void _undo() {
    if (_historyIndex <= 0) return;
    _historyIndex--;
    final snapshot = _history[_historyIndex];
    setState(() {
      _design = {
        'css': (snapshot['css'] ?? '').toString(),
        'header': List<Map<String, dynamic>>.from((snapshot['header'] as List?) ?? const []),
        'blocks': List<Map<String, dynamic>>.from((snapshot['blocks'] as List?) ?? const []),
        'footer': List<Map<String, dynamic>>.from((snapshot['footer'] as List?) ?? const []),
      };
    });
  }

  void _redo() {
    if (_historyIndex >= _history.length - 1) return;
    _historyIndex++;
    final snapshot = _history[_historyIndex];
    setState(() {
      _design = {
        'css': (snapshot['css'] ?? '').toString(),
        'header': List<Map<String, dynamic>>.from((snapshot['header'] as List?) ?? const []),
        'blocks': List<Map<String, dynamic>>.from((snapshot['blocks'] as List?) ?? const []),
        'footer': List<Map<String, dynamic>>.from((snapshot['footer'] as List?) ?? const []),
      };
    });
  }

  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex < _history.length - 1;

  Future<void> _saveTemplate() async {
    if (_nameCtrl.text.trim().isEmpty) {
      SnackBarHelper.showError(context, message: 'نام قالب الزامی است');
      return;
    }
    if (_scopeCatalog.isNotEmpty &&
        !_scopeCatalog.any(
          (s) =>
              (s['module_key'] ?? '').toString() == (_moduleKey ?? '') &&
              (s['subtype'] ?? '').toString() == (_subtype ?? ''),
        )) {
      SnackBarHelper.showError(context, message: 'ابتدا کاربرد معتبر قالب را انتخاب کنید');
      return;
    }

    setState(() => _saving = true);
    try {
      final ok = await _validateDesignBeforeSave();
      if (!ok) return;
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

      if (widget.template == null) {
        // Create new
        await _service.createTemplate(
          businessId: widget.businessId,
          moduleKey: _moduleKey ?? 'invoices',
          subtype: _subtype,
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          contentHtml: '<html><body></body></html>',
          assets: {'builder_design': _design, ..._assets},
          engine: 'builder',
          paperSize: _effectivePaperSize(),
          orientation: _orientation,
          margins: margins,
        );
        if (mounted) {
          SnackBarHelper.showSuccess(context, message: 'قالب با موفقیت ایجاد شد');
          _lastSavedFingerprint = _fingerprint();
          Navigator.of(context).pop(true);
        }
      } else {
        // Update existing
        await _service.updateTemplate(
          businessId: widget.businessId,
          templateId: (widget.template!['id'] as num).toInt(),
          changes: {
            'name': _nameCtrl.text.trim(),
            'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
            'assets': {'builder_design': _design, ..._assets},
            'engine': 'builder',
            'paper_size': _effectivePaperSize(),
            'orientation': _orientation,
            if (margins != null) 'margins': margins,
          },
        );
        if (mounted) {
          SnackBarHelper.showSuccess(context, message: 'قالب با موفقیت به‌روزرسانی شد');
          _lastSavedFingerprint = _fingerprint();
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
        context,
        message: 'خطا در ذخیره‌سازی: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _previewTemplate() async {
    setState(() {
      _previewLoading = true;
      _previewHtml = null;
      _previewPdfBytes = null;
    });

    try {
      final sampleContext = await _samplePreviewContext();
      // Get HTML preview first
      final res = await _service.preview(
        businessId: widget.businessId,
        engine: 'builder',
        design: _design,
        assets: _assets,
        context: sampleContext,
      );

      if (!mounted) return;

      final html = (res['html'] ?? '').toString();
      
      // Get PDF bytes
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

      try {
        final pdfBytes = await _service.previewPdf(
          businessId: widget.businessId,
          engine: 'builder',
          design: _design,
          assets: _assets,
          context: sampleContext,
          paperSize: _effectivePaperSize(),
          orientation: _orientation,
          margins: margins,
        );

        setState(() {
          _previewHtml = html;
          _previewPdfBytes = Uint8List.fromList(pdfBytes);
          _previewLoading = false;
          _showPreview = true;
        });
      } catch (e) {
        // If PDF preview fails, still show HTML
        setState(() {
          _previewHtml = html;
          _previewLoading = false;
          _showPreview = true;
        });
        debugPrint('خطا در دریافت PDF: $e');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _previewLoading = false);
        SnackBarHelper.showError(
        context,
        message: 'خطا در پیش‌نمایش: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final isCtrlPressed = HardwareKeyboard.instance.isControlPressed ||
          event.logicalKey == LogicalKeyboardKey.metaLeft ||
          event.logicalKey == LogicalKeyboardKey.metaRight;
      final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      
      if (event.logicalKey == LogicalKeyboardKey.keyZ && isCtrlPressed && !isShiftPressed) {
        if (_canUndo) {
          _undo();
        }
      } else if (event.logicalKey == LogicalKeyboardKey.keyZ && isCtrlPressed && isShiftPressed) {
        if (_canRedo) {
          _redo();
        }
      } else if (event.logicalKey == LogicalKeyboardKey.keyS && isCtrlPressed) {
        _saveTemplate();
      }
    }
  }

  String _effectivePaperSize() {
    final c = _paperCustomCtrl.text.trim();
    if (c.isEmpty) return _paperSize ?? 'A4';
    return c.length > kReportTemplatePaperSizeMaxLength
        ? c.substring(0, kReportTemplatePaperSizeMaxLength)
        : c;
  }

  List<DropdownMenuItem<String>> _paperSizeDropdownItems() {
    final cur = _paperSize;
    return [
      ...kReportTemplatePaperSizeOptions.map(
        (e) => DropdownMenuItem<String>(value: e, child: Text(e)),
      ),
      if (cur != null && cur.isNotEmpty && !kReportTemplatePaperSizeOptions.contains(cur))
        DropdownMenuItem<String>(value: cur, child: Text(cur)),
    ];
  }

  void _showPageSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('تنظیمات صفحه'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _paperSize,
                        decoration: const InputDecoration(
                          labelText: 'سایز صفحه',
                          border: OutlineInputBorder(),
                        ),
                        items: _paperSizeDropdownItems(),
                        onChanged: (v) {
                          setState(() => _paperSize = v);
                          setSt(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _orientation,
                        decoration: const InputDecoration(
                          labelText: 'جهت',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'portrait', child: Text('عمودی')),
                          DropdownMenuItem(value: 'landscape', child: Text('افقی')),
                        ],
                        onChanged: (v) {
                          setState(() => _orientation = v);
                          setSt(() {});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _paperCustomCtrl,
                  maxLength: kReportTemplatePaperSizeMaxLength,
                  decoration: const InputDecoration(
                    labelText: 'سایز سفارشی کاغذ (اختیاری)',
                    helperText:
                        'اگر پر باشد، به‌جای سایز انتخاب‌شده در لیست استفاده می‌شود (حداکثر ۳۲ نویسه)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setSt(() {}),
                ),
                const SizedBox(height: 16),
                const Text('حاشیه‌ها (mm):', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _marginTopCtrl,
                        decoration: const InputDecoration(
                          labelText: 'بالا',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          EnglishDigitsFormatter(),
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _marginRightCtrl,
                        decoration: const InputDecoration(
                          labelText: 'راست',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          EnglishDigitsFormatter(),
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _marginBottomCtrl,
                        decoration: const InputDecoration(
                          labelText: 'پایین',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          EnglishDigitsFormatter(),
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _marginLeftCtrl,
                        decoration: const InputDecoration(
                          labelText: 'چپ',
                          border: OutlineInputBorder(),
                          isDense: true,
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
                const SizedBox(height: 8),
                TextField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'توضیحات',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('بستن'),
            ),
          ],
        ),
      ),
    );
  }

  String _scopeTitle() {
    final mk = (_moduleKey ?? '').trim();
    final st = (_subtype ?? '').trim();
    if (mk == 'invoices' && st == 'list') return 'فاکتورها (لیست)';
    if (mk == 'invoices' && st == 'detail') return 'فاکتور (جزئیات)';
    if (mk == 'receipts_payments' && st == 'list') return 'دریافت/پرداخت (لیست)';
    if (mk == 'receipts_payments' && st == 'detail') return 'دریافت/پرداخت (جزئیات)';
    if (mk == 'expense_income' && st == 'list') return 'هزینه/درآمد (لیست)';
    if (mk == 'documents' && st == 'list') return 'اسناد (لیست)';
    if (mk == 'documents' && st == 'detail') return 'سند (جزئیات)';
    if (mk == 'transfers' && st == 'list') return 'انتقالات (لیست)';
    if (mk == 'transfers' && st == 'detail') return 'انتقال (جزئیات)';
    if (mk == 'warehouse_documents' && st == 'postal_label') return 'حواله انبار (برچسب پستی)';
    return '$mk / ${st.isEmpty ? '—' : st}';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final canWrite = widget.authStore.hasBusinessPermission('report_templates', 'write');

    if (!canWrite) {
      return AccessDeniedPage(
        message: 'شما دسترسی لازم برای ویرایش قالب‌ها را ندارید',
      );
    }

    final title = widget.template == null ? 'قالب جدید' : 'ویرایش قالب';

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final canLeave = await _confirmDiscardIfDirty();
        if (canLeave && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () async {
              final canLeave = await _confirmDiscardIfDirty();
              if (!canLeave || !mounted) return;
              Navigator.of(context).pop();
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: _canUndo ? _undo : null,
              tooltip: 'Undo (Ctrl+Z)',
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: _canRedo ? _redo : null,
              tooltip: 'Redo (Ctrl+Shift+Z)',
            ),
            IconButton(
              icon: const Icon(Icons.visibility),
              onPressed: _previewLoading ? null : _previewTemplate,
              tooltip: t.previewPdf,
            ),
            TextButton.icon(
              onPressed: _saving || _loading ? null : _saveTemplate,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'در حال ذخیره...' : 'ذخیره'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: LoadingIndicator())
            : KeyboardListener(
                focusNode: _focusNode,
                autofocus: true,
                onKeyEvent: _handleKeyEvent,
                child: Row(
                  children: [
                    // Main editor area
                    Expanded(
                      flex: _showPreview ? 1 : 2,
                      child: _buildEditorArea(),
                    ),
                    // Preview panel
                    if (_showPreview)
                      Container(
                        width: 1,
                        color: Theme.of(context).dividerColor,
                      ),
                    if (_showPreview)
                      Expanded(
                        flex: 1,
                        child: _buildPreviewPanel(),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildEditorArea() {
    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'نام قالب',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  value: _scopeCatalog.any(
                    (s) =>
                        '${(s['module_key'] ?? '').toString()}:${(s['subtype'] ?? '').toString()}' ==
                        _currentScopeId(),
                  )
                      ? _currentScopeId()
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'کاربرد قالب',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _scopeCatalog
                      .map(
                        (s) => DropdownMenuItem<String>(
                          value: '${(s['module_key'] ?? '').toString()}:${(s['subtype'] ?? '').toString()}',
                          child: Text((s['label_fa'] ?? '').toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _setScopeFromId(v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  _scopeTitle(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                avatar: const Icon(Icons.description_outlined, size: 16),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              if ((_moduleKey ?? '') == 'invoices' && (_subtype ?? '') == 'detail')
                TextButton.icon(
                  onPressed: _applyInvoiceDetailPreset,
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('قالب آماده فاکتور'),
                ),
              if ((_moduleKey ?? '') == 'invoices' && (_subtype ?? '') == 'detail')
                const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.settings),
                tooltip: 'تنظیمات صفحه',
                onSelected: (value) {
                  if (value == 'settings') {
                    _showPageSettingsDialog();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'settings',
                    child: Row(
                      children: [
                        Icon(Icons.settings, size: 20),
                        SizedBox(width: 8),
                        Text('تنظیمات صفحه'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              ToggleButtons(
                isSelected: [_viewMode == 'list', _viewMode == 'canvas'],
                onPressed: (index) {
                  setState(() {
                    _viewMode = index == 0 ? 'list' : 'canvas';
                  });
                },
                children: const [
                  Tooltip(
                    message: 'نمایش لیستی',
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.list, size: 20),
                    ),
                  ),
                  Tooltip(
                    message: 'نمایش Canvas',
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.view_quilt, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(_showBlockPalette ? Icons.widgets : Icons.widgets_outlined),
                onPressed: () {
                  setState(() {
                    _showBlockPalette = !_showBlockPalette;
                    if (_showBlockPalette) {
                      _showVariablesPanel = false;
                      _showValidationPanel = false;
                    }
                  });
                },
                tooltip: 'پالت بلوک‌ها',
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(_showVariablesPanel ? Icons.help : Icons.help_outline),
                onPressed: () {
                  setState(() {
                    _showVariablesPanel = !_showVariablesPanel;
                    if (_showVariablesPanel) {
                      _showBlockPalette = false;
                      _showValidationPanel = false;
                    }
                  });
                },
                tooltip: 'راهنمای متغیرها',
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(_showValidationPanel ? Icons.rule : Icons.rule_outlined),
                onPressed: () async {
                  if (_showValidationPanel) {
                    setState(() => _showValidationPanel = false);
                    return;
                  }
                  setState(() {
                    _showValidationPanel = true;
                    _showVariablesPanel = false;
                    _showBlockPalette = false;
                  });
                  await _runDesignValidation();
                },
                tooltip: 'اعتبارسنجی قالب',
              ),
            ],
          ),
        ),
        // Main content
        Expanded(
          child: Row(
            children: [
              // Sidebar panels
              if (_showVariablesPanel || _showBlockPalette || _showValidationPanel)
                Container(
                  width: 300,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    border: Border(
                      right: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: _showVariablesPanel
                      ? _buildVariablesPanel()
                      : _showBlockPalette
                          ? _buildBlockPalette()
                          : _buildValidationPanel(),
                ),
              // Editor tabs
              Expanded(
                child: DefaultTabController(
                  length: 4,
                  child: Column(
                    children: [
                      TabBar(
                        tabs: const [
                          Tab(text: 'Header'),
                          Tab(text: 'Body'),
                          Tab(text: 'Footer'),
                          Tab(text: 'CSS'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _viewMode == 'list'
                                ? _buildBlocksEditor('header')
                                : _buildCanvasView('header'),
                            _viewMode == 'list'
                                ? _buildBlocksEditor('blocks')
                                : _buildCanvasView('blocks'),
                            _viewMode == 'list'
                                ? _buildBlocksEditor('footer')
                                : _buildCanvasView('footer'),
                            _buildCssEditor(),
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
      ],
    );
  }

  Widget _buildVariablesPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              const Text('متغیرهای قابل استفاده', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() => _showVariablesPanel = false);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _variables.length,
            itemBuilder: (context, index) {
              final variable = _variables[index];
              final name = (variable['name'] ?? '').toString();
              final desc = (variable['desc'] ?? '').toString();
              return ListTile(
                dense: true,
                title: Text(name, style: const TextStyle(fontFamily: 'monospace')),
                subtitle: desc.isNotEmpty ? Text(desc) : null,
                trailing: IconButton(
                  icon: const Icon(Icons.content_copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '{{ $name }}'));
                    SnackBarHelper.show(context, message: 'متغیر کپی شد: {{ $name }}');
                  },
                  tooltip: 'کپی',
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBlockPalette() {
    final blockTypes = _availableBlockTypes();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              const Text('پالت بلوک‌ها', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() => _showBlockPalette = false);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: blockTypes.length,
            itemBuilder: (context, index) {
              final blockType = blockTypes[index];
              return Draggable<String>(
                data: blockType['type'] as String,
                feedback: Material(
                  elevation: 4,
                  child: Container(
                    width: 200,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (blockType['color'] as Color).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(blockType['icon'] as IconData, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          blockType['label'] as String,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: Icon(
                      blockType['icon'] as IconData,
                      color: blockType['color'] as Color,
                    ),
                    title: Text(blockType['label'] as String),
                    trailing: const Icon(Icons.drag_handle),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildValidationPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              const Text('اعتبارسنجی قالب', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _validationLoading ? null : () => _runDesignValidation(),
                tooltip: 'بازبینی',
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() => _showValidationPanel = false);
                },
              ),
            ],
          ),
        ),
        if (_validationLoading)
          const Expanded(child: Center(child: LoadingIndicator()))
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                if (_validationErrors.isEmpty && _validationWarnings.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.check_circle, color: Colors.green),
                    title: Text('موردی برای اصلاح پیدا نشد'),
                  ),
                ..._validationErrors.map(
                  (e) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.error_outline, color: Colors.red),
                    title: Text(e),
                  ),
                ),
                ..._validationWarnings.map(
                  (w) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    title: Text(w),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBlocksEditor(String section) {
    final blocks = List<Map<String, dynamic>>.from(
      (_design[section] as List?) ?? const [],
    );
    final blockTypes = _availableBlockTypes();

    return Column(
      children: [
        // Toolbar for adding blocks
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: blockTypes
                .map(
                  (b) => _buildAddBlockButton(
                    (b['type'] as String),
                    (b['label'] as String),
                    (b['icon'] as IconData),
                    section,
                  ),
                )
                .toList(),
          ),
        ),
        // Blocks list
        Expanded(
          child: DragTarget<String>(
            onAccept: (blockType) {
              final allowed = blockTypes.any((b) => b['type'] == blockType);
              if (!allowed) return;
              setState(() {
                blocks.add(_createBlock(blockType));
                _design[section] = blocks;
                _pushHistory();
              });
            },
            builder: (context, candidateData, rejectedData) {
              return ReorderableListView.builder(
                itemCount: blocks.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = blocks.removeAt(oldIndex);
                    blocks.insert(newIndex, item);
                    _design[section] = blocks;
                    _pushHistory();
                  });
                },
                itemBuilder: (context, index) {
                  return _buildBlockCard(blocks[index], index, section);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddBlockButton(String type, String label, IconData icon, String section) {
    return OutlinedButton.icon(
      onPressed: () {
        setState(() {
          final blocks = List<Map<String, dynamic>>.from(
            (_design[section] as List?) ?? const [],
          );
          blocks.add(_createBlock(type));
          _design[section] = blocks;
          _pushHistory();
        });
      },
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Map<String, dynamic> _createBlock(String type) {
    switch (type) {
      case 'text':
        return {
          'type': 'text',
          'props': {
            'text': 'متن {{ title_text }}',
            'align': 'right',
            'showIf': '',
          },
        };
      case 'image':
        return {
          'type': 'image',
          'props': {
            'src': 'https://example.com/logo.png',
            'width': 120,
            'height': null,
            'alt': 'Logo',
            'showIf': '',
          },
        };
      case 'table':
        if ((_moduleKey ?? '') == 'invoices' && (_subtype ?? '') == 'detail') {
          return {
            'type': 'table',
            'props': {
              'items': 'items',
              'columns': [
                {'key': 'product_name', 'title': 'شرح', 'format': ''},
                {'key': 'quantity', 'title': 'تعداد', 'format': ''},
                {'key': 'unit_price', 'title': 'فی', 'format': 'money'},
                {'key': 'line_total', 'title': 'مبلغ', 'format': 'money'},
              ],
              'showIf': '',
            },
          };
        }
        return {
          'type': 'table',
          'props': {
            'items': 'items',
            'columns': [
              {'key': 'name', 'title': 'نام', 'format': ''},
              {'key': 'qty', 'title': 'تعداد', 'format': ''},
              {'key': 'price', 'title': 'قیمت', 'format': 'money'},
            ],
            'showIf': '',
          },
        };
      case 'divider':
        return {
          'type': 'divider',
          'props': {
            'thickness': 1.0,
            'showIf': '',
          },
        };
      case 'spacer':
        return {
          'type': 'spacer',
          'props': {
            'height': 12.0,
            'showIf': '',
          },
        };
      case 'qr':
        return {
          'type': 'qr',
          'props': {
            'src': 'asset:qr',
            'size': 120,
            'showIf': '',
          },
        };
      case 'totals':
        if ((_moduleKey ?? '') == 'invoices' && (_subtype ?? '') == 'detail') {
          return {
            'type': 'totals',
            'props': {
              'items': [
                {'title': 'جمع کل', 'expr': "invoice.payable_total", 'format': 'money'},
                {'title': 'مالیات', 'expr': "invoice.tax_total", 'format': 'money'},
              ],
              'showIf': '',
            },
          };
        }
        return {
          'type': 'totals',
          'props': {
            'items': [
              {'title': 'جمع اقلام', 'expr': "items|sum(attribute='amount')", 'format': 'money'},
              {'title': 'جمع کل', 'expr': "grand_total", 'format': 'money'},
            ],
            'showIf': '',
          },
        };
      default:
        return {'type': type, 'props': {}};
    }
  }

  Widget _buildBlockCard(Map<String, dynamic> block, int index, String section) {
    final type = (block['type'] ?? '').toString();
    final props = (block['props'] as Map?)?.cast<String, dynamic>() ?? {};
    final blocks = List<Map<String, dynamic>>.from(
      (_design[section] as List?) ?? const [],
    );

    return Card(
      key: ValueKey('${section}_$index'),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Icon(_getBlockIcon(type)),
        title: Text(_getBlockTitle(type)),
        subtitle: Text(_getBlockPreview(type, props), maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.drag_handle,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'کپی',
              onPressed: () {
                setState(() {
                  blocks.insert(index + 1, Map<String, dynamic>.from(block));
                  _design[section] = blocks;
                  _pushHistory();
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18),
              tooltip: 'بالا',
              onPressed: index == 0
                  ? null
                  : () {
                      setState(() {
                        final cur = blocks.removeAt(index);
                        blocks.insert(index - 1, cur);
                        _design[section] = blocks;
                        _pushHistory();
                      });
                    },
            ),
            IconButton(
              icon: const Icon(Icons.arrow_downward, size: 18),
              tooltip: 'پایین',
              onPressed: index >= blocks.length - 1
                  ? null
                  : () {
                      setState(() {
                        final cur = blocks.removeAt(index);
                        blocks.insert(index + 1, cur);
                        _design[section] = blocks;
                        _pushHistory();
                      });
                    },
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              tooltip: 'ویرایش',
              onPressed: () => _editBlock(block, index, section),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'حذف',
              onPressed: () {
                setState(() {
                  blocks.removeAt(index);
                  _design[section] = blocks;
                  _pushHistory();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _getBlockIcon(String type) {
    switch (type) {
      case 'text':
        return Icons.text_fields;
      case 'image':
        return Icons.image;
      case 'table':
        return Icons.table_chart;
      case 'divider':
        return Icons.horizontal_rule;
      case 'spacer':
        return Icons.space_bar;
      case 'qr':
        return Icons.qr_code;
      case 'totals':
        return Icons.summarize;
      default:
        return Icons.widgets;
    }
  }

  String _getBlockTitle(String type) {
    switch (type) {
      case 'text':
        return 'متن';
      case 'image':
        return 'تصویر';
      case 'table':
        return 'جدول';
      case 'divider':
        return 'خط جداکننده';
      case 'spacer':
        return 'فاصله';
      case 'qr':
        return 'QR Code';
      case 'totals':
        return 'جمع‌بندی';
      default:
        return type;
    }
  }

  String _getBlockPreview(String type, Map<String, dynamic> props) {
    switch (type) {
      case 'text':
        return (props['text'] ?? '').toString();
      case 'image':
        return (props['src'] ?? '').toString();
      case 'table':
        return '${(props['items'] ?? '').toString()} - ${((props['columns'] as List?)?.length ?? 0)} ستون';
      default:
        return '';
    }
  }

  void _editBlock(Map<String, dynamic> block, int index, String section) {
    final type = (block['type'] ?? '').toString();
    final props = (block['props'] as Map?)?.cast<String, dynamic>() ?? {};
    
    showDialog(
      context: context,
      builder: (ctx) => _buildBlockEditDialog(block, index, section, type, props),
    );
  }

  Widget _buildBlockEditDialog(
    Map<String, dynamic> block,
    int index,
    String section,
    String type,
    Map<String, dynamic> props,
  ) {
    if (type == 'text') {
      return _buildTextBlockDialog(block, index, section, props);
    } else if (type == 'image') {
      return _buildImageBlockDialog(block, index, section, props);
    } else if (type == 'table') {
      return _buildTableBlockDialog(block, index, section, props);
    } else if (type == 'totals') {
      return _buildTotalsBlockDialog(block, index, section, props);
    } else if (type == 'divider') {
      return _buildDividerBlockDialog(block, index, section, props);
    } else if (type == 'spacer') {
      return _buildSpacerBlockDialog(block, index, section, props);
    } else if (type == 'qr') {
      return _buildQrBlockDialog(block, index, section, props);
    }
    
    // For other block types, show a simple message
    return AlertDialog(
      title: Text('ویرایش $type'),
      content: const Text('ویرایش این نوع بلوک در حال توسعه است'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('بستن'),
        ),
      ],
    );
  }

  Widget _buildTextBlockDialog(
    Map<String, dynamic> block,
    int index,
    String section,
    Map<String, dynamic> props,
  ) {
    final textCtrl = TextEditingController(text: (props['text'] ?? '').toString());
    final showIfCtrl = TextEditingController(text: (props['showIf'] ?? '').toString());
    String align = (props['align'] ?? 'right').toString();
    
    return StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: const Text('ویرایش متن'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: textCtrl,
                  decoration: const InputDecoration(
                    labelText: 'متن (می‌توانید از متغیرها استفاده کنید: {{ variable }})',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: align.isEmpty ? 'right' : align,
                  decoration: const InputDecoration(
                    labelText: 'تراز',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'left', child: Text('چپ')),
                    DropdownMenuItem(value: 'center', child: Text('وسط')),
                    DropdownMenuItem(value: 'right', child: Text('راست')),
                  ],
                  onChanged: (v) {
                    align = v ?? 'right';
                    setSt(() {});
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: showIfCtrl,
                  decoration: const InputDecoration(
                    labelText: 'شرط نمایش (اختیاری، Jinja condition)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
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
              setState(() {
                props['text'] = textCtrl.text;
                props['align'] = align;
                props['showIf'] = showIfCtrl.text;
                block['props'] = props;
                final blocks = List<Map<String, dynamic>>.from(
                  (_design[section] as List?) ?? const [],
                );
                blocks[index] = block;
                _design[section] = blocks;
                _pushHistory();
              });
              Navigator.pop(ctx);
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }

  Widget _buildImageBlockDialog(
    Map<String, dynamic> block,
    int index,
    String section,
    Map<String, dynamic> props,
  ) {
    final srcCtrl = TextEditingController(text: (props['src'] ?? '').toString());
    final altCtrl = TextEditingController(text: (props['alt'] ?? '').toString());
    final showIfCtrl = TextEditingController(text: (props['showIf'] ?? '').toString());
    final widthCtrl = TextEditingController(text: (props['width']?.toString() ?? ''));
    final heightCtrl = TextEditingController(text: (props['height']?.toString() ?? ''));

    return StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: const Text('ویرایش تصویر'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: srcCtrl,
                  decoration: const InputDecoration(
                    labelText: 'src (URL یا {{ var }})',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    props['src'] = v;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: widthCtrl,
                        decoration: const InputDecoration(
                          labelText: 'width (px)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          EnglishDigitsFormatter(),
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                        ],
                        onChanged: (v) {
                          if (v.trim().isEmpty) {
                            props['width'] = null;
                          } else {
                            final n = int.tryParse(v.trim());
                            if (n != null) {
                              final step = 4;
                              props['width'] = ((n / step).round() * step);
                              widthCtrl.text = props['width'].toString();
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: heightCtrl,
                        decoration: const InputDecoration(
                          labelText: 'height (px)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          EnglishDigitsFormatter(),
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                        ],
                        onChanged: (v) {
                          if (v.trim().isEmpty) {
                            props['height'] = null;
                          } else {
                            final n = int.tryParse(v.trim());
                            if (n != null) {
                              final step = 4;
                              props['height'] = ((n / step).round() * step);
                              heightCtrl.text = props['height'].toString();
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: altCtrl,
                  decoration: const InputDecoration(
                    labelText: 'alt',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    props['alt'] = v;
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final res = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                        withData: true,
                      );
                      final f = res?.files.isNotEmpty == true ? res!.files.first : null;
                      if (f == null) return;
                      final bytes = f.bytes;
                      if (bytes == null) return;
                      String ext = '';
                      if (f.extension != null && f.extension!.isNotEmpty) {
                        ext = f.extension!.toLowerCase();
                      } else if (f.name.contains('.')) {
                        ext = f.name.split('.').last.toLowerCase();
                      }
                      String mime = 'image/png';
                      if (ext == 'jpg' || ext == 'jpeg') mime = 'image/jpeg';
                      if (ext == 'gif') mime = 'image/gif';
                      final dataUri = 'data:$mime;base64,${base64Encode(bytes)}';
                      props['src'] = dataUri;
                      srcCtrl.text = dataUri;
                      setSt(() {});
                    } catch (e) {
                      debugPrint('خطا در انتخاب فایل: $e');
                    }
                  },
                  icon: const Icon(Icons.file_upload, size: 18),
                  label: const Text('انتخاب فایل و درج Data URI'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: showIfCtrl,
                  decoration: const InputDecoration(
                    labelText: 'showIf (اختیاری، Jinja condition)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    props['showIf'] = v;
                  },
                ),
              ],
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
              setState(() {
                block['props'] = props;
                final blocks = List<Map<String, dynamic>>.from(
                  (_design[section] as List?) ?? const [],
                );
                blocks[index] = block;
                _design[section] = blocks;
                _pushHistory();
              });
              Navigator.pop(ctx);
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }

  Widget _buildTableBlockDialog(
    Map<String, dynamic> block,
    int index,
    String section,
    Map<String, dynamic> props,
  ) {
    final itemsVarCtrl = TextEditingController(text: (props['items'] ?? 'items').toString());
    final cols = List<Map<String, dynamic>>.from((props['columns'] as List?) ?? const []);
    final showIfCtrl = TextEditingController(text: (props['showIf'] ?? '').toString());

    return StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: const Text('ویرایش جدول'),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: itemsVarCtrl,
                  decoration: const InputDecoration(
                    labelText: 'نام آرایه (مثلاً items)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    props['items'] = v;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('ستون‌ها:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () {
                        cols.add({'key': '', 'title': '', 'format': ''});
                        props['columns'] = cols;
                        setSt(() {});
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('افزودن ستون'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...cols.asMap().entries.map((e) {
                  final colIdx = e.key;
                  final col = e.value;
                  final keyCtrl = TextEditingController(text: (col['key'] ?? '').toString());
                  final titleCtrl = TextEditingController(text: (col['title'] ?? '').toString());
                  String fmt = (col['format'] ?? '').toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: keyCtrl,
                            decoration: const InputDecoration(
                              labelText: 'key',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) {
                              col['key'] = v;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: titleCtrl,
                            decoration: const InputDecoration(
                              labelText: 'title',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) {
                              col['title'] = v;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 120,
                          child: DropdownButtonFormField<String>(
                            value: fmt.isEmpty ? null : fmt,
                            decoration: const InputDecoration(
                              labelText: 'format',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(value: 'money', child: Text('money')),
                              DropdownMenuItem(value: 'date', child: Text('date')),
                              DropdownMenuItem(value: '', child: Text('none')),
                            ],
                            onChanged: (v) {
                              col['format'] = v ?? '';
                              setSt(() {});
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            cols.removeAt(colIdx);
                            props['columns'] = cols;
                            setSt(() {});
                          },
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                TextField(
                  controller: showIfCtrl,
                  decoration: const InputDecoration(
                    labelText: 'showIf (اختیاری، Jinja condition)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    props['showIf'] = v;
                  },
                ),
              ],
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
              setState(() {
                block['props'] = props;
                final blocks = List<Map<String, dynamic>>.from(
                  (_design[section] as List?) ?? const [],
                );
                blocks[index] = block;
                _design[section] = blocks;
                _pushHistory();
              });
              Navigator.pop(ctx);
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsBlockDialog(
    Map<String, dynamic> block,
    int index,
    String section,
    Map<String, dynamic> props,
  ) {
    final items = List<Map<String, dynamic>>.from((props['items'] as List?) ?? const []);
    final showIfCtrl = TextEditingController(text: (props['showIf'] ?? '').toString());

    return StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: const Text('ویرایش جمع‌بندی'),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('آیتم‌ها:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () {
                        items.add({'title': 'آیتم', 'expr': '0', 'format': ''});
                        props['items'] = items;
                        setSt(() {});
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('افزودن ردیف'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...items.asMap().entries.map((e) {
                  final idx = e.key;
                  final it = e.value;
                  final titleCtrl = TextEditingController(text: (it['title'] ?? '').toString());
                  final exprCtrl = TextEditingController(text: (it['expr'] ?? '').toString());
                  String fmt = (it['format'] ?? '').toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: titleCtrl,
                            decoration: const InputDecoration(
                              labelText: 'عنوان',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) {
                              it['title'] = v;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: exprCtrl,
                            decoration: const InputDecoration(
                              labelText: 'expr (مثلاً items|sum(attribute="amount"))',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) {
                              it['expr'] = v;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 120,
                          child: DropdownButtonFormField<String>(
                            value: fmt.isEmpty ? null : fmt,
                            decoration: const InputDecoration(
                              labelText: 'format',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(value: 'money', child: Text('money')),
                              DropdownMenuItem(value: 'date', child: Text('date')),
                              DropdownMenuItem(value: '', child: Text('none')),
                            ],
                            onChanged: (v) {
                              it['format'] = v ?? '';
                              setSt(() {});
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            items.removeAt(idx);
                            props['items'] = items;
                            setSt(() {});
                          },
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                TextField(
                  controller: showIfCtrl,
                  decoration: const InputDecoration(
                    labelText: 'showIf (اختیاری، Jinja condition)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    props['showIf'] = v;
                  },
                ),
              ],
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
              setState(() {
                block['props'] = props;
                final blocks = List<Map<String, dynamic>>.from(
                  (_design[section] as List?) ?? const [],
                );
                blocks[index] = block;
                _design[section] = blocks;
                _pushHistory();
              });
              Navigator.pop(ctx);
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }

  Widget _buildDividerBlockDialog(
    Map<String, dynamic> block,
    int index,
    String section,
    Map<String, dynamic> props,
  ) {
    final thicknessCtrl = TextEditingController(text: (props['thickness']?.toString() ?? '1'));
    final showIfCtrl = TextEditingController(text: (props['showIf'] ?? '').toString());

    return StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: const Text('ویرایش خط جداکننده'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: thicknessCtrl,
                decoration: const InputDecoration(
                  labelText: 'ضخامت (px)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (v) {
                  props['thickness'] = double.tryParse(v.trim()) ?? 1.0;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: showIfCtrl,
                decoration: const InputDecoration(
                  labelText: 'showIf (اختیاری، Jinja condition)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  props['showIf'] = v;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                block['props'] = props;
                final blocks = List<Map<String, dynamic>>.from(
                  (_design[section] as List?) ?? const [],
                );
                blocks[index] = block;
                _design[section] = blocks;
                _pushHistory();
              });
              Navigator.pop(ctx);
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }

  Widget _buildSpacerBlockDialog(
    Map<String, dynamic> block,
    int index,
    String section,
    Map<String, dynamic> props,
  ) {
    final heightCtrl = TextEditingController(text: (props['height']?.toString() ?? '12'));
    final showIfCtrl = TextEditingController(text: (props['showIf'] ?? '').toString());

    return StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: const Text('ویرایش فاصله'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: heightCtrl,
                decoration: const InputDecoration(
                  labelText: 'ارتفاع (px)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (v) {
                  props['height'] = double.tryParse(v.trim()) ?? 12.0;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: showIfCtrl,
                decoration: const InputDecoration(
                  labelText: 'showIf (اختیاری، Jinja condition)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  props['showIf'] = v;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                block['props'] = props;
                final blocks = List<Map<String, dynamic>>.from(
                  (_design[section] as List?) ?? const [],
                );
                blocks[index] = block;
                _design[section] = blocks;
                _pushHistory();
              });
              Navigator.pop(ctx);
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }

  Widget _buildQrBlockDialog(
    Map<String, dynamic> block,
    int index,
    String section,
    Map<String, dynamic> props,
  ) {
    final srcCtrl = TextEditingController(text: (props['src'] ?? '').toString());
    final sizeCtrl = TextEditingController(text: (props['size']?.toString() ?? '120'));
    final showIfCtrl = TextEditingController(text: (props['showIf'] ?? '').toString());

    return StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: const Text('ویرایش QR Code'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: srcCtrl,
                decoration: const InputDecoration(
                  labelText: 'src (مثلاً asset:qr یا {{ variable }})',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  props['src'] = v;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sizeCtrl,
                decoration: const InputDecoration(
                  labelText: 'اندازه (px)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                ],
                onChanged: (v) {
                  props['size'] = int.tryParse(v.trim()) ?? 120;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: showIfCtrl,
                decoration: const InputDecoration(
                  labelText: 'showIf (اختیاری، Jinja condition)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  props['showIf'] = v;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                block['props'] = props;
                final blocks = List<Map<String, dynamic>>.from(
                  (_design[section] as List?) ?? const [],
                );
                blocks[index] = block;
                _design[section] = blocks;
                _pushHistory();
              });
              Navigator.pop(ctx);
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }

  Widget _buildCssEditor() {
    final cssCtrl = TextEditingController(text: (_design['css'] ?? '').toString());
    
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.code, size: 20),
              SizedBox(width: 8),
              Text('CSS سفارشی (اختیاری)'),
            ],
          ),
        ),
        Expanded(
          child: TextField(
            controller: cssCtrl,
            decoration: const InputDecoration(
              hintText: 'CSS styles...',
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
            ),
            maxLines: null,
            expands: true,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            onChanged: (value) {
              setState(() {
                _design['css'] = value;
                _pushHistory();
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              const Text('پیش‌نمایش', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() => _showPreview = false);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _previewLoading
              ? const Center(child: LoadingIndicator())
                  : _previewHtml == null
                      ? const Center(child: Text('برای مشاهده پیش‌نمایش، دکمه پیش‌نمایش را بزنید'))
                      : _previewPdfBytes != null
                          ? _buildPdfPreview(_previewPdfBytes!)
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Theme.of(context).dividerColor),
                                  color: Colors.white,
                                ),
                                child: _buildHtmlPreview(_previewHtml!),
                              ),
                            ),
        ),
      ],
    );
  }

  Widget _buildPdfPreview(Uint8List pdfBytes) {
    // For web, use iframe to display PDF
    // For other platforms, show download option
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              const Text('پیش‌نمایش PDF', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
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
                        SnackBarHelper.show(context, message: 'دانلود PDF آغاز شد');
                      }
                    } else {
                      final path = await FileSaver.saveBytes(pdfBytes, 'report_preview.pdf');
                      if (mounted) {
                        SnackBarHelper.show(
                          context,
                          message: path != null ? 'ذخیره شد: $path' : 'فایل ذخیره شد',
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      SnackBarHelper.showError(
                        context,
                        message:
                            'خطا در دانلود: ${ErrorExtractor.forContext(e, context)}',
                      );
                    }
                  }
                },
                icon: const Icon(Icons.download, size: 18),
                label: const Text('دانلود PDF'),
              ),
              if (kIsWeb) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    final url = web_utils.createObjectUrlFromBytes(
                      pdfBytes,
                      mimeType: 'application/pdf',
                    );
                    web_utils.openUrlInNewTabWeb(url);
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('تب جدید'),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              color: Colors.white,
            ),
            clipBehavior: Clip.hardEdge,
            child: _buildPdfViewer(pdfBytes),
          ),
        ),
      ],
    );
  }
  
  Widget _buildPdfViewer(Uint8List pdfBytes) {
    return SizedBox.expand(
      child: ReportTemplateEmbeddedPdf(bytes: pdfBytes),
    );
  }

  Widget _buildCanvasView(String section) {
    final blocks = List<Map<String, dynamic>>.from(
      (_design[section] as List?) ?? const [],
    );

    return Column(
      children: [
        // Canvas toolbar
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              const Text('Canvas View', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.zoom_out, size: 20),
                onPressed: () {
                  setState(() {
                    _canvasZoom = (_canvasZoom - 0.1).clamp(0.5, 2.0);
                  });
                },
                tooltip: 'کوچک کردن',
              ),
              Text('${(_canvasZoom * 100).toInt()}%'),
              IconButton(
                icon: const Icon(Icons.zoom_in, size: 20),
                onPressed: () {
                  setState(() {
                    _canvasZoom = (_canvasZoom + 0.1).clamp(0.5, 2.0);
                  });
                },
                tooltip: 'بزرگ کردن',
              ),
              IconButton(
                icon: const Icon(Icons.center_focus_strong, size: 20),
                onPressed: () {
                  setState(() {
                    _canvasZoom = 1.0;
                    _canvasPan = Offset.zero;
                  });
                },
                tooltip: 'بازنشانی',
              ),
            ],
          ),
        ),
        // Canvas area
        Expanded(
          child: DragTarget<String>(
            onAccept: (blockType) {
              final allowed = _availableBlockTypes().any((b) => b['type'] == blockType);
              if (!allowed) return;
              setState(() {
                blocks.add(_createBlock(blockType));
                _design[section] = blocks;
                _pushHistory();
              });
            },
            builder: (context, candidateData, rejectedData) {
              return GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _canvasPan += details.delta;
                  });
                },
                onScaleUpdate: (details) {
                  setState(() {
                    _canvasZoom = (_canvasZoom * details.scale).clamp(0.5, 2.0);
                  });
                },
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
                  child: Transform.scale(
                    scale: _canvasZoom,
                    child: Transform.translate(
                      offset: _canvasPan,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (blocks.isEmpty)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.drag_indicator,
                                        size: 64,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'بلوک‌ها را از پالت اینجا بکشید',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ...blocks.asMap().entries.map((entry) {
                                final index = entry.key;
                                final block = entry.value;
                                return _buildCanvasBlock(block, index, section);
                              }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCanvasBlock(Map<String, dynamic> block, int index, String section) {
    final type = (block['type'] ?? '').toString();
    final props = (block['props'] as Map?)?.cast<String, dynamic>() ?? {};
    final blocks = List<Map<String, dynamic>>.from(
      (_design[section] as List?) ?? const [],
    );

    return Card(
      key: ValueKey('canvas_${section}_$index'),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => _editBlock(block, index, section),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_getBlockIcon(type), color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    _getBlockTitle(type),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (value) {
                      if (value == 'duplicate') {
                        setState(() {
                          blocks.insert(index + 1, Map<String, dynamic>.from(block));
                          _design[section] = blocks;
                          _pushHistory();
                        });
                      } else if (value == 'delete') {
                        setState(() {
                          blocks.removeAt(index);
                          _design[section] = blocks;
                          _pushHistory();
                        });
                      } else if (value == 'up' && index > 0) {
                        setState(() {
                          final cur = blocks.removeAt(index);
                          blocks.insert(index - 1, cur);
                          _design[section] = blocks;
                          _pushHistory();
                        });
                      } else if (value == 'down' && index < blocks.length - 1) {
                        setState(() {
                          final cur = blocks.removeAt(index);
                          blocks.insert(index + 1, cur);
                          _design[section] = blocks;
                          _pushHistory();
                        });
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'duplicate',
                        child: Row(
                          children: [
                            Icon(Icons.copy, size: 18),
                            SizedBox(width: 8),
                            Text('کپی'),
                          ],
                        ),
                      ),
                      if (index > 0)
                        const PopupMenuItem(
                          value: 'up',
                          child: Row(
                            children: [
                              Icon(Icons.arrow_upward, size: 18),
                              SizedBox(width: 8),
                              Text('بالا'),
                            ],
                          ),
                        ),
                      if (index < blocks.length - 1)
                        const PopupMenuItem(
                          value: 'down',
                          child: Row(
                            children: [
                              Icon(Icons.arrow_downward, size: 18),
                              SizedBox(width: 8),
                              Text('پایین'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('حذف', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: _buildBlockPreviewContent(type, props),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlockPreviewContent(String type, Map<String, dynamic> props) {
    switch (type) {
      case 'text':
        final text = (props['text'] ?? '').toString();
        return Text(
          text.isEmpty ? 'متن خالی' : text,
          textAlign: _getTextAlign(props['align']),
          style: const TextStyle(fontSize: 14),
        );
      case 'image':
        final src = (props['src'] ?? '').toString();
        if (src.startsWith('data:')) {
          try {
            final base64 = src.split(',')[1];
            final bytes = base64Decode(base64);
            return Image.memory(
              bytes,
              height: (props['height'] as num?)?.toDouble() ?? 100,
              width: (props['width'] as num?)?.toDouble(),
              fit: BoxFit.contain,
            );
          } catch (e) {
            return const Text('خطا در نمایش تصویر');
          }
        }
        return Text('تصویر: $src');
      case 'table':
        final items = (props['items'] ?? 'items').toString();
        final cols = ((props['columns'] as List?) ?? []).length;
        return Text('جدول: $items (${cols} ستون)');
      case 'totals':
        final items = ((props['items'] as List?) ?? []).length;
        return Text('جمع‌بندی: $items آیتم');
      case 'divider':
        final thickness = (props['thickness'] as num?)?.toDouble() ?? 1.0;
        return Divider(thickness: thickness);
      case 'spacer':
        final height = (props['height'] as num?)?.toDouble() ?? 12.0;
        return SizedBox(height: height);
      case 'qr':
        return Row(
          children: [
            const Icon(Icons.qr_code, size: 48),
            const SizedBox(width: 8),
            Text('QR Code: ${props['src'] ?? ''}'),
          ],
        );
      default:
        return Text('نوع بلوک: $type');
    }
  }

  TextAlign _getTextAlign(dynamic align) {
    final alignStr = (align ?? 'right').toString();
    switch (alignStr) {
      case 'left':
        return TextAlign.left;
      case 'center':
        return TextAlign.center;
      case 'right':
      default:
        return TextAlign.right;
    }
  }

  Widget _buildHtmlPreview(String html) {
    // For now, show HTML as formatted text
    // TODO: In the future, we can add a proper HTML renderer or use iframe for web
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('پیش‌نمایش HTML:', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: html));
                  SnackBarHelper.show(context, message: 'HTML کپی شد');
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('کپی HTML'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  html,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
