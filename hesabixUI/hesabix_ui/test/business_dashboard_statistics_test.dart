import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/business_dashboard_models.dart';
import 'package:hesabix_ui/utils/currency_display_utils.dart';

void main() {
  test('BusinessStatistics parses currency unit for launcher sales', () {
    final stats = BusinessStatistics.fromJson({
      'total_sales': 14900000,
      'total_purchases': 150,
      'active_members': 3,
      'recent_transactions': 2,
      'fiscal_year_id': 9,
      'currency': {
        'id': 1,
        'code': 'IRR',
        'title': 'ریال',
        'symbol': 'ریال',
        'decimal_places': 0,
      },
    });

    expect(stats.totalSales, 14900000);
    expect(stats.recentTransactions, 2);
    expect(stats.fiscalYearId, 9);
    expect(stats.currency?.code, 'IRR');
    expect(stats.currency?.decimalPlaces, 0);

    final unit = currencyUnitLabelFromBusinessCurrencyMap(
      stats.currency!.toUnitMap(),
      fallback: '',
    );
    expect(
      formatAmountWithCurrencyUnit(
        stats.totalSales,
        unit: unit,
        decimalPlaces: stats.currency!.decimalPlaces,
      ),
      '14,900,000 ریال',
    );
  });

  test('BusinessStatistics keeps USD decimals and symbol', () {
    final stats = BusinessStatistics.fromJson({
      'total_sales': 1234.5,
      'total_purchases': 0,
      'active_members': 1,
      'recent_transactions': 4,
      'currency': {
        'id': 2,
        'code': 'USD',
        'title': 'US Dollar',
        'symbol': r'$',
        'decimal_places': 2,
      },
    });

    expect(stats.currency?.symbol, r'$');
    expect(
      formatAmountWithCurrencyUnit(
        stats.totalSales,
        unit: stats.currency!.symbol,
        decimalPlaces: stats.currency!.decimalPlaces,
      ),
      r'1,234.50 $',
    );
  });
}
