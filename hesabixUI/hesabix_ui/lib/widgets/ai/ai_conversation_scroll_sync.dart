import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// محاسبهٔ index پیام فعال بر اساس موقعیت scroll.
abstract final class AIConversationScrollSync {
  static const double defaultAnchorFraction = 0.22;

  static int computeActiveIndex({
    required ScrollController scrollController,
    required List<GlobalKey> messageKeys,
    double anchorViewportFraction = defaultAnchorFraction,
  }) {
    if (!scrollController.hasClients || messageKeys.isEmpty) return 0;

    final position = scrollController.position;
    final viewportStart = position.pixels;
    final viewportEnd = position.pixels + position.viewportDimension;
    final anchor =
        viewportStart + position.viewportDimension * anchorViewportFraction;

    var bestIndex = 0;
    var bestScore = -1.0;
    var bestDistance = double.infinity;

    for (var i = 0; i < messageKeys.length; i++) {
      final ctx = messageKeys[i].currentContext;
      if (ctx == null) continue;
      final renderObject = ctx.findRenderObject();
      if (renderObject == null) continue;

      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null) continue;

      final revealed = viewport.getOffsetToReveal(renderObject, 0.0);
      final start = revealed.offset;
      final height = renderObject.paintBounds.height;
      if (height <= 0) continue;
      final end = start + height;
      final overlap = (viewportEnd < start || viewportStart > end)
          ? 0.0
          : (viewportEnd < end ? viewportEnd : end) -
                (viewportStart > start ? viewportStart : start);
      final visibility = overlap / height;
      final center = start + height / 2;
      final distance = (center - anchor).abs();

      if (visibility > bestScore ||
          (visibility == bestScore && distance < bestDistance)) {
        bestScore = visibility;
        bestDistance = distance;
        bestIndex = i;
      }
    }

    return bestIndex;
  }
}
