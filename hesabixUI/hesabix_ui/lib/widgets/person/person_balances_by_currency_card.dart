import 'package:flutter/material.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
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
    final status = payload?['status']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'مانده به تفکیک ارز',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...balances.map((raw) {
                final b = Map<String, dynamic>.from(raw as Map);
                final code = (b['currency_code'] ?? b['currency_symbol'] ?? '').toString();
                final bal = (b['balance'] as num?)?.toDouble() ?? 0;
                final baseEq = (b['base_equivalent'] as num?)?.toDouble() ?? 0;
                final dp = (b['decimal_places'] as num?)?.toInt() ?? 2;
                final st = (b['status'] ?? '').toString();
                final isBase = b['is_base_currency'] == true;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          isBase ? '$code (پایه)' : code,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${formatWithThousands(bal, decimalPlaces: dp)} ($st)',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (!isBase) ...[
                        const SizedBox(width: 8),
                        Text(
                          '≈ ${formatWithThousands(baseEq, decimalPlaces: 0)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
              const Divider(height: 16),
              Text(
                'جمع معادل پایه: ${formatWithThousands(totalBase, decimalPlaces: 0)}'
                '${status.isNotEmpty ? ' — $status' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
