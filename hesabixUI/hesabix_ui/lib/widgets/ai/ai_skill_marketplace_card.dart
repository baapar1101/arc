import 'package:flutter/material.dart';

import 'ai_chat_design.dart';

/// کارت مهارت برای مارکت‌پلیس و لیست‌های مهارت.
class AISkillMarketplaceCard extends StatelessWidget {
  final String title;
  final String description;
  final String priceLabel;
  final bool isOfficial;
  final bool isPurchased;
  final bool busy;
  final VoidCallback? onInstall;
  final IconData leadingIcon;

  const AISkillMarketplaceCard({
    super.key,
    required this.title,
    required this.description,
    required this.priceLabel,
    this.isOfficial = false,
    this.isPurchased = false,
    this.busy = false,
    this.onInstall,
    this.leadingIcon = Icons.extension_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isFree = priceLabel == 'رایگان';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AIChatDesign.elevatedCard(theme, alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(leadingIcon, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Badge(
                  label: priceLabel,
                  color: isPurchased
                      ? scheme.secondary
                      : isFree
                          ? scheme.primary
                          : scheme.tertiary,
                ),
                if (isOfficial) ...[
                  const SizedBox(width: 6),
                  _Badge(label: 'رسمی', color: scheme.primary),
                ],
                const Spacer(),
                FilledButton.tonal(
                  onPressed: busy || isPurchased ? null : onInstall,
                  child: Text(isPurchased ? 'نصب‌شده' : 'نصب'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
