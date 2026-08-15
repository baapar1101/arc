import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/auth_store.dart';
import '../../../models/barcode_label/label_printer_profile.dart';
import '../../../models/barcode_label/label_design_v1.dart';
import '../../../services/barcode_label_service.dart';
import '../../../services/bytes_export/bytes_export_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/barcode_label/render/label_image_resolver.dart';
import '../../../widgets/barcode_label/render/label_pdf_renderer.dart';
import '../../../widgets/barcode_label/studio/label_studio_barcode_painter.dart';
import '../../../widgets/barcode_label/studio/label_element_handles.dart';
import '../../../widgets/barcode_label/studio/label_rulers.dart';
import '../../../widgets/barcode_label/studio/label_studio_history.dart';
import '../../../widgets/barcode_label/studio/label_studio_image_view.dart';
import '../../../widgets/barcode_label/studio/label_studio_live_preview.dart';
import '../../../widgets/barcode_label/studio/label_studio_matrix_painter.dart';
import '../../../widgets/business_subpage_back_leading.dart';

/// Label design studio — Phase B (canvas mm, selection, toolbox, save).
class LabelStudioPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final int? templateId;
  final double? initialWidthMm;
  final double? initialHeightMm;
  final bool initialRollMode;

  const LabelStudioPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.templateId,
    this.initialWidthMm,
    this.initialHeightMm,
    this.initialRollMode = false,
  });

  @override
  State<LabelStudioPage> createState() => _LabelStudioPageState();
}

class _LabelStudioPageState extends State<LabelStudioPage> {
  final _service = BarcodeLabelService();
  final _nameCtrl = TextEditingController();
  final _transform = TransformationController();
  final _history = LabelStudioHistory();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  int? _templateId;
  String _status = 'draft';
  bool _isDefault = false;
  int _version = 1;
  LabelDesignDocument _design = LabelDesignDocument.empty();
  LabelSheet _sheet = const LabelSheet();
  Map<String, dynamic> _sample = const {};
  final Map<String, String> _sampleOverrides = {};
  String? _selectedId;
  String _tool = 'select';
  bool _dirty = false;
  String? _savedFingerprint;
  double _canvasZoom = 1.0;
  bool _handleDragCheckpointed = false;
  bool _draggingElement = false;
  bool _showLivePreview = false;
  LabelPrinterSettings? _printerSettings;

  static const double _pxPerMm = 3.7795275591; // ~96dpi
  static const double _canvasOffsetPx = 40.0;
  static const double _rulerThickness = 24.0;

  /// Convert GestureDetector pan deltas to canvas mm.
  /// Same approach as [WorkflowNodeWidget]: deltas inside InteractiveViewer are
  /// viewport pixels, so divide by current zoom before px→mm.
  Offset _deltaPxToMm(double dxPx, double dyPx) {
    final scale = _transform.value.getMaxScaleOnAxis().abs();
    final s = scale < 1e-6 ? 1.0 : scale;
    return Offset(dxPx / (_pxPerMm * s), dyPx / (_pxPerMm * s));
  }

  double _snapMm(double value) {
    if (!_design.canvas.snapToGrid) return value;
    final g = _design.canvas.gridMm;
    if (g <= 0) return value;
    return (value / g).round() * g;
  }

  Map<String, dynamic> get _effectiveSample => _mergeSample(_sample, _sampleOverrides);

  static Map<String, dynamic> _mergeSample(
    Map<String, dynamic> base,
    Map<String, String> overrides,
  ) {
    if (overrides.isEmpty) return base;
    final out = Map<String, dynamic>.from(base);
    for (final e in overrides.entries) {
      final parts = e.key.split('.');
      if (parts.length != 2) continue;
      final section = out.putIfAbsent(parts[0], () => <String, dynamic>{});
      if (section is Map<String, dynamic>) {
        section[parts[1]] = e.value;
      }
    }
    return out;
  }

  Set<String> _previewBindingKeys() {
    const defaults = {
      'product.name',
      'product.code',
      'product.general_barcode',
      'product.price',
      'product.sale_price',
    };
    return {...defaults, ..._usedBindings()};
  }

  Set<String> _usedBindings() {
    final keys = <String>{};
    for (final el in _design.elements) {
      if ((el.props['content_mode'] ?? 'binding').toString() == 'binding') {
        final b = el.props['binding']?.toString();
        if (b != null && b.isNotEmpty) keys.add(b);
      }
    }
    return keys;
  }

  bool get _canDesign =>
      widget.authStore.hasBusinessPermission('barcode_labels', 'design');

