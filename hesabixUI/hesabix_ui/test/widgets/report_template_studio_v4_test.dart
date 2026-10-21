import 'package:flutter/material.dart';
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
}
