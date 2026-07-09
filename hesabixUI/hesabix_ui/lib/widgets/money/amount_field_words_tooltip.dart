import 'package:flutter/material.dart';

import 'package:hesabix_ui/utils/amount_to_words.dart';

/// در دسکتاپ با hover و در موبایل با long-press، معادل نوشتاری مبلغ را نشان می‌دهد.
class AmountFieldWordsTooltip extends StatefulWidget {
  final Widget child;
  final TextEditingController controller;
  final String currencyUnit;

  const AmountFieldWordsTooltip({
    super.key,
    required this.child,
    required this.controller,
    this.currencyUnit = 'ریال',
  });

  @override
  State<AmountFieldWordsTooltip> createState() => _AmountFieldWordsTooltipState();
}

class _AmountFieldWordsTooltipState extends State<AmountFieldWordsTooltip> {
  String? _tooltipMessage;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = _computeMessage();
    if (next != _tooltipMessage) {
      _tooltipMessage = next;
    }
  }

  @override
  void didUpdateWidget(covariant AmountFieldWordsTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _tooltipMessage = _computeMessage();
    } else if (oldWidget.currencyUnit != widget.currencyUnit) {
      _tooltipMessage = _computeMessage();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final next = _computeMessage();
    if (next != _tooltipMessage) {
      setState(() => _tooltipMessage = next);
    }
  }

  String? _computeMessage() {
    final locale = Localizations.localeOf(context);
    final persian = locale.languageCode.toLowerCase().startsWith('fa');
    return amountFormattedInputToWords(
      widget.controller.text,
      usePersian: persian,
      currencyUnit: widget.currencyUnit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // پیام خالی را با فاصلهٔ نامرئی نگه می‌داریم تا ساختار Tooltip ثابت بماند.
    final tooltipText = (_tooltipMessage == null || _tooltipMessage!.isEmpty)
        ? '\u200b'
        : _tooltipMessage!;

    return TooltipTheme(
      data: TooltipThemeData(
        decoration: BoxDecoration(
          color: theme.colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        textStyle: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onInverseSurface,
          height: 1.4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        waitDuration: const Duration(milliseconds: 380),
        showDuration: const Duration(seconds: 14),
      ),
      child: Tooltip(
        message: tooltipText,
        verticalOffset: 10,
        excludeFromSemantics: true,
        child: widget.child,
      ),
    );
  }
}
