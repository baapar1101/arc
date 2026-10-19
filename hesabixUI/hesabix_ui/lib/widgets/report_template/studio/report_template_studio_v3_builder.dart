import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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

class _ReportTemplateStudioV3BuilderState
    extends State<ReportTemplateStudioV3Builder> {
  final List<Map<String, dynamic>> _history = [];
  int _historyIndex = -1;
  int _idSequence = 0;
  String? _selectedBlockId;

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
    return (design['regions'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
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
    final block = <String, dynamic>{
      'id': _newId(type),
      'type': type,
      'visible': true,
      'props': _cloneMap(definition['default_props']),
      'style': <String, dynamic>{},
    };
    blocks.insert(index.clamp(0, blocks.length), block);
    regions[region] = blocks;
    design['regions'] = regions;
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
    final target = List<Map<String, dynamic>>.from(
      (regions[targetRegion] as List?) ?? const [],
    );
    if (sourceRegion == targetRegion && sourceIndex < targetIndex) {
      targetIndex--;
    }
    target.insert(targetIndex.clamp(0, target.length), moving);
    regions[targetRegion] = target;
    design['regions'] = regions;
    _commit(design);
  }

  void _handleDrop(_BlockDragData data, String region, int index) {
    if (data.blockType != null) {
      _addBlock(data.blockType!, region, index);
    } else if (data.blockId != null) {
      _moveBlock(data.blockId!, region, index);
    }
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
    design['regions'] = regions;
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
    blocks.insert(found.index + 1, copy);
    regions[found.region] = blocks;
    design['regions'] = regions;
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
        design['regions'] = regions;
        _commit(design);
        return;
      }
    }
  }

  void _patchRoot(void Function(Map<String, dynamic> design) mutate) {
    final design = _clone(widget.design);
    mutate(design);
    _commit(design);
  }

  String _labelForType(String type) {
    return (_definition(type)?['label_fa'] ?? type).toString();
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
              Expanded(child: widget.previewPane!),
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
                    Tab(icon: Icon(Icons.preview_outlined), text: 'پیش‌نمایش'),
                    Tab(icon: Icon(Icons.tune), text: 'تنظیمات بلوک'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    designerPane,
                    widget.previewPane!,
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
              'طراح بلوکی',
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
          'قطعه را بکشید و در محل دلخواه رها کنید؛ برای موبایل می‌توانید روی قطعه بزنید.',
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
                    'یک بلوک را انتخاب کنید تا تنظیمات آن در این ستون نمایش داده شود.',
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
        onTap: () => setState(() => _selectedBlockId = id),
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
