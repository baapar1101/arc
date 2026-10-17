num quickSalesPaymentTarget({
  required num invoiceTotal,
  required num customerBalance,
  required bool applyBalance,
}) {
  if (!applyBalance) return invoiceTotal;
  if (customerBalance < 0) return invoiceTotal + customerBalance.abs();
  final target = invoiceTotal - customerBalance;
  return target > 0 ? target : 0;
}

String quickSalesCustomerBalanceStatus(num balance) {
  if (balance > 0) return 'بستانکار';
  if (balance < 0) return 'بدهکار';
  return 'تسویه';
}
