import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'ai_chat_design.dart';

/// بنر بازیابی پس از خطای استریم AI.
class AIErrorRecoveryBanner extends StatelessWidget {
  final String message;
  final bool recoverable;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  const AIErrorRecoveryBanner({
    super.key,
    required this.message,
    this.recoverable = false,
    this.onRetry,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      elevation: 0,
      color: scheme.errorContainer.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.aiErrorRecoveryTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
            if (recoverable && onRetry != null)
              FilledButton.tonal(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(l10n.aiErrorRecoveryRetry),
              ),
            if (onDismiss != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onDismiss,
                child: Text(l10n.aiErrorRecoveryDismiss),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
