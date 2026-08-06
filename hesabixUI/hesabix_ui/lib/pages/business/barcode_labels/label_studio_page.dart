import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../models/barcode_label/label_design_v1.dart';
import '../../../services/barcode_label_service.dart';
import '../../../services/bytes_export/bytes_export_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/barcode_label/render/label_pdf_renderer.dart';
import '../../../widgets/barcode_label/studio/label_element_handles.dart';
import '../../../widgets/barcode_label/studio/label_rulers.dart';
import '../../../widgets/barcode_label/studio/label_studio_history.dart';
import '../../../widgets/business_subpage_back_leading.dart';

/// Label design studio — Phase B (canvas mm, selection, toolbox, save).
class LabelStudioPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final int? templateId;

  const LabelStudioPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.templateId,
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
  String? _selectedId;
  String _tool = 'select';
  bool _dirty = false;
  String? _savedFingerprint;
  double _canvasZoom = 1.0;
  bool _handleDragCheckpointed = false;

  static const double _pxPerMm = 3.7795275591; // ~96dpi
  static const double _canvasOffsetPx = 40.0;
  static const double _rulerThickness = 24.0;

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
        _design = LabelDesignDocument.empty();
        _sheet = const LabelSheet();
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

  Future<void> _handleBack() async {
    if (!await _confirmLeave() || !mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/business/${widget.businessId}/settings');
    }
  }

  void _popAfterLeaveConfirmed() {
    _dirty = false;
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/business/${widget.businessId}/settings');
    }
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
        contexts: [_sample, _sample],
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

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_dirty) return;
        final leave = await _confirmLeave();
        if (leave && mounted) _popAfterLeaveConfirmed();
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
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _handleBack,
            ),
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
          body: Row(
            children: [
              _Toolbox(
                tool: _tool,
                onTool: (v) => setState(() => _tool = v),
                onAdd: _addElement,
                enabled: _canDesign,
              ),
              Expanded(child: _buildCanvas(cs)),
              _Inspector(
                element: _selected,
                design: _design,
                canDesign: _canDesign,
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

  Widget _buildCanvas(ColorScheme cs) {
    final w = _design.canvas.widthMm * _pxPerMm;
    final h = _design.canvas.heightMm * _pxPerMm;
    final canvasArea = InteractiveViewer(
      transformationController: _transform,
      minScale: 0.25,
      maxScale: 4,
      constrained: false,
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
                                      sample: _sample,
                                      onTap: () => setState(() => _selectedId = el.id),
                                      onDragStart: _canDesign && !el.locked
                                          ? () => _checkpoint()
                                          : null,
                                      onDrag: _canDesign && !el.locked
                                          ? (dxPx, dyPx) {
                                              final dx = dxPx / _pxPerMm;
                                              final dy = dyPx / _pxPerMm;
                                              setState(() {
                                                _design = _design.copyWith(
                                                  elements: _design.elements.map((e) {
                                                    if (e.id != el.id) return e;
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
                                                _selectedId = el.id;
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
                                        onDrag: (kind, dxPx, dyPx) {
                                          if (!_handleDragCheckpointed) {
                                            _checkpoint();
                                            _handleDragCheckpointed = true;
                                          }
                                          final current = _design.elements
                                              .firstWhere((e) => e.id == el.id);
                                          final updated = applyHandleDrag(
                                            element: current,
                                            kind: kind,
                                            dxMm: dxPx / _pxPerMm,
                                            dyMm: dyPx / _pxPerMm,
                                            canvasW: _design.canvas.widthMm,
                                            canvasH: _design.canvas.heightMm,
                                          );
                                          setState(() {
                                            _design = _design.copyWith(
                                              elements: _design.elements
                                                  .map((e) => e.id == el.id ? updated : e)
                                                  .toList(),
                                            );
                                          });
                                          _markDirty();
                                        },
                                        onDragEnd: () => _handleDragCheckpointed = false,
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
  final bool canDesign;
  final ValueChanged<LabelElement> onChanged;
  final ValueChanged<String> onSelect;

  const _Inspector({
    required this.element,
    required this.design,
    required this.canDesign,
    required this.onChanged,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 1,
      child: SizedBox(
        width: 300,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(t.barcodeLabelLayers, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
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
              if (element!.type == LabelElementType.barcode ||
                  element!.type == LabelElementType.text ||
                  element!.type == LabelElementType.qr ||
                  element!.type == LabelElementType.datamatrix) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: (element!.props['binding'] ?? 'product.name').toString(),
                  decoration: InputDecoration(labelText: t.barcodeLabelBinding),
                  items: [
                    for (final b in LabelBindingCatalog.entries)
                      DropdownMenuItem(
                        value: b['key'],
                        child: Text(Localizations.localeOf(context).languageCode == 'fa' ? b['label_fa']! : b['label_en']!),
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
              ],
            ],
          ],
        ),
      ),
    );
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
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        key: ValueKey('$label-$value'),
        initialValue: value.toStringAsFixed(1),
        enabled: enabled,
        decoration: InputDecoration(labelText: label, isDense: true),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onFieldSubmitted: (s) {
          final v = double.tryParse(s.replaceAll(',', '.'));
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _ElementView extends StatelessWidget {
  final LabelElement element;
  final bool selected;
  final Map<String, dynamic> sample;
  final VoidCallback onTap;
  final VoidCallback? onDragStart;
  final void Function(double dx, double dy)? onDrag;

  const _ElementView({
    required this.element,
    required this.selected,
    required this.sample,
    required this.onTap,
    this.onDragStart,
    this.onDrag,
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
        child = Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: CustomPaint(
                  painter: _BarsPainter(),
                  child: const SizedBox.expand(),
                ),
              ),
              if (element.props['show_text'] != false)
                Text(
                  value.isEmpty ? '—' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8, letterSpacing: 0.4),
                ),
            ],
          ),
        );
        break;
      case LabelElementType.qr:
      case LabelElementType.datamatrix:
        child = Container(
          color: Colors.white,
          alignment: Alignment.center,
          child: Icon(
            element.type == LabelElementType.qr ? Icons.qr_code_2 : Icons.grid_on,
            size: 28,
            color: Colors.black87,
          ),
        );
        break;
      case LabelElementType.image:
        child = Container(
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image_outlined, color: Colors.grey),
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

    return GestureDetector(
      onTap: onTap,
      onPanStart: onDrag == null ? null : (_) => onDragStart?.call(),
      onPanUpdate: onDrag == null ? null : (d) => onDrag!(d.delta.dx, d.delta.dy),
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
  }
}

class _BarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black87;
    var x = 0.0;
    final rnd = math.Random(7);
    while (x < size.width) {
      final w = 1.0 + rnd.nextInt(3);
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      x += w + 1 + rnd.nextInt(2);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
