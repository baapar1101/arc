import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/report_template/studio/report_template_snap_engine.dart';
import 'package:hesabix_ui/widgets/report_template/studio/report_template_studio_v3_builder.dart';
import 'package:hesabix_ui/widgets/report_template/studio/report_template_studio_v4_adapter.dart';

Map<String, dynamic> _design() {
  const rowLayout = <String, dynamic>{
    'type': 'grid',
    'columns': 60,
    'gap_mm': 0,
  };
  const placement = <String, dynamic>{
    'column_span': 30,
    'x_mm': 5,
    'y_mm': 8,
    'width_mm': 60,
    'height_mm': 24,
  };
  final root = <String, dynamic>{
    'id': 'invoice-root',
    'kind': 'container',
    'layout': {
      'type': 'page_grid',
      'grid_mm': 1,
      'snap': true,
      'width_mm': 190,
      'height_mm': 277,
    },
    'children': [
      for (final region in const ['header', 'body', 'footer'])
        <String, dynamic>{
          'id': 'region-$region',
          'kind': 'container',
          'region': region,
          'layout': {'type': 'flow'},
          'children': region == 'body'
              ? [
                  {
                    'id': 'row-text',
                    'kind': 'container',
                    'layout': rowLayout,
                    'children': [
                      {
                        'id': 'text-one',
                        'kind': 'component',
                        'component': 'custom_text',
                        'visible': true,
                        'props': {'text': 'متن تست'},
                        'style': <String, dynamic>{},
                        'placement': placement,
                      },
                      {
                        'id': 'text-two',
                        'kind': 'component',
                        'component': 'custom_text',
                        'visible': true,
                        'props': {'text': 'متن دوم'},
                        'style': <String, dynamic>{},
                        'placement': {...placement, 'y_mm': 50},
                      },
                    ],
                  },
                ]
              : <dynamic>[],
        },
    ],
  };
  Map<String, dynamic> overrides(double x, double width) => <String, dynamic>{
    'invoice-root': {
      'layout': {
        'type': 'page_grid',
        'grid_mm': 1,
        'snap': true,
        'width_mm': width == 60 ? 190 : 76,
        'height_mm': 277,
      },
    },
    'region-header': {
      'layout': {'type': 'flow'},
    },
    'region-body': {
      'layout': {'type': 'flow'},
    },
    'region-footer': {
      'layout': {'type': 'flow'},
    },
    'row-text': {'layout': rowLayout},
    'text-one': {
      'placement': {...placement, 'x_mm': x, 'width_mm': width},
    },
    'text-two': {
      'placement': {...placement, 'x_mm': x, 'y_mm': 50, 'width_mm': width},
    },
  };
  return <String, dynamic>{
    'schema_version': 4,
    'family_id': 'invoice_classic',
    'layout': 'invoice_detail',
    'theme': {'direction': 'rtl'},
    'branding': <String, dynamic>{},
    'media': {
      'type': 'sheet',
      'preset': 'A4',
      'width_mm': 210,
      'height_mm': 297,
      'orientation': 'portrait',
      'margins_mm': {'top': 10, 'right': 10, 'bottom': 10, 'left': 10},
    },
    'root': root,
    'variants': {
      'a4_portrait': {
        'media': <String, dynamic>{},
        'node_overrides': overrides(5, 60),
      },
      'roll_80': {
        'media': <String, dynamic>{},
        'node_overrides': overrides(2, 76),
      },
    },
  };
}

Map<String, dynamic>? _findNode(Map<String, dynamic> node, String id) {
  if (node['id'] == id) return node;
  for (final child in (node['children'] as List?) ?? const []) {
    if (child is Map) {
      final found = _findNode(child.cast<String, dynamic>(), id);
      if (found != null) return found;
    }
  }
  return null;
}

