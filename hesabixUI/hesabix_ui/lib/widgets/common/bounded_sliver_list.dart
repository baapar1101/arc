import 'package:flutter/widgets.dart';

/// A small shared wrapper for large, stateless list rows.
///
/// Flutter's sliver builder creates children lazily. Disabling automatic
/// keep-alives prevents off-screen task/activity/file rows from accumulating
/// element state as more server pages are appended, while repaint boundaries
/// isolate expensive glass/card paints.
class BoundedSliverList extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool addSemanticIndexes;

  const BoundedSliverList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.addSemanticIndexes = true,
  });

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        itemBuilder,
        childCount: itemCount,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        addSemanticIndexes: addSemanticIndexes,
      ),
    );
  }
}
