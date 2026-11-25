import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../utils/quick_sales_pinned_products.dart';

class QuickSalesProductChipStrip extends StatelessWidget {
  final List<Map<String, dynamic>> pinnedProducts;
  final List<Map<String, dynamic>> recentProducts;
  final bool showRecents;
  final bool compact;
  final int? loadingProductId;
  final int? pinningProductId;
  final String Function(Map<String, dynamic> product) formatPrice;
  final ValueChanged<Map<String, dynamic>> onAdd;
  final ValueChanged<Map<String, dynamic>> onPin;
  final ValueChanged<Map<String, dynamic>> onUnpin;

  const QuickSalesProductChipStrip({
    super.key,
    required this.pinnedProducts,
    required this.recentProducts,
    required this.showRecents,
    required this.compact,
    required this.formatPrice,
    required this.onAdd,
    required this.onPin,
    required this.onUnpin,
    this.loadingProductId,
    this.pinningProductId,
  });

  @override
  Widget build(BuildContext context) {
    final recents = showRecents
        ? recentProductsExcludingPinned(
            recentProducts: recentProducts,
            pinnedProducts: pinnedProducts,
          )
        : const <Map<String, dynamic>>[];
    if (pinnedProducts.isEmpty && recents.isEmpty) {
      return const SizedBox.shrink();
    }

    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final title = pinnedProducts.isNotEmpty && recents.isNotEmpty
        ? t.quickSalesPinnedAndRecentTitle
        : pinnedProducts.isNotEmpty
        ? t.quickSalesPinnedProductsTitle
        : t.quickSalesRecentProductsTitle;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: 8,
      ),
      color: cs.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                pinnedProducts.isNotEmpty
                    ? Icons.push_pin
                    : Icons.history,
                size: 18,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...pinnedProducts.map(
                  (product) => _Chip(
                    product: product,
                    pinned: true,
                    colorScheme: cs,
                    loading: loadingProductId == quickSalesProductIntId(product),
                    pinning: pinningProductId == quickSalesProductIntId(product),
                    priceText: formatPrice(product),
                    pinTooltip: t.quickSalesUnpinProduct,
                    onAdd: () => onAdd(product),
                    onTogglePin: () => onUnpin(product),
                  ),
                ),
                ...recents.map(
                  (product) => _Chip(
                    product: product,
                    pinned: false,
                    colorScheme: cs,
                    loading: loadingProductId == quickSalesProductIntId(product),
                    pinning: pinningProductId == quickSalesProductIntId(product),
                    priceText: formatPrice(product),
                    pinTooltip: t.quickSalesPinProduct,
                    onAdd: () => onAdd(product),
                    onTogglePin: () => onPin(product),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final Map<String, dynamic> product;
  final bool pinned;
  final ColorScheme colorScheme;
  final bool loading;
  final bool pinning;
  final String priceText;
  final String pinTooltip;
  final VoidCallback onAdd;
  final VoidCallback onTogglePin;

  const _Chip({
    required this.product,
    required this.pinned,
    required this.colorScheme,
    required this.loading,
    required this.pinning,
    required this.priceText,
    required this.pinTooltip,
    required this.onAdd,
    required this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InkWell(
        onTap: loading || pinning ? null : onAdd,
        onLongPress: loading || pinning ? null : onTogglePin,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsetsDirectional.only(
            start: 12,
            end: 4,
            top: 8,
            bottom: 8,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: pinned || loading
                  ? colorScheme.primary
                  : colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 80,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product['name']?.toString() ?? '—',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            priceText,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: pinning
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              tooltip: pinTooltip,
                              padding: EdgeInsets.zero,
                              iconSize: 16,
                              onPressed: onTogglePin,
                              icon: Icon(
                                pinned ? Icons.push_pin : Icons.push_pin_outlined,
                                color: pinned
                                    ? colorScheme.primary
                                    : colorScheme.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
