import 'package:flutter/material.dart';

import '../../utils/responsive_helper.dart';

/// ابعاد فشرده و یکسان برای فیلدهای فرم فاکتور.
abstract final class InvoiceFormFieldMetrics {
  static const double gridSpacing = 8;
  static const double blockSpacing = 8;

  static const EdgeInsets contentPadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 8);

  static const BoxConstraints suffixIconConstraints = BoxConstraints(
    minHeight: 36,
    maxHeight: 36,
    minWidth: 36,
    maxWidth: 88,
  );

  static const BoxConstraints compactSuffixIconConstraints = BoxConstraints(
    minHeight: 36,
    maxHeight: 36,
    minWidth: 36,
    maxWidth: 36,
  );

  static InputDecoration mergeDecoration(
    BuildContext context,
    InputDecoration decoration,
  ) {
    final theme = Theme.of(context).inputDecorationTheme;
    return decoration.applyDefaults(theme).copyWith(
          isDense: true,
          contentPadding: contentPadding,
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        );
  }
}

/// گرید فشرده با ردیف‌های هم‌ارتفاع (IntrinsicHeight).
class InvoiceFormGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;

  const InvoiceFormGrid({
    super.key,
    required this.children,
    this.spacing = InvoiceFormFieldMetrics.gridSpacing,
  });

  static int _columnCount(double width) {
    if (width < ResponsiveHelper.mobileBreakpoint) return 1;
    if (width < ResponsiveHelper.tabletSmallBreakpoint) return 2;
    if (width < 1280) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final visible = children.where((c) => c is! InvoiceFormGridGap).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _columnCount(constraints.maxWidth);
        final rows = <List<Widget>>[];
        for (var i = 0; i < visible.length; i += cols) {
          final end = (i + cols < visible.length) ? i + cols : visible.length;
          rows.add(visible.sublist(i, end));
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) SizedBox(height: spacing),
              _FormGridRow(
                columns: cols,
                spacing: spacing,
                children: rows[r],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _FormGridRow extends StatelessWidget {
  final int columns;
  final double spacing;
  final List<Widget> children;

  const _FormGridRow({
    required this.columns,
    required this.spacing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (columns == 1) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            children[i],
          ],
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < columns; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            Expanded(
              child: i < children.length
                  ? Align(
                      alignment: Alignment.center,
                      child: children[i],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }
}

/// جای خالی در گرید.
class InvoiceFormGridGap extends SizedBox {
  const InvoiceFormGridGap() : super.shrink();
}

/// سویچ فشرده در یک ردیف (پیش‌نویس، شماره خودکار).
class InvoiceFormCompactToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const InvoiceFormCompactToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          height: 28,
          child: Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}

/// انیمیشن کوتاه برای فیلدهای شرطی.
class InvoiceFormAnimatedSlot extends StatelessWidget {
  final bool visible;
  final Widget child;

  const InvoiceFormAnimatedSlot({
    super.key,
    required this.visible,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeInOut,
      alignment: AlignmentDirectional.topCenter,
      child: visible ? child : const SizedBox.shrink(),
    );
  }
}
