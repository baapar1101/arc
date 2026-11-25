import '../../../models/barcode_label/label_design_v1.dart';

/// Geometry of one roll row — one PDF/ZPL page.
///
/// Each multi-column row is its own page. Height does not grow with label count.
/// If top/bottom margins are both zero, the vertical gap is split equally so the
/// label is centered in the feed.
class RollLabelPageMetrics {
  const RollLabelPageMetrics({
    required this.columns,
    required this.widthMm,
    required this.heightMm,
    required this.leftMm,
    required this.rightMm,
    required this.topMm,
    required this.bottomMm,
    required this.gapXMm,
    required this.requiredWidthMm,
  });

  final int columns;
  final double widthMm;
  final double heightMm;
  final double leftMm;
  final double rightMm;
  final double topMm;
  final double bottomMm;
  final double gapXMm;
  final double requiredWidthMm;

  bool get fits => widthMm + 0.01 >= requiredWidthMm;
}

RollLabelPageMetrics rollLabelPageMetrics({
  required LabelSheet sheet,
  required double labelWidthMm,
  required double labelHeightMm,
}) {
  final leftMm = sheet.rollMarginMm['left'] ?? 0;
  final rightMm = sheet.rollMarginMm['right'] ?? 0;
  final topMm = sheet.rollMarginMm['top'] ?? 0;
  final bottomMm = sheet.rollMarginMm['bottom'] ?? 0;
  final columns = sheet.rollColumns.clamp(1, 20).toInt();
  final gapXMm = sheet.rollGapMm['x'] ?? 2;
  final gapYMm = sheet.rollGapMm['y'] ?? 2;
  final requiredWidthMm = leftMm + rightMm + columns * labelWidthMm + (columns - 1) * gapXMm;
  final widthMm = sheet.rollPaperWidthMm > 0 ? sheet.rollPaperWidthMm : requiredWidthMm;
  final splitGap = topMm == 0 && bottomMm == 0;
  final pageTopMm = splitGap ? gapYMm / 2 : topMm;
  final pageBottomMm = splitGap ? gapYMm / 2 : bottomMm;
  return RollLabelPageMetrics(
    columns: columns,
    widthMm: widthMm,
    heightMm: pageTopMm + labelHeightMm + pageBottomMm,
    leftMm: leftMm,
    rightMm: rightMm,
    topMm: pageTopMm,
    bottomMm: pageBottomMm,
    gapXMm: gapXMm,
    requiredWidthMm: requiredWidthMm,
  );
}
