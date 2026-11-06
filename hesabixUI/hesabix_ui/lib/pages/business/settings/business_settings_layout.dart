import 'package:flutter/material.dart';

import '../../../theme/tokens/extensions.dart';

/// Layout helpers for the business settings hub.
abstract final class BusinessSettingsLayout {
  static int columnCount(BuildContext context) {
    return context.settingsHub.gridColumns(MediaQuery.sizeOf(context).width);
  }

  static Widget buildResponsiveGrid({
    required BuildContext context,
    required List<Widget> children,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();

    final hub = context.settingsHub;
    final gap = hub.gridGap;
    final runSpacing = hub.gridRunSpacing;
    final columns = columnCount(context);

    if (columns <= 1) {
      return Column(
        children: [
          for (var i = 0; i < children.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == children.length - 1 ? 0 : runSpacing,
              ),
              child: children[i],
            ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: runSpacing,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }
}
