import 'package:flutter/material.dart';

/// Layout helpers for the business settings hub.
abstract final class BusinessSettingsLayout {
  /// Screen width at which setting cards use a two-column grid.
  static const double twoColumnMinScreenWidth = 768;

  static bool useTwoColumns(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= twoColumnMinScreenWidth;
  }

  static Widget buildTwoColumnGrid({
    required BuildContext context,
    required List<Widget> children,
    double gap = 8,
    double runSpacing = 6,
  }) {
    if (children.isEmpty) return const SizedBox.shrink();

    if (!useTwoColumns(context)) {
      return Column(
        children: [
          for (var i = 0; i < children.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == children.length - 1 ? 0 : runSpacing),
              child: children[i],
            ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - gap) / 2;
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
