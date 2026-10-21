import 'dart:convert';

Map<String, dynamic> _cloneMap(Map<String, dynamic> value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList()
    : <Map<String, dynamic>>[];

double _number(dynamic value, double fallback) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

double _printableWidth(Map<String, dynamic> media) {
  final margins = _map(media['margins_mm']);
  final landscape =
      media['type'] != 'roll' && media['orientation'] == 'landscape';
  final width = landscape
      ? _number(media['height_mm'], 297)
      : _number(media['width_mm'], 210);
  return (width - _number(margins['left'], 0) - _number(margins['right'], 0))
      .clamp(10, 1000);
}

double _printableHeight(Map<String, dynamic> media) {
  final margins = _map(media['margins_mm']);
  final landscape =
      media['type'] != 'roll' && media['orientation'] == 'landscape';
  final height = landscape
      ? _number(media['width_mm'], 210)
      : _number(media['height_mm'], media['type'] == 'roll' ? 300 : 297);
  return (height - _number(margins['top'], 0) - _number(margins['bottom'], 0))
      .clamp(20, 5000);
}

double _defaultHeight(String component) => switch (component) {
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

bool isReportTemplateV4(Map<String, dynamic> design) =>
    (design['schema_version'] as num?)?.toInt() == 4;

String reportTemplateV4ProfileKey(Map<String, dynamic> design) {
  final media = _map(design['media']);
  if (media['type'] == 'roll') {
    final width = (media['width_mm'] as num?)?.toDouble() ?? 80;
    for (final preset in const [58, 60, 80, 100]) {
      if ((width - preset).abs() < 0.01) return 'roll_$preset';
    }
    return 'custom_roll';
  }
  final preset = (media['preset'] ?? 'A4').toString();
  final orientation = media['orientation'] == 'landscape'
      ? 'landscape'
      : 'portrait';
  if (const {'A3', 'A4', 'A5', 'A6', 'Letter', 'Legal'}.contains(preset)) {
    return '${preset.toLowerCase()}_$orientation';
  }
  return 'custom_sheet_$orientation';
}

void syncReportTemplateV4ActiveMedia(Map<String, dynamic> design) {
  if (!isReportTemplateV4(design)) return;
  final variants = _map(design['variants']);
  final key = reportTemplateV4ProfileKey(design);
  final variant = _map(variants[key]);
  if (variant.isEmpty) return;
  variant['media'] = _cloneMap(_map(design['media']));
  variants[key] = variant;
  design['variants'] = variants;
  design['active_variant'] = key;
}

Map<String, dynamic> _activeOverrides(Map<String, dynamic> design) {
  final variants = _map(design['variants']);
  final variant = _map(variants[reportTemplateV4ProfileKey(design)]);
  return _map(variant['node_overrides']);
}

Map<String, dynamic> _mergedNode(
  Map<String, dynamic> node,
  Map<String, dynamic> overrides,
) {
  final result = _cloneMap(node);
  final override = _map(overrides[(node['id'] ?? '').toString()]);
  for (final key in const ['layout', 'placement', 'style']) {
    if (override[key] is Map) {
      result[key] = <String, dynamic>{
        ..._map(result[key]),
        ..._map(override[key]),
      };
    }
  }
  return result;
}

/// Produces the flat, v3-shaped editing projection. It is never persisted.
Map<String, dynamic> reportTemplateV4StudioProjection(
  Map<String, dynamic> design,
) {
  if (!isReportTemplateV4(design)) return _cloneMap(design);
  final overrides = _activeOverrides(design);
  final regions = <String, dynamic>{
    'header': <Map<String, dynamic>>[],
    'body': <Map<String, dynamic>>[],
    'footer': <Map<String, dynamic>>[],
  };
  final root = _mergedNode(_map(design['root']), overrides);
  final rootLayout = _map(root['layout']);
  final sourcePageGrid = rootLayout['type'] == 'page_grid';
  // Every v4 document is edited as one page-wide millimeter grid. This also
  // upgrades drafts produced by the short-lived row/freeform v4 prototype.
  final media = _map(design['media']);
  final pageWidth = _number(rootLayout['width_mm'], _printableWidth(media));
  var fallbackY = 0.0;
  for (final rawRegion in _maps(root['children'])) {
    final region = _mergedNode(rawRegion, overrides);
    final regionName = (region['region'] ?? '').toString();
    if (!regions.containsKey(regionName)) continue;
    final blocks = regions[regionName] as List<Map<String, dynamic>>;
    for (final rawRow in _maps(region['children'])) {
      final row = _mergedNode(rawRow, overrides);
      final layout = _map(row['layout']);
      final layoutType = (layout['type'] ?? 'grid').toString();
      final rowChildren = _maps(row['children']);
      final fallbackHeight = rowChildren
          .map((child) => _defaultHeight((child['component'] ?? '').toString()))
          .fold<double>(20, (height, next) => next > height ? next : height);
      var fallbackX = 0.0;
      for (final rawComponent in rowChildren) {
        final component = _mergedNode(rawComponent, overrides);
        if (component['kind'] != 'component') continue;
        final placement = _map(component['placement']);
        final span = _number(placement['column_span'], 60).clamp(1, 60);
        final fallbackWidth = pageWidth * span / 60;
        final style = <String, dynamic>{
          ..._map(component['style']),
          'row_id': row['id'],
          'layout_type': 'page_grid',
          'grid_span': placement['column_span'] ?? 60,
          if (layout['height_mode'] != null)
            'row_height_mode': layout['height_mode'],
          if (layout['height_mm'] != null) 'row_height_mm': layout['height_mm'],
          if (layoutType == 'freeform') ...{
            'freeform_grid_mm': layout['grid_mm'] ?? 1,
            'freeform_snap': layout['snap'] != false,
            'freeform_height_mm': layout['height_mm'] ?? 40,
            'x_mm': placement['x_mm'] ?? 0,
            'y_mm': placement['y_mm'] ?? 0,
            'width_mm': placement['width_mm'] ?? 30,
            'height_mm': placement['height_mm'] ?? 15,
          },
          'page_grid_mm': rootLayout['grid_mm'] ?? 1,
          'page_snap': rootLayout['snap'] != false,
          'page_height_mm': rootLayout['height_mm'] ?? _printableHeight(media),
          'x_mm': sourcePageGrid
              ? placement['x_mm'] ?? fallbackX
              : layoutType == 'freeform'
              ? placement['x_mm'] ?? fallbackX
              : fallbackX,
          'y_mm': sourcePageGrid
              ? placement['y_mm'] ?? fallbackY
              : fallbackY +
                    (layoutType == 'freeform'
                        ? _number(placement['y_mm'], 0)
                        : 0),
          'width_mm': sourcePageGrid || layoutType == 'freeform'
              ? placement['width_mm'] ?? fallbackWidth
              : fallbackWidth,
          'height_mm': sourcePageGrid || layoutType == 'freeform'
              ? placement['height_mm'] ?? fallbackHeight
              : fallbackHeight,
        };
        blocks.add(<String, dynamic>{
          'id': component['id'],
          'type': component['component'],
          'visible': component['visible'] != false,
          'props': _cloneMap(_map(component['props'])),
          'style': style,
        });
        fallbackX += fallbackWidth;
      }
      fallbackY += fallbackHeight + 3;
    }
  }
  return <String, dynamic>{
    'schema_version': 3,
    'family_id': design['family_id'],
    'layout': design['layout'],
    'theme': _cloneMap(_map(design['theme'])),
    'branding': _cloneMap(_map(design['branding'])),
    'custom_css': (design['custom_css'] ?? '').toString(),
    'media': _cloneMap(_map(design['media'])),
    'regions': regions,
  };
}

Map<String, dynamic> _layoutFromBlocks(List<Map<String, dynamic>> blocks) {
  final style = _map(blocks.first['style']);
  final type = (style['layout_type'] ?? 'grid').toString();
  if (type == 'freeform') {
    return <String, dynamic>{
      'type': 'freeform',
      'height_mm':
          ((style['freeform_height_mm'] ?? style['row_height_mm']) as num?)
              ?.toDouble() ??
          40,
      'grid_mm': (style['freeform_grid_mm'] as num?)?.toInt() ?? 1,
      'snap': style['freeform_snap'] != false,
    };
  }
  // page_grid is the document-level layout. Semantic rows remain ordinary
  // containers so the component/region catalog stays intact.
  return <String, dynamic>{
    'type': 'grid',
    'columns': 60,
    'gap_mm': 0,
    if (style['row_height_mode'] != null)
      'height_mode': style['row_height_mode'],
    if (style['row_height_mm'] != null) 'height_mm': style['row_height_mm'],
  };
}

Map<String, dynamic> _componentFromBlock(Map<String, dynamic> block) {
  final style = _cloneMap(_map(block['style']));
  final layoutType = (style['layout_type'] ?? 'grid').toString();
  final placement = layoutType == 'freeform' || layoutType == 'page_grid'
      ? <String, dynamic>{
          'x_mm': (style['x_mm'] as num?)?.toDouble() ?? 0,
          'y_mm': (style['y_mm'] as num?)?.toDouble() ?? 0,
          'width_mm': (style['width_mm'] as num?)?.toDouble() ?? 30,
          'height_mm': (style['height_mm'] as num?)?.toDouble() ?? 15,
        }
      : <String, dynamic>{
          'column_span': (style['grid_span'] as num?)?.toInt() ?? 60,
        };
  for (final key in const [
    'row_id',
    'layout_type',
    'grid_span',
    'row_height_mode',
    'row_height_mm',
    'freeform_grid_mm',
    'freeform_snap',
    'freeform_height_mm',
    'page_grid_mm',
    'page_snap',
    'page_height_mm',
    'x_mm',
    'y_mm',
    'width_mm',
    'height_mm',
  ]) {
    style.remove(key);
  }
  return <String, dynamic>{
    'id': block['id'],
    'kind': 'component',
    'component': block['type'],
    'visible': block['visible'] != false,
    'props': _cloneMap(_map(block['props'])),
    'style': style,
    'placement': placement,
  };
}

List<Map<String, dynamic>> _rowsFromBlocks(
  List<Map<String, dynamic>> blocks,
  String region,
) {
  final rows = <Map<String, dynamic>>[];
  var index = 0;
  while (index < blocks.length) {
    final block = blocks[index];
    final style = _map(block['style']);
    final rowId = (style['row_id'] ?? 'row-${block['id']}').toString();
    final grouped = <Map<String, dynamic>>[block];
    index++;
    while (index < blocks.length &&
        (_map(blocks[index]['style'])['row_id'] ?? '').toString() == rowId) {
      grouped.add(blocks[index]);
      index++;
    }
    rows.add(<String, dynamic>{
      'id': rowId,
      'kind': 'container',
      'layout': _layoutFromBlocks(grouped),
      'children': grouped.map(_componentFromBlock).toList(),
    });
  }
  return rows;
}

Iterable<Map<String, dynamic>> _walk(Map<String, dynamic> node) sync* {
  yield node;
  for (final child in _maps(node['children'])) {
    yield* _walk(child);
  }
}

/// Applies a flat editing projection back to the canonical tree and updates
/// only the active responsive variant. Other paper layouts stay explicit.
Map<String, dynamic> applyStudioProjectionToReportTemplateV4(
  Map<String, dynamic> original,
  Map<String, dynamic> projection,
) {
  if (!isReportTemplateV4(original)) return _cloneMap(projection);
  final design = _cloneMap(original);
  final projectionRegions = _map(projection['regions']);
  final root = _map(design['root']);
  final existingRegions = <String, Map<String, dynamic>>{
    for (final node in _maps(root['children']))
      if (node['region'] != null) node['region'].toString(): node,
  };
  final regionNodes = <Map<String, dynamic>>[];
  for (final region in const ['header', 'body', 'footer']) {
    final existing = existingRegions[region];
    regionNodes.add(<String, dynamic>{
      'id': existing?['id'] ?? 'region-$region',
      'kind': 'container',
      'region': region,
      'layout': _cloneMap(
        _map(existing?['layout']).isEmpty
            ? <String, dynamic>{'type': 'flow', 'gap_mm': 2}
            : _map(existing?['layout']),
      ),
      'children': _rowsFromBlocks(_maps(projectionRegions[region]), region),
    });
  }
  final allBlocks = <Map<String, dynamic>>[
    for (final region in const ['header', 'body', 'footer'])
      ..._maps(projectionRegions[region]),
  ];
  final firstStyle = allBlocks.isEmpty
      ? <String, dynamic>{}
      : _map(allBlocks.first['style']);
  if (firstStyle['layout_type'] == 'page_grid') {
    final media = _map(projection['media']);
    root['layout'] = <String, dynamic>{
      ..._map(root['layout']),
      'type': 'page_grid',
      'grid_mm': (firstStyle['page_grid_mm'] as num?)?.toInt() ?? 1,
      'snap': firstStyle['page_snap'] != false,
      'width_mm': _printableWidth(media),
      'height_mm': _number(
        firstStyle['page_height_mm'],
        _printableHeight(media),
      ),
    };
  }
  root['children'] = regionNodes;
  design['root'] = root;
  for (final key in const [
    'family_id',
    'layout',
    'theme',
    'branding',
    'custom_css',
    'media',
  ]) {
    if (projection.containsKey(key)) design[key] = projection[key];
  }
  final nodes = <String, Map<String, dynamic>>{
    for (final node in _walk(root)) (node['id'] ?? '').toString(): node,
  }..remove('');
  final variants = _map(design['variants']);
  final activeKey = reportTemplateV4ProfileKey(design);
  final rootId = (root['id'] ?? 'invoice-root').toString();
  final activeRootLayout = _map(root['layout']);
  final activeCanvasWidth = _number(
    activeRootLayout['width_mm'],
    _printableWidth(_map(design['media'])),
  );
  final activeCanvasHeight = _number(
    activeRootLayout['height_mm'],
    _printableHeight(_map(design['media'])),
  );
  for (final entry in variants.entries.toList()) {
    final variant = _map(entry.value);
    if (entry.key == activeKey) {
      variant['media'] = _cloneMap(_map(design['media']));
    }
    final oldOverrides = _map(variant['node_overrides']);
    final nextOverrides = <String, dynamic>{};
    final narrow = entry.key.startsWith('roll_') || entry.key == 'custom_roll';
    final variantMedia = _map(variant['media']).isEmpty
        ? _map(design['media'])
        : _map(variant['media']);
    final variantRootLayout = _map(_map(oldOverrides[rootId])['layout']);
    final targetCanvasWidth = _number(
      variantRootLayout['width_mm'],
      _printableWidth(variantMedia),
    );
    final targetCanvasHeight = _number(
      variantRootLayout['height_mm'],
      _printableHeight(variantMedia),
    );
    for (final nodeEntry in nodes.entries) {
      final node = nodeEntry.value;
      final existing = _map(oldOverrides[nodeEntry.key]);
      if (node['kind'] == 'container') {
        nextOverrides[nodeEntry.key] = <String, dynamic>{
          'layout': entry.key == activeKey
              ? _cloneMap(_map(node['layout']))
              : _cloneMap(
                  _map(existing['layout']).isEmpty
                      ? _map(node['layout'])
                      : _map(existing['layout']),
                ),
        };
      } else {
        var placement = entry.key == activeKey
            ? _cloneMap(_map(node['placement']))
            : _cloneMap(
                _map(existing['placement']).isEmpty
                    ? _map(node['placement'])
                    : _map(existing['placement']),
              );
        if (existing.isEmpty &&
            narrow &&
            placement.containsKey('column_span')) {
          placement['column_span'] = 60;
        }
        if (entry.key != activeKey &&
            existing.isEmpty &&
            placement.containsKey('x_mm')) {
          final sourceX = _number(placement['x_mm'], 0);
          final sourceY = _number(placement['y_mm'], 0);
          final sourceWidth = _number(placement['width_mm'], 30);
          final sourceHeight = _number(placement['height_mm'], 20);
          final widthRatio =
              targetCanvasWidth / activeCanvasWidth.clamp(1, 1000);
          final heightRatio =
              targetCanvasHeight / activeCanvasHeight.clamp(1, 5000);
          final width = (narrow ? targetCanvasWidth : sourceWidth * widthRatio)
              .clamp(1, targetCanvasWidth)
              .toDouble();
          final height = (sourceHeight * heightRatio)
              .clamp(1, targetCanvasHeight)
              .toDouble();
          placement = <String, dynamic>{
            ...placement,
            'x_mm': narrow
                ? 0.0
                : (sourceX * widthRatio)
                      .clamp(0, targetCanvasWidth - width)
                      .toDouble(),
            'y_mm': (sourceY * heightRatio)
                .clamp(0, targetCanvasHeight - height)
                .toDouble(),
            'width_mm': width,
            'height_mm': height,
          };
        }
        nextOverrides[nodeEntry.key] = <String, dynamic>{
          'placement': placement,
        };
      }
    }
    variant['node_overrides'] = nextOverrides;
    variants[entry.key] = variant;
  }
  design['variants'] = variants;
  design['active_variant'] = activeKey;
  return design;
}
