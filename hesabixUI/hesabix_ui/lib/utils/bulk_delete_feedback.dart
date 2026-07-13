import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'snackbar_helper.dart';

class BulkDeleteResult {
  final int deleted;
  final int skipped;
  final List<String> errors;

  const BulkDeleteResult({
    required this.deleted,
    required this.skipped,
    required this.errors,
  });

  factory BulkDeleteResult.fromResponseBody(Map<String, dynamic>? body) {
    final data = body?['data'] as Map<String, dynamic>? ?? const {};
    final errors = (data['errors'] as List<dynamic>? ?? const [])
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();

    return BulkDeleteResult(
      deleted: (data['deleted'] as num?)?.toInt() ?? 0,
      skipped: (data['skipped'] as num?)?.toInt() ?? 0,
      errors: errors,
    );
  }
}

class BulkDeleteFeedback {
  static const int inlineErrorLimit = 3;

  static Future<void> show(
    BuildContext context,
    AppLocalizations t, {
    required BulkDeleteResult result,
    required String allDeletedMessage,
  }) async {
    if (result.deleted > 0 && result.skipped == 0) {
      SnackBarHelper.showSuccess(context, message: allDeletedMessage);
      return;
    }

    if (result.skipped > 0) {
      final sample = result.errors.take(inlineErrorLimit).join('؛ ');
      final hasSample = sample.isNotEmpty;

      if (result.deleted > 0) {
        final message = hasSample
            ? t.bulkDeletePartialWithSample(result.deleted, result.skipped, sample)
            : t.bulkDeletePartialSnack(result.deleted, result.skipped);
        SnackBarHelper.showWarning(context, message: message);
      } else {
        final message = hasSample
            ? t.bulkDeleteFailedWithSample(sample)
            : t.bulkDeleteFailedSnack;
        SnackBarHelper.showError(context, message: message);
      }

      if (result.skipped > inlineErrorLimit) {
        if (!context.mounted) return;
        await showDetailsDialog(context, t, result);
      }
      return;
    }

    SnackBarHelper.showSuccess(context, message: allDeletedMessage);
  }

  static Future<void> showDetailsDialog(
    BuildContext context,
    AppLocalizations t,
    BulkDeleteResult result,
  ) async {
    if (!context.mounted) return;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(t.bulkDeleteResultTitle)),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow(
                  t.bulkDeleteDeletedLabel,
                  '${result.deleted}',
                  colorScheme.primary,
                ),
                const SizedBox(height: 8),
                _summaryRow(
                  t.bulkDeleteSkippedLabel,
                  '${result.skipped}',
                  colorScheme.error,
                ),
                if (result.errors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    t.bulkDeleteSkippedDetails,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...result.errors.map(
                    (error) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• $error',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t.close),
          ),
        ],
      ),
    );
  }

  static Widget _summaryRow(String label, String value, Color color) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(width: 8),
        Text(value),
      ],
    );
  }
}