  @override
  void initState() {
    super.initState();
    _templateId = widget.templateId;
    _transform.addListener(_onTransformChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _nameCtrl.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final z = _transform.value.getMaxScaleOnAxis();
    if (z != _canvasZoom && mounted) {
      setState(() => _canvasZoom = z);
    }
  }

  String _fingerprint() =>
      '${_nameCtrl.text}|${_design.toJson()}|${_sheet.toJson()}';

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _sample = await _service.sampleContext(businessId: widget.businessId);
      try {
        _printerSettings = await _service.getPrinterSettings(businessId: widget.businessId);
      } catch (_) {
        _printerSettings = null;
      }
      if (_templateId != null) {
        final detail = await _service.getTemplate(
          businessId: widget.businessId,
          templateId: _templateId!,
        );
        _nameCtrl.text = detail.name;
        _design = detail.design;
        _sheet = detail.sheet;
        _status = detail.status;
        _isDefault = detail.isDefault;
        _version = detail.version;
      } else {
        _nameCtrl.text = 'Untitled';
        final w = widget.initialWidthMm ?? 50;
        final h = widget.initialHeightMm ?? 30;
        _design = LabelDesignDocument.empty(widthMm: w, heightMm: h);
        _sheet = widget.initialRollMode
            ? const LabelSheet(printMode: 'roll')
            : const LabelSheet();
      }
      _savedFingerprint = _fingerprint();
      _dirty = false;
      _history.clear();
      if (mounted) setState(() => _loading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitView();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  void _fitView() {
    final w = _design.canvas.widthMm * _pxPerMm;
    final scale = math.min(1.5, 600 / math.max(w, 1));
    _transform.value = Matrix4.identity()
      ..translateByDouble(_canvasOffsetPx, _canvasOffsetPx, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    setState(() {});
  }

  void _markDirty() {
    final dirty = _fingerprint() != _savedFingerprint;
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  void _checkpoint() => _history.checkpoint(_design);

  void _undo() {
    final prev = _history.undo(_design);
    if (prev == null) return;
    setState(() => _design = prev);
    _markDirty();
  }

  void _redo() {
    final next = _history.redo(_design);
    if (next == null) return;
    setState(() => _design = next);
    _markDirty();
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFa ? 'خروج' : 'Leave'),
        content: Text(
          isFa
              ? 'تغییرات ذخیره‌نشده دارید. خارج می‌شوید؟'
              : 'You have unsaved changes. Leave?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isFa ? 'ماندن' : 'Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isFa ? 'خروج' : 'Leave'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _popAfterLeaveConfirmed() {
    _dirty = false;
    if (!mounted) return;
    hesabixNavigateBack(context, businessId: widget.businessId);
  }

  Future<void> _save({bool publish = false}) async {
    if (!_canDesign) return;
    setState(() => _saving = true);
    try {
      LabelTemplateDetail detail;
      if (_templateId == null) {
        detail = await _service.createTemplate(
          businessId: widget.businessId,
          name: _nameCtrl.text.trim().isEmpty
              ? AppLocalizations.of(context).barcodeLabelUntitled
              : _nameCtrl.text.trim(),
          designJson: _design.toJson(),
          sheetJson: _sheet.toJson(),
        );
        _templateId = detail.id;
      } else {
        detail = await _service.updateTemplate(
          businessId: widget.businessId,
          templateId: _templateId!,
          name: _nameCtrl.text.trim(),
          designJson: _design.toJson(),
          sheetJson: _sheet.toJson(),
        );
      }
      if (publish) {
        detail = await _service.publishTemplate(
          businessId: widget.businessId,
          templateId: detail.id,
        );
      }
      _status = detail.status;
      _isDefault = detail.isDefault;
      _version = detail.version;
      _savedFingerprint = _fingerprint();
      _dirty = false;
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: publish
            ? AppLocalizations.of(context).barcodeLabelPublished
            : AppLocalizations.of(context).barcodeLabelSaved,
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _previewPdf() async {
    final t = AppLocalizations.of(context);
    try {
      final bytes = await LabelPdfRenderer.render(
        design: _design,
        sheet: _sheet,
        contexts: [_effectiveSample, _effectiveSample],
        rollMode: _sheet.isRollMode,
        businessId: widget.businessId,
      );
      if (!mounted) return;
      final result = await BytesExportService.export(
        bytes: bytes,
        filename: 'label-studio-preview.pdf',
        mimeType: 'application/pdf',
      );
      if (!mounted) return;
      BytesExportService.showFeedback(context, result, successOverride: t.labelPdfSaved);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  void _addElement(LabelElementType type) {
    if (!_canDesign) return;
    _checkpoint();
    final id = 'el_${DateTime.now().microsecondsSinceEpoch}';
    final defaults = switch (type) {
      LabelElementType.text => (
          20.0,
          6.0,
          <String, dynamic>{
            'content_mode': 'binding',
            'binding': 'product.name',
            'font_family': 'YekanBakhFaNum',
            'font_size_pt': 9,
            'font_weight': 'bold',
            'align': 'center',
            'valign': 'middle',
            'color': '#000000',
            'rtl': true,
            'wrap': true,
          },
        ),
      LabelElementType.barcode => (
          40.0,
          14.0,
          <String, dynamic>{
            'symbology': 'code128',
            'content_mode': 'binding',
            'binding': 'product.general_barcode',
            'show_text': true,
            'text_size_pt': 7,
            'quiet_zone_mm': 1,
          },
        ),
      LabelElementType.qr => (
          18.0,
          18.0,
          <String, dynamic>{
            'content_mode': 'binding',
            'binding': 'product.general_barcode',
            'ecc': 'M',
            'quiet_zone_mm': 1,
          },
        ),
      LabelElementType.datamatrix => (
          16.0,
          16.0,
          <String, dynamic>{
            'content_mode': 'binding',
            'binding': 'product.general_barcode',
            'quiet_zone_mm': 1,
          },
        ),
      LabelElementType.image => (
          12.0,
          12.0,
          <String, dynamic>{'source': 'business.logo', 'fit': 'contain', 'opacity': 1},
        ),
      LabelElementType.shape => (
          20.0,
          10.0,
          <String, dynamic>{
            'shape': 'rect',
            'stroke': '#000000',
            'fill': null,
            'stroke_width_mm': 0.3,
          },
        ),
      LabelElementType.line => (
          30.0,
          1.0,
          <String, dynamic>{'stroke': '#000000', 'stroke_width_mm': 0.4},
        ),
    };

    final el = LabelElement(
      id: id,
      type: type,
      name: type.name,
      xMm: 4,
      yMm: 4,
      wMm: defaults.$1,
      hMm: defaults.$2,
      zIndex: _design.elements.length + 1,
      props: defaults.$3,
    );
    setState(() {
      _design = _design.copyWith(elements: [..._design.elements, el]);
      _selectedId = id;
      _tool = 'select';
    });
    _markDirty();
  }

  void _deleteSelected() {
    if (_selectedId == null || !_canDesign) return;
    final el = _design.elements.cast<LabelElement?>().firstWhere(
          (e) => e?.id == _selectedId,
          orElse: () => null,
        );
    if (el == null || el.locked) return;
    _checkpoint();
    setState(() {
      _design = _design.copyWith(
        elements: _design.elements.where((e) => e.id != _selectedId).toList(),
      );
      _selectedId = null;
    });
    _markDirty();
  }

  void _nudgeSelected(double dx, double dy) {
    if (_selectedId == null || !_canDesign) return;
    _checkpoint();
    setState(() {
      _design = _design.copyWith(
        elements: _design.elements.map((e) {
          if (e.id != _selectedId || e.locked) return e;
          var x = e.xMm + dx;
          var y = e.yMm + dy;
          if (_design.canvas.snapToGrid) {
            final g = _design.canvas.gridMm;
            x = (x / g).round() * g;
            y = (y / g).round() * g;
          }
          return e.copyWith(xMm: x, yMm: y);
        }).toList(),
      );
    });
    _markDirty();
  }

  LabelElement? get _selected {
    if (_selectedId == null) return null;
    for (final e in _design.elements) {
      if (e.id == _selectedId) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t.barcodeLabelStudioTitle),
          leading: businessSubpageBackLeading(context, widget.businessId),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t.barcodeLabelStudioTitle),
          leading: businessSubpageBackLeading(context, widget.businessId),
        ),
        body: Center(child: Text(_error!)),
      );
    }

    return HesabixBackInterceptor(
      onWillPop: () async {
        if (!_dirty) return true;
        return _confirmLeave();
      },
      child: CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save(),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _redo,
        const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
        const SingleActivator(LogicalKeyboardKey.backspace): _deleteSelected,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _nudgeSelected(-1, 0),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _nudgeSelected(1, 0),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _nudgeSelected(0, -1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _nudgeSelected(0, 1),
        const SingleActivator(LogicalKeyboardKey.keyV): () => setState(() => _tool = 'select'),
        const SingleActivator(LogicalKeyboardKey.keyT): () => _addElement(LabelElementType.text),
        const SingleActivator(LogicalKeyboardKey.keyB): () => _addElement(LabelElementType.barcode),
        const SingleActivator(LogicalKeyboardKey.keyQ): () => _addElement(LabelElementType.qr),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
            title: Row(
              children: [
                Flexible(
                  child: TextField(
                    controller: _nameCtrl,
                    readOnly: !_canDesign,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                    onChanged: (_) => _markDirty(),
                  ),
                ),
                if (_dirty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('•', style: TextStyle(color: cs.primary, fontSize: 22)),
                  ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_status == 'published' ? t.barcodeLabelFilterPublished : t.barcodeLabelFilterDraft),
                ),
              ],
            ),
            actions: [
              if (_canDesign)
                IconButton(
                  tooltip: 'Undo',
                  onPressed: _history.canUndo ? _undo : null,
                  icon: const Icon(Icons.undo),
                ),
              if (_canDesign)
                IconButton(
                  tooltip: 'Redo',
                  onPressed: _history.canRedo ? _redo : null,
                  icon: const Icon(Icons.redo),
                ),
              IconButton(
                tooltip: t.barcodeLabelLivePreview,
                onPressed: () => setState(() => _showLivePreview = !_showLivePreview),
                icon: Icon(_showLivePreview ? Icons.visibility : Icons.visibility_outlined),
              ),
              IconButton(
                tooltip: t.barcodeLabelPreviewPdf,
                onPressed: _previewPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
              ),
              if (_canDesign)
                TextButton(
                  onPressed: _saving ? null : () => _save(),
                  child: Text(t.save),
                ),
              if (_canDesign)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(publish: true),
                    child: Text(t.barcodeLabelPublish),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _Toolbox(
                      tool: _tool,
                      onTool: (v) => setState(() => _tool = v),
                      onAdd: _addElement,
                      enabled: _canDesign,
                    ),
                    Expanded(child: _buildEditorRow(cs)),
                    _Inspector(
                      element: _selected,
                      design: _design,
                      sheet: _sheet,
                      canDesign: _canDesign,
                      printerProfile: _printerSettings?.activeProfile,
                      onApplyPrinterSize: _canDesign ? _applyPrinterSizeToCanvas : null,
                      sampleBindings: _previewBindingKeys(),
                      sampleOverrides: _sampleOverrides,
                      sample: _effectiveSample,
                      onSampleOverride: (key, value) {
                        setState(() {
                          if (value.trim().isEmpty) {
                            _sampleOverrides.remove(key);
                          } else {
                            _sampleOverrides[key] = value;
                          }
                        });
                      },
                      onCanvasChanged: (canvas) {
                        _checkpoint();
                        setState(() => _design = _design.copyWith(canvas: canvas));
                        _markDirty();
                      },
                      onSheetChanged: (sheet) {
                        _checkpoint();
                        setState(() => _sheet = sheet);
                        _markDirty();
                      },
                      onChanged: (el) {
                        _checkpoint();
                        setState(() {
                          _design = _design.copyWith(
                            elements: _design.elements.map((e) => e.id == el.id ? el : e).toList(),
                          );
                        });
                        _markDirty();
                      },
                onSelect: (id) => setState(() => _selectedId = id),
                onReorderLayers: _reorderLayers,
              ),
                  ],
                ),
              ),
              if (_showLivePreview)
                SizedBox(
                  height: 280,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                        child: Text(
                          t.barcodeLabelLivePreview,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      Expanded(
                        child: LabelStudioLivePreview(
                          design: _design,
                          sheet: _sheet,
                          sampleContext: _effectiveSample,
                          businessId: widget.businessId,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          bottomNavigationBar: Material(
            elevation: 2,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      '${_design.canvas.widthMm.toStringAsFixed(0)}×${_design.canvas.heightMm.toStringAsFixed(0)} mm',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(width: 16),
                    if (_selected != null)
                      Text(
                        'X:${_selected!.xMm.toStringAsFixed(1)}  Y:${_selected!.yMm.toStringAsFixed(1)}  '
                        'W:${_selected!.wMm.toStringAsFixed(1)}  H:${_selected!.hMm.toStringAsFixed(1)}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    const Spacer(),
                    Text('v$_version${_isDefault ? ' ★' : ''}', style: Theme.of(context).textTheme.labelSmall),
                    IconButton(
                      tooltip: 'Fit',
                      onPressed: _fitView,
                      icon: const Icon(Icons.fit_screen),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  void _reorderLayers(int oldIndex, int newIndex) {
    if (!_canDesign) return;
    if (newIndex > oldIndex) newIndex -= 1;
    _checkpoint();
    final sorted = List<LabelElement>.from(_design.elements)
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    final visual = sorted.reversed.toList();
    final item = visual.removeAt(oldIndex);
    visual.insert(newIndex, item);
    final reordered = visual.reversed.toList();
    final updated = <LabelElement>[
      for (var i = 0; i < reordered.length; i++)
        reordered[i].copyWith(zIndex: i + 1),
    ];
    setState(() => _design = _design.copyWith(elements: updated));
    _markDirty();
  }

  void _applyPrinterSizeToCanvas() {
    final profile = _printerSettings?.activeProfile;
    if (profile == null || !_canDesign) return;
    _checkpoint();
    setState(() {
      _design = _design.copyWith(
        canvas: _design.canvas.copyWith(
          widthMm: profile.labelWidthMm,
          heightMm: profile.labelHeightMm,
        ),
      );
      if (!_sheet.isRollMode) {
        _sheet = _sheet.copyWith(printMode: 'roll');
      }
    });
    _markDirty();
  }

  Widget _buildEditorRow(ColorScheme cs) {
    final w = _design.canvas.widthMm * _pxPerMm;
    final h = _design.canvas.heightMm * _pxPerMm;
    final canvasArea = InteractiveViewer(
      transformationController: _transform,
      minScale: 0.25,
      maxScale: 4,
      constrained: false,
      // While dragging an element, keep the viewport still so pan doesn't fight move.
      panEnabled: _tool == 'hand' && !_draggingElement,
      scaleEnabled: !_draggingElement,
      boundaryMargin: const EdgeInsets.all(800),
      child: SizedBox(
        width: w + 80,
        height: h + 80,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: _canvasOffsetPx,
              top: _canvasOffsetPx,
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: CustomPaint(
                  painter: _GridPainter(
                    widthMm: _design.canvas.widthMm,
                    heightMm: _design.canvas.heightMm,
                    gridMm: _design.canvas.gridMm,
                    pxPerMm: _pxPerMm,
                  ),
                  child: Builder(
                    builder: (context) {
                      final els = List<LabelElement>.from(_design.elements)
                        ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final el in els)
                            if (el.visible)
                              Positioned(
                                left: el.xMm * _pxPerMm,
                                top: el.yMm * _pxPerMm,
                                width: el.wMm * _pxPerMm,
                                height: el.hMm * _pxPerMm,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    _ElementView(
                                      element: el,
                                      selected: el.id == _selectedId,
                                      sample: _effectiveSample,
                                      businessId: widget.businessId,
                                      onTap: () => setState(() => _selectedId = el.id),
                                      onDragStart: _canDesign && !el.locked
                                          ? () {
                                              _checkpoint();
                                              setState(() => _draggingElement = true);
                                            }
                                          : null,
                                      onDrag: _canDesign && !el.locked
                                          ? (dxPx, dyPx) {
                                              final d = _deltaPxToMm(dxPx, dyPx);
                                              setState(() {
                                                _design = _design.copyWith(
                                                  elements: _design.elements.map((e) {
                                                    if (e.id != el.id) return e;
                                                    // Continuous drag without per-frame snap so
                                                    // motion tracks the pointer; snap on end.
                                                    return e.copyWith(
                                                      xMm: e.xMm + d.dx,
                                                      yMm: e.yMm + d.dy,
                                                    );
                                                  }).toList(),
                                                );
                                                _selectedId = el.id;
                                              });
                                              _markDirty();
                                            }
                                          : null,
                                      onDragEnd: _canDesign && !el.locked
                                          ? () {
                                              setState(() {
                                                _draggingElement = false;
                                                if (_design.canvas.snapToGrid) {
                                                  _design = _design.copyWith(
                                                    elements: _design.elements.map((e) {
                                                      if (e.id != el.id) return e;
                                                      return e.copyWith(
                                                        xMm: _snapMm(e.xMm),
                                                        yMm: _snapMm(e.yMm),
                                                      );
                                                    }).toList(),
                                                  );
                                                }
                                              });
                                              _markDirty();
                                            }
                                          : null,
                                    ),
                                    if (el.id == _selectedId && !el.locked && _canDesign)
                                      LabelElementTransformHandles(
                                        element: el,
                                        pxPerMm: _pxPerMm,
                                        enabled: true,
                                        onDragStart: () {
                                          if (!_handleDragCheckpointed) {
                                            _checkpoint();
                                            _handleDragCheckpointed = true;
                                          }
                                          setState(() => _draggingElement = true);
                                        },
                                        onDrag: (kind, dxPx, dyPx) {
                                          final current = _design.elements
                                              .firstWhere((e) => e.id == el.id);
                                          final LabelElement updated;
                                          if (kind == LabelHandleKind.rotate) {
                                            updated = applyHandleDrag(
                                              element: current,
                                              kind: kind,
                                              dxMm: dxPx,
                                              dyMm: 0,
                                              canvasW: _design.canvas.widthMm,
                                              canvasH: _design.canvas.heightMm,
                                            );
                                          } else {
                                            final d = _deltaPxToMm(dxPx, dyPx);
                                            updated = applyHandleDrag(
                                              element: current,
                                              kind: kind,
                                              dxMm: d.dx,
                                              dyMm: d.dy,
                                              canvasW: _design.canvas.widthMm,
                                              canvasH: _design.canvas.heightMm,
                                            );
                                          }
                                          setState(() {
                                            _design = _design.copyWith(
                                              elements: _design.elements
                                                  .map((e) => e.id == el.id ? updated : e)
                                                  .toList(),
                                            );
                                          });
                                          _markDirty();
                                        },
                                        onDragEnd: () {
                                          _handleDragCheckpointed = false;
                                          setState(() {
                                            _draggingElement = false;
                                            if (_design.canvas.snapToGrid) {
                                              final current = _design.elements
                                                  .firstWhere((e) => e.id == el.id);
                                              final snapped = current.copyWith(
                                                xMm: _snapMm(current.xMm),
                                                yMm: _snapMm(current.yMm),
                                                wMm: _snapMm(current.wMm).clamp(2, _design.canvas.widthMm),
                                                hMm: _snapMm(current.hMm).clamp(2, _design.canvas.heightMm),
                                              );
                                              _design = _design.copyWith(
                                                elements: _design.elements
                                                    .map((e) => e.id == el.id ? snapped : e)
                                                    .toList(),
                                              );
                                            }
                                          });
                                          _markDirty();
                                        },
                                      ),
                                  ],
                                ),
                              ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return ColoredBox(
      color: const Color(0xFF2A2E33),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: _rulerThickness,
                height: _rulerThickness,
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
                ),
              ),
              Expanded(
                child: LabelRulerBar(
                  horizontal: true,
                  lengthMm: _design.canvas.widthMm,
                  pxPerMm: _pxPerMm,
                  zoom: _canvasZoom,
                  offsetPx: _canvasOffsetPx,
                  thickness: _rulerThickness,
                ),
              ),
            ],
          ),
          Expanded(
            child: Row(
              children: [
                LabelRulerBar(
                  horizontal: false,
                  lengthMm: _design.canvas.heightMm,
                  pxPerMm: _pxPerMm,
                  zoom: _canvasZoom,
                  offsetPx: _canvasOffsetPx,
                  thickness: _rulerThickness,
                ),
                Expanded(child: canvasArea),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Toolbox extends StatelessWidget {
  final String tool;
  final ValueChanged<String> onTool;
  final ValueChanged<LabelElementType> onAdd;
  final bool enabled;

  const _Toolbox({
    required this.tool,
    required this.onTool,
    required this.onAdd,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    Widget btn(IconData icon, String tip, VoidCallback? onPressed, {bool selected = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: IconButton.filledTonal(
          isSelected: selected,
          tooltip: tip,
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon),
        ),
      );
    }

    return Material(
      elevation: 1,
      child: SizedBox(
        width: 64,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            btn(Icons.near_me, 'V', () => onTool('select'), selected: tool == 'select'),
            btn(Icons.pan_tool_alt_outlined, 'H', () => onTool('hand'), selected: tool == 'hand'),
            const Divider(height: 16),
            btn(Icons.text_fields, 'T ${t.barcodeLabelToolText}', () => onAdd(LabelElementType.text)),
            btn(Icons.view_week, 'B ${t.barcodeLabelToolBarcode}', () => onAdd(LabelElementType.barcode)),
            btn(Icons.qr_code_2, 'Q QR', () => onAdd(LabelElementType.qr)),
            btn(Icons.grid_on, 'DataMatrix', () => onAdd(LabelElementType.datamatrix)),
            btn(Icons.image_outlined, t.barcodeLabelToolImage, () => onAdd(LabelElementType.image)),
            btn(Icons.crop_square, t.barcodeLabelToolShape, () => onAdd(LabelElementType.shape)),
            btn(Icons.horizontal_rule, t.barcodeLabelToolLine, () => onAdd(LabelElementType.line)),
          ],
        ),
      ),
    );
  }
}

class _Inspector extends StatelessWidget {
  final LabelElement? element;
  final LabelDesignDocument design;
  final LabelSheet sheet;
  final bool canDesign;
  final LabelPrinterProfile? printerProfile;
  final VoidCallback? onApplyPrinterSize;
  final Set<String> sampleBindings;
  final Map<String, String> sampleOverrides;
  final Map<String, dynamic> sample;
  final void Function(String key, String value) onSampleOverride;
  final ValueChanged<LabelCanvas> onCanvasChanged;
  final ValueChanged<LabelSheet> onSheetChanged;
  final ValueChanged<LabelElement> onChanged;
  final ValueChanged<String> onSelect;
  final void Function(int oldIndex, int newIndex)? onReorderLayers;

  const _Inspector({
    required this.element,
    required this.design,
    required this.sheet,
    required this.canDesign,
    this.printerProfile,
    this.onApplyPrinterSize,
    required this.sampleBindings,
    required this.sampleOverrides,
    required this.sample,
    required this.onSampleOverride,
    required this.onCanvasChanged,
    required this.onSheetChanged,
    required this.onChanged,
    required this.onSelect,
    this.onReorderLayers,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    return Material(
      elevation: 1,
      child: SizedBox(
        width: 300,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(t.barcodeLabelCanvasSettings, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _numField(context, t.barcodeLabelCanvasWidth, design.canvas.widthMm, canDesign, (v) {
              onCanvasChanged(design.canvas.copyWith(widthMm: v.clamp(10, 500)));
            }),
            _numField(context, t.barcodeLabelCanvasHeight, design.canvas.heightMm, canDesign, (v) {
              onCanvasChanged(design.canvas.copyWith(heightMm: v.clamp(5, 500)));
            }),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: sheet.printMode,
              decoration: InputDecoration(labelText: t.barcodeLabelPrintLayout),
              items: [
                DropdownMenuItem(value: 'sheet', child: Text(t.barcodeLabelPrintLayoutSheet)),
                DropdownMenuItem(value: 'roll', child: Text(t.barcodeLabelPrintLayoutRoll)),
              ],
              onChanged: canDesign
                  ? (v) {
                      if (v == null) return;
                      onSheetChanged(sheet.copyWith(printMode: v));
                    }
                  : null,
            ),
            if (!sheet.isRollMode) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: sheet.paper,
                decoration: InputDecoration(labelText: t.barcodeLabelPaperSize),
                items: [
                  DropdownMenuItem(value: 'A4', child: Text('A4')),
                  DropdownMenuItem(value: 'A5', child: Text('A5')),
                  DropdownMenuItem(value: 'Letter', child: Text('Letter')),
                  DropdownMenuItem(value: 'custom', child: Text(t.barcodeLabelPaperCustom)),
                ],
                onChanged: canDesign
                    ? (v) {
                        if (v == null) return;
                        onSheetChanged(sheet.copyWith(paper: v));
                      }
                    : null,
              ),
              if (sheet.paper == 'custom') ...[
                const SizedBox(height: 8),
                _numField(
                  context,
                  t.barcodeLabelPaperWidth,
                  sheet.customPaperMm?['width'] ?? 210,
                  canDesign,
                  (v) => onSheetChanged(sheet.copyWith(
                    customPaperMm: {
                      'width': v,
                      'height': sheet.customPaperMm?['height'] ?? 297,
                    },
                  )),
                ),
                _numField(
                  context,
                  t.barcodeLabelPaperHeight,
                  sheet.customPaperMm?['height'] ?? 297,
                  canDesign,
                  (v) => onSheetChanged(sheet.copyWith(
                    customPaperMm: {
                      'width': sheet.customPaperMm?['width'] ?? 210,
                      'height': v,
                    },
                  )),
                ),
              ],
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: sheet.orientation,
                decoration: InputDecoration(labelText: t.barcodeLabelOrientation),
                items: [
                  DropdownMenuItem(value: 'portrait', child: Text(t.barcodeLabelPortrait)),
                  DropdownMenuItem(value: 'landscape', child: Text(t.barcodeLabelLandscape)),
                ],
                onChanged: canDesign
                    ? (v) {
                        if (v == null) return;
                        onSheetChanged(sheet.copyWith(orientation: v));
                      }
                    : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _numField(
                      context,
                      t.barcodeLabelSheetColumns,
                      sheet.columns.toDouble(),
                      canDesign,
                      (v) => onSheetChanged(sheet.copyWith(columns: v.round().clamp(1, 20))),
                      decimals: 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _numField(
                      context,
                      t.barcodeLabelSheetRows,
                      sheet.rows.toDouble(),
                      canDesign,
                      (v) => onSheetChanged(sheet.copyWith(rows: v.round().clamp(1, 40))),
                      decimals: 0,
                    ),
                  ),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t.barcodeLabelRollModeHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            if (printerProfile != null && onApplyPrinterSize != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onApplyPrinterSize,
                icon: const Icon(Icons.sync, size: 18),
                label: Text(
                  t.barcodeLabelApplyPrinterSize(
                    printerProfile!.labelWidthMm.toStringAsFixed(0),
                    printerProfile!.labelHeightMm.toStringAsFixed(0),
                  ),
                ),
              ),
            ],
            const Divider(height: 24),
            Text(t.barcodeLabelPreviewData, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (sampleBindings.isEmpty)
              Text(
                t.barcodeLabelPreviewDataHint,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              )
            else
              for (final key in sampleBindings.toList()..sort())
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    key: ValueKey('sample-$key'),
                    initialValue: sampleOverrides[key] ??
                        resolveLabelBinding(key, sample),
                    enabled: canDesign,
                    decoration: InputDecoration(
                      labelText: _bindingLabel(key, isFa),
                      isDense: true,
                    ),
                    onChanged: (v) => onSampleOverride(key, v),
                  ),
                ),
            const Divider(height: 24),
            Text(t.barcodeLabelLayers, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (onReorderLayers != null && canDesign)
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: onReorderLayers!,
                children: [
                  for (final e in [...design.elements].reversed)
                    ListTile(
                      key: ValueKey('layer-${e.id}'),
                      dense: true,
                      selected: element?.id == e.id,
                      selectedTileColor: cs.primaryContainer.withValues(alpha: 0.35),
                      leading: Icon(_iconFor(e.type), size: 18),
                      title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.drag_handle, size: 18),
                      onTap: () => onSelect(e.id),
                    ),
                ],
              )
            else
              ...[...design.elements].reversed.map((e) {
                final selected = element?.id == e.id;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: cs.primaryContainer.withValues(alpha: 0.35),
                  leading: Icon(_iconFor(e.type), size: 18),
                  title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => onSelect(e.id),
                );
              }),
            const Divider(height: 24),
            Text(t.barcodeLabelProperties, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (element == null)
              Text(t.barcodeLabelNoSelection, style: TextStyle(color: cs.onSurfaceVariant))
            else ...[
              _numField(context, 'X mm', element!.xMm, canDesign, (v) => onChanged(element!.copyWith(xMm: v))),
              _numField(context, 'Y mm', element!.yMm, canDesign, (v) => onChanged(element!.copyWith(yMm: v))),
              _numField(context, 'W mm', element!.wMm, canDesign, (v) => onChanged(element!.copyWith(wMm: v))),
              _numField(context, 'H mm', element!.hMm, canDesign, (v) => onChanged(element!.copyWith(hMm: v))),
              _numField(
                context,
                t.barcodeLabelRotation,
                element!.rotationDeg,
                canDesign,
                (v) => onChanged(element!.copyWith(rotationDeg: v % 360)),
              ),
              if (canDesign)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: () => onChanged(
                      element!.copyWith(rotationDeg: (element!.rotationDeg + 90) % 360),
                    ),
                    icon: const Icon(Icons.rotate_right, size: 18),
                    label: Text(t.barcodeLabelRotate90),
                  ),
                ),
              if (element!.type == LabelElementType.barcode ||
                  element!.type == LabelElementType.text ||
                  element!.type == LabelElementType.qr ||
                  element!.type == LabelElementType.datamatrix) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: (element!.props['content_mode'] ?? 'binding').toString(),
                  decoration: InputDecoration(labelText: t.barcodeLabelContentMode),
                  items: [
                    DropdownMenuItem(value: 'binding', child: Text(t.barcodeLabelContentBinding)),
                    DropdownMenuItem(value: 'fixed', child: Text(t.barcodeLabelContentFixed)),
                  ],
                  onChanged: canDesign
                      ? (v) {
                          if (v == null) return;
                          final props = Map<String, dynamic>.from(element!.props)
                            ..['content_mode'] = v;
                          onChanged(element!.copyWith(props: props));
                        }
                      : null,
                ),
                if ((element!.props['content_mode'] ?? 'binding').toString() == 'fixed') ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey('fixed-${element!.id}-${element!.props['value']}'),
                    initialValue: (element!.props['value'] ?? element!.props['text'] ?? '').toString(),
                    enabled: canDesign,
                    decoration: InputDecoration(labelText: t.barcodeLabelFixedValue, isDense: true),
                    onChanged: canDesign
                        ? (v) {
                            final props = Map<String, dynamic>.from(element!.props)
                              ..['content_mode'] = 'fixed'
                              ..['value'] = v;
                            onChanged(element!.copyWith(props: props));
                          }
                        : null,
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: (element!.props['binding'] ?? 'product.name').toString(),
                    decoration: InputDecoration(labelText: t.barcodeLabelBinding),
                    items: [
                      for (final b in LabelBindingCatalog.entries)
                        DropdownMenuItem(
                          value: b['key'],
                          child: Text(isFa ? b['label_fa']! : b['label_en']!),
                        ),
                    ],
                    onChanged: canDesign
                        ? (v) {
                            if (v == null) return;
                            final props = Map<String, dynamic>.from(element!.props)
                              ..['content_mode'] = 'binding'
                              ..['binding'] = v;
                            onChanged(element!.copyWith(props: props));
                          }
                        : null,
                  ),
                ],
              ],
              if (element!.type == LabelElementType.barcode) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: (element!.props['symbology'] ?? 'code128').toString(),
                  decoration: InputDecoration(labelText: t.barcodeLabelSymbology),
                  items: const [
                    DropdownMenuItem(value: 'code128', child: Text('Code128')),
                    DropdownMenuItem(value: 'code39', child: Text('Code39')),
                    DropdownMenuItem(value: 'code93', child: Text('Code93')),
                    DropdownMenuItem(value: 'ean13', child: Text('EAN-13')),
                    DropdownMenuItem(value: 'ean8', child: Text('EAN-8')),
                    DropdownMenuItem(value: 'codabar', child: Text('CodaBar')),
                  ],
                  onChanged: canDesign
                      ? (v) {
                          if (v == null) return;
                          final props = Map<String, dynamic>.from(element!.props)..['symbology'] = v;
                          onChanged(element!.copyWith(props: props));
                        }
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.barcodeLabelShowBarcodeText),
                  value: element!.props['show_text'] != false,
                  onChanged: canDesign
                      ? (v) {
                          final props = Map<String, dynamic>.from(element!.props)..['show_text'] = v;
                          onChanged(element!.copyWith(props: props));
                        }
                      : null,
                ),
              ],
              if (element!.type == LabelElementType.image) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: (element!.props['source'] ?? 'business.logo').toString(),
                  decoration: InputDecoration(labelText: t.barcodeLabelImageSource),
                  items: [
                    DropdownMenuItem(value: 'business.logo', child: Text(t.barcodeLabelImageBusinessLogo)),
                    DropdownMenuItem(value: 'product.image', child: Text(t.barcodeLabelImageProduct)),
                    DropdownMenuItem(value: 'upload', child: Text(t.barcodeLabelImageUpload)),
                  ],
                  onChanged: canDesign
                      ? (v) {
                          if (v == null) return;
                          final props = Map<String, dynamic>.from(element!.props)..['source'] = v;
                          onChanged(element!.copyWith(props: props));
                        }
                      : null,
                ),
                if ((element!.props['source'] ?? 'business.logo').toString() == 'upload' && canDesign) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _pickUploadImage(context, element!, onChanged),
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: Text(t.barcodeLabelPickImage),
                  ),
                ],
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: (element!.props['fit'] ?? 'contain').toString(),
                  decoration: InputDecoration(labelText: t.barcodeLabelImageFit),
                  items: [
                    DropdownMenuItem(value: 'contain', child: Text(t.barcodeLabelImageFitContain)),
                    DropdownMenuItem(value: 'cover', child: Text(t.barcodeLabelImageFitCover)),
                    DropdownMenuItem(value: 'fill', child: Text(t.barcodeLabelImageFitFill)),
                  ],
                  onChanged: canDesign
                      ? (v) {
                          if (v == null) return;
                          final props = Map<String, dynamic>.from(element!.props)..['fit'] = v;
                          onChanged(element!.copyWith(props: props));
                        }
                      : null,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _bindingLabel(String key, bool isFa) {
    for (final b in LabelBindingCatalog.entries) {
      if (b['key'] == key) return isFa ? b['label_fa']! : b['label_en']!;
    }
    return key;
  }

  Future<void> _pickUploadImage(
    BuildContext context,
    LabelElement element,
    ValueChanged<LabelElement> onChanged,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return;
    final ext = (file.extension ?? 'png').toLowerCase();
    final mime = ext == 'jpg' || ext == 'jpeg' ? 'image/jpeg' : 'image/png';
    final props = Map<String, dynamic>.from(element.props)
      ..['source'] = 'upload'
      ..['data_uri'] = bytesToDataUri(bytes, mime: mime);
    LabelImageResolver.clearCache();
    onChanged(element.copyWith(props: props));
  }

  IconData _iconFor(LabelElementType t) => switch (t) {
        LabelElementType.text => Icons.text_fields,
        LabelElementType.barcode => Icons.view_week,
        LabelElementType.qr => Icons.qr_code_2,
        LabelElementType.datamatrix => Icons.grid_on,
        LabelElementType.image => Icons.image_outlined,
        LabelElementType.shape => Icons.crop_square,
        LabelElementType.line => Icons.horizontal_rule,
      };

  Widget _numField(
    BuildContext context,
    String label,
    double value,
    bool enabled,
    ValueChanged<double> onChanged, {
    int decimals = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        key: ValueKey('$label-$value'),
        initialValue: decimals == 0 ? value.round().toString() : value.toStringAsFixed(decimals),
        enabled: enabled,
        decoration: InputDecoration(labelText: label, isDense: true),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onFieldSubmitted: (s) {
          final v = double.tryParse(s.replaceAll(',', '.'));
          if (v != null) onChanged(v);
        },
        onEditingComplete: () {
          FocusScope.of(context).unfocus();
        },
      ),
    );
  }
}

class _ElementView extends StatelessWidget {
  final LabelElement element;
  final bool selected;
  final Map<String, dynamic> sample;
  final int? businessId;
  final VoidCallback onTap;
  final VoidCallback? onDragStart;
  final void Function(double dx, double dy)? onDrag;
  final VoidCallback? onDragEnd;

  const _ElementView({
    required this.element,
    required this.selected,
    required this.sample,
    this.businessId,
    required this.onTap,
    this.onDragStart,
    this.onDrag,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    Widget child;
    final value = resolveElementValue(element, sample);
    switch (element.type) {
      case LabelElementType.text:
        child = Center(
          child: Text(
            value.isEmpty ? '—' : value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: (element.props['font_size_pt'] as num?)?.toDouble() ?? 9,
              fontWeight: element.props['font_weight'] == 'bold' ? FontWeight.bold : FontWeight.normal,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        );
        break;
      case LabelElementType.barcode:
        final sym = (element.props['symbology'] ?? 'code128').toString();
        final showText = element.props['show_text'] != false;
        child = Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(2),
          color: Colors.white,
          child: CustomPaint(
            painter: LabelStudioBarcodePainter(
              symbology: sym,
              data: value,
              showText: showText,
            ),
            child: const SizedBox.expand(),
          ),
        );
        break;
      case LabelElementType.qr:
        final qrData = value.trim().isEmpty ? 'SAMPLE-QR' : value.trim();
        child = ColoredBox(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
              errorStateBuilder: (_, __) => const Icon(Icons.qr_code_2, color: Colors.black54),
            ),
          ),
        );
        break;
      case LabelElementType.datamatrix:
        child = ColoredBox(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: CustomPaint(
              painter: LabelStudioMatrixPainter(data: value),
              child: const SizedBox.expand(),
            ),
          ),
        );
        break;
      case LabelElementType.image:
        child = LabelStudioImageView(
          element: element,
          businessId: businessId,
          context: sample,
        );
        break;
      case LabelElementType.shape:
        child = Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black87, width: 1),
            borderRadius: element.props['shape'] == 'ellipse' ? BorderRadius.circular(999) : null,
          ),
        );
        break;
      case LabelElementType.line:
        child = const Align(
          alignment: Alignment.centerLeft,
          child: Divider(color: Colors.black87, thickness: 1.5, height: 2),
        );
        break;
    }

    final body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanStart: onDrag == null ? null : (_) => onDragStart?.call(),
      onPanUpdate: onDrag == null ? null : (d) => onDrag!(d.delta.dx, d.delta.dy),
      onPanEnd: onDrag == null ? null : (_) => onDragEnd?.call(),
      onPanCancel: onDrag == null ? null : () => onDragEnd?.call(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: selected ? 1.5 : 0,
          ),
        ),
        child: child,
      ),
    );

    if (element.rotationDeg.abs() < 0.01) return body;
    return Transform.rotate(
      angle: element.rotationDeg * math.pi / 180.0,
      alignment: Alignment.center,
      child: body,
    );
  }
}

class _GridPainter extends CustomPainter {
  final double widthMm;
  final double heightMm;
  final double gridMm;
  final double pxPerMm;

  _GridPainter({
    required this.widthMm,
    required this.heightMm,
    required this.gridMm,
    required this.pxPerMm,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE8EAED)
      ..strokeWidth = 1;
    final step = math.max(gridMm, 1) * pxPerMm;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.gridMm != gridMm || oldDelegate.pxPerMm != pxPerMm;
}
