import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/report_template/studio/report_template_media_settings.dart';
import 'package:hesabix_ui/widgets/report_template/studio/report_template_studio_preview_panel.dart';
import 'package:hesabix_ui/widgets/report_template/studio/report_template_studio_v3_builder.dart';

void main() {
  test('maps legacy paper sizes to sheet and custom roll media', () {
    final sheet = reportTemplateMediaFromLegacy(
      paperSize: 'A5',
      orientation: 'landscape',
    );
    expect(sheet['type'], 'sheet');
    expect(sheet['width_mm'], 148);
    expect(sheet['height_mm'], 210);
    expect(reportTemplatePaperSizeFromMedia(sheet), 'A5');

    final roll = reportTemplateMediaFromLegacy(paperSize: '72.5mm');
    expect(roll['type'], 'roll');
    expect(roll['width_mm'], 72.5);
    expect(reportTemplatePaperSizeFromMedia(roll), '72.5mm');
  });

  testWidgets('adds a palette block and supports undo', (tester) async {
    var design = <String, dynamic>{
      'schema_version': 3,
      'family_id': 'invoice_classic',
      'layout': 'invoice_detail',
      'theme': <String, dynamic>{
        'primary_color': '#1e3a5f',
        'font_size_base': 11,
      },
      'branding': <String, dynamic>{
        'show_logo': true,
        'show_business_name': true,
      },
      'regions': <String, dynamic>{
        'header': <Map<String, dynamic>>[],
        'body': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'invoice-lines',
            'type': 'invoice_lines',
            'visible': true,
            'props': <String, dynamic>{
              'columns': <Map<String, dynamic>>[
                <String, dynamic>{
                  'key': 'product_name',
                  'title': 'شرح',
                  'visible': true,
                  'width': 'auto',
                },
              ],
            },
            'style': <String, dynamic>{},
          },
        ],
        'footer': <Map<String, dynamic>>[],
      },
    };
    const catalog = <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'invoice_lines',
        'label_fa': 'جدول اقلام',
        'allowed_regions': <String>['body'],
        'max_instances': 1,
        'required': true,
        'default_props': <String, dynamic>{},
      },
      <String, dynamic>{
        'type': 'custom_text',
        'label_fa': 'متن دلخواه',
        'allowed_regions': <String>['header', 'body', 'footer'],
        'default_props': <String, dynamic>{
          'text': 'متن دلخواه',
          'align': 'right',
        },
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                width: 600,
                height: 900,
                child: ReportTemplateStudioV3Builder(
                  design: design,
                  blockCatalog: catalog,
                  onDesignChanged: (next) => setState(() => design = next),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('ظاهر، برندینگ و جهت نوشتار'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('چپ‌به‌راست'));
    await tester.pump();
    expect((design['theme'] as Map)['direction'], 'ltr');

    await tester.tap(find.text('متن دلخواه').first);
    await tester.pump();

    final body = ((design['regions'] as Map)['body'] as List)
        .cast<Map<String, dynamic>>();
    expect(body.map((block) => block['type']), contains('custom_text'));

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();

    final restoredBody = ((design['regions'] as Map)['body'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      restoredBody.map((block) => block['type']),
      isNot(contains('custom_text')),
    );
  });

  testWidgets('shows block settings in the left workspace column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var design = <String, dynamic>{
      'schema_version': 3,
      'family_id': 'invoice_classic',
      'layout': 'invoice_detail',
      'theme': <String, dynamic>{},
      'branding': <String, dynamic>{},
      'regions': <String, dynamic>{
        'header': <Map<String, dynamic>>[],
        'body': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'invoice-lines',
            'type': 'invoice_lines',
            'visible': true,
            'props': <String, dynamic>{'columns': <Map<String, dynamic>>[]},
            'style': <String, dynamic>{},
          },
        ],
        'footer': <Map<String, dynamic>>[],
      },
    };
    const catalog = <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'invoice_lines',
        'label_fa': 'جدول اقلام',
        'allowed_regions': <String>['body'],
        'max_instances': 1,
        'required': true,
        'default_props': <String, dynamic>{},
      },
      <String, dynamic>{
        'type': 'custom_text',
        'label_fa': 'متن دلخواه',
        'allowed_regions': <String>['header', 'body', 'footer'],
        'default_props': <String, dynamic>{'text': 'متن دلخواه'},
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ReportTemplateStudioV3Builder(
              design: design,
              blockCatalog: catalog,
              onDesignChanged: (next) => setState(() => design = next),
              editorHeader: const Text('مشخصات قالب'),
              previewPane: const Center(child: Text('پیش‌نمایش آزمایشی')),
            ),
          ),
        ),
      ),
    );

    expect(
      find.text(
        'یک بلوک را انتخاب کنید تا تنظیمات آن زیر تنظیمات صفحه نمایش داده شود.',
      ),
      findsOneWidget,
    );

    expect(find.text('صفحه و چاپ'), findsOneWidget);
    await tester.tap(find.text('رول'));
    await tester.pump();
    expect((design['media'] as Map)['type'], 'roll');
    expect((design['media'] as Map)['width_mm'], 80);

    expect(
      find.byKey(const ValueKey('interactive-invoice-canvas')),
      findsOneWidget,
    );
    expect(find.text('نمونه کالا 1'), findsOneWidget);

    final paletteText = find.text('متن دلخواه').first;
    final footerDropTarget = find.textContaining(
      'پاورقی — بلوک را اینجا رها کنید',
    );
    await tester.dragFrom(
      tester.getCenter(paletteText),
      tester.getCenter(footerDropTarget) - tester.getCenter(paletteText),
    );
    await tester.pumpAndSettle();
    final footer = ((design['regions'] as Map)['footer'] as List)
        .cast<Map<String, dynamic>>();
    expect(footer.map((block) => block['type']), contains('custom_text'));

    await tester.tap(find.text('نمونه کالا 1'));
    await tester.pump();

    final inspector = find.text('تنظیمات جدول اقلام');
    final canvas = find.byKey(const ValueKey('interactive-invoice-canvas'));
    final designer = find.text('طراح بلوکی');
    expect(inspector, findsOneWidget);
    expect(find.text('عرض بلوک'), findsOneWidget);
    expect(find.text('تمام عرض'), findsOneWidget);
    expect(
      tester.getCenter(inspector).dx,
      lessThan(tester.getCenter(canvas).dx),
    );
    expect(
      tester.getCenter(canvas).dx,
      lessThan(tester.getCenter(designer).dx),
    );

    await tester.tap(find.text('وسط'));
    await tester.pump();
    final body = ((design['regions'] as Map)['body'] as List)
        .cast<Map<String, dynamic>>();
    expect((body.first['style'] as Map)['text_align'], 'center');

    await tester.tap(find.text('خروجی'));
    await tester.pump();
    expect(find.text('پیش‌نمایش آزمایشی'), findsOneWidget);
  });

  testWidgets('keeps live HTML visible after print PDF is generated', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 800,
            child: ReportTemplateStudioPreviewPanel(
              loading: false,
              html: '<!doctype html><html><body>preview</body></html>',
              pdfBytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
              showPdf: true,
              previewRevision: 1,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('پیش‌نمایش HTML فقط در نسخه وب در دسترس است.'),
      findsOneWidget,
    );
    expect(find.textContaining('برای مشاهدهٔ PDF در دسکتاپ'), findsNothing);
  });

  testWidgets('preview toolbar remains usable on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportTemplateStudioPreviewPanel(
            loading: false,
            html: '<html><body>preview</body></html>',
            pdfBytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
            showPdf: true,
            media: defaultReportTemplateMedia(roll: true),
            onRefresh: () {},
            onGeneratePdf: () {},
            onShowHtml: () {},
          ),
        ),
      ),
    );

    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('80mm'), findsOneWidget);
  });
}
