import 'package:flutter/material.dart';

/// دادهٔ نمایشی یک فروش باز برای نوار صندوق.
class QuickSalesParkedSaleChipData {
  final String id;
  final String title;
  final String subtitle;
  final bool isActive;
  final bool isBlank;
  final bool showDiscard;
  final String? customerInitial;

  const QuickSalesParkedSaleChipData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.isBlank,
    required this.showDiscard,
    this.customerInitial,
  });
}

/// نوار سبدهای باز فروش سریع: تعویض با یک ضربه، فروش جدید، حذف.
class QuickSalesParkedSalesBar extends StatelessWidget {
  final List<QuickSalesParkedSaleChipData> sales;
  final bool compact;
  final bool enabled;
  final bool newSaleEnabled;
  final String newSaleLabel;
  final String newSaleTooltip;
  final String discardTooltip;
  final VoidCallback onNewSale;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDiscard;

  const QuickSalesParkedSalesBar({
    super.key,
    required this.sales,
    required this.compact,
    required this.enabled,
    required this.newSaleEnabled,
    required this.newSaleLabel,
    required this.newSaleTooltip,
    required this.discardTooltip,
    required this.onNewSale,
    required this.onSelect,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final barHeight = compact ? 56.0 : 64.0;

    return Material(
      color: cs.surfaceContainerLow,
      child: SizedBox(
        height: barHeight + (compact ? 8 : 12),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: compact ? 8 : 12,
            end: compact ? 8 : 12,
            top: compact ? 4 : 6,
            bottom: compact ? 4 : 6,
          ),
          child: Row(
            children: [
              _NewSaleButton(
                compact: compact,
                enabled: enabled && newSaleEnabled,
                label: newSaleLabel,
                tooltip: newSaleTooltip,
                onPressed: enabled && newSaleEnabled ? onNewSale : null,
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: sales.length,
                  separatorBuilder: (context, _) => SizedBox(width: compact ? 6 : 8),
                  itemBuilder: (context, index) {
                    final sale = sales[index];
                    return _ParkedSaleChip(
                      data: sale,
                      compact: compact,
                      enabled: enabled,
                      discardTooltip: discardTooltip,
                      onSelect: () => onSelect(sale.id),
                      onDiscard: sale.showDiscard ? () => onDiscard(sale.id) : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewSaleButton extends StatelessWidget {
  final bool compact;
  final bool enabled;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  const _NewSaleButton({
    required this.compact,
    required this.enabled,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final button = compact
        ? IconButton.filledTonal(
            onPressed: onPressed,
            icon: const Icon(Icons.add),
            visualDensity: VisualDensity.compact,
          )
        : FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: const Icon(Icons.add, size: 20),
            label: Text(label),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          );
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: button,
      ),
    );
  }
}

class _ParkedSaleChip extends StatelessWidget {
  final QuickSalesParkedSaleChipData data;
  final bool compact;
  final bool enabled;
  final String discardTooltip;
  final VoidCallback onSelect;
  final VoidCallback? onDiscard;

  const _ParkedSaleChip({
    required this.data,
    required this.compact,
    required this.enabled,
    required this.discardTooltip,
    required this.onSelect,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final active = data.isActive;
    final bg = active ? cs.primaryContainer : cs.surface;
    final fg = active ? cs.onPrimaryContainer : cs.onSurface;
    final border = active ? cs.primary : cs.outlineVariant;

    return Tooltip(
      message: '${data.title}\n${data.subtitle}',
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: bg,
        elevation: active ? 1 : 0,
        shadowColor: cs.shadow.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: active ? 1.5 : 1),
        ),
        child: InkWell(
          onTap: enabled && !active ? onSelect : null,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: compact ? 168 : 196,
            padding: EdgeInsetsDirectional.only(
              start: compact ? 8 : 10,
              end: onDiscard != null ? 0 : (compact ? 8 : 10),
              top: 6,
              bottom: 6,
            ),
            child: Row(
              children: [
                _SaleAvatar(
                  initial: data.customerInitial,
                  isBlank: data.isBlank,
                  isActive: active,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: fg,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: fg.withValues(alpha: 0.78),
                          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                          height: 1.1,
                          fontSize: compact ? 11 : 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onDiscard != null)
                  IconButton(
                    tooltip: discardTooltip,
                    onPressed: enabled ? onDiscard : null,
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: fg.withValues(alpha: 0.7),
                    ),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SaleAvatar extends StatelessWidget {
  final String? initial;
  final bool isBlank;
  final bool isActive;

  const _SaleAvatar({
    required this.initial,
    required this.isBlank,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = isActive ? cs.primary : cs.secondaryContainer;
    final fg = isActive ? cs.onPrimary : cs.onSecondaryContainer;
    final letter = initial?.trim();
    final Widget child;
    if (letter != null && letter.isNotEmpty) {
      child = Text(
        String.fromCharCode(letter.runes.first),
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      );
    } else {
      child = Icon(
        isBlank ? Icons.add_shopping_cart_outlined : Icons.person_outline,
        size: 16,
        color: fg,
      );
    }
    return CircleAvatar(
      radius: 14,
      backgroundColor: bg,
      child: child,
    );
  }
}