Map<String, dynamic> _designWithExistingAnchor() {
  final design = _design();
  final node = _findNode(
    (design['root'] as Map).cast<String, dynamic>(),
    'text-two',
  )!;
  node['constraints'] = {
    'links': [
      {
        'id': 'vertical-anchor',
        'axis': 'vertical',
        'source_anchor': 'top',
        'target': {'type': 'node', 'id': 'text-one', 'anchor': 'bottom'},
        'offset_mm': 5,
        'variant_offsets': {'a4_portrait': 5, 'roll_80': 2},
      },
    ],
  };
  return design;
}

Map<String, dynamic> _designWithThirdBlock() {
  final design = _designWithExistingAnchor();
  final row = _findNode(
    (design['root'] as Map).cast<String, dynamic>(),
    'row-text',
  )!;
  (row['children'] as List).add({
    'id': 'text-three',
    'kind': 'component',
    'component': 'custom_text',
    'visible': true,
    'props': {'text': 'متن سوم'},
    'style': <String, dynamic>{},
    'placement': {
      'column_span': 30,
      'x_mm': 80,
      'y_mm': 80,
      'width_mm': 60,
      'height_mm': 24,
    },
  });
  for (final variant in (design['variants'] as Map).values) {
    ((variant as Map)['node_overrides'] as Map)['text-three'] = {
      'placement': {
        'column_span': 30,
        'x_mm': 80,
        'y_mm': 80,
        'width_mm': 60,
        'height_mm': 24,
      },
    };
  }
  return design;
}

