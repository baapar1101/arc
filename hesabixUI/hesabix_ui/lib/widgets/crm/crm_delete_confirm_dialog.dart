import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// تأیید حذف یکسان برای ماژول CRM (آیکن، هشدار ثانویه، دکمهٔ خطر).
Future<bool?> showCrmDeleteConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? irreversibleOverride,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final t = AppLocalizations.of(ctx);
      final warn = irreversibleOverride ?? t.crmDeleteIrreversible;
      return AlertDialog(
        icon: Icon(Icons.delete_outline, color: theme.colorScheme.error, size: 28),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            Text(
              warn,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.crmNotesDelete),
          ),
        ],
      );
    },
  );
}
