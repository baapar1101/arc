import 'package:flutter/material.dart';

/// روی عرض دسکتاپ کشیدن مستقیم است و روی عرض باریک فشار طولانی، تا لمس تصادفی کارت را جابه‌جا نکند.
class CrmKanbanDraggable extends StatelessWidget {
  const CrmKanbanDraggable({
    super.key,
    required this.data,
    required this.child,
    required this.feedbackTitle,
  });

  final Map<String, dynamic> data;
  final Widget child;
  final String feedbackTitle;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final feedback = Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 240,
        child: Card(
          child: ListTile(
            dense: true,
            title: Text(feedbackTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const Text('رها کنید روی مرحله مقصد'),
          ),
        ),
      ),
    );
    if (wide) {
      return Draggable<Map<String, dynamic>>(
        data: data,
        feedback: feedback,
        childWhenDragging: Opacity(opacity: 0.35, child: child),
        child: child,
      );
    }
    return LongPressDraggable<Map<String, dynamic>>(
      data: data,
      feedback: feedback,
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: child,
    );
  }
}
