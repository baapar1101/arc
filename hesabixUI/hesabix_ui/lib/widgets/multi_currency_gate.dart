import 'package:flutter/material.dart';

/// نمایش محتوا فقط وقتی کسب‌وکار چندارزی است.
class MultiCurrencyGate extends StatelessWidget {
  const MultiCurrencyGate({
    super.key,
    required this.isMultiCurrency,
    required this.child,
    this.singleCurrencyChild = const SizedBox.shrink(),
  });

  final bool isMultiCurrency;
  final Widget child;
  final Widget singleCurrencyChild;

  @override
  Widget build(BuildContext context) {
    return isMultiCurrency ? child : singleCurrencyChild;
  }
}
