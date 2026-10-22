import 'dart:math' as math;

class StudioMmRect {
  final double x;
  final double y;
  final double width;
  final double height;

  const StudioMmRect(this.x, this.y, this.width, this.height);

  double get right => x + width;
  double get bottom => y + height;
  double get centerX => x + width / 2;
  double get centerY => y + height / 2;

  StudioMmRect clampInside(double containerWidth, double containerHeight) {
    final nextWidth = width.clamp(1, containerWidth).toDouble();
    final nextHeight = height.clamp(1, containerHeight).toDouble();
    return StudioMmRect(
      x.clamp(0, math.max(0, containerWidth - nextWidth)).toDouble(),
      y.clamp(0, math.max(0, containerHeight - nextHeight)).toDouble(),
      nextWidth,
      nextHeight,
    );
  }
}

class StudioSnapGuide {
  final bool vertical;
  final double positionMm;
  final String source;

  const StudioSnapGuide({
    required this.vertical,
    required this.positionMm,
    required this.source,
  });
}

class StudioSnapResult {
  final StudioMmRect rect;
  final List<StudioSnapGuide> guides;

  const StudioSnapResult(this.rect, this.guides);
}

class _Candidate {
  final double delta;
  final double guide;
  final int priority;
  final String source;

  const _Candidate(this.delta, this.guide, this.priority, this.source);
}

_Candidate? _best(List<_Candidate> candidates, double thresholdMm) {
  final within =
      candidates
          .where((candidate) => candidate.delta.abs() <= thresholdMm)
          .toList()
        ..sort((a, b) {
          final priority = a.priority.compareTo(b.priority);
          return priority != 0
              ? priority
              : a.delta.abs().compareTo(b.delta.abs());
        });
  return within.isEmpty ? null : within.first;
}

StudioSnapResult snapStudioMove({
  required StudioMmRect proposed,
  required List<StudioMmRect> siblings,
  required double containerWidthMm,
  required double containerHeightMm,
  required double gridMm,
  required double thresholdMm,
  bool enabled = true,
}) {
  var rect = proposed.clampInside(containerWidthMm, containerHeightMm);
  if (!enabled) return StudioSnapResult(rect, const []);
  final xCandidates = <_Candidate>[];
  final yCandidates = <_Candidate>[];

  void addX(double moving, double target, int priority, String source) =>
      xCandidates.add(_Candidate(target - moving, target, priority, source));
  void addY(double moving, double target, int priority, String source) =>
      yCandidates.add(_Candidate(target - moving, target, priority, source));

  for (final sibling in siblings) {
    for (final target in [sibling.x, sibling.centerX, sibling.right]) {
      addX(rect.x, target, 0, 'sibling');
      addX(rect.centerX, target, 0, 'sibling');
      addX(rect.right, target, 0, 'sibling');
    }
    for (final target in [sibling.y, sibling.centerY, sibling.bottom]) {
      addY(rect.y, target, 0, 'sibling');
      addY(rect.centerY, target, 0, 'sibling');
      addY(rect.bottom, target, 0, 'sibling');
    }
  }
  for (final target in [0.0, containerWidthMm / 2, containerWidthMm]) {
    addX(rect.x, target, 1, 'margin');
    addX(rect.centerX, target, 1, 'margin');
    addX(rect.right, target, 1, 'margin');
  }
  for (final target in [0.0, containerHeightMm / 2, containerHeightMm]) {
    addY(rect.y, target, 1, 'margin');
    addY(rect.centerY, target, 1, 'margin');
    addY(rect.bottom, target, 1, 'margin');
  }
  if (gridMm > 0) {
    final gridX = (rect.x / gridMm).round() * gridMm;
    final gridY = (rect.y / gridMm).round() * gridMm;
    addX(rect.x, gridX, 2, 'grid');
    addY(rect.y, gridY, 2, 'grid');
  }

  final bestX = _best(xCandidates, thresholdMm);
  final bestY = _best(yCandidates, thresholdMm);
  rect = StudioMmRect(
    rect.x + (bestX?.delta ?? 0),
    rect.y + (bestY?.delta ?? 0),
    rect.width,
    rect.height,
  ).clampInside(containerWidthMm, containerHeightMm);
  return StudioSnapResult(rect, [
    if (bestX != null)
      StudioSnapGuide(
        vertical: true,
        positionMm: bestX.guide,
        source: bestX.source,
      ),
    if (bestY != null)
      StudioSnapGuide(
        vertical: false,
        positionMm: bestY.guide,
        source: bestY.source,
      ),
  ]);
}

StudioSnapResult snapStudioResize({
  required StudioMmRect proposed,
  required List<StudioMmRect> siblings,
  required double containerWidthMm,
  required double containerHeightMm,
  required double gridMm,
  required double thresholdMm,
  bool enabled = true,
}) {
  var rect = proposed.clampInside(containerWidthMm, containerHeightMm);
  if (!enabled) return StudioSnapResult(rect, const []);
  final xCandidates = <_Candidate>[];
  final yCandidates = <_Candidate>[];
  for (final sibling in siblings) {
    for (final target in [sibling.x, sibling.centerX, sibling.right]) {
      xCandidates.add(_Candidate(target - rect.right, target, 0, 'sibling'));
    }
    for (final target in [sibling.y, sibling.centerY, sibling.bottom]) {
      yCandidates.add(_Candidate(target - rect.bottom, target, 0, 'sibling'));
    }
  }
  for (final target in [containerWidthMm / 2, containerWidthMm]) {
    xCandidates.add(_Candidate(target - rect.right, target, 1, 'margin'));
  }
  for (final target in [containerHeightMm / 2, containerHeightMm]) {
    yCandidates.add(_Candidate(target - rect.bottom, target, 1, 'margin'));
  }
  if (gridMm > 0) {
    final gridRight = (rect.right / gridMm).round() * gridMm;
    final gridBottom = (rect.bottom / gridMm).round() * gridMm;
    xCandidates.add(_Candidate(gridRight - rect.right, gridRight, 2, 'grid'));
    yCandidates.add(
      _Candidate(gridBottom - rect.bottom, gridBottom, 2, 'grid'),
    );
  }
  final bestX = _best(xCandidates, thresholdMm);
  final bestY = _best(yCandidates, thresholdMm);
  rect = StudioMmRect(
    rect.x,
    rect.y,
    math.max(1, rect.width + (bestX?.delta ?? 0)),
    math.max(1, rect.height + (bestY?.delta ?? 0)),
  ).clampInside(containerWidthMm, containerHeightMm);
  return StudioSnapResult(rect, [
    if (bestX != null)
      StudioSnapGuide(
        vertical: true,
        positionMm: bestX.guide,
        source: bestX.source,
      ),
    if (bestY != null)
      StudioSnapGuide(
        vertical: false,
        positionMm: bestY.guide,
        source: bestY.source,
      ),
  ]);
}
