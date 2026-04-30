import 'package:flutter/material.dart';

import 'package:hesabix_ui/utils/amount_to_words.dart';

/// در دسکتاپ با hover و در موبایل با long-press، معادل نوشتاری مبلغ را نشان می‌دهد.
class AmountFieldWordsTooltip extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final persian = locale.languageCode.toLowerCase().startsWith('fa');

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final msg = amountFormattedInputToWords(
          controller.text,
          usePersian: persian,
          currencyUnit: currencyUnit,
        );
        final theme = Theme.of(context);
        // همیشه همان عمق درخت را نگه می‌داریم؛ عوض کردن والد مستقیم TextField باعث پرت شدن فوکوس می‌شد.
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
            message: msg ?? '',
            verticalOffset: 10,
            excludeFromSemantics: msg == null || msg.isEmpty,
            child: child,
          ),
        );
      },
    );
  }
}
