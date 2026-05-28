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
    final anchor = position.pixels + position.viewportDimension * anchorViewportFraction;

    var bestIndex = 0;
    var bestOffset = -double.infinity;

    for (var i = 0; i < messageKeys.length; i++) {
      final ctx = messageKeys[i].currentContext;
      if (ctx == null) continue;
      final renderObject = ctx.findRenderObject();
      if (renderObject == null) continue;

      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null) continue;

      final revealed = viewport.getOffsetToReveal(renderObject, 0.0);
      final offset = revealed.offset;

      if (offset <= anchor && offset >= bestOffset) {
        bestOffset = offset;
        bestIndex = i;
      }
    }

    return bestIndex;
  }
}
