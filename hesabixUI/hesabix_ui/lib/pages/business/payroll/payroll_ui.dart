import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../utils/number_formatters.dart' show formatWithThousands;
import '../../../utils/number_normalizer.dart'
    show EnglishDigitsFormatter, ThousandsSeparatorInputFormatter, formatNumberForInput, parseFormattedDouble, parseFormattedInt;

/// اجزای UI مشترک افزونه حقوق و دستمزد.
class PayrollUi {
  PayrollUi._();

  static const double cardRadius = 16;
  static const double dialogRadius = 20;
  static const EdgeInsets pagePadding = EdgeInsets.all(16);

  /// نمایش مبالغ و اعداد بزرگ با جداکننده هزارگان.
  static String formatMoney(dynamic value) {
    if (value == null || (value is String && value.trim().isEmpty)) return '-';
    return formatWithThousands(value);
  }

  /// نمایش شمارنده‌ها (تعداد پرسنل، خطاها و …) با جداکننده هزارگان.
  static String formatCount(dynamic value) => formatMoney(value);

  /// مقدار اولیه فیلدهای عددی قابل ویرایش.
  static String formatInputValue(dynamic value, {bool allowDecimal = true}) {
    if (value == null) return '';
    num? n;
    if (value is num) {
      n = value;
    } else {
      n = allowDecimal ? parseFormattedDouble('$value') : parseFormattedInt('$value');
    }
    if (n == null) return '';
    return formatNumberForInput(n);
  }

  static List<TextInputFormatter> numericInputFormatters({bool allowDecimal = true}) => [
        const EnglishDigitsFormatter(),
        ThousandsSeparatorInputFormatter(allowDecimal: allowDecimal),
      ];

  static double? parseMoneyInput(String? text) => parseFormattedDouble(text);

  static double? parseDecimalInput(String? text) => parseFormattedDouble(text);

  static int? parseIntInput(String? text) => parseFormattedInt(text);

  static InputDecoration fieldDecoration(
    BuildContext context,
    String label, {
    IconData? prefixIcon,
    String? hint,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20) : null,
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  static String runStatusLabel(AppLocalizations t, String? status) {
    switch (status) {
      case 'draft':
        return t.payrollStatusDraft;
      case 'finalized':
        return t.payrollStatusFinalized;
      case 'pending_approval':
        return t.payrollStatusPendingApproval;
      case 'approved':
        return t.payrollStatusApproved;
      case 'posted':
        return t.payrollStatusPosted;
      case 'cancelled':
        return t.payrollStatusCancelled;
      default:
        return status ?? '';
    }
  }

  static String periodStatusLabel(AppLocalizations t, String? status) {
    if (status == 'closed') return t.payrollPeriodStatusClosed;
    return t.payrollPeriodStatusOpen;
  }

  static String itemKindLabel(AppLocalizations t, String? kind) {
    switch (kind) {
      case 'earning':
        return t.payrollItemKindEarning;
      case 'deduction':
        return t.payrollItemKindDeduction;
      case 'employer_cost':
        return t.payrollItemKindEmployerCost;
      default:
        return kind ?? '';
    }
  }

  static Color runStatusColor(BuildContext context, String? status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case 'draft':
        return cs.outline;
      case 'pending_approval':
        return cs.tertiary;
      case 'approved':
      case 'finalized':
        return cs.primary;
      case 'posted':
        return Colors.green.shade700;
      case 'cancelled':
        return cs.error;
      default:
        return cs.outline;
    }
  }

  static Widget dialogShell({
    required BuildContext context,
    required String title,
    IconData? icon,
    Color? iconColor,
    required Widget child,
    required List<Widget> actions,
    double maxWidth = 520,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = iconColor ?? cs.primary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(dialogRadius)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35))),
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: child,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<T?> showFormDialog<T>({
    required BuildContext context,
    required String title,
    IconData? icon,
    Color? iconColor,
    required Widget content,
    required List<Widget> Function(BuildContext dialogContext) actionsBuilder,
    double maxWidth = 520,
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => dialogShell(
        context: ctx,
        title: title,
        icon: icon,
        iconColor: iconColor,
        maxWidth: maxWidth,
        child: content,
        actions: actionsBuilder(ctx),
      ),
    );
  }

  static Future<bool?> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String message,
    IconData icon = Icons.help_outline,
    Color? iconColor,
    String? confirmLabel,
    bool destructive = false,
  }) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final accent = iconColor ?? (destructive ? cs.error : cs.primary);

    return showFormDialog<bool>(
      context: context,
      title: title,
      icon: icon,
      iconColor: accent,
      maxWidth: 440,
      content: Text(message, style: Theme.of(context).textTheme.bodyLarge),
      actionsBuilder: (dialogCtx) => [
        TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: Text(t.cancel)),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: cs.error) : null,
          onPressed: () => Navigator.pop(dialogCtx, true),
          child: Text(confirmLabel ?? t.confirm),
        ),
      ],
    );
  }

  static Widget sectionCard({
    required BuildContext context,
    required String title,
    IconData? icon,
    Widget? trailing,
    required Widget child,
    EdgeInsets? padding,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  static Widget formSection({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    return sectionCard(
      context: context,
      title: title,
      icon: Icons.tune_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ],
      ),
    );
  }

  static Widget statCard({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  static Widget listTileCard({
    required BuildContext context,
    required Widget leading,
    required Widget title,
    Widget? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? accentColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final accent = accentColor ?? cs.primary;
    return Material(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(cardRadius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(cardRadius),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: leading,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle(style: Theme.of(context).textTheme.titleSmall!, child: title),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      DefaultTextStyle(
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                        child: subtitle,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
        ),
      ),
    );
  }

  static Widget statusChip(BuildContext context, String label, {Color? color, IconData? icon}) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  static Widget kindChip(BuildContext context, String label, String? kind) {
    final cs = Theme.of(context).colorScheme;
    Color color;
    switch (kind) {
      case 'earning':
        color = Colors.green.shade700;
      case 'deduction':
        color = cs.error;
      case 'employer_cost':
        color = cs.tertiary;
      default:
        color = cs.outline;
    }
    return statusChip(context, label, color: color);
  }

  static Widget emptyState({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: cs.primary),
            ),
            const SizedBox(height: 20),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action],
          ],
        ),
      ),
    );
  }

  static Widget toolbar({
    required List<Widget> actions,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: actions,
      ),
    );
  }

  static Widget actionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    bool filled = false,
  }) {
    if (filled) {
      return FilledButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label));
    }
    return OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label));
  }

  static Widget infoBanner({
    required BuildContext context,
    required String message,
    IconData icon = Icons.info_outline,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? cs.primaryContainer.withValues(alpha: 0.45);
    final fg = foregroundColor ?? cs.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: fg))),
        ],
      ),
    );
  }

  static Widget bottomActionBar({required List<Widget> children}) {
    return Material(
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: children),
        ),
      ),
    );
  }

  static Widget loadingOverlay({bool visible = true}) {
    if (!visible) return const SizedBox.shrink();
    return const Center(child: CircularProgressIndicator());
  }

  static Widget importStepCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onPressed,
    String? buttonLabel,
    bool selected = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? cs.primaryContainer.withValues(alpha: 0.25) : cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? cs.primary.withValues(alpha: 0.5) : cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (buttonLabel != null)
            TextButton(onPressed: onPressed, child: Text(buttonLabel)),
        ],
      ),
    );
  }
}
