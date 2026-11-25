import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/barcode_label/label_design_v1.dart';
import 'package:hesabix_ui/widgets/barcode_label/render/roll_label_page_metrics.dart';

void main() {
  const labelW = 40.0;
  const labelH = 30.0;

  test('roll page height is one row, not the label count', () {
    const sheet = LabelSheet(
      printMode: 'roll',
      rollPaperWidthMm: 100,
      rollColumns: 3,
      rollGapMm: {'x': 2, 'y': 4},
      rollMarginMm: {'top': 0, 'right': 0, 'bottom': 0, 'left': 0},
    );
    final metrics = rollLabelPageMetrics(sheet: sheet, labelWidthMm: labelW, labelHeightMm: labelH);
    expect(metrics.columns, 3);
    expect(metrics.widthMm, 100);
    // Vertical gap 4 mm is split 2+2 when top/bottom are 0.
    expect(metrics.topMm, 2);
    expect(metrics.bottomMm, 2);
    expect(metrics.heightMm, 34);
  });

  test('explicit top/bottom margins replace the vertical gap split', () {
    const sheet = LabelSheet(
      printMode: 'roll',
      rollPaperWidthMm: 100,
      rollColumns: 2,
      rollGapMm: {'x': 3, 'y': 10},
      rollMarginMm: {'top': 1, 'right': 2, 'bottom': 5, 'left': 4},
    );
    final metrics = rollLabelPageMetrics(sheet: sheet, labelWidthMm: labelW, labelHeightMm: labelH);
    expect(metrics.topMm, 1);
    expect(metrics.bottomMm, 5);
    expect(metrics.heightMm, 36);
    expect(metrics.leftMm, 4);
    expect(metrics.gapXMm, 3);
    expect(metrics.requiredWidthMm, 4 + 2 + 40 + 3 + 40);
  });

  test('roll width auto-fits columns when paper width is zero', () {
    const sheet = LabelSheet(
      printMode: 'roll',
      rollPaperWidthMm: 0,
      rollColumns: 3,
      rollGapMm: {'x': 2, 'y': 0},
      rollMarginMm: {'top': 0, 'right': 1, 'bottom': 0, 'left': 1},
    );
    final metrics = rollLabelPageMetrics(sheet: sheet, labelWidthMm: labelW, labelHeightMm: labelH);
    expect(metrics.widthMm, 1 + 1 + 40 * 3 + 2 * 2);
    expect(metrics.fits, isTrue);
    expect(metrics.heightMm, labelH);
  });
}
