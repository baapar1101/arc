import 'package:flutter/material.dart';

import '../../widgets/multi_currency_gate.dart';
import '../../utils/number_formatters.dart';
import '../../utils/number_normalizer.dart';

/// نمایش جمع دوگانه فاکتور ارزی (ارز سند + معادل پایه) — فقط وقتی MC=ON و showDual.
class InvoiceFxDualTotalsBanner extends StatelessWidget {
  const InvoiceFxDualTotalsBanner({
    super.key,
    required this.isMultiCurrency,
    required this.showDual,
    required this.foreignPayable,
    required this.basePayable,
    required this.rate,
    required this.foreignCurrencyLabel,
    required this.baseCurrencyLabel,
    required this.foreignDecimalPlaces,
    required this.baseDecimalPlaces,
  });

  final bool isMultiCurrency;
  final bool showDual;
  final double foreignPayable;
  final double basePayable;
  final double rate;
  final String foreignCurrencyLabel;
  final String baseCurrencyLabel;
  final int foreignDecimalPlaces;
  final int baseDecimalPlaces;

  @override
  Widget build(BuildContext context) {
    return MultiCurrencyGate(
      isMultiCurrency: isMultiCurrency,
      child: (!showDual)
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'معادل ارز پایه',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${formatWithThousands(foreignPayable, decimalPlaces: foreignDecimalPlaces)} $foreignCurrencyLabel'
                        '  ≈  '
                        '${formatWithThousands(basePayable, decimalPlaces: baseDecimalPlaces)} $baseCurrencyLabel',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'نرخ: ${formatWithThousands(rate, decimalPlaces: baseDecimalPlaces > 0 ? 4 : 0)}'
                        ' ($baseCurrencyLabel / $foreignCurrencyLabel)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  /// ساخت از پاسخ API (`fx_totals` + `base_currency`).
  static InvoiceFxDualTotalsBanner? fromInvoicePayload({
    required bool isMultiCurrency,
    required Map<String, dynamic>? fxTotals,
    required Map<String, dynamic>? baseCurrency,
    required String foreignCurrencyLabel,
    required int foreignDecimalPlaces,
  }) {
    if (!isMultiCurrency || fxTotals == null) return null;
    final showDual = fxTotals['show_dual'] == true;
    if (!showDual) return null;
    final foreign = fxTotals['foreign'];
    final base = fxTotals['base'];
    if (foreign is! Map || base is! Map) return null;

    final foreignPayable = parseJsonDoubleOrNull(foreign['payable']) ??
        parseJsonDoubleOrNull(foreign['net']) ??
        0.0;
    final basePayable = parseJsonDoubleOrNull(base['payable']) ??
        parseJsonDoubleOrNull(base['net']) ??
        0.0;
    final rate = parseJsonDoubleOrNull(base['rate']) ?? 0.0;
    final baseLabel = (baseCurrency?['code'] as String?) ??
        (baseCurrency?['symbol'] as String?) ??
        (baseCurrency?['title'] as String?) ??
        'BASE';
    final baseDp = (baseCurrency?['decimal_places'] as num?)?.toInt() ?? 0;

    return InvoiceFxDualTotalsBanner(
      isMultiCurrency: isMultiCurrency,
      showDual: true,
      foreignPayable: foreignPayable,
      basePayable: basePayable,
      rate: rate,
      foreignCurrencyLabel: foreignCurrencyLabel,
      baseCurrencyLabel: baseLabel,
      foreignDecimalPlaces: foreignDecimalPlaces,
      baseDecimalPlaces: baseDp,
    );
  }
}
