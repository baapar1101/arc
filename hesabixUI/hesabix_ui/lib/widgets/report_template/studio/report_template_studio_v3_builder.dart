import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'report_template_media_settings.dart';
import 'report_template_snap_engine.dart';
import 'report_template_studio_v4_adapter.dart';

class ReportTemplateStudioV3Builder extends StatefulWidget {
  final Map<String, dynamic> design;
  final List<Map<String, dynamic>> blockCatalog;
  final ValueChanged<Map<String, dynamic>> onDesignChanged;
  final Widget? editorHeader;
  final Widget? previewPane;

  const ReportTemplateStudioV3Builder({
    super.key,
    required this.design,
    required this.blockCatalog,
    required this.onDesignChanged,
    this.editorHeader,
    this.previewPane,
  });

  @override
  State<ReportTemplateStudioV3Builder> createState() =>
      _ReportTemplateStudioV3BuilderState();
}

class _BlockDragData {
  final String? blockId;
  final String? blockType;

  const _BlockDragData.existing(this.blockId) : blockType = null;
  const _BlockDragData.palette(this.blockType) : blockId = null;
}

class _CanvasRow {
  final String id;
  final int startIndex;
  final List<Map<String, dynamic>> blocks;

  const _CanvasRow({
    required this.id,
    required this.startIndex,
    required this.blocks,
  });
}

