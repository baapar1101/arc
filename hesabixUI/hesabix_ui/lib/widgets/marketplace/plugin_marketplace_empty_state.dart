import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class PluginMarketplaceEmptyState extends StatelessWidget {
  final bool myPluginsTab;
  final VoidCallback? onRefresh;

  const PluginMarketplaceEmptyState({
    super.key,
    required this.myPluginsTab,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                myPluginsTab ? Icons.extension_off_outlined : Icons.storefront_outlined,
                size: 64,
                color: cs.outline,
              ),
              const SizedBox(height: 16),
              Text(
                myPluginsTab ? t.pluginMarketplaceMyEmpty : t.pluginMarketplaceEmpty,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (onRefresh != null) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(t.pluginMarketplaceRefresh),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