void main() {
  test('responsive paper variants are projected and edited independently', () {
    final design = _design();
    var projection = reportTemplateV4StudioProjection(design);
    var block = ((projection['regions'] as Map)['body'] as List).first as Map;
    expect((block['style'] as Map)['x_mm'], 5);

    (block['style'] as Map)['x_mm'] = 20;
    final updated = applyStudioProjectionToReportTemplateV4(design, projection);
    final variants = updated['variants'] as Map;
    expect(
      (((variants['a4_portrait'] as Map)['node_overrides'] as Map)['text-one']
          as Map)['placement']['x_mm'],
      20,
    );
    expect(
      (((variants['roll_80'] as Map)['node_overrides'] as Map)['text-one']
          as Map)['placement']['x_mm'],
      2,
    );

    final bodyBlocks = (projection['regions'] as Map)['body'] as List;
    bodyBlocks.add({
      'id': 'text-new',
      'type': 'custom_text',
      'visible': true,
      'props': {'text': 'جدید'},
      'style': {
        'row_id': 'row-new',
        'layout_type': 'page_grid',
        'page_grid_mm': 1,
        'page_snap': true,
        'page_height_mm': 277,
        'x_mm': 5,
        'y_mm': 220,
        'width_mm': 180,
        'height_mm': 20,
      },
    });
    final withNewBlock = applyStudioProjectionToReportTemplateV4(
      design,
      projection,
    );
    final rollVariant = (withNewBlock['variants'] as Map)['roll_80'] as Map;
    final rollOverrides = rollVariant['node_overrides'] as Map;
    final newRollNode = rollOverrides['text-new'] as Map;
    final newRollPlacement = newRollNode['placement'] as Map;
    expect(newRollPlacement['x_mm'], 0);
    expect(newRollPlacement['width_mm'], 76);

    (updated['media'] as Map)
      ..['type'] = 'roll'
      ..['preset'] = '80mm'
      ..['width_mm'] = 80;
    projection = reportTemplateV4StudioProjection(updated);
    block = ((projection['regions'] as Map)['body'] as List).first as Map;
    expect((block['style'] as Map)['x_mm'], 2);
  });

  test('snap move prefers sibling edges and clamps inside container', () {
    final result = snapStudioMove(
      proposed: const StudioMmRect(19.4, 7.2, 10, 10),
      siblings: const [StudioMmRect(30, 5, 12, 10)],
      containerWidthMm: 80,
      containerHeightMm: 40,
      gridMm: 5,
      thresholdMm: 1,
    );
    expect(result.rect.right, 30);
    expect(result.guides.any((guide) => guide.source == 'sibling'), isTrue);

    final clamped = snapStudioMove(
      proposed: const StudioMmRect(78, 38, 10, 10),
      siblings: const [],
      containerWidthMm: 80,
      containerHeightMm: 40,
      gridMm: 1,
      thresholdMm: 0,
      enabled: false,
    );
    expect(clamped.rect.x, 70);
    expect(clamped.rect.y, 30);
  });

  testWidgets('v4 full-page grid keeps content visible and supports gestures', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, dynamic>? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1500,
            height: 900,
            child: ReportTemplateStudioV3Builder(
              design: _design(),
              blockCatalog: const [
                {
                  'type': 'custom_text',
                  'label_fa': 'متن دلخواه',
                  'allowed_regions': ['header', 'body', 'footer'],
                  'default_props': {'text': 'متن'},
                },
              ],
              onDesignChanged: (value) => changed = value,
              previewPane: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final block = find.byKey(const ValueKey('freeform-block-text-one'));
    expect(block, findsOneWidget);
    expect(find.text('متن تست'), findsOneWidget);
    final beforeZoom = tester.getSize(block);
    await tester.tap(find.byKey(const ValueKey('studio-zoom-in')));
    await tester.pumpAndSettle();
    expect(find.text('110٪'), findsOneWidget);
    expect(tester.getSize(block).width, greaterThan(beforeZoom.width));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(block),
        scrollDelta: const Offset(0, -20),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('120٪'), findsOneWidget);
    final beforeMove = tester.getTopLeft(block);
    final moveGesture = await tester.startGesture(tester.getCenter(block));
    await moveGesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(tester.getTopLeft(block).dx, greaterThan(beforeMove.dx));
    await moveGesture.up();
    await tester.pump();
    expect(changed, isNotNull);
    changed = null;
    final handle = find.byKey(
      const ValueKey('freeform-resize-handle-text-one'),
    );
    expect(handle, findsOneWidget);
    final before = tester.getSize(block);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(36, 0));
    await tester.pump();
    expect(tester.getSize(block).width, greaterThan(before.width));
    await gesture.up();
    await tester.pump();
    expect(changed, isNotNull);
    expect(changed!['schema_version'], 4);
  });

  testWidgets('anchor handles persist a responsive node constraint', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, dynamic>? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1500,
            height: 900,
            child: ReportTemplateStudioV3Builder(
              design: _design(),
              blockCatalog: const [
                {
                  'type': 'custom_text',
                  'label_fa': 'متن دلخواه',
                  'allowed_regions': ['header', 'body', 'footer'],
                  'default_props': {'text': 'متن'},
                },
              ],
              onDesignChanged: (value) => changed = value,
              previewPane: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final second = find.byKey(const ValueKey('freeform-block-text-two'));
    await tester.tapAt(tester.getCenter(second));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('anchor-handle-text-two-top')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('anchor-handle-text-one-bottom')),
    );
    await tester.pumpAndSettle();
    expect(changed, isNotNull);

    Map? findNode(Map node, String id) {
      if (node['id'] == id) return node;
      for (final child in (node['children'] as List?) ?? const []) {
        if (child is Map) {
          final found = findNode(child, id);
          if (found != null) return found;
        }
      }
      return null;
    }

    final node = findNode(changed!['root'] as Map, 'text-two')!;
    final links = ((node['constraints'] as Map)['links'] as List);
    expect(links, hasLength(1));
    expect((links.first as Map)['source_anchor'], 'top');
    expect(((links.first as Map)['target'] as Map)['id'], 'text-one');
    expect(
      ((links.first as Map)['variant_offsets'] as Map),
      contains('a4_portrait'),
    );
    final variants = changed!['variants'] as Map;
    for (final variant in variants.values) {
      final overrides = (variant as Map)['node_overrides'] as Map;
      final responsiveConstraints =
          (overrides['text-two'] as Map)['constraints'] as Map;
      final responsiveLink =
          (responsiveConstraints['links'] as List).single as Map;
      expect(responsiveLink['source_anchor'], 'top');
      expect((responsiveLink['target'] as Map)['id'], 'text-one');
      expect(responsiveLink['variant_offsets'], contains('a4_portrait'));
    }
  });

  test('grid snapping supports 1, 3, and 5 millimeters and hard bounds', () {
    for (final grid in const [1.0, 3.0, 5.0]) {
      final result = snapStudioMove(
        proposed: const StudioMmRect(107.8, 107.8, 10, 10),
        siblings: const [],
        containerWidthMm: 1000,
        containerHeightMm: 1000,
        gridMm: grid,
        thresholdMm: grid,
      );
      expect(result.rect.x % grid, closeTo(0, 0.0001));
      expect(result.rect.y % grid, closeTo(0, 0.0001));
    }

    final exactBoundary = snapStudioMove(
      proposed: const StudioMmRect(70, 30, 10, 10),
      siblings: const [],
      containerWidthMm: 80,
      containerHeightMm: 40,
      gridMm: 1,
      thresholdMm: 0,
      enabled: false,
    );
    expect(exactBoundary.rect.x, 70);
    expect(exactBoundary.rect.y, 30);

    final outsideBoundary = snapStudioResize(
      proposed: const StudioMmRect(70, 30, 11, 11),
      siblings: const [],
      containerWidthMm: 80,
      containerHeightMm: 40,
      gridMm: 1,
      thresholdMm: 0,
      enabled: false,
    );
    expect(outsideBoundary.rect.right, 80);
    expect(outsideBoundary.rect.bottom, 40);
  });

  testWidgets('page grid keeps sibling blocks side by side', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final design = _design();
    for (final variant in (design['variants'] as Map).values) {
      final overrides = (variant as Map)['node_overrides'] as Map;
      (overrides['text-one'] as Map)['placement'] = <String, dynamic>{
        ...Map<String, dynamic>.from(
          (overrides['text-one'] as Map)['placement'] as Map,
        ),
        'x_mm': 5,
        'y_mm': 8,
        'width_mm': 60,
      };
      (overrides['text-two'] as Map)['placement'] = <String, dynamic>{
        ...Map<String, dynamic>.from(
          (overrides['text-two'] as Map)['placement'] as Map,
        ),
        'x_mm': 70,
        'y_mm': 8,
        'width_mm': 60,
      };
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportTemplateStudioV3Builder(
            design: design,
            blockCatalog: const [
              {
                'type': 'custom_text',
                'label_fa': 'متن دلخواه',
                'allowed_regions': ['header', 'body', 'footer'],
                'default_props': {'text': 'متن'},
              },
            ],
            onDesignChanged: (_) {},
            previewPane: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('freeform-block-text-one'));
    final second = find.byKey(const ValueKey('freeform-block-text-two'));
    expect(
      tester.getTopLeft(first).dy,
      closeTo(tester.getTopLeft(second).dy, 0.5),
    );
    expect(tester.getTopLeft(first).dx, lessThan(tester.getTopLeft(second).dx));
  });

  testWidgets('studio persists page grid choices 1, 3, and 5', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var current = _design();
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: ReportTemplateStudioV3Builder(
              design: current,
              blockCatalog: const [
                {
                  'type': 'custom_text',
                  'label_fa': 'متن دلخواه',
                  'allowed_regions': ['header', 'body', 'footer'],
                  'default_props': {'text': 'متن'},
                },
              ],
              onDesignChanged: (value) => setState(() => current = value),
              previewPane: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('freeform-block-text-one'))),
    );
    await tester.pumpAndSettle();
    for (final grid in const [3, 5, 1]) {
      await tester.tap(
        find.text(
          '$grid mm'
              .replaceAll('1', '۱')
              .replaceAll('3', '۳')
              .replaceAll('5', '۵'),
        ),
      );
      await tester.pumpAndSettle();
      expect(((current['root'] as Map)['layout'] as Map)['grid_mm'], grid);
    }
  });

  testWidgets('anchor can be removed from settings and persisted document', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var current = _designWithExistingAnchor();
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: ReportTemplateStudioV3Builder(
              design: current,
              blockCatalog: const [
                {
                  'type': 'custom_text',
                  'label_fa': 'متن دلخواه',
                  'allowed_regions': ['header', 'body', 'footer'],
                  'default_props': {'text': 'متن'},
                },
              ],
              onDesignChanged: (value) => setState(() => current = value),
              previewPane: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('freeform-block-text-two'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('قطع اتصال'));
    await tester.pumpAndSettle();
    final node = _findNode(
      (current['root'] as Map).cast<String, dynamic>(),
      'text-two',
    )!;
    expect(((node['constraints'] as Map)['links'] as List), isEmpty);
  });

  testWidgets('anchor UI rejects cycles and a second direct follower', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var current = _designWithThirdBlock();
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: ReportTemplateStudioV3Builder(
              design: current,
              blockCatalog: const [
                {
                  'type': 'custom_text',
                  'label_fa': 'متن دلخواه',
                  'allowed_regions': ['header', 'body', 'footer'],
                  'default_props': {'text': 'متن'},
                },
              ],
              onDesignChanged: (value) => setState(() => current = value),
              previewPane: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('freeform-block-text-one'))),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('anchor-handle-text-one-top')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('anchor-handle-text-two-bottom')),
    );
    await tester.pump();
    expect(find.text('این اتصال یک چرخه ایجاد می‌کند.'), findsOneWidget);
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('freeform-block-text-three'))),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('anchor-handle-text-three-top')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('anchor-handle-text-one-bottom')),
    );
    await tester.pump();
    final third = _findNode(
      (current['root'] as Map).cast<String, dynamic>(),
      'text-three',
    )!;
    final constraints = (third['constraints'] as Map?) ?? const {};
    expect((constraints['links'] as List?) ?? const [], isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('zoom is clamped, resets, and never changes the design', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var changes = 0;
    final design = _design();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportTemplateStudioV3Builder(
            design: design,
            blockCatalog: const [
              {
                'type': 'custom_text',
                'label_fa': 'متن دلخواه',
                'allowed_regions': ['header', 'body', 'footer'],
                'default_props': {'text': 'متن'},
              },
            ],
            onDesignChanged: (_) => changes++,
            previewPane: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var index = 0; index < 20; index++) {
      await tester.tap(find.byKey(const ValueKey('studio-zoom-in')));
      await tester.pump();
    }
    expect(find.text('250٪'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('studio-zoom-in')));
    await tester.pump();
    expect(find.text('250٪'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('studio-zoom-reset')));
    await tester.pump();
    expect(find.text('100٪'), findsOneWidget);
    for (var index = 0; index < 20; index++) {
      await tester.tap(find.byKey(const ValueKey('studio-zoom-out')));
      await tester.pump();
    }
    expect(find.text('50٪'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('freeform-block-text-one')),
        ),
        scrollDelta: const Offset(0, 30),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('50٪'), findsOneWidget);
    expect(changes, 0);
    expect(design.toString(), isNot(contains('zoom')));
  });

  testWidgets('viewport resize does not change the print media profile', (
    tester,
  ) async {
    var changes = 0;
    final design = _design();
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportTemplateStudioV3Builder(
            design: design,
            blockCatalog: const [
              {
                'type': 'custom_text',
                'label_fa': 'متن دلخواه',
                'allowed_regions': ['header', 'body', 'footer'],
                'default_props': {'text': 'متن'},
              },
            ],
            onDesignChanged: (_) => changes++,
            previewPane: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(reportTemplateV4ProfileKey(design), 'a4_portrait');
    await tester.binding.setSurfaceSize(const Size(700, 900));
    await tester.pumpAndSettle();
    expect(reportTemplateV4ProfileKey(design), 'a4_portrait');
    expect(changes, 0);
  });
}