class _ReportTemplateStudioV3BuilderState
    extends State<ReportTemplateStudioV3Builder> {
  final GlobalKey _pageGridCanvasKey = GlobalKey();
  final List<Map<String, dynamic>> _history = [];
  int _historyIndex = -1;
  int _idSequence = 0;
  String? _selectedBlockId;
  bool _showLivePreview = false;
  String? _resizingBlockId;
  int? _resizeStartSpan;
  int? _resizePreviewSpan;
  double _resizeHorizontalDelta = 0;
  String? _resizingRowId;
  double? _resizeStartHeightMm;
  double? _resizePreviewHeightMm;
  double _resizeVerticalDelta = 0;
  String? _freeformGestureId;
  StudioMmRect? _freeformStartRect;
  StudioMmRect? _freeformPreviewRect;
  Offset _freeformDelta = Offset.zero;
  List<StudioSnapGuide> _freeformGuides = const [];
  int? _freeformResizePointer;
  String? _freeformResizingId;
  int? _freeformMovePointer;
  double _canvasZoom = 1;
  String? _pendingAnchorBlockId;
  String? _pendingAnchorPoint;

  static const _horizontalAnchorPoints = {'left', 'right', 'center_x'};
  static const _verticalAnchorPoints = {'top', 'bottom', 'center_y'};

  @override
  void initState() {
    super.initState();
    _resetHistory(widget.design);
  }

  @override
  void didUpdateWidget(covariant ReportTemplateStudioV3Builder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_historyIndex < 0 ||
        _encoded(_history[_historyIndex]) != _encoded(widget.design)) {
      _resetHistory(widget.design);
    }
  }

  String _encoded(Map<String, dynamic> value) => jsonEncode(value);

  Map<String, dynamic> _clone(Map<String, dynamic> value) {
    return (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
  }

  void _resetHistory(Map<String, dynamic> design) {
    _history
      ..clear()
      ..add(_clone(design));
    _historyIndex = 0;
  }

  void _commit(Map<String, dynamic> design) {
    final copy = _clone(design);
    if (_historyIndex >= 0 &&
        _encoded(_history[_historyIndex]) == _encoded(copy)) {
      return;
    }
    if (_historyIndex + 1 < _history.length) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(copy);
    if (_history.length > 50) _history.removeAt(0);
    _historyIndex = _history.length - 1;
    widget.onDesignChanged(copy);
    setState(() {});
  }

  void _undo() {
    if (_historyIndex <= 0) return;
    _historyIndex--;
    widget.onDesignChanged(_clone(_history[_historyIndex]));
    setState(() {});
  }

  void _redo() {
    if (_historyIndex + 1 >= _history.length) return;
    _historyIndex++;
    widget.onDesignChanged(_clone(_history[_historyIndex]));
    setState(() {});
  }

  Map<String, dynamic> _regions(Map<String, dynamic> design) {
    if (isReportTemplateV4(design)) {
      final projection = reportTemplateV4StudioProjection(design);
      return (projection['regions'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
    }
    return (design['regions'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
  }

  void _setRegions(Map<String, dynamic> design, Map<String, dynamic> regions) {
    if (!isReportTemplateV4(design)) {
      design['regions'] = regions;
      return;
    }
    _resolveProjectionAnchors(design, regions);
    final projection = reportTemplateV4StudioProjection(design)
      ..['regions'] = regions;
    final updated = applyStudioProjectionToReportTemplateV4(design, projection);
    design
      ..clear()
      ..addAll(updated);
  }

  List<Map<String, dynamic>> _regionBlocks(
    Map<String, dynamic> design,
    String region,
  ) {
    final regions = _regions(design);
    return List<Map<String, dynamic>>.from(
      (regions[region] as List?) ?? const [],
    );
  }

  Map<String, dynamic>? _definition(String type) {
    for (final definition in widget.blockCatalog) {
      if (definition['type']?.toString() == type) return definition;
    }
    return null;
  }

  int _typeCount(String type) {
    var count = 0;
    for (final region in const ['header', 'body', 'footer']) {
      count += _regionBlocks(
        widget.design,
        region,
      ).where((block) => block['type'] == type).length;
    }
    return count;
  }

  bool _canAdd(Map<String, dynamic> definition) {
    final max = (definition['max_instances'] as num?)?.toInt();
    return max == null || _typeCount(definition['type'].toString()) < max;
  }

  String _newId(String type) {
    _idSequence++;
    return '${type}_${DateTime.now().microsecondsSinceEpoch}_$_idSequence';
  }

  String _newRowId() => _newId('row');

  String _blockRowId(Map<String, dynamic> block, String region) {
    final style = (block['style'] as Map?)?.cast<String, dynamic>() ?? const {};
    final configured = (style['row_id'] ?? '').toString().trim();
    if (configured.isNotEmpty) return configured;
    return 'legacy-$region-${block['id']}';
  }

  int _blockSpan(Map<String, dynamic> block) {
    final style = (block['style'] as Map?)?.cast<String, dynamic>() ?? const {};
    final configured = (style['grid_span'] as num?)?.round();
    if (configured != null) return configured.clamp(1, 60).toInt();
    final mode = (style['width_mode'] ?? 'full').toString();
    final value = (style['width_value'] as num?)?.toDouble();
    if (mode == 'percentage') {
      return ((value ?? 100) * 0.6).round().clamp(1, 60).toInt();
    }
    return 60;
  }

  List<_CanvasRow> _canvasRows(
    List<Map<String, dynamic>> blocks,
    String region,
  ) {
    final rows = <_CanvasRow>[];
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      final rowId = _blockRowId(block, region);
      if (rows.isEmpty || rows.last.id != rowId) {
        rows.add(_CanvasRow(id: rowId, startIndex: index, blocks: [block]));
      } else {
        rows.last.blocks.add(block);
      }
    }
    return rows;
  }

  Map<String, dynamic> _newBlock(String type, String rowId, int span) {
    final definition = _definition(type)!;
    return <String, dynamic>{
      'id': _newId(type),
      'type': type,
      'visible': true,
      'props': _cloneMap(definition['default_props']),
      'style': <String, dynamic>{
        'width_mode': 'full',
        'row_id': rowId,
        'grid_span': span.clamp(1, 60),
      },
    };
  }

  void _addBlock(String type, String region, int index) {
    final definition = _definition(type);
    if (definition == null || !_canAdd(definition)) return;
    final allowed = List<String>.from(
      (definition['allowed_regions'] as List?) ?? const [],
    );
    if (!allowed.contains(region)) {
      region = allowed.isEmpty ? 'body' : allowed.first;
    }
    final design = _clone(widget.design);
    final regions = _regions(design);
    final blocks = List<Map<String, dynamic>>.from(
      (regions[region] as List?) ?? const [],
    );
    final block = _newBlock(type, _newRowId(), 60);
    blocks.insert(index.clamp(0, blocks.length), block);
    regions[region] = blocks;
    _setRegions(design, regions);
    _selectedBlockId = block['id'].toString();
    _commit(design);
  }

  Map<String, dynamic> _cloneMap(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    return (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
  }

  ({String region, int index, Map<String, dynamic> block})? _findBlock(
    String id,
  ) {
    for (final region in const ['header', 'body', 'footer']) {
      final blocks = _regionBlocks(widget.design, region);
      final index = blocks.indexWhere((block) => block['id']?.toString() == id);
      if (index >= 0) {
        return (region: region, index: index, block: blocks[index]);
      }
    }
    return null;
  }

  void _moveBlock(String id, String targetRegion, int targetIndex) {
    final design = _clone(widget.design);
    final regions = _regions(design);
    Map<String, dynamic>? moving;
    String? sourceRegion;
    int sourceIndex = -1;
    for (final region in const ['header', 'body', 'footer']) {
      final blocks = List<Map<String, dynamic>>.from(
        (regions[region] as List?) ?? const [],
      );
      final index = blocks.indexWhere((block) => block['id']?.toString() == id);
      if (index >= 0) {
        moving = blocks.removeAt(index);
        sourceRegion = region;
        sourceIndex = index;
        regions[region] = blocks;
        break;
      }
    }
    if (moving == null) return;
    final definition = _definition(moving['type'].toString());
    final allowed = List<String>.from(
      (definition?['allowed_regions'] as List?) ?? const [],
    );
    if (!allowed.contains(targetRegion)) return;
    final movingStyle =
        (moving['style'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    moving['style'] = {
      ...movingStyle,
      'width_mode': 'full',
      'row_id': _newRowId(),
      'grid_span': 60,
    };
    final target = List<Map<String, dynamic>>.from(
      (regions[targetRegion] as List?) ?? const [],
    );
    if (sourceRegion == targetRegion && sourceIndex < targetIndex) {
      targetIndex--;
    }
    target.insert(targetIndex.clamp(0, target.length), moving);
    regions[targetRegion] = target;
    _setRegions(design, regions);
    _commit(design);
  }

  void _handleDrop(_BlockDragData data, String region, int index) {
    if (data.blockType != null) {
      _addBlock(data.blockType!, region, index);
    } else if (data.blockId != null) {
      _moveBlock(data.blockId!, region, index);
    }
  }

  void _handleDropBeside(_BlockDragData data, String region, String rowId) {
    final type =
        data.blockType ??
        _findBlock(data.blockId ?? '')?.block['type']?.toString();
    final definition = _definition(type ?? '');
    if (definition == null ||
        !List<String>.from(
          (definition['allowed_regions'] as List?) ?? const [],
        ).contains(region)) {
      return;
    }
    if (data.blockType != null && !_canAdd(definition)) return;

    final design = _clone(widget.design);
    final regions = _regions(design);
    Map<String, dynamic>? moving;
    for (final sourceRegion in const ['header', 'body', 'footer']) {
      final source = List<Map<String, dynamic>>.from(
        (regions[sourceRegion] as List?) ?? const [],
      );
      final index = source.indexWhere(
        (block) => block['id']?.toString() == data.blockId,
      );
      if (index >= 0) {
        moving = source.removeAt(index);
        regions[sourceRegion] = source;
        break;
      }
    }
    moving ??= _newBlock(type!, rowId, 30);

    final target = List<Map<String, dynamic>>.from(
      (regions[region] as List?) ?? const [],
    );
    final rowIndexes = <int>[];
    for (var index = 0; index < target.length; index++) {
      if (_blockRowId(target[index], region) == rowId) rowIndexes.add(index);
    }
    if (rowIndexes.isEmpty) {
      final style =
          (moving['style'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      moving['style'] = {
        ...style,
        'width_mode': 'full',
        'row_id': _newRowId(),
        'grid_span': 60,
      };
      target.add(moving);
    } else {
      final targetRowStyle =
          (target[rowIndexes.first]['style'] as Map?)
              ?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      for (final index in rowIndexes) {
        final block = Map<String, dynamic>.from(target[index]);
        final style =
            (block['style'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        block['style'] = {
          ...style,
          'width_mode': 'full',
          'row_id': rowId,
          'grid_span': _blockSpan(block),
        };
        target[index] = block;
      }
      final occupied = rowIndexes.fold<int>(
        0,
        (sum, index) => sum + _blockSpan(target[index]),
      );
      final remaining = 60 - occupied;
      if (remaining <= 0) {
        final count = rowIndexes.length + 1;
        final base = 60 ~/ count;
        var remainder = 60 % count;
        for (final index in rowIndexes) {
          final span = base + (remainder-- > 0 ? 1 : 0);
          final block = Map<String, dynamic>.from(target[index]);
          final style =
              (block['style'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          block['style'] = {
            ...style,
            'width_mode': 'full',
            'row_id': rowId,
            'grid_span': span,
          };
          target[index] = block;
        }
        final style =
            (moving['style'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        style.remove('row_height_mode');
        style.remove('row_height_mm');
        moving['style'] = {
          ...style,
          'width_mode': 'full',
          'row_id': rowId,
          'grid_span': base + (remainder-- > 0 ? 1 : 0),
          if (targetRowStyle['row_height_mode'] != null)
            'row_height_mode': targetRowStyle['row_height_mode'],
          if (targetRowStyle['row_height_mm'] != null)
            'row_height_mm': targetRowStyle['row_height_mm'],
        };
      } else {
        final style =
            (moving['style'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        style.remove('row_height_mode');
        style.remove('row_height_mm');
        moving['style'] = {
          ...style,
          'width_mode': 'full',
          'row_id': rowId,
          'grid_span': remaining.clamp(1, 30),
          if (targetRowStyle['row_height_mode'] != null)
            'row_height_mode': targetRowStyle['row_height_mode'],
          if (targetRowStyle['row_height_mm'] != null)
            'row_height_mm': targetRowStyle['row_height_mm'],
        };
      }
      target.insert(rowIndexes.last + 1, moving);
    }
    regions[region] = target;
    _setRegions(design, regions);
    _selectedBlockId = moving['id'].toString();
    _commit(design);
  }

  void _selectBlock(String id) {
    setState(() => _selectedBlockId = id);
  }

  void _removeBlock(String id) {
    final found = _findBlock(id);
    if (found == null) return;
    final definition = _definition(found.block['type'].toString());
    if (definition?['required'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('این بخش برای فاکتور الزامی است.')),
      );
      return;
    }
    final design = _clone(widget.design);
    final regions = _regions(design);
    final blocks = List<Map<String, dynamic>>.from(
      (regions[found.region] as List?) ?? const [],
    );
    blocks.removeAt(found.index);
    regions[found.region] = blocks;
    for (final region in const ['header', 'body', 'footer']) {
      final candidates = List<Map<String, dynamic>>.from(
        (regions[region] as List?) ?? const [],
      );
      for (var index = 0; index < candidates.length; index++) {
        final candidate = Map<String, dynamic>.from(candidates[index]);
        final style =
            (candidate['style'] as Map?)?.cast<String, dynamic>() ?? const {};
        final constraints = (style['anchor_constraints'] as Map?)
            ?.cast<String, dynamic>();
        if (constraints == null) continue;
        final nextConstraints = _clone(constraints);
        final links =
            List<Map<String, dynamic>>.from(
              (nextConstraints['links'] as List?) ?? const [],
            )..removeWhere(
              (link) =>
                  ((link['target'] as Map?)?['id'] ?? '').toString() == id,
            );
        nextConstraints['links'] = links;
        candidate['style'] = <String, dynamic>{
          ...style,
          'anchor_constraints': nextConstraints,
        };
        candidates[index] = candidate;
      }
      regions[region] = candidates;
    }
    _setRegions(design, regions);
    if (_selectedBlockId == id) _selectedBlockId = null;
    _commit(design);
  }

  void _duplicateBlock(String id) {
    final found = _findBlock(id);
    if (found == null) return;
    final type = found.block['type'].toString();
    final definition = _definition(type);
    if (definition == null || !_canAdd(definition)) return;
    final design = _clone(widget.design);
    final regions = _regions(design);
    final blocks = List<Map<String, dynamic>>.from(
      (regions[found.region] as List?) ?? const [],
    );
    final copy = _clone(found.block)..['id'] = _newId(type);
    final style =
        (copy['style'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    copy['style'] = {
      ...style,
      'width_mode': 'full',
      'row_id': _newRowId(),
      'grid_span': 60,
    };
    blocks.insert(found.index + 1, copy);
    regions[found.region] = blocks;
    _setRegions(design, regions);
    _selectedBlockId = copy['id'].toString();
    _commit(design);
  }

  void _patchBlock(
    String id,
    void Function(Map<String, dynamic> block) mutate,
  ) {
    final design = _clone(widget.design);
    final regions = _regions(design);
    for (final region in const ['header', 'body', 'footer']) {
      final blocks = List<Map<String, dynamic>>.from(
        (regions[region] as List?) ?? const [],
      );
      final index = blocks.indexWhere((block) => block['id']?.toString() == id);
      if (index >= 0) {
        final block = Map<String, dynamic>.from(blocks[index]);
        mutate(block);
        blocks[index] = block;
        regions[region] = blocks;
        _setRegions(design, regions);
        _commit(design);
        return;
      }
    }
  }

  void _patchRoot(void Function(Map<String, dynamic> design) mutate) {
    final design = _clone(widget.design);
    mutate(design);
    syncReportTemplateV4ActiveMedia(design);
    _commit(design);
  }

  void _patchRowStyle(String rowId, Map<String, dynamic> patch) {
    final design = _clone(widget.design);
    final regions = _regions(design);
    for (final region in const ['header', 'body', 'footer']) {
      final blocks = List<Map<String, dynamic>>.from(
        (regions[region] as List?) ?? const [],
      );
      var changed = false;
      for (var index = 0; index < blocks.length; index++) {
        if (_blockRowId(blocks[index], region) != rowId) continue;
        final block = Map<String, dynamic>.from(blocks[index]);
        final style =
            (block['style'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        block['style'] = {...style, ...patch, 'row_id': rowId};
        blocks[index] = block;
        changed = true;
      }
      if (changed) regions[region] = blocks;
    }
    _setRegions(design, regions);
    _commit(design);
  }

  String _labelForType(String type) {
    return (_definition(type)?['label_fa'] ?? type).toString();
  }

  String _labelForBlockId(String id) {
    final block = _findBlock(id)?.block;
    return block == null ? id : _labelForType(block['type'].toString());
  }

  IconData _iconForType(String type) {
    return switch (type) {
      'brand_header' => Icons.branding_watermark_outlined,
      'party_info' => Icons.person_outline,
      'invoice_lines' => Icons.table_chart_outlined,
      'invoice_totals' => Icons.calculate_outlined,
      'payments' => Icons.payments_outlined,
      'note' => Icons.notes,
      'signatures' => Icons.draw_outlined,
      'qr' => Icons.qr_code,
      'footer_meta' => Icons.schedule,
      'custom_text' => Icons.text_fields,
      'divider' => Icons.horizontal_rule,
      'spacer' => Icons.height,
      _ => Icons.widgets_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedBlockId == null
        ? null
        : _findBlock(_selectedBlockId!);
    final designerPane = _designerPane(context);

    if (widget.previewPane == null) {
      return _designerPane(context, selected: selected?.block);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1024) {
          final spacious = constraints.maxWidth >= 1400;
          return Row(
            textDirection: TextDirection.rtl,
            children: [
              SizedBox(width: spacious ? 420 : 380, child: designerPane),
              VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
              Expanded(child: _workspacePane(context)),
              VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
              SizedBox(
                width: spacious ? 350 : 320,
                child: _inspectorPane(context, selected?.block),
              ),
            ],
          );
        }

        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              const Material(
                child: TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.dashboard_customize), text: 'طراحی'),
                    Tab(icon: Icon(Icons.edit_note_outlined), text: 'صفحه'),
                    Tab(icon: Icon(Icons.tune), text: 'تنظیمات'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    designerPane,
                    _workspacePane(context),
                    _inspectorPane(context, selected?.block),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _workspacePane(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.dashboard_customize_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _showLivePreview
                        ? 'پیش‌نمایش واقعی خروجی'
                        : 'بوم طراحی تعاملی',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: WidgetStatePropertyAll(Size(0, 34)),
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 5),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.touch_app_outlined, size: 18),
                      label: Text('طراحی'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.visibility_outlined, size: 18),
                      label: Text('خروجی'),
                    ),
                  ],
                  selected: {_showLivePreview},
                  onSelectionChanged: (value) => setState(() {
                    _showLivePreview = value.first;
                  }),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _showLivePreview
              ? widget.previewPane!
              : _visualCanvas(context),
        ),
      ],
    );
  }

  void _setCanvasZoom(double value) {
    setState(() => _canvasZoom = value.clamp(0.5, 2.5).toDouble());
  }

  Widget _zoomControls(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const ValueKey('studio-zoom-out'),
            visualDensity: VisualDensity.compact,
            tooltip: 'کوچک‌نمایی',
            onPressed: _canvasZoom <= 0.5
                ? null
                : () => _setCanvasZoom(_canvasZoom - 0.1),
            icon: const Icon(Icons.remove, size: 18),
          ),
          InkWell(
            key: const ValueKey('studio-zoom-reset'),
            onTap: () => _setCanvasZoom(1),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text('${(_canvasZoom * 100).round()}٪'),
            ),
          ),
          IconButton(
            key: const ValueKey('studio-zoom-in'),
            visualDensity: VisualDensity.compact,
            tooltip: 'بزرگ‌نمایی',
            onPressed: _canvasZoom >= 2.5
                ? null
                : () => _setCanvasZoom(_canvasZoom + 0.1),
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }

  void _handleCanvasPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    _setCanvasZoom(_canvasZoom + (event.scrollDelta.dy < 0 ? 0.1 : -0.1));
  }

  List<Map<String, dynamic>> _allPageGridBlocks() {
    final regions = _regions(widget.design);
    _resolveProjectionAnchors(widget.design, regions);
    return [
      for (final region in const ['header', 'body', 'footer'])
        ...List<Map<String, dynamic>>.from(
          (regions[region] as List?) ?? const [],
        ),
    ];
  }

  double _pageGridDefaultWidth(String type, double canvasWidthMm) =>
      switch (type) {
        'invoice_lines' || 'brand_header' => canvasWidthMm,
        'party_info' => canvasWidthMm * 0.48,
        'invoice_totals' => canvasWidthMm * 0.55,
        'signatures' => canvasWidthMm * 0.65,
        'qr' => 34,
        _ => canvasWidthMm * 0.5,
      };

  double _pageGridDefaultHeight(String type) => switch (type) {
    'brand_header' => 30,
    'party_info' => 24,
    'invoice_lines' => 72,
    'invoice_totals' => 38,
    'payments' => 24,
    'note' => 22,
    'signatures' => 38,
    'qr' => 34,
    'footer_meta' => 14,
    'divider' => 4,
    'spacer' => 10,
    _ => 20,
  };

  bool _canDropOnPageGrid(_BlockDragData data) {
    final type =
        data.blockType ??
        _findBlock(data.blockId ?? '')?.block['type']?.toString();
    return type != null && _definition(type) != null;
  }

  void _dropOnPageGrid(
    _BlockDragData data,
    double xMm,
    double yMm,
    double canvasWidthMm,
    double canvasHeightMm,
  ) {
    final design = _clone(widget.design);
    final regions = _regions(design);
    Map<String, dynamic>? block;
    String? region;
    if (data.blockId != null) {
      for (final candidateRegion in const ['header', 'body', 'footer']) {
        final blocks = List<Map<String, dynamic>>.from(
          (regions[candidateRegion] as List?) ?? const [],
        );
        final index = blocks.indexWhere(
          (candidate) => candidate['id']?.toString() == data.blockId,
        );
        if (index >= 0) {
          block = Map<String, dynamic>.from(blocks[index]);
          region = candidateRegion;
          break;
        }
      }
    } else if (data.blockType != null) {
      final definition = _definition(data.blockType!);
      if (definition == null || !_canAdd(definition)) return;
      final allowed = List<String>.from(
        (definition['allowed_regions'] as List?) ?? const ['body'],
      );
      region = allowed.contains('body')
          ? 'body'
          : (allowed.isEmpty ? 'body' : allowed.first);
      block = _newBlock(data.blockType!, _newRowId(), 60);
      final blocks = List<Map<String, dynamic>>.from(
        (regions[region] as List?) ?? const [],
      )..add(block);
      regions[region] = blocks;
    }
    if (block == null || region == null) return;
    final type = block['type'].toString();
    final oldStyle =
        (block['style'] as Map?)?.cast<String, dynamic>() ?? const {};
    final width = _styleNumber(
      oldStyle,
      'width_mm',
      _pageGridDefaultWidth(type, canvasWidthMm),
    ).clamp(4, canvasWidthMm).toDouble();
    final height = _styleNumber(
      oldStyle,
      'height_mm',
      _pageGridDefaultHeight(type),
    ).clamp(4, canvasHeightMm).toDouble();
    final rect = StudioMmRect(
      xMm - width / 2,
      yMm - 8,
      width,
      height,
    ).clampInside(canvasWidthMm, canvasHeightMm);
    final blocks = List<Map<String, dynamic>>.from(
      (regions[region] as List?) ?? const [],
    );
    final index = blocks.indexWhere(
      (candidate) => candidate['id']?.toString() == block!['id']?.toString(),
    );
    if (index < 0) return;
    block['style'] = <String, dynamic>{
      ...oldStyle,
      'layout_type': 'page_grid',
      'x_mm': rect.x,
      'y_mm': rect.y,
      'width_mm': rect.width,
      'height_mm': rect.height,
    };
    blocks[index] = block;
    regions[region] = blocks;
    _setRegions(design, regions);
    _selectedBlockId = block['id'].toString();
    _commit(design);
  }

  void _patchPageGridSettings(Map<String, dynamic> patch) {
    final design = _clone(widget.design);
    final regions = _regions(design);
    for (final region in const ['header', 'body', 'footer']) {
      final blocks = List<Map<String, dynamic>>.from(
        (regions[region] as List?) ?? const [],
      );
      for (var index = 0; index < blocks.length; index++) {
        final block = Map<String, dynamic>.from(blocks[index]);
        final style =
            (block['style'] as Map?)?.cast<String, dynamic>() ?? const {};
        block['style'] = <String, dynamic>{
          ...style,
          'layout_type': 'page_grid',
          ...patch,
        };
        blocks[index] = block;
      }
      regions[region] = blocks;
    }
    _setRegions(design, regions);
    _commit(design);
  }

  Widget _pageGridCanvas(BuildContext context) {
    final media = normalizedReportTemplateMedia(
      widget.design,
      preferRoll: widget.design['layout'] == 'invoice_receipt',
    );
    final mediaSize = reportTemplateMediaSizeMm(media);
    final isRoll = media['type'] == 'roll';
    final margins =
        (media['margins_mm'] as Map?)?.cast<String, dynamic>() ?? const {};
    double marginMm(String side, double fallback) =>
        (margins[side] as num?)?.toDouble() ?? fallback;
    final leftMm = marginMm('left', isRoll ? 2 : 10);
    final rightMm = marginMm('right', isRoll ? 2 : 10);
    final topMm = marginMm('top', isRoll ? 3 : 10);
    final bottomMm = marginMm('bottom', isRoll ? 4 : 10);
    final canvasWidthMm = (mediaSize.width - leftMm - rightMm)
        .clamp(10, 1000)
        .toDouble();
    final blocks = _allPageGridBlocks();
    final firstStyle = blocks.isEmpty
        ? const <String, dynamic>{}
        : (blocks.first['style'] as Map?)?.cast<String, dynamic>() ?? const {};
    final gridMm = _styleNumber(
      firstStyle,
      'page_grid_mm',
      1,
    ).clamp(1, 5).toDouble();
    final snapEnabled = firstStyle['page_snap'] != false;
    final requiredBottom = blocks.fold<double>(
      0,
      (value, block) => math.max(value, _freeformRect(block).bottom + 10),
    );
    final sheetHeight = (mediaSize.height - topMm - bottomMm)
        .clamp(20, 5000)
        .toDouble();
    final configuredHeight = _styleNumber(
      firstStyle,
      'page_height_mm',
      sheetHeight,
    );
    final double canvasHeightMm = isRoll
        ? math.max(120.0, math.max(configuredHeight, requiredBottom))
        : sheetHeight;
    final direction = ((widget.design['theme'] as Map?)?['direction'] == 'ltr')
        ? TextDirection.ltr
        : TextDirection.rtl;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 800.0;
        final fittedPageWidthPx = (availableWidth - 48)
            .clamp(280.0, 760.0)
            .toDouble();
        final pageWidthPx = fittedPageWidthPx * _canvasZoom;
        final pixelsPerMm = pageWidthPx / mediaSize.width;
        final pageHeightPx = (topMm + canvasHeightMm + bottomMm) * pixelsPerMm;
        return Listener(
          onPointerSignal: _handleCanvasPointerSignal,
          child: ColoredBox(
            color: const Color(0xffe5e7eb),
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: math.max(availableWidth, pageWidthPx + 48),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Container(
                            width: pageWidthPx,
                            height: pageHeightPx,
                            padding: EdgeInsets.fromLTRB(
                              leftMm * pixelsPerMm,
                              topMm * pixelsPerMm,
                              rightMm * pixelsPerMm,
                              bottomMm * pixelsPerMm,
                            ),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x26000000),
                                  blurRadius: 18,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Directionality(
                              textDirection: direction,
                              child: Builder(
                                builder: (canvasContext) => DragTarget<_BlockDragData>(
                                  onWillAcceptWithDetails: (details) =>
                                      _canDropOnPageGrid(details.data),
                                  onAcceptWithDetails: (details) {
                                    final box =
                                        _pageGridCanvasKey.currentContext
                                                ?.findRenderObject()
                                            as RenderBox?;
                                    if (box == null) return;
                                    final local = box.globalToLocal(
                                      details.offset,
                                    );
                                    _dropOnPageGrid(
                                      details.data,
                                      local.dx / pixelsPerMm,
                                      local.dy / pixelsPerMm,
                                      canvasWidthMm,
                                      canvasHeightMm,
                                    );
                                  },
                                  builder: (context, candidates, rejected) =>
                                      Container(
                                        key: _pageGridCanvasKey,
                                        width: canvasWidthMm * pixelsPerMm,
                                        height: canvasHeightMm * pixelsPerMm,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: candidates.isNotEmpty
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.primary
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.outlineVariant,
                                          ),
                                        ),
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Positioned.fill(
                                              child: CustomPaint(
                                                painter: _MillimeterGridPainter(
                                                  pixelsPerMm: pixelsPerMm,
                                                  gridMm: gridMm,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outlineVariant
                                                      .withValues(alpha: 0.5),
                                                ),
                                              ),
                                            ),
                                            for (final block in blocks)
                                              _freeformCanvasBlock(
                                                context,
                                                block,
                                                siblings: blocks
                                                    .where(
                                                      (candidate) =>
                                                          candidate['id']
                                                              ?.toString() !=
                                                          block['id']
                                                              ?.toString(),
                                                    )
                                                    .map(_freeformRect)
                                                    .toList(),
                                                widthMm: canvasWidthMm,
                                                heightMm: canvasHeightMm,
                                                pixelsPerMm: pixelsPerMm,
                                                gridMm: gridMm,
                                                snapEnabled: snapEnabled,
                                              ),
                                            Positioned.fill(
                                              child: IgnorePointer(
                                                child: CustomPaint(
                                                  painter: _AnchorLinksPainter(
                                                    segments:
                                                        _canvasAnchorSegments(
                                                          blocks,
                                                        ),
                                                    pixelsPerMm: pixelsPerMm,
                                                    color:
                                                        Colors.green.shade700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            for (final guide in _freeformGuides)
                                              if (guide.vertical)
                                                Positioned(
                                                  left:
                                                      guide.positionMm *
                                                      pixelsPerMm,
                                                  top: 0,
                                                  bottom: 0,
                                                  child: Container(
                                                    width: 1,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.tertiary,
                                                  ),
                                                )
                                              else
                                                Positioned(
                                                  top:
                                                      guide.positionMm *
                                                      pixelsPerMm,
                                                  left: 0,
                                                  right: 0,
                                                  child: Container(
                                                    height: 1,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.tertiary,
                                                  ),
                                                ),
                                            PositionedDirectional(
                                              top: 4,
                                              end: 4,
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest
                                                      .withValues(alpha: 0.9),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                  child: Text(
                                                    'گرید کل صفحه · ${gridMm.toStringAsFixed(0)}mm${snapEnabled ? ' · Snap' : ''}',
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.labelSmall,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 12,
                  bottom: 12,
                  child: _zoomControls(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _visualCanvas(BuildContext context) {
    if (isReportTemplateV4(widget.design)) {
      return _pageGridCanvas(context);
    }
    final media = normalizedReportTemplateMedia(
      widget.design,
      preferRoll: widget.design['layout'] == 'invoice_receipt',
    );
    final mediaSize = reportTemplateMediaSizeMm(media);
    final isRoll = media['type'] == 'roll';
    final margins =
        (media['margins_mm'] as Map?)?.cast<String, dynamic>() ?? const {};
    final direction = ((widget.design['theme'] as Map?)?['direction'] == 'ltr')
        ? TextDirection.ltr
        : TextDirection.rtl;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 800.0;
        final pageWidth = (availableWidth - 48).clamp(280.0, 760.0).toDouble();
        final pageHeight = isRoll
            ? 760.0
            : pageWidth * mediaSize.height / mediaSize.width;
        double pageMargin(String side, double fallback) {
          final raw = margins[side];
          final mm = raw is num ? raw.toDouble() : double.tryParse('$raw');
          final reference = side == 'top' || side == 'bottom'
              ? mediaSize.height
              : mediaSize.width;
          return (((mm ?? fallback) / reference) * pageWidth).clamp(6.0, 64.0);
        }

        return ColoredBox(
          color: const Color(0xffe5e7eb),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Container(
                key: const ValueKey('interactive-invoice-canvas'),
                width: pageWidth,
                constraints: BoxConstraints(minHeight: pageHeight),
                padding: EdgeInsets.fromLTRB(
                  pageMargin('left', isRoll ? 2 : 10),
                  pageMargin('top', isRoll ? 3 : 10),
                  pageMargin('right', isRoll ? 2 : 10),
                  pageMargin('bottom', isRoll ? 4 : 10),
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: isRoll
                      ? Border.symmetric(
                          vertical: BorderSide(color: Colors.grey.shade400),
                        )
                      : null,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Directionality(
                  textDirection: direction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _canvasRegion(context, 'header', 'سربرگ'),
                      _canvasRegion(context, 'body', 'بدنه فاکتور'),
                      _canvasRegion(context, 'footer', 'پاورقی'),
                      if (isRoll)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Divider(color: Colors.grey.shade400),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  'ادامه رول',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: Colors.grey.shade600),
                                ),
                              ),
                              Expanded(
                                child: Divider(color: Colors.grey.shade400),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _canvasRegion(BuildContext context, String region, String title) {
    final blocks = _regionBlocks(widget.design, region);
    final rows = _canvasRows(blocks, region);
    return DragTarget<_BlockDragData>(
      onWillAcceptWithDetails: (details) =>
          _canDropOnRegion(details.data, region),
      onAcceptWithDetails: (details) =>
          _handleDrop(details.data, region, blocks.length),
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.45)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: active
                ? Border.all(color: Theme.of(context).colorScheme.primary)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (blocks.isEmpty)
                _canvasEmptyRegion(context, region, title)
              else ...[
                for (final row in rows) ...[
                  _canvasDropLine(region, row.startIndex),
                  _canvasRow(context, region, row),
                ],
              ],
              _canvasDropLine(region, blocks.length, expanded: active),
            ],
          ),
        );
      },
    );
  }

  Widget _canvasRow(BuildContext context, String region, _CanvasRow row) {
    final firstStyle =
        (row.blocks.first['style'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    if (isReportTemplateV4(widget.design) &&
        firstStyle['layout_type'] == 'freeform') {
      return _freeformCanvasRow(context, region, row, firstStyle);
    }
    final heightMode = (firstStyle['row_height_mode'] ?? 'auto').toString();
    final configuredHeight =
        (firstStyle['row_height_mm'] as num?)?.toDouble() ?? 20;
    final previewHeight = _resizingRowId == row.id
        ? _resizePreviewHeightMm
        : null;
    final heightMm = previewHeight ?? configuredHeight;
    final selectedInRow = row.blocks.any(
      (block) => block['id']?.toString() == _selectedBlockId,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final rowWidth = constraints.maxWidth;
        final media = normalizedReportTemplateMedia(widget.design);
        final mediaWidth = (media['width_mm'] as num?)?.toDouble() ?? 210;
        final margins =
            (media['margins_mm'] as Map?)?.cast<String, dynamic>() ?? const {};
        final printableMm =
            mediaWidth -
            ((margins['left'] as num?)?.toDouble() ?? 0) -
            ((margins['right'] as num?)?.toDouble() ?? 0);
        final pixelsPerMm = rowWidth / printableMm.clamp(10, 500);
        final minHeight = (heightMode != 'auto' || previewHeight != null)
            ? heightMm.clamp(4, 500) * pixelsPerMm
            : 0.0;
        final totalSpan = row.blocks.fold<int>(
          0,
          (sum, block) => sum + _blockSpan(block),
        );

        Widget rowContent = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final block in row.blocks)
              SizedBox(
                width:
                    rowWidth *
                    ((_resizingBlockId == block['id']?.toString()
                            ? _resizePreviewSpan
                            : null) ??
                        _blockSpan(block)) /
                    60,
                child: DragTarget<_BlockDragData>(
                  key: ValueKey('canvas-row-drop-${row.id}-${block['id']}'),
                  onWillAcceptWithDetails: (details) =>
                      details.data.blockId != block['id']?.toString() &&
                      _canDropOnRegion(details.data, region),
                  onAcceptWithDetails: (details) =>
                      _handleDropBeside(details.data, region, row.id),
                  builder: (context, candidates, rejected) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: candidates.isNotEmpty
                          ? Theme.of(context).colorScheme.primaryContainer
                                .withValues(alpha: 0.45)
                          : Colors.transparent,
                      border: candidates.isNotEmpty
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                    ),
                    child: _canvasBlock(
                      context,
                      block,
                      rowWidth: rowWidth,
                      maxSpan: (60 - (totalSpan - _blockSpan(block)))
                          .clamp(1, 60)
                          .toInt(),
                    ),
                  ),
                ),
              ),
            if (totalSpan < 60)
              Expanded(
                child: DragTarget<_BlockDragData>(
                  onWillAcceptWithDetails: (details) =>
                      _canDropOnRegion(details.data, region),
                  onAcceptWithDetails: (details) =>
                      _handleDropBeside(details.data, region, row.id),
                  builder: (context, candidates, rejected) => AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    constraints: const BoxConstraints(minHeight: 38),
                    decoration: BoxDecoration(
                      color: candidates.isNotEmpty
                          ? Theme.of(context).colorScheme.primaryContainer
                                .withValues(alpha: 0.45)
                          : Colors.transparent,
                      border: candidates.isNotEmpty
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: candidates.isNotEmpty
                        ? const Icon(Icons.add, size: 18)
                        : null,
                  ),
                ),
              ),
          ],
        );
        if (minHeight > 0) {
          rowContent = ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: rowContent,
          );
        }
        return Stack(
          clipBehavior: Clip.none,
          children: [
            rowContent,
            if (selectedInRow)
              PositionedDirectional(
                start: 0,
                end: 0,
                bottom: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    key: ValueKey('row-height-handle-${row.id}'),
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: () => _patchRowStyle(row.id, {
                      'row_height_mode': 'auto',
                      'row_height_mm': null,
                    }),
                    onVerticalDragStart: (_) {
                      _resizingRowId = row.id;
                      _resizeStartHeightMm = heightMode == 'auto'
                          ? 20
                          : configuredHeight;
                      _resizePreviewHeightMm = _resizeStartHeightMm;
                      _resizeVerticalDelta = 0;
                      setState(() {});
                    },
                    onVerticalDragUpdate: (details) {
                      _resizeVerticalDelta += details.delta.dy;
                      setState(() {
                        _resizePreviewHeightMm =
                            ((_resizeStartHeightMm ?? 20) +
                                    _resizeVerticalDelta / pixelsPerMm)
                                .clamp(4, 500);
                      });
                    },
                    onVerticalDragEnd: (_) {
                      final value = _resizePreviewHeightMm ?? configuredHeight;
                      _resizingRowId = null;
                      _resizeStartHeightMm = null;
                      _resizePreviewHeightMm = null;
                      _resizeVerticalDelta = 0;
                      _patchRowStyle(row.id, {
                        'row_height_mode': 'minimum',
                        'row_height_mm': double.parse(value.toStringAsFixed(1)),
                      });
                    },
                    child: Container(
                      height: 10,
                      alignment: Alignment.center,
                      child: Container(
                        width: 54,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  double _styleNumber(
    Map<String, dynamic> style,
    String key,
    double fallback,
  ) => (style[key] as num?)?.toDouble() ?? fallback;

  StudioMmRect _freeformRect(Map<String, dynamic> block) {
    final style = (block['style'] as Map?)?.cast<String, dynamic>() ?? const {};
    return StudioMmRect(
      _styleNumber(style, 'x_mm', 0),
      _styleNumber(style, 'y_mm', 0),
      _styleNumber(style, 'width_mm', 30),
      _styleNumber(style, 'height_mm', 15),
    );
  }

  Map<String, dynamic> _anchorConstraints(Map<String, dynamic> block) {
    final style = (block['style'] as Map?)?.cast<String, dynamic>() ?? const {};
    return (style['anchor_constraints'] as Map?)?.cast<String, dynamic>() ??
        const {};
  }

  List<Map<String, dynamic>> _anchorLinks(Map<String, dynamic> block) {
    return List<Map<String, dynamic>>.from(
      (_anchorConstraints(block)['links'] as List?) ?? const [],
    );
  }

  double _anchorCoordinate(StudioMmRect rect, String point) => switch (point) {
    'left' => rect.x,
    'right' => rect.right,
    'center_x' => rect.centerX,
    'top' => rect.y,
    'bottom' => rect.bottom,
    _ => rect.centerY,
  };

  double _activeAnchorOffset(Map<String, dynamic> link) {
    final offsets = (link['variant_offsets'] as Map?)?.cast<String, dynamic>();
    final value =
        offsets?[reportTemplateV4ProfileKey(widget.design)] ??
        link['offset_mm'];
    return (value as num?)?.toDouble() ?? double.tryParse('$value') ?? 0;
  }

  void _resolveProjectionAnchors(
    Map<String, dynamic> design,
    Map<String, dynamic> regions,
  ) {
    final blocks = <Map<String, dynamic>>[
      for (final region in const ['header', 'body', 'footer'])
        ...List<Map<String, dynamic>>.from(
          (regions[region] as List?) ?? const [],
        ),
    ];
    final byId = <String, Map<String, dynamic>>{
      for (final block in blocks) block['id'].toString(): block,
    };
    final media = normalizedReportTemplateMedia(design);
    final size = reportTemplateMediaSizeMm(media);
    final margins =
        (media['margins_mm'] as Map?)?.cast<String, dynamic>() ?? const {};
    final width =
        (size.width -
                ((margins['left'] as num?)?.toDouble() ?? 0) -
                ((margins['right'] as num?)?.toDouble() ?? 0))
            .clamp(10, 1000)
            .toDouble();
    final height =
        (size.height -
                ((margins['top'] as num?)?.toDouble() ?? 0) -
                ((margins['bottom'] as num?)?.toDouble() ?? 0))
            .clamp(20, 5000)
            .toDouble();
    final profile = reportTemplateV4ProfileKey(design);
    for (final block in blocks) {
      final constraints = _anchorConstraints(block);
      final pins =
          (constraints['pins'] as Map?)?.cast<String, dynamic>() ?? const {};
      final baseOffsets =
          (constraints['pin_offsets_mm'] as Map?)?.cast<String, dynamic>() ??
          const {};
      final variantOffsets =
          ((constraints['variant_pin_offsets'] as Map?)?[profile] as Map?)
              ?.cast<String, dynamic>();
      double offset(String edge) =>
          ((variantOffsets?[edge] ?? baseOffsets[edge]) as num?)?.toDouble() ??
          0;
      var rect = _freeformRect(block);
      if (pins['left'] == true && pins['right'] == true) {
        rect = StudioMmRect(
          offset('left'),
          rect.y,
          math.max(1, width - offset('left') - offset('right')),
          rect.height,
        );
      } else if (pins['right'] == true) {
        rect = StudioMmRect(
          width - offset('right') - rect.width,
          rect.y,
          rect.width,
          rect.height,
        );
      } else if (pins['left'] == true) {
        rect = StudioMmRect(offset('left'), rect.y, rect.width, rect.height);
      } else if (pins['center_x'] == true) {
        rect = StudioMmRect(
          (width - rect.width) / 2 + offset('center_x'),
          rect.y,
          rect.width,
          rect.height,
        );
      }
      if (pins['top'] == true && pins['bottom'] == true) {
        rect = StudioMmRect(
          rect.x,
          offset('top'),
          rect.width,
          math.max(1, height - offset('top') - offset('bottom')),
        );
      } else if (pins['bottom'] == true) {
        rect = StudioMmRect(
          rect.x,
          height - offset('bottom') - rect.height,
          rect.width,
          rect.height,
        );
      } else if (pins['top'] == true) {
        rect = StudioMmRect(rect.x, offset('top'), rect.width, rect.height);
      } else if (pins['center_y'] == true) {
        rect = StudioMmRect(
          rect.x,
          (height - rect.height) / 2 + offset('center_y'),
          rect.width,
          rect.height,
        );
      }
      final style = (block['style'] as Map).cast<String, dynamic>();
      block['style'] = <String, dynamic>{
        ...style,
        'x_mm': rect.x,
        'y_mm': rect.y,
        'width_mm': rect.width,
        'height_mm': rect.height,
      };
    }
    for (var pass = 0; pass < blocks.length; pass++) {
      var changed = false;
      for (final block in blocks) {
        var rect = _freeformRect(block);
        for (final link in _anchorLinks(block)) {
          final target = (link['target'] as Map?)?.cast<String, dynamic>();
          final targetBlock = byId[target?['id']?.toString()];
          if (targetBlock == null) continue;
          final sourcePoint = (link['source_anchor'] ?? '').toString();
          final targetPoint = (target?['anchor'] ?? '').toString();
          final desired =
              _anchorCoordinate(_freeformRect(targetBlock), targetPoint) +
              _activeAnchorOffset(link);
          final current = _anchorCoordinate(rect, sourcePoint);
          if ((desired - current).abs() < 0.001) continue;
          if (link['axis'] == 'horizontal') {
            rect = StudioMmRect(
              rect.x + desired - current,
              rect.y,
              rect.width,
              rect.height,
            ).clampInside(width, height);
          } else {
            rect = StudioMmRect(
              rect.x,
              rect.y + desired - current,
              rect.width,
              rect.height,
            ).clampInside(width, height);
          }
          changed = true;
        }
        final style = (block['style'] as Map).cast<String, dynamic>();
        block['style'] = <String, dynamic>{
          ...style,
          'x_mm': rect.x,
          'y_mm': rect.y,
        };
      }
      if (!changed) break;
    }
  }

  String? _anchorAxis(String point) {
    if (_horizontalAnchorPoints.contains(point)) return 'horizontal';
    if (_verticalAnchorPoints.contains(point)) return 'vertical';
    return null;
  }

  void _onAnchorHandleTap(String blockId, String point) {
    final pendingId = _pendingAnchorBlockId;
    final pendingPoint = _pendingAnchorPoint;
    if (pendingId == null || pendingPoint == null || pendingId == blockId) {
      setState(() {
        _selectedBlockId = blockId;
        _pendingAnchorBlockId = blockId;
        _pendingAnchorPoint = point;
      });
      return;
    }
    final axis = _anchorAxis(pendingPoint);
    if (axis == null || axis != _anchorAxis(point)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('نقطه‌های اتصال باید روی یک محور باشند.')),
      );
      return;
    }
    final resolvedBlocks = _allPageGridBlocks();
    Map<String, dynamic>? resolvedBlock(String id) {
      for (final block in resolvedBlocks) {
        if (block['id']?.toString() == id) return block;
      }
      return null;
    }

    final source = resolvedBlock(pendingId);
    final target = resolvedBlock(blockId);
    if (source == null || target == null) return;
    if (_wouldCreateAnchorCycle(pendingId, blockId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('این اتصال یک چرخه ایجاد می‌کند.')),
      );
      setState(() {
        _pendingAnchorBlockId = null;
        _pendingAnchorPoint = null;
      });
      return;
    }
    if (axis == 'vertical' && pendingPoint == 'top' && point == 'bottom') {
      final alreadyFollowed = _allPageGridBlocks().any(
        (candidate) =>
            candidate['id']?.toString() != pendingId &&
            _anchorLinks(candidate).any((link) {
              final target = (link['target'] as Map?);
              return link['axis'] == 'vertical' &&
                  link['source_anchor'] == 'top' &&
                  target?['anchor'] == 'bottom' &&
                  target?['id']?.toString() == blockId;
            }),
      );
      if (alreadyFollowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'این نقطه یک دنبال‌کننده دارد؛ بلوک جدید را به انتهای همان زنجیره وصل کنید.',
            ),
          ),
        );
        return;
      }
    }
    final offset =
        _anchorCoordinate(_freeformRect(source), pendingPoint) -
        _anchorCoordinate(_freeformRect(target), point);
    final profile = reportTemplateV4ProfileKey(widget.design);
    final constraints = _clone(_anchorConstraints(source));
    final links = List<Map<String, dynamic>>.from(
      (constraints['links'] as List?) ?? const [],
    )..removeWhere((link) => link['axis'] == axis);
    links.add(<String, dynamic>{
      'id': '$axis-anchor',
      'axis': axis,
      'source_anchor': pendingPoint,
      'target': {'type': 'node', 'id': blockId, 'anchor': point},
      'offset_mm': double.parse(offset.toStringAsFixed(2)),
      'variant_offsets': {profile: double.parse(offset.toStringAsFixed(2))},
    });
    constraints['links'] = links;
    final pins =
        (constraints['pins'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    for (final edge
        in axis == 'horizontal'
            ? const ['left', 'right', 'center_x']
            : const ['top', 'bottom', 'center_y']) {
      pins[edge] = false;
    }
    constraints['pins'] = pins;
    _patchBlockStyle(pendingId, {'anchor_constraints': constraints});
    setState(() {
      _selectedBlockId = pendingId;
      _pendingAnchorBlockId = null;
      _pendingAnchorPoint = null;
    });
  }

  bool _wouldCreateAnchorCycle(String sourceId, String targetId) {
    final dependencies = <String, List<String>>{};
    for (final block in _allPageGridBlocks()) {
      dependencies[block['id'].toString()] = _anchorLinks(block)
          .map((link) => ((link['target'] as Map?)?['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();
    }
    dependencies[sourceId] = [
      ...(dependencies[sourceId] ?? const []),
      targetId,
    ];
    final seen = <String>{};
    bool reachesSource(String id) {
      if (id == sourceId) return true;
      if (!seen.add(id)) return false;
      return (dependencies[id] ?? const []).any(reachesSource);
    }

    return reachesSource(targetId);
  }

  void _removeAnchorAxis(String id, String axis) {
    final block = _findBlock(id)?.block;
    if (block == null) return;
    final constraints = _clone(_anchorConstraints(block));
    final links = List<Map<String, dynamic>>.from(
      (constraints['links'] as List?) ?? const [],
    )..removeWhere((link) => link['axis'] == axis);
    constraints['links'] = links;
    _patchBlockStyle(id, {'anchor_constraints': constraints});
  }

  void _setAnchorGap(String id, Map<String, dynamic> link, double value) {
    final block = _findBlock(id)?.block;
    if (block == null) return;
    final constraints = _clone(_anchorConstraints(block));
    final links = List<Map<String, dynamic>>.from(
      (constraints['links'] as List?) ?? const [],
    );
    final index = links.indexWhere((item) => item['axis'] == link['axis']);
    if (index < 0) return;
    final next = Map<String, dynamic>.from(links[index]);
    final offsets =
        (next['variant_offsets'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    next['variant_offsets'] = <String, dynamic>{
      ...offsets,
      reportTemplateV4ProfileKey(widget.design): value,
    };
    links[index] = next;
    constraints['links'] = links;
    _patchBlockStyle(id, {'anchor_constraints': constraints});
  }

  void _togglePagePin(
    String id,
    String edge,
    bool enabled,
    double canvasWidthMm,
    double canvasHeightMm,
  ) {
    Map<String, dynamic>? block;
    for (final candidate in _allPageGridBlocks()) {
      if (candidate['id']?.toString() == id) {
        block = candidate;
        break;
      }
    }
    if (block == null) return;
    final rect = _freeformRect(block);
    final constraints = _clone(_anchorConstraints(block));
    final pins =
        (constraints['pins'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    pins[edge] = enabled;
    if (enabled && edge == 'center_x') {
      pins['left'] = false;
      pins['right'] = false;
    } else if (enabled && const {'left', 'right'}.contains(edge)) {
      pins['center_x'] = false;
    }
    if (enabled && edge == 'center_y') {
      pins['top'] = false;
      pins['bottom'] = false;
    } else if (enabled && const {'top', 'bottom'}.contains(edge)) {
      pins['center_y'] = false;
    }
    if (enabled) {
      final axis = const {'left', 'right', 'center_x'}.contains(edge)
          ? 'horizontal'
          : 'vertical';
      final links = List<Map<String, dynamic>>.from(
        (constraints['links'] as List?) ?? const [],
      )..removeWhere((link) => link['axis'] == axis);
      constraints['links'] = links;
    }
    constraints['pins'] = pins;
    if (edge == 'bottom' && enabled && constraints['bottom_mode'] == null) {
      constraints['bottom_mode'] = 'last_page';
    }
    final profile = reportTemplateV4ProfileKey(widget.design);
    final allVariantOffsets =
        (constraints['variant_pin_offsets'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final offsets =
        (allVariantOffsets[profile] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final edgeOffset = switch (edge) {
      'left' => rect.x,
      'right' => canvasWidthMm - rect.right,
      'top' => rect.y,
      'bottom' => canvasHeightMm - rect.bottom,
      'center_x' => rect.centerX - canvasWidthMm / 2,
      'center_y' => rect.centerY - canvasHeightMm / 2,
      _ => 0,
    };
    offsets[edge] = edgeOffset;
    final baseOffsets =
        (constraints['pin_offsets_mm'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    baseOffsets.putIfAbsent(edge, () => edgeOffset);
    constraints['pin_offsets_mm'] = baseOffsets;
    allVariantOffsets[profile] = offsets;
    constraints['variant_pin_offsets'] = allVariantOffsets;
    _patchBlockStyle(id, {'anchor_constraints': constraints});
  }

  void _setAnchorConstraintValue(String id, String key, dynamic value) {
    final block = _findBlock(id)?.block;
    if (block == null) return;
    final constraints = _clone(_anchorConstraints(block));
    constraints[key] = value;
    _patchBlockStyle(id, {'anchor_constraints': constraints});
  }

  List<_CanvasAnchorSegment> _canvasAnchorSegments(
    List<Map<String, dynamic>> blocks,
  ) {
    final byId = <String, Map<String, dynamic>>{
      for (final block in blocks) block['id'].toString(): block,
    };
    final segments = <_CanvasAnchorSegment>[];
    for (final block in blocks) {
      final sourceRect = _freeformRect(block);
      for (final link in _anchorLinks(block)) {
        final target = (link['target'] as Map?)?.cast<String, dynamic>();
        final targetBlock = byId[target?['id']?.toString()];
        if (targetBlock == null) continue;
        final targetRect = _freeformRect(targetBlock);
        final sourcePoint = (link['source_anchor'] ?? '').toString();
        final targetPoint = (target?['anchor'] ?? '').toString();
        Offset point(StudioMmRect rect, String anchor) => switch (anchor) {
          'left' => Offset(rect.x, rect.centerY),
          'right' => Offset(rect.right, rect.centerY),
          'top' => Offset(rect.centerX, rect.y),
          'bottom' => Offset(rect.centerX, rect.bottom),
          'center_x' => Offset(rect.centerX, rect.centerY),
          _ => Offset(rect.centerX, rect.centerY),
        };
        segments.add(
          _CanvasAnchorSegment(
            point(sourceRect, sourcePoint),
            point(targetRect, targetPoint),
          ),
        );
      }
    }
    return segments;
  }

  void _finishFreeformGesture(String id) {
    final rect = _freeformPreviewRect;
    _freeformGestureId = null;
    _freeformStartRect = null;
    _freeformPreviewRect = null;
    _freeformDelta = Offset.zero;
    _freeformGuides = const [];
    if (rect == null) {
      setState(() {});
      return;
    }
    _patchBlockStyle(id, {
      'x_mm': double.parse(rect.x.toStringAsFixed(2)),
      'y_mm': double.parse(rect.y.toStringAsFixed(2)),
      'width_mm': double.parse(rect.width.toStringAsFixed(2)),
      'height_mm': double.parse(rect.height.toStringAsFixed(2)),
    });
  }

  void _patchFreeformGeometryField(
    Map<String, dynamic> block,
    String field,
    double value,
    double containerHeightMm,
  ) {
    final media = normalizedReportTemplateMedia(widget.design);
    final margins =
        (media['margins_mm'] as Map?)?.cast<String, dynamic>() ?? const {};
    final containerWidthMm =
        ((media['width_mm'] as num?)?.toDouble() ?? 210) -
        ((margins['left'] as num?)?.toDouble() ?? 0) -
        ((margins['right'] as num?)?.toDouble() ?? 0);
    final current = _freeformRect(block);
    final proposed = StudioMmRect(
      field == 'x_mm' ? value : current.x,
      field == 'y_mm' ? value : current.y,
      field == 'width_mm' ? value.clamp(1, containerWidthMm) : current.width,
      field == 'height_mm' ? value.clamp(1, containerHeightMm) : current.height,
    ).clampInside(containerWidthMm, containerHeightMm);
    _patchBlockStyle(block['id'].toString(), {
      'x_mm': proposed.x,
      'y_mm': proposed.y,
      'width_mm': proposed.width,
      'height_mm': proposed.height,
    });
  }

  Widget _freeformCanvasRow(
    BuildContext context,
    String region,
    _CanvasRow row,
    Map<String, dynamic> rowStyle,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = normalizedReportTemplateMedia(widget.design);
        final mediaWidth = (media['width_mm'] as num?)?.toDouble() ?? 210;
        final margins =
            (media['margins_mm'] as Map?)?.cast<String, dynamic>() ?? const {};
        final printableWidth =
            mediaWidth -
            ((margins['left'] as num?)?.toDouble() ?? 0) -
            ((margins['right'] as num?)?.toDouble() ?? 0);
        final widthMm = printableWidth.clamp(10, 500).toDouble();
        final pixelsPerMm = constraints.maxWidth / widthMm;
        final heightMm = _styleNumber(
          rowStyle,
          'freeform_height_mm',
          40,
        ).clamp(4, 500).toDouble();
        final gridMm = _styleNumber(
          rowStyle,
          'freeform_grid_mm',
          1,
        ).clamp(1, 5).toDouble();
        final snapEnabled = rowStyle['freeform_snap'] != false;

        return Container(
          key: ValueKey('freeform-row-${row.id}'),
          height: heightMm * pixelsPerMm,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _MillimeterGridPainter(
                    pixelsPerMm: pixelsPerMm,
                    gridMm: gridMm,
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
              ),
              for (final block in row.blocks)
                _freeformCanvasBlock(
                  context,
                  block,
                  siblings: row.blocks
                      .where(
                        (candidate) =>
                            candidate['id']?.toString() !=
                            block['id']?.toString(),
                      )
                      .map(_freeformRect)
                      .toList(),
                  widthMm: widthMm,
                  heightMm: heightMm,
                  pixelsPerMm: pixelsPerMm,
                  gridMm: gridMm,
                  snapEnabled: snapEnabled,
                ),
              for (final guide in _freeformGuides)
                if (guide.vertical)
                  Positioned(
                    left: guide.positionMm * pixelsPerMm,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      key: const ValueKey('freeform-guide-vertical'),
                      width: 1,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  )
                else
                  Positioned(
                    top: guide.positionMm * pixelsPerMm,
                    left: 0,
                    right: 0,
                    child: Container(
                      key: const ValueKey('freeform-guide-horizontal'),
                      height: 1,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
              PositionedDirectional(
                top: 4,
                end: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    child: Text(
                      'آزاد · شبکه ${gridMm.toStringAsFixed(0)}mm${snapEnabled ? ' · Snap' : ''}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _freeformCanvasBlock(
    BuildContext context,
    Map<String, dynamic> block, {
    required List<StudioMmRect> siblings,
    required double widthMm,
    required double heightMm,
    required double pixelsPerMm,
    required double gridMm,
    required bool snapEnabled,
  }) {
    final id = block['id'].toString();
    final selected = id == _selectedBlockId;
    final stored = _freeformRect(block);
    final rect = _freeformGestureId == id
        ? (_freeformPreviewRect ?? stored)
        : stored;
    return Positioned(
      key: ValueKey('freeform-block-$id'),
      left: rect.x * pixelsPerMm,
      top: rect.y * pixelsPerMm,
      width: rect.width * pixelsPerMm,
      height: rect.height * pixelsPerMm,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectBlock(id),
        // Claim the gesture against the surrounding scroll view. Geometry is
        // driven by raw pointer deltas below so both axes remain available.
        onPanStart: (_) {},
        onPanUpdate: (_) {},
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_freeformResizingId == id) return;
            _freeformMovePointer = event.pointer;
            _selectBlock(id);
            _freeformGestureId = id;
            _freeformStartRect = stored;
            _freeformPreviewRect = stored;
            _freeformDelta = Offset.zero;
          },
          onPointerMove: (event) {
            if (_freeformMovePointer != event.pointer ||
                _freeformResizingId == id) {
              return;
            }
            _freeformDelta += event.delta;
            final start = _freeformStartRect ?? stored;
            final proposed = StudioMmRect(
              start.x + _freeformDelta.dx / pixelsPerMm,
              start.y + _freeformDelta.dy / pixelsPerMm,
              start.width,
              start.height,
            );
            final result = snapStudioMove(
              proposed: proposed,
              siblings: siblings,
              containerWidthMm: widthMm,
              containerHeightMm: heightMm,
              gridMm: gridMm,
              thresholdMm: 6 / pixelsPerMm,
              enabled: snapEnabled,
            );
            setState(() {
              _freeformPreviewRect = result.rect;
              _freeformGuides = result.guides;
            });
          },
          onPointerUp: (event) {
            if (_freeformMovePointer != event.pointer) return;
            _freeformMovePointer = null;
            _finishFreeformGesture(id);
          },
          onPointerCancel: (event) {
            if (_freeformMovePointer != event.pointer) return;
            _freeformMovePointer = null;
            _finishFreeformGesture(id);
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.65)
                  : Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.92),
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: ClipRect(child: _canvasBlockContent(context, block)),
                  ),
                ),
                if (selected || _pendingAnchorBlockId != null)
                  for (final entry in const <String, Alignment>{
                    'top': Alignment.topCenter,
                    'right': Alignment.centerRight,
                    'bottom': Alignment.bottomCenter,
                    'left': Alignment.centerLeft,
                  }.entries)
                    Positioned.fill(
                      child: Align(
                        alignment: entry.value,
                        child: Tooltip(
                          message: _pendingAnchorBlockId == null
                              ? 'شروع اتصال از ${_anchorPointLabel(entry.key)}'
                              : 'اتصال به ${_anchorPointLabel(entry.key)}',
                          child: GestureDetector(
                            key: ValueKey('anchor-handle-$id-${entry.key}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _onAnchorHandleTap(id, entry.key),
                            child: Container(
                              width: 13,
                              height: 13,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    _pendingAnchorBlockId == id &&
                                        _pendingAnchorPoint == entry.key
                                    ? Colors.green
                                    : Theme.of(context).colorScheme.surface,
                                border: Border.all(
                                  color: Colors.green.shade700,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                if (selected)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: Listener(
                        key: ValueKey('freeform-resize-handle-$id'),
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) {
                          _freeformMovePointer = null;
                          _freeformResizePointer = event.pointer;
                          _freeformResizingId = id;
                          _freeformGestureId = id;
                          _freeformStartRect = stored;
                          _freeformPreviewRect = stored;
                          _freeformDelta = Offset.zero;
                        },
                        onPointerMove: (event) {
                          if (_freeformResizePointer != event.pointer) return;
                          _freeformDelta += event.delta;
                          final start = _freeformStartRect ?? stored;
                          final proposed = StudioMmRect(
                            start.x,
                            start.y,
                            (start.width + _freeformDelta.dx / pixelsPerMm)
                                .clamp(4, widthMm),
                            (start.height + _freeformDelta.dy / pixelsPerMm)
                                .clamp(4, heightMm),
                          );
                          final result = snapStudioResize(
                            proposed: proposed,
                            siblings: siblings,
                            containerWidthMm: widthMm,
                            containerHeightMm: heightMm,
                            gridMm: gridMm,
                            thresholdMm: 6 / pixelsPerMm,
                            enabled: snapEnabled,
                          );
                          setState(() {
                            _freeformPreviewRect = result.rect;
                            _freeformGuides = result.guides;
                          });
                        },
                        onPointerUp: (event) {
                          if (_freeformResizePointer != event.pointer) return;
                          _freeformResizePointer = null;
                          _freeformResizingId = null;
                          _finishFreeformGesture(id);
                        },
                        onPointerCancel: (event) {
                          if (_freeformResizePointer != event.pointer) return;
                          _freeformResizePointer = null;
                          _freeformResizingId = null;
                          _finishFreeformGesture(id);
                        },
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            border: Border.all(color: Colors.white, width: 2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _anchorPointLabel(String point) => switch (point) {
    'top' => 'بالا',
    'right' => 'راست',
    'bottom' => 'پایین',
    'left' => 'چپ',
    'center_x' => 'مرکز افقی',
    _ => 'مرکز عمودی',
  };

  bool _canDropOnRegion(_BlockDragData data, String region) {
    final type =
        data.blockType ??
        _findBlock(data.blockId ?? '')?.block['type']?.toString();
    final allowed = List<String>.from(
      (_definition(type ?? '')?['allowed_regions'] as List?) ?? const [],
    );
    return allowed.contains(region);
  }

  Widget _canvasEmptyRegion(BuildContext context, String region, String title) {
    return DragTarget<_BlockDragData>(
      onWillAcceptWithDetails: (details) =>
          _canDropOnRegion(details.data, region),
      onAcceptWithDetails: (details) => _handleDrop(details.data, region, 0),
      builder: (context, candidates, rejected) => Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: candidates.isNotEmpty
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
            style: BorderStyle.solid,
          ),
        ),
        child: Text(
          '$title — بلوک را اینجا رها کنید',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: Colors.grey.shade600),
        ),
      ),
    );
  }

  Widget _canvasDropLine(String region, int index, {bool expanded = false}) {
    return DragTarget<_BlockDragData>(
      onWillAcceptWithDetails: (details) =>
          _canDropOnRegion(details.data, region),
      onAcceptWithDetails: (details) =>
          _handleDrop(details.data, region, index),
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: active || expanded ? 24 : 6,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: active
                ? Border.all(color: Theme.of(context).colorScheme.primary)
                : null,
          ),
          alignment: Alignment.center,
          child: active
              ? Icon(
                  Icons.add,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
        );
      },
    );
  }

  Widget _canvasBlock(
    BuildContext context,
    Map<String, dynamic> block, {
    required double rowWidth,
    required int maxSpan,
  }) {
    final id = block['id'].toString();
    final type = block['type'].toString();
    final selected = id == _selectedBlockId;
    final style = (block['style'] as Map?)?.cast<String, dynamic>() ?? const {};
    final alignment = switch (style['text_align']) {
      'left' => Alignment.centerLeft,
      'center' => Alignment.center,
      _ => Alignment.centerRight,
    };
    final blockCard = GestureDetector(
      key: ValueKey('canvas-block-$id'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectBlock(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.35)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: alignment,
              child: _canvasBlockContent(context, block),
            ),
            if (selected)
              PositionedDirectional(
                top: -20,
                end: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.drag_indicator,
                        size: 13,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _labelForType(type),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (selected)
              PositionedDirectional(
                top: 0,
                bottom: 0,
                end: -6,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    key: ValueKey('block-width-handle-$id'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) {
                      _resizingBlockId = id;
                      _resizeStartSpan = _blockSpan(block);
                      _resizePreviewSpan = _resizeStartSpan;
                      _resizeHorizontalDelta = 0;
                      setState(() {});
                    },
                    onHorizontalDragUpdate: (details) {
                      _resizeHorizontalDelta += details.delta.dx;
                      final rtl =
                          Directionality.of(context) == TextDirection.rtl;
                      final deltaColumns =
                          _resizeHorizontalDelta /
                          (rowWidth / 60) *
                          (rtl ? -1 : 1);
                      setState(() {
                        _resizePreviewSpan =
                            ((_resizeStartSpan ?? 60) + deltaColumns.round())
                                .clamp(1, maxSpan)
                                .toInt();
                      });
                    },
                    onHorizontalDragEnd: (_) {
                      final span = _resizePreviewSpan ?? _blockSpan(block);
                      _resizingBlockId = null;
                      _resizeStartSpan = null;
                      _resizePreviewSpan = null;
                      _resizeHorizontalDelta = 0;
                      _patchBlockStyle(id, {
                        'width_mode': 'full',
                        'grid_span': span,
                      });
                    },
                    child: Container(
                      width: 12,
                      alignment: Alignment.center,
                      child: Container(
                        width: 4,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Opacity(
      opacity: block['visible'] == false ? 0.42 : 1,
      child: Draggable<_BlockDragData>(
        data: _BlockDragData.existing(id),
        onDragStarted: () => _selectBlock(id),
        feedback: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 280,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(_iconForType(type), size: 18),
                  const SizedBox(width: 8),
                  Text(_labelForType(type)),
                ],
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.25, child: blockCard),
        child: MouseRegion(cursor: SystemMouseCursors.grab, child: blockCard),
      ),
    );
  }

  Widget _canvasBlockContent(BuildContext context, Map<String, dynamic> block) {
    final type = block['type'].toString();
    final props = (block['props'] as Map?)?.cast<String, dynamic>() ?? const {};
    final theme =
        (widget.design['theme'] as Map?)?.cast<String, dynamic>() ?? const {};
    final primary = _colorFromHex(
      (theme['primary_color'] ?? '#1e3a5f').toString(),
    );
    final small = Theme.of(context).textTheme.bodySmall;
    switch (type) {
      case 'brand_header':
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'فاکتور فروش',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text('شماره: ۱۰۰۱  •  تاریخ: ۱۴۰۵/۰۷/۲۷', style: small),
                ],
              ),
            ),
            Icon(Icons.business, color: primary, size: 34),
          ],
        );
      case 'party_info':
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (props['title'] ?? 'طرف حساب').toString(),
                style: small?.copyWith(
                  color: primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text('نام و مشخصات طرف حساب'),
            ],
          ),
        );
      case 'invoice_lines':
        final columns = ((props['columns'] as List?) ?? const [])
            .whereType<Map>()
            .where((column) => column['visible'] != false)
            .take(4)
            .toList();
        final titles = columns.isEmpty
            ? const ['شرح', 'تعداد', 'مبلغ']
            : columns
                  .map(
                    (column) => (column['title'] ?? column['key']).toString(),
                  )
                  .toList();
        return Table(
          border: TableBorder.all(color: Colors.grey.shade300),
          children: [
            TableRow(
              decoration: BoxDecoration(color: primary),
              children: [
                for (final title in titles)
                  Padding(
                    padding: const EdgeInsets.all(5),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
              ],
            ),
            for (var row = 0; row < 3; row++)
              TableRow(
                children: [
                  for (var column = 0; column < titles.length; column++)
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: Text(
                        column == 0
                            ? 'نمونه کالا ${row + 1}'
                            : '${row + column + 1}',
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                ],
              ),
          ],
        );
      case 'invoice_totals':
        return Column(
          children: const [
            _CanvasTotalRow(label: 'جمع اقلام', value: '۱٬۲۰۰٬۰۰۰'),
            _CanvasTotalRow(label: 'تخفیف', value: '۵۰٬۰۰۰'),
            _CanvasTotalRow(
              label: 'قابل پرداخت',
              value: '۱٬۱۵۰٬۰۰۰',
              bold: true,
            ),
          ],
        );
      case 'payments':
        return const ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.payments_outlined),
          title: Text('پرداخت‌ها'),
          subtitle: Text('کارت‌خوان — ۱٬۱۵۰٬۰۰۰'),
        );
      case 'note':
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: const Color(0xfffffbeb),
          child: const Text('یادداشت فاکتور در این قسمت نمایش داده می‌شود.'),
        );
      case 'signatures':
        return const Row(
          children: [
            Expanded(child: _CanvasSignature(label: 'امضای فروشنده')),
            SizedBox(width: 12),
            Expanded(child: _CanvasSignature(label: 'امضای خریدار')),
          ],
        );
      case 'qr':
        return const Center(child: Icon(Icons.qr_code_2, size: 72));
      case 'footer_meta':
        return Text(
          'زمان چاپ  •  تهیه‌کننده سند',
          textAlign: TextAlign.center,
          style: small?.copyWith(color: Colors.grey.shade600),
        );
      case 'custom_text':
        return Text((props['text'] ?? 'متن دلخواه').toString());
      case 'divider':
        return Divider(color: Colors.grey.shade500);
      case 'spacer':
        return SizedBox(
          height: ((props['height'] as num?)?.toDouble() ?? 12)
              .clamp(4, 80)
              .toDouble(),
        );
      default:
        return Row(
          children: [
            Icon(_iconForType(type), size: 18),
            const SizedBox(width: 8),
            Text(_labelForType(type)),
          ],
        );
    }
  }

  Color _colorFromHex(String value) {
    final hex = value.replaceFirst('#', '');
    final parsed = int.tryParse(hex.length == 6 ? 'ff$hex' : hex, radix: 16);
    return Color(parsed ?? 0xff1e3a5f);
  }

  Widget _designerPane(BuildContext context, {Map<String, dynamic>? selected}) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (widget.editorHeader != null) ...[
          widget.editorHeader!,
          const Divider(height: 24),
        ],
        Row(
          children: [
            Text(
              isReportTemplateV4(widget.design)
                  ? 'طراح گرید تمام‌صفحه'
                  : 'طراح بلوکی',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              onPressed: _historyIndex > 0 ? _undo : null,
              icon: const Icon(Icons.undo),
              tooltip: 'بازگشت',
            ),
            IconButton(
              onPressed: _historyIndex + 1 < _history.length ? _redo : null,
              icon: const Icon(Icons.redo),
              tooltip: 'انجام دوباره',
            ),
          ],
        ),
        Text(
          isReportTemplateV4(widget.design)
              ? 'قطعه را از فهرست روی هر نقطهٔ صفحه رها کنید؛ سپس آن را آزادانه جابه‌جا یا تغییر اندازه دهید.'
              : 'برای ساخت ردیف جدید، قطعه را بین ردیف‌ها رها کنید؛ برای چیدن چند قطعه کنار هم، آن را روی یک قطعهٔ دیگر رها کنید.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        _buildAppearance(context),
        const SizedBox(height: 12),
        Text(
          'قطعات',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: widget.blockCatalog
              .map((definition) => _paletteItem(context, definition))
              .toList(),
        ),
        const SizedBox(height: 16),
        _region(context, 'header', 'سربرگ'),
        const SizedBox(height: 10),
        _region(context, 'body', 'بدنه فاکتور'),
        const SizedBox(height: 10),
        _region(context, 'footer', 'پاورقی'),
        if (selected != null) ...[
          const SizedBox(height: 16),
          _inspector(context, selected),
        ],
      ],
    );
  }

  Widget _inspectorPane(BuildContext context, Map<String, dynamic>? selected) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ExpansionTile(
          key: ValueKey('studio-media-settings-${selected == null}'),
          initiallyExpanded: selected == null,
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.straighten_outlined),
          title: const Text('صفحه و چاپ'),
          subtitle: Text(_mediaSummary()),
          children: [
            ReportTemplateMediaSettings(
              media: normalizedReportTemplateMedia(
                widget.design,
                preferRoll: widget.design['layout'] == 'invoice_receipt',
              ),
              compact: true,
              onChanged: (media) => _patchRoot((design) {
                design['media'] = media;
              }),
            ),
            if (isReportTemplateV4(widget.design))
              Card(
                margin: const EdgeInsets.only(top: 10),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.devices_fold_outlined),
                  title: Text(
                    'Variant فعال: ${reportTemplateV4ProfileKey(widget.design)}',
                  ),
                  subtitle: const Text(
                    'چیدمان هر کاغذ مستقل است؛ با تغییر اندازه کاغذ، variant همان کاغذ ویرایش می‌شود.',
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
        const Divider(),
        if (selected == null)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    size: 40,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'یک بلوک را انتخاب کنید تا تنظیمات آن زیر تنظیمات صفحه نمایش داده شود.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          _inspector(context, selected),
      ],
    );
  }

  String _mediaSummary() {
    final media = normalizedReportTemplateMedia(
      widget.design,
      preferRoll: widget.design['layout'] == 'invoice_receipt',
    );
    if (media['type'] == 'roll') {
      return 'رول ${reportTemplatePaperSizeFromMedia(media)} با ارتفاع خودکار';
    }
    final orientation = media['orientation'] == 'landscape' ? 'افقی' : 'عمودی';
    final preset = (media['preset'] ?? 'A4').toString();
    return '${preset == 'custom' ? reportTemplatePaperSizeFromMedia(media) : preset}، $orientation';
  }

  Widget _buildAppearance(BuildContext context) {
    final theme =
        (widget.design['theme'] as Map?)?.cast<String, dynamic>() ?? const {};
    final branding =
        (widget.design['branding'] as Map?)?.cast<String, dynamic>() ??
        const {};
    const colors = [
      '#1e3a5f',
      '#2563eb',
      '#0f766e',
      '#7c3aed',
      '#b45309',
      '#be123c',
    ];
    final logoSource = (branding['logo_source'] ?? 'business').toString();
    final direction = theme['direction'] == 'ltr' ? 'ltr' : 'rtl';
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('ظاهر، برندینگ و جهت نوشتار'),
      children: [
        const Align(
          alignment: Alignment.centerRight,
          child: Text('جهت کلی فاکتور'),
        ),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'rtl',
              icon: Icon(Icons.format_textdirection_r_to_l),
              label: Text('راست‌به‌چپ'),
            ),
            ButtonSegment(
              value: 'ltr',
              icon: Icon(Icons.format_textdirection_l_to_r),
              label: Text('چپ‌به‌راست'),
            ),
          ],
          selected: {direction},
          onSelectionChanged: (values) => _patchRoot((design) {
            final next =
                (design['theme'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            design['theme'] = {...next, 'direction': values.first};
          }),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: colors.map((hex) {
            final color = Color(
              int.parse(hex.substring(1), radix: 16) + 0xFF000000,
            );
            final selected =
                theme['primary_color']?.toString().toLowerCase() == hex;
            return InkWell(
              onTap: () => _patchRoot((design) {
                final next =
                    (design['theme'] as Map?)?.cast<String, dynamic>() ??
                    <String, dynamic>{};
                design['theme'] = {
                  ...next,
                  'primary_color': hex,
                  'accent_color': hex,
                };
              }),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            );
          }).toList(),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('نمایش لوگو'),
          value: branding['show_logo'] != false,
          onChanged: (value) => _patchRoot((design) {
            final next =
                (design['branding'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            design['branding'] = {...next, 'show_logo': value};
          }),
        ),
        if (branding['show_logo'] != false) ...[
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'business', label: Text('کسب‌وکار')),
              ButtonSegment(value: 'custom', label: Text('سفارشی')),
              ButtonSegment(value: 'none', label: Text('بدون لوگو')),
            ],
            selected: {logoSource},
            onSelectionChanged: (values) => _patchRoot((design) {
              final next =
                  (design['branding'] as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{};
              design['branding'] = {...next, 'logo_source': values.first};
            }),
          ),
          if (logoSource == 'custom')
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _pickLogo,
                icon: const Icon(Icons.upload_file),
                label: Text(
                  (branding['custom_logo_data_uri'] ?? '').toString().isEmpty
                      ? 'بارگذاری لوگو'
                      : 'تغییر لوگو',
                ),
              ),
            ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('نمایش نام کسب‌وکار'),
          value: branding['show_business_name'] != false,
          onChanged: (value) => _patchRoot((design) {
            final next =
                (design['branding'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            design['branding'] = {...next, 'show_business_name': value};
          }),
        ),
        Text(
          'اندازه فونت: ${((theme['font_size_base'] as num?) ?? 11).round()}',
        ),
        Slider(
          min: 8,
          max: 16,
          divisions: 8,
          value: ((theme['font_size_base'] as num?)?.toDouble() ?? 11).clamp(
            8.0,
            16.0,
          ),
          onChanged: (value) => _patchRoot((design) {
            final next =
                (design['theme'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            design['theme'] = {...next, 'font_size_base': value.round()};
          }),
        ),
      ],
    );
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.first.bytes == null) {
      return;
    }
    final file = result.files.first;
    final lower = file.name.toLowerCase();
    final mime = lower.endsWith('.jpg') || lower.endsWith('.jpeg')
        ? 'image/jpeg'
        : lower.endsWith('.webp')
        ? 'image/webp'
        : lower.endsWith('.gif')
        ? 'image/gif'
        : 'image/png';
    final dataUri = 'data:$mime;base64,${base64Encode(file.bytes!)}';
    _patchRoot((design) {
      final next =
          (design['branding'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      design['branding'] = {
        ...next,
        'show_logo': true,
        'logo_source': 'custom',
        'custom_logo_data_uri': dataUri,
      };
    });
  }

  Widget _paletteItem(BuildContext context, Map<String, dynamic> definition) {
    final type = definition['type'].toString();
    final enabled = _canAdd(definition);
    final allowed = List<String>.from(
      (definition['allowed_regions'] as List?) ?? const ['body'],
    );
    final defaultRegion = allowed.contains('body') ? 'body' : allowed.first;
    final chip = ActionChip(
      avatar: Icon(_iconForType(type), size: 17),
      label: Text((definition['label_fa'] ?? type).toString()),
      onPressed: enabled
          ? () => _addBlock(
              type,
              defaultRegion,
              _regionBlocks(widget.design, defaultRegion).length,
            )
          : null,
    );
    if (!enabled) return Opacity(opacity: 0.45, child: chip);
    return Draggable<_BlockDragData>(
      data: _BlockDragData.palette(type),
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(20),
        child: chip,
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: chip),
      child: chip,
    );
  }

  Widget _region(BuildContext context, String region, String title) {
    final blocks = _regionBlocks(widget.design, region);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            _dropZone(region, 0, expanded: blocks.isEmpty),
            for (var index = 0; index < blocks.length; index++) ...[
              _blockTile(context, region, index, blocks[index]),
              _dropZone(region, index + 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dropZone(String region, int index, {bool expanded = false}) {
    return DragTarget<_BlockDragData>(
      onWillAcceptWithDetails: (details) {
        final type =
            details.data.blockType ??
            _findBlock(details.data.blockId ?? '')?.block['type']?.toString();
        final allowed = List<String>.from(
          (_definition(type ?? '')?['allowed_regions'] as List?) ?? const [],
        );
        return allowed.contains(region);
      },
      onAcceptWithDetails: (details) =>
          _handleDrop(details.data, region, index),
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: expanded ? 48 : (active ? 28 : 12),
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: expanded || active
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(
                      alpha: active ? 0.8 : 0.25,
                    ),
                  )
                : null,
          ),
          alignment: Alignment.center,
          child: expanded
              ? Text(active ? 'اینجا رها کنید' : 'قطعه‌ای به این بخش بکشید')
              : null,
        );
      },
    );
  }

  Widget _blockTile(
    BuildContext context,
    String region,
    int index,
    Map<String, dynamic> block,
  ) {
    final id = block['id'].toString();
    final type = block['type'].toString();
    final selected = id == _selectedBlockId;
    return Card(
      color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        dense: true,
        onTap: () => _selectBlock(id),
        leading: Draggable<_BlockDragData>(
          data: _BlockDragData.existing(id),
          feedback: Material(
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(_labelForType(type)),
            ),
          ),
          child: const MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: Icon(Icons.drag_handle),
          ),
        ),
        title: Text(_labelForType(type)),
        subtitle: type == 'party_info'
            ? Text(((block['props'] as Map?)?['title'] ?? '').toString())
            : null,
        trailing: Wrap(
          spacing: 0,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'بالا',
              onPressed: index > 0
                  ? () => _moveBlock(id, region, index - 1)
                  : null,
              icon: const Icon(Icons.keyboard_arrow_up, size: 19),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'پایین',
              onPressed: index + 1 < _regionBlocks(widget.design, region).length
                  ? () => _moveBlock(id, region, index + 2)
                  : null,
              icon: const Icon(Icons.keyboard_arrow_down, size: 19),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'کپی',
              onPressed: _canAdd(_definition(type) ?? const <String, dynamic>{})
                  ? () => _duplicateBlock(id)
                  : null,
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'حذف',
              onPressed: () => _removeBlock(id),
              icon: const Icon(Icons.delete_outline, size: 19),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inspector(BuildContext context, Map<String, dynamic> block) {
    final id = block['id'].toString();
    final type = block['type'].toString();
    final props = (block['props'] as Map?)?.cast<String, dynamic>() ?? const {};
    final style = (block['style'] as Map?)?.cast<String, dynamic>() ?? const {};
    final theme =
        (widget.design['theme'] as Map?)?.cast<String, dynamic>() ?? const {};
    final defaultAlignment = theme['direction'] == 'ltr' ? 'left' : 'right';
    final textAlignment =
        (style['text_align'] ??
                (type == 'custom_text' ? props['align'] : null) ??
                defaultAlignment)
            .toString();
    final found = _findBlock(id);
    final rowId = found == null
        ? (style['row_id'] ?? '').toString()
        : _blockRowId(block, found.region);
    final gridSpan = _blockSpan(block);
    final rowBlocks = found == null
        ? <Map<String, dynamic>>[block]
        : _regionBlocks(widget.design, found.region)
              .where(
                (candidate) => _blockRowId(candidate, found.region) == rowId,
              )
              .toList();
    final otherSpans = rowBlocks
        .where((candidate) => candidate['id']?.toString() != id)
        .fold<int>(0, (sum, candidate) => sum + _blockSpan(candidate));
    final maxGridSpan = (60 - otherSpans).clamp(1, 60).toInt();
    final rowHeightMode = (style['row_height_mode'] ?? 'auto').toString();
    final rowHeightMm = ((style['row_height_mm'] as num?)?.toDouble() ?? 20)
        .clamp(4, 500)
        .toDouble();
    final layoutType = (style['layout_type'] ?? 'grid').toString();
    final pageGrid = isReportTemplateV4(widget.design);
    final freeformGrid =
        ((style[pageGrid ? 'page_grid_mm' : 'freeform_grid_mm'] as num?)
                    ?.toInt() ??
                1)
            .clamp(1, 5);
    final media = normalizedReportTemplateMedia(widget.design);
    final mediaSize = reportTemplateMediaSizeMm(media);
    final mediaMargins =
        (media['margins_mm'] as Map?)?.cast<String, dynamic>() ?? const {};
    final defaultCanvasHeight =
        mediaSize.height -
        ((mediaMargins['top'] as num?)?.toDouble() ?? 0) -
        ((mediaMargins['bottom'] as num?)?.toDouble() ?? 0);
    final defaultCanvasWidth =
        mediaSize.width -
        ((mediaMargins['left'] as num?)?.toDouble() ?? 0) -
        ((mediaMargins['right'] as num?)?.toDouble() ?? 0);
    final freeformHeight =
        ((style[pageGrid ? 'page_height_mm' : 'freeform_height_mm'] as num?)
                    ?.toDouble() ??
                (pageGrid ? defaultCanvasHeight : 40))
            .clamp(10, 5000)
            .toDouble();
    final freeformRect = _freeformRect(block);
    final anchorConstraints = _anchorConstraints(block);
    final links = _anchorLinks(block);
    final pins =
        (anchorConstraints['pins'] as Map?)?.cast<String, dynamic>() ??
        const {};
    final rawBottomMode = (anchorConstraints['bottom_mode'] ?? 'last_page')
        .toString();
    final bottomMode = const {'last_page', 'every_page'}.contains(rawBottomMode)
        ? rawBottomMode
        : 'last_page';
    const alignableTypes = {
      'brand_header',
      'party_info',
      'invoice_lines',
      'invoice_totals',
      'payments',
      'note',
      'signatures',
      'footer_meta',
      'custom_text',
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'تنظیمات ${_labelForType(type)}',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('نمایش این بخش'),
              value: block['visible'] != false,
              onChanged: (value) =>
                  _patchBlock(id, (next) => next['visible'] = value),
            ),
            if (alignableTypes.contains(type)) ...[
              const Text('تراز متن این بلوک'),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'right',
                    icon: Icon(Icons.format_align_right),
                    label: Text('راست'),
                  ),
                  ButtonSegment(
                    value: 'center',
                    icon: Icon(Icons.format_align_center),
                    label: Text('وسط'),
                  ),
                  ButtonSegment(
                    value: 'left',
                    icon: Icon(Icons.format_align_left),
                    label: Text('چپ'),
                  ),
                ],
                selected: {
                  const {'right', 'center', 'left'}.contains(textAlignment)
                      ? textAlignment
                      : defaultAlignment,
                },
                onSelectionChanged: (values) =>
                    _patchBlockStyle(id, {'text_align': values.first}),
              ),
              const SizedBox(height: 12),
            ],
            if (pageGrid) ...[
              const Text('جای‌گذاری روی گرید کل صفحه'),
              Text(
                'همه اجزا روی یک بوم مشترک حرکت و تغییر اندازه می‌دهند.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              const Divider(),
              Row(
                children: [
                  const Icon(Icons.hub_outlined, size: 18),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Anchor و اتصال داینامیک',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (_pendingAnchorBlockId == id)
                    TextButton(
                      onPressed: () => setState(() {
                        _pendingAnchorBlockId = null;
                        _pendingAnchorPoint = null;
                      }),
                      child: const Text('لغو'),
                    ),
                ],
              ),
              Text(
                _pendingAnchorBlockId == id
                    ? 'حالا نقطه هم‌محور روی بلوک مقصد را انتخاب کنید.'
                    : 'یکی از نقطه‌های سبز بلوک را بزنید، سپس نقطهٔ مقصد را انتخاب کنید.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (links.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final link in links)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.link, size: 17),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${_anchorPointLabel((link['source_anchor'] ?? '').toString())} ← ${_labelForBlockId((((link['target'] as Map?)?['id']) ?? '').toString())} (${_anchorPointLabel((((link['target'] as Map?)?['anchor']) ?? '').toString())})',
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'قطع اتصال',
                                onPressed: () => _removeAnchorAxis(
                                  id,
                                  (link['axis'] ?? '').toString(),
                                ),
                                icon: const Icon(Icons.link_off, size: 18),
                              ),
                            ],
                          ),
                          Text(
                            'فاصله در این اندازه کاغذ: ${_activeAnchorOffset(link).toStringAsFixed(1)} mm',
                          ),
                          if (link['axis'] == 'vertical' &&
                              link['source_anchor'] == 'top' &&
                              (link['target'] as Map?)?['anchor'] == 'bottom')
                            Text(
                              'در چاپ بعد از ارتفاع واقعی محتوای مقصد قرار می‌گیرد.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          Slider(
                            min: -20,
                            max: 40,
                            divisions: 120,
                            value: _activeAnchorOffset(link).clamp(-20, 40),
                            onChanged: (value) =>
                                _setAnchorGap(id, link, value),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              const Text('نقاط ثابت نسبت به صفحه'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final edge in const [
                    'top',
                    'right',
                    'bottom',
                    'left',
                    'center_x',
                    'center_y',
                  ])
                    FilterChip(
                      label: Text(_anchorPointLabel(edge)),
                      selected: pins[edge] == true,
                      onSelected: (selected) => _togglePagePin(
                        id,
                        edge,
                        selected,
                        defaultCanvasWidth,
                        defaultCanvasHeight,
                      ),
                    ),
                ],
              ),
              if (pins['bottom'] == true) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: bottomMode,
                  decoration: const InputDecoration(
                    labelText: 'رفتار اتصال پایین در چاپ',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'last_page',
                      child: Text('پایین صفحه آخر'),
                    ),
                    DropdownMenuItem(
                      value: 'every_page',
                      child: Text('پایین همه صفحات'),
                    ),
                  ],
                  onChanged: (value) => value == null
                      ? null
                      : _setAnchorConstraintValue(id, 'bottom_mode', value),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('بلوک هنگام شکست صفحه یکپارچه بماند'),
                subtitle: const Text('برای پرداخت، جمع‌بندی و امضا مناسب است.'),
                value:
                    anchorConstraints['keep_together'] == true ||
                    (anchorConstraints['keep_together'] == null &&
                        const {
                          'invoice_totals',
                          'payments',
                          'signatures',
                        }.contains(type)),
                onChanged: (value) =>
                    _setAnchorConstraintValue(id, 'keep_together', value),
              ),
              const Divider(),
            ],
            if (layoutType == 'freeform' || pageGrid) ...[
              Text(pageGrid ? 'شبکه کل صفحه و Snap' : 'شبکه و Snap'),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('۱ mm')),
                  ButtonSegment(value: 3, label: Text('۳ mm')),
                  ButtonSegment(value: 5, label: Text('۵ mm')),
                ],
                selected: {
                  const {1, 3, 5}.contains(freeformGrid) ? freeformGrid : 1,
                },
                onSelectionChanged: (values) => pageGrid
                    ? _patchPageGridSettings({'page_grid_mm': values.first})
                    : _patchRowStyle(rowId, {
                        'freeform_grid_mm': values.first,
                        'layout_type': 'freeform',
                      }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Snap هوشمند'),
                subtitle: const Text('گرید، حاشیه، لبه و مرکز عناصر'),
                value: style[pageGrid ? 'page_snap' : 'freeform_snap'] != false,
                onChanged: (value) => pageGrid
                    ? _patchPageGridSettings({'page_snap': value})
                    : _patchRowStyle(rowId, {
                        'freeform_snap': value,
                        'layout_type': 'freeform',
                      }),
              ),
              if (!pageGrid || media['type'] == 'roll') ...[
                Text(
                  '${pageGrid ? 'طول بوم رول' : 'ارتفاع محدوده'}: ${freeformHeight.toStringAsFixed(0)} mm',
                ),
                Slider(
                  min: pageGrid ? 120 : 10,
                  max: pageGrid ? 1500 : 300,
                  divisions: pageGrid ? 138 : 290,
                  value: freeformHeight.clamp(
                    pageGrid ? 120 : 10,
                    pageGrid ? 1500 : 300,
                  ),
                  onChanged: (value) => pageGrid
                      ? _patchPageGridSettings({
                          'page_height_mm': value.round(),
                        })
                      : _patchRowStyle(rowId, {
                          'freeform_height_mm': value.round(),
                          'layout_type': 'freeform',
                        }),
                ),
              ],
              Text(
                'X ${freeformRect.x.toStringAsFixed(1)} · Y ${freeformRect.y.toStringAsFixed(1)} · W ${freeformRect.width.toStringAsFixed(1)} · H ${freeformRect.height.toStringAsFixed(1)} mm',
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final field in <(String, String, double)>[
                    ('x_mm', 'X', freeformRect.x),
                    ('y_mm', 'Y', freeformRect.y),
                    ('width_mm', 'W', freeformRect.width),
                    ('height_mm', 'H', freeformRect.height),
                  ]) ...[
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('$id-${field.$1}-${field.$3}'),
                        initialValue: field.$3.toStringAsFixed(1),
                        decoration: InputDecoration(
                          labelText: field.$2,
                          suffixText: 'mm',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onFieldSubmitted: (raw) {
                          final value = double.tryParse(raw);
                          if (value != null && value >= 0) {
                            _patchFreeformGeometryField(
                              block,
                              field.$1,
                              value,
                              freeformHeight,
                            );
                          }
                        },
                      ),
                    ),
                    if (field.$1 != 'height_mm') const SizedBox(width: 5),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'عنصر را در کل صفحه بکشید؛ برای تغییر اندازه از دستگیرهٔ گوشه استفاده کنید.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...[
              const Text('عرض بلوک'),
              Text(
                'شبکهٔ دقیق ۶۰ ستونه',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    const <(String, int)>[
                      ('تمام عرض', 60),
                      ('نصف', 30),
                      ('یک‌سوم', 20),
                      ('یک‌چهارم', 15),
                      ('یک‌پنجم', 12),
                      ('یک‌ششم', 10),
                    ].map((preset) {
                      return ChoiceChip(
                        label: Text(preset.$1),
                        selected: gridSpan == preset.$2,
                        onSelected: preset.$2 > maxGridSpan
                            ? null
                            : (_) => _patchBlockStyle(id, {
                                'width_mode': 'full',
                                'grid_span': preset.$2,
                              }),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                '$gridSpan از ۶۰ ستون (${(gridSpan * 100 / 60).toStringAsFixed(1)}٪)',
              ),
              Slider(
                min: 1,
                max: maxGridSpan.toDouble(),
                divisions: maxGridSpan > 1 ? maxGridSpan - 1 : null,
                value: gridSpan.clamp(1, maxGridSpan).toDouble(),
                onChanged: (value) => _patchBlockStyle(id, {
                  'width_mode': 'full',
                  'grid_span': value.round(),
                }),
              ),
              Text(
                'دستگیرهٔ عمودی کنار بلوک را هم می‌توانید با ماوس بکشید.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              const Text('ارتفاع ردیف'),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'auto', label: Text('خودکار')),
                  ButtonSegment(value: 'minimum', label: Text('حداقل')),
                  ButtonSegment(value: 'fixed', label: Text('ثابت')),
                ],
                selected: {
                  const {'auto', 'minimum', 'fixed'}.contains(rowHeightMode)
                      ? rowHeightMode
                      : 'auto',
                },
                onSelectionChanged: rowId.isEmpty
                    ? null
                    : (values) => _patchRowStyle(rowId, {
                        'row_height_mode': values.first,
                        if (values.first != 'auto')
                          'row_height_mm': rowHeightMm,
                      }),
              ),
              if (rowHeightMode != 'auto') ...[
                const SizedBox(height: 8),
                Text('ارتفاع: ${rowHeightMm.toStringAsFixed(0)} میلی‌متر'),
                Slider(
                  min: 4,
                  max: 200,
                  divisions: 196,
                  value: rowHeightMm.clamp(4, 200),
                  onChanged: rowId.isEmpty
                      ? null
                      : (value) => _patchRowStyle(rowId, {
                          'row_height_mode': rowHeightMode,
                          'row_height_mm': value.round(),
                        }),
                ),
              ],
              Text(
                'دستگیرهٔ افقی پایین ردیف را بکشید؛ دوبار کلیک، ارتفاع را خودکار می‌کند.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            if (type == 'custom_text')
              TextFormField(
                key: ValueKey('$id-custom-text'),
                initialValue: (props['text'] ?? '').toString(),
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'متن',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => _patchProps(id, {'text': value}),
              ),
            if (type == 'party_info')
              TextFormField(
                key: ValueKey('$id-party-title'),
                initialValue: (props['title'] ?? '').toString(),
                decoration: const InputDecoration(
                  labelText: 'عنوان بخش',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => _patchProps(id, {'title': value}),
              ),
            if (type == 'signatures') ...[
              _propertySwitch(id, props, 'show_seller', 'امضای فروشنده'),
              _propertySwitch(id, props, 'show_buyer', 'امضای خریدار'),
            ],
            if (type == 'footer_meta') ...[
              _propertySwitch(id, props, 'show_print_time', 'زمان چاپ'),
              _propertySwitch(id, props, 'show_preparer', 'نام صادرکننده'),
            ],
            if (type == 'divider')
              DropdownButtonFormField<String>(
                initialValue: (props['style'] ?? 'solid').toString(),
                decoration: const InputDecoration(labelText: 'نوع خط'),
                items: const [
                  DropdownMenuItem(value: 'solid', child: Text('پیوسته')),
                  DropdownMenuItem(value: 'dashed', child: Text('خط‌چین')),
                ],
                onChanged: (value) => _patchProps(id, {'style': value}),
              ),
            if (type == 'spacer')
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ارتفاع فاصله: ${(props['height'] as num?)?.round() ?? 12}px',
                  ),
                  Slider(
                    min: 4,
                    max: 80,
                    divisions: 19,
                    value: ((props['height'] as num?)?.toDouble() ?? 12).clamp(
                      4.0,
                      80.0,
                    ),
                    onChanged: (value) =>
                        _patchProps(id, {'height': value.round()}),
                  ),
                ],
              ),
            if (type == 'invoice_lines') _columnsEditor(id, props),
            if (type == 'invoice_totals') _totalsEditor(id, props),
          ],
        ),
      ),
    );
  }

  Widget _propertySwitch(
    String id,
    Map<String, dynamic> props,
    String key,
    String label,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: props[key] != false,
      onChanged: (value) => _patchProps(id, {key: value}),
    );
  }

  void _patchProps(String id, Map<String, dynamic> changes) {
    _patchBlock(id, (block) {
      final props =
          (block['props'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      block['props'] = {...props, ...changes};
    });
  }

  void _patchBlockStyle(String id, Map<String, dynamic> changes) {
    _patchBlock(id, (block) {
      final style =
          (block['style'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      block['style'] = {...style, ...changes};
    });
  }

  Widget _columnsEditor(String id, Map<String, dynamic> props) {
    final columns = List<Map<String, dynamic>>.from(
      (props['columns'] as List?) ?? const [],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const Text('ستون‌های جدول'),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: columns.length,
          onReorder: (oldIndex, newIndex) {
            if (newIndex > oldIndex) newIndex--;
            final next = List<Map<String, dynamic>>.from(columns);
            final item = next.removeAt(oldIndex);
            next.insert(newIndex, item);
            _patchProps(id, {'columns': next});
          },
          itemBuilder: (context, index) {
            final column = columns[index];
            return Card(
              key: ValueKey('$id-column-${column['key']}'),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    secondary: const Icon(Icons.drag_handle),
                    title: Text((column['title'] ?? column['key']).toString()),
                    subtitle: Text((column['key'] ?? '').toString()),
                    value: column['visible'] != false,
                    onChanged: (value) => _updateColumn(id, columns, index, {
                      ...column,
                      'visible': value,
                    }),
                  ),
                  if (column['visible'] != false)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: ValueKey(
                                '$id-column-title-${column['key']}',
                              ),
                              initialValue: (column['title'] ?? '').toString(),
                              decoration: const InputDecoration(
                                labelText: 'عنوان',
                                isDense: true,
                              ),
                              onChanged: (value) => _updateColumn(
                                id,
                                columns,
                                index,
                                {...column, 'title': value},
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 100,
                            child: DropdownButtonFormField<String>(
                              initialValue:
                                  const [
                                    'auto',
                                    '8%',
                                    '10%',
                                    '12%',
                                    '16%',
                                    '20%',
                                    '24%',
                                    '30%',
                                    '40%',
                                    '50%',
                                  ].contains(column['width'])
                                  ? column['width'].toString()
                                  : 'auto',
                              decoration: const InputDecoration(
                                labelText: 'عرض',
                                isDense: true,
                              ),
                              items:
                                  const [
                                        'auto',
                                        '8%',
                                        '10%',
                                        '12%',
                                        '16%',
                                        '20%',
                                        '24%',
                                        '30%',
                                        '40%',
                                        '50%',
                                      ]
                                      .map(
                                        (value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(value),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (value) => _updateColumn(
                                id,
                                columns,
                                index,
                                {...column, 'width': value},
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  void _updateColumn(
    String id,
    List<Map<String, dynamic>> columns,
    int index,
    Map<String, dynamic> column,
  ) {
    final next = List<Map<String, dynamic>>.from(columns);
    next[index] = column;
    _patchProps(id, {'columns': next});
  }

  Widget _totalsEditor(String id, Map<String, dynamic> props) {
    final rows = List<Map<String, dynamic>>.from(
      (props['rows'] as List?) ?? const [],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const Text('ردیف‌های جمع‌بندی'),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows.length,
          onReorder: (oldIndex, newIndex) {
            if (newIndex > oldIndex) newIndex--;
            final next = List<Map<String, dynamic>>.from(rows);
            final item = next.removeAt(oldIndex);
            next.insert(newIndex, item);
            _patchProps(id, {'rows': next});
          },
          itemBuilder: (context, index) {
            final row = rows[index];
            return SwitchListTile(
              key: ValueKey('$id-total-${row['key']}'),
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.drag_handle),
              title: Text((row['title'] ?? row['key']).toString()),
              value: row['visible'] != false,
              onChanged: (value) {
                final next = List<Map<String, dynamic>>.from(rows);
                next[index] = {...row, 'visible': value};
                _patchProps(id, {'rows': next});
              },
            );
          },
        ),
      ],
    );
  }
}

class _CanvasAnchorSegment {
  final Offset sourceMm;
  final Offset targetMm;

  const _CanvasAnchorSegment(this.sourceMm, this.targetMm);
}

class _AnchorLinksPainter extends CustomPainter {
  final List<_CanvasAnchorSegment> segments;
  final double pixelsPerMm;
  final Color color;

  const _AnchorLinksPainter({
    required this.segments,
    required this.pixelsPerMm,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final segment in segments) {
      final source = segment.sourceMm * pixelsPerMm;
      final target = segment.targetMm * pixelsPerMm;
      final middle = Offset(source.dx, (source.dy + target.dy) / 2);
      final second = Offset(target.dx, middle.dy);
      final path = Path()
        ..moveTo(source.dx, source.dy)
        ..lineTo(middle.dx, middle.dy)
        ..lineTo(second.dx, second.dy)
        ..lineTo(target.dx, target.dy);
      canvas.drawPath(path, paint);
      canvas.drawCircle(source, 3, paint);
      canvas.drawCircle(target, 3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnchorLinksPainter oldDelegate) =>
      oldDelegate.pixelsPerMm != pixelsPerMm ||
      oldDelegate.color != color ||
      oldDelegate.segments.length != segments.length ||
      !List.generate(
        segments.length,
        (index) =>
            oldDelegate.segments[index].sourceMm == segments[index].sourceMm &&
            oldDelegate.segments[index].targetMm == segments[index].targetMm,
      ).every((same) => same);
}

class _CanvasTotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _CanvasTotalRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 10,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _CanvasSignature extends StatelessWidget {
  final String label;

  const _CanvasSignature({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 54,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _MillimeterGridPainter extends CustomPainter {
  final double pixelsPerMm;
  final double gridMm;
  final Color color;

  const _MillimeterGridPainter({
    required this.pixelsPerMm,
    required this.gridMm,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final step = pixelsPerMm * gridMm;
    if (step < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MillimeterGridPainter oldDelegate) =>
      oldDelegate.pixelsPerMm != pixelsPerMm ||
      oldDelegate.gridMm != gridMm ||
      oldDelegate.color != color;
}
