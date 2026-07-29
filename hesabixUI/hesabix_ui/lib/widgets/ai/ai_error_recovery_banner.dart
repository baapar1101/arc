import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'ai_chat_design.dart';

/// بنر بازیابی پس از خطای استریم AI.
class AIErrorRecoveryBanner extends StatelessWidget {
  final String message;
  final bool recoverable;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;
  final bool inline;

  const AIErrorRecoveryBanner({
    super.key,
    required this.message,
    this.recoverable = false,
    this.onRetry,
    this.onDismiss,
    this.inline = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (inline) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AIChatDesign.contentMaxWidth),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.error.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: scheme.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                  if (recoverable && onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(l10n.aiErrorRecoveryRetry),
                    ),
                  if (onDismiss != null)
                    IconButton(
                      tooltip: l10n.aiErrorRecoveryDismiss,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: onDismiss,
                      icon: Icon(Icons.close_rounded, size: 16, color: scheme.outline),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

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

/// خط هشدار اعتبار — زیر composer.
class AIChatCreditHint extends StatelessWidget {
  final String message;
  final VoidCallback? onUpgrade;

  const AIChatCreditHint({
    super.key,
    required this.message,
    this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AIChatDesign.contentMaxWidth),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: scheme.tertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onUpgrade != null)
                TextButton(
                  onPressed: onUpgrade,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('ارتقا'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
