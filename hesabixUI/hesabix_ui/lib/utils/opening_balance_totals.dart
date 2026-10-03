class OpeningBalanceTotals {
  final double debit;
  final double credit;

  const OpeningBalanceTotals({required this.debit, required this.credit});

  double get difference => debit - credit;
}

OpeningBalanceTotals applyOpeningBalanceAutoBalance({
  required double debit,
  required double credit,
  required bool autoBalanceEnabled,
  required bool hasEquityAccount,
}) {
  if (!autoBalanceEnabled || !hasEquityAccount) {
    return OpeningBalanceTotals(debit: debit, credit: credit);
  }

  final difference = debit - credit;
  if (difference > 0) {
    credit += difference;
  } else if (difference < 0) {
    debit += -difference;
  }

  return OpeningBalanceTotals(debit: debit, credit: credit);
}
