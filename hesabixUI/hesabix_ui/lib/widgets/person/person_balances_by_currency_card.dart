import 'package:flutter/material.dart';
import 'package:hesabix_ui/utils/currency_display_utils.dart';
import 'package:hesabix_ui/widgets/multi_currency_gate.dart';

/// کارت مانده شخص به تفکیک ارز — فقط وقتی MC=ON و بیش از یک ارز یا ارز غیرپایه.
class PersonBalancesByCurrencyCard extends StatelessWidget {
  const PersonBalancesByCurrencyCard({
    super.key,
    required this.isMultiCurrency,
    required this.payload,
    this.loading = false,
    this.error,
  });

  final bool isMultiCurrency;
  final Map<String, dynamic>? payload;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return MultiCurrencyGate(
      isMultiCurrency: isMultiCurrency,
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
      );
    }
    final balances = (payload?['balances'] as List?) ?? const [];
    if (balances.isEmpty) return const SizedBox.shrink();

    // تک‌ردیفی با ارز پایه: نیازی به کارت جدا نیست (تراز هدر کافی است)
    if (balances.length == 1) {
      final only = Map<String, dynamic>.from(balances.first as Map);
      if (only['is_base_currency'] == true) return const SizedBox.shrink();
    }

    final totalBase = (payload?['total_base'] as num?)?.toDouble() ?? 0;
    final status = personBalanceStatusLabel(payload?['status']?.toString());
    final baseUnit = () {
      for (final raw in balances) {
        final b = Map<String, dynamic>.from(raw as Map);
        if (b['is_base_currency'] == true) {
          return (b['currency_symbol'] ?? b['currency_code'] ?? 'ریال').toString();
        }
      }
      return 'ریال';
    }();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.currency_exchange, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'مانده به تفکیک ارز',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...balances.map((raw) {
                final b = Map<String, dynamic>.from(raw as Map);
                final code = (b['currency_code'] ?? b['currency_symbol'] ?? '').toString();
                final unit = (b['currency_symbol'] ?? b['currency_code'] ?? code).toString();
                final bal = (b['balance'] as num?)?.toDouble() ?? 0;
                final baseEq = (b['base_equivalent'] as num?)?.toDouble() ?? 0;
                final dp = (b['decimal_places'] as num?)?.toInt() ?? 2;
                final st = (b['status'] ?? '').toString();
                final isBase = b['is_base_currency'] == true;
                final line = formatPersonCurrencyBalanceLine(
                  balance: bal,
                  currencyUnit: unit,
                  status: st,
                  baseEquivalent: baseEq,
                  baseUnit: baseUnit,
                  isBaseCurrency: isBase,
                  balanceDecimalPlaces: dp,
                  baseDecimalPlaces: 0,
                );
                final stLabel = personBalanceStatusLabel(st);
                Color? accent;
                if (stLabel == 'بدهکار') {
                  accent = theme.colorScheme.error;
                } else if (stLabel == 'بستانکار') {
                  accent = const Color(0xFF2E7D32);
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isBase ? 'پایه' : code,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          line,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(height: 18),
              Text(
                'جمع معادل پایه: ${formatAmountWithCurrencyUnit(totalBase, unit: baseUnit, decimalPlaces: 0)}'
                '${status.isNotEmpty ? ' — $status' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                'معادل ریالی بر اساس نرخ مرجع ثبت‌شده در اسناد محاسبه شده است.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
