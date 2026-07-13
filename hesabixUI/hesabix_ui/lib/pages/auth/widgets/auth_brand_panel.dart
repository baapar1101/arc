import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// پنل برند سمت چپ (دسکتاپ) — storytelling و trust signals.
class AuthBrandPanel extends StatelessWidget {
  final String logoAsset;

  const AuthBrandPanel({super.key, required this.logoAsset});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: isDark
              ? [
                  scheme.primary.withValues(alpha: 0.25),
                  scheme.surfaceContainerHighest,
                ]
              : [
                  scheme.primaryContainer.withValues(alpha: 0.6),
                  scheme.primary.withValues(alpha: 0.08),
                ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(logoAsset, height: 48),
            const SizedBox(height: 32),
            Text(
              t.welcomeTitle,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              t.welcomeSubtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.6,
                  ),
            ),
            const SizedBox(height: 32),
            Text(
              t.brandTagline,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 40),
            ..._trustItems(context, t),
          ],
        ),
      ),
    );
  }

  List<Widget> _trustItems(BuildContext context, AppLocalizations t) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      (Icons.cloud_done_outlined, t.authTrustCloud),
      (Icons.lock_outline_rounded, t.authTrustEncrypted),
      (Icons.support_agent_outlined, t.authTrustSupport),
    ];

    return items
        .map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(e.$1, size: 20, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    e.$2,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }
}
