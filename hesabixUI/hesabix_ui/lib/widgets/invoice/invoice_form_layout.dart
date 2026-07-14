import 'package:flutter/material.dart';

import '../../utils/responsive_helper.dart';

/// ابعاد و استایل یکسان برای فیلدهای فرم فاکتور.
abstract final class InvoiceFormFieldMetrics {
  static const double fieldHeight = 56;
  static const double helperSlotHeight = 18;
  static const double gridSpacing = 12;
  static const double sectionSpacing = 16;
  static const double sectionInnerPadding = 16;

  static const EdgeInsets contentPadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 10);

  static const BoxConstraints suffixIconConstraints = BoxConstraints(
    minHeight: 40,
    maxHeight: 40,
    minWidth: 40,
    maxWidth: 96,
  );

  static const BoxConstraints compactSuffixIconConstraints = BoxConstraints(
    minHeight: 40,
    maxHeight: 40,
    minWidth: 40,
    maxWidth: 40,
  );

  static InputDecoration mergeDecoration(
    BuildContext context,
    InputDecoration decoration,
  ) {
    final theme = Theme.of(context).inputDecorationTheme;
    return decoration.applyDefaults(theme).copyWith(
          isDense: true,
          contentPadding: contentPadding,
        );
  }
}

/// پوستهٔ فیلد تک‌خطی با ارتفاع ثابت و جای اختیاری برای راهنما.
class InvoiceFormFieldShell extends StatelessWidget {
  final Widget child;
  final String? helperText;
  final Widget? header;
  final bool multiline;
  final double? minMultilineHeight;
  final bool reserveHelperSlot;

  const InvoiceFormFieldShell({
    super.key,
    required this.child,
    this.helperText,
    this.header,
    this.multiline = false,
    this.minMultilineHeight,
    this.reserveHelperSlot = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final helperStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.2,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (header != null) ...[
          header!,
          const SizedBox(height: 4),
        ],
        if (multiline)
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: minMultilineHeight ?? InvoiceFormFieldMetrics.fieldHeight * 2,
            ),
            child: child,
          )
        else
          SizedBox(
            height: InvoiceFormFieldMetrics.fieldHeight,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: child,
            ),
          ),
        if (reserveHelperSlot || helperText != null)
          SizedBox(
            height: InvoiceFormFieldMetrics.helperSlotHeight,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: helperText == null
                  ? null
                  : Text(
                      helperText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: helperStyle,
                    ),
            ),
          ),
      ],
    );
  }
}

/// سویچ فشردهٔ بیرون از فیلد (پیش‌نویس، تولید خودکار شماره و …).
class InvoiceFormInlineToggle extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData icon;

  const InvoiceFormInlineToggle({
    super.key,
    required this.label,
    required this.tooltip,
    required this.value,
    required this.onChanged,
    this.icon = Icons.toggle_on_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabled = onChanged != null;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: value
            ? cs.primaryContainer.withValues(alpha: 0.45)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: enabled ? () => onChanged!(!value) : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: value ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: value ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: value ? FontWeight.w600 : FontWeight.w500,
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
            ),
          ),
        ),
      ),
    );
  }
}

/// کارت بخش فرم فاکتور.
class InvoiceFormSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  const InvoiceFormSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final padding = isMobile ? 12.0 : InvoiceFormFieldMetrics.sectionInnerPadding;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            SizedBox(height: isMobile ? 10 : 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// گرید واکنش‌گرا برای چیدمان فیلدهای فرم فاکتور.
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
    if (width < 1400) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final visible = children.where((c) => c is! InvoiceFormGridGap).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _columnCount(constraints.maxWidth);
        if (cols == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _intersperse(visible, SizedBox(height: spacing)),
          );
        }

        final itemWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in visible)
              SizedBox(
                width: itemWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }

  List<Widget> _intersperse(List<Widget> items, Widget separator) {
    if (items.isEmpty) return items;
    final out = <Widget>[items.first];
    for (var i = 1; i < items.length; i++) {
      out.add(separator);
      out.add(items[i]);
    }
    return out;
  }
}

/// جای خالی در گرید — برای حفظ فاصلهٔ یکنواخت در حالت تک‌ستونه.
class InvoiceFormGridGap extends SizedBox {
  const InvoiceFormGridGap() : super.shrink();
}

/// نوار خلاصهٔ بالای تب اطلاعات فاکتور.
class InvoiceInfoSummaryBar extends StatelessWidget {
  final String? typeLabel;
  final String? numberLabel;
  final String? dateLabel;
  final String? currencyLabel;
  final bool isDraft;

  const InvoiceInfoSummaryBar({
    super.key,
    this.typeLabel,
    this.numberLabel,
    this.dateLabel,
    this.currencyLabel,
    this.isDraft = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final chips = <Widget>[
      if (typeLabel != null && typeLabel!.isNotEmpty)
        _SummaryChip(
          icon: Icons.receipt_long_outlined,
          label: typeLabel!,
          emphasized: true,
        ),
      if (isDraft)
        _SummaryChip(
          icon: Icons.edit_note_outlined,
          label: 'پیش‌نویس',
          color: cs.tertiaryContainer,
          foreground: cs.onTertiaryContainer,
        ),
      if (numberLabel != null && numberLabel!.isNotEmpty)
        _SummaryChip(icon: Icons.tag_outlined, label: numberLabel!),
      if (dateLabel != null && dateLabel!.isNotEmpty)
        _SummaryChip(icon: Icons.event_outlined, label: dateLabel!),
      if (currencyLabel != null && currencyLabel!.isNotEmpty)
        _SummaryChip(icon: Icons.payments_outlined, label: currencyLabel!),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: Material(
        key: ValueKey<String>(
          '${typeLabel ?? ''}|${numberLabel ?? ''}|${dateLabel ?? ''}|$isDraft',
        ),
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: chips,
          ),
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool emphasized;
  final Color? color;
  final Color? foreground;

  const _SummaryChip({
    required this.icon,
    required this.label,
    this.emphasized = false,
    this.color,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = color ?? cs.surface.withValues(alpha: 0.72);
    final fg = foreground ?? cs.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: emphasized
            ? Border.all(color: cs.primary.withValues(alpha: 0.35))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: emphasized ? cs.primary : fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: emphasized ? cs.primary : fg,
              fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// انیمیشن نرم برای فیلدهای شرطی.
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
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: AlignmentDirectional.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: visible
            ? KeyedSubtree(key: const ValueKey('visible'), child: child)
            : const SizedBox.shrink(key: ValueKey('hidden')),
      ),
    );
  }
}
