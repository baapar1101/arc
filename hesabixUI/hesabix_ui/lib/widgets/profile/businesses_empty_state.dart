import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../utils/responsive_helper.dart';
import 'legacy_import_wizard.dart';

class BusinessesEmptyState extends StatelessWidget {
  final bool noSearchResults;
  final String? searchQuery;
  final VoidCallback? onClearSearch;

  const BusinessesEmptyState({
    super.key,
    this.noSearchResults = false,
    this.searchQuery,
    this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isMobile = ResponsiveHelper.isMobile(context);
    final padding = ResponsiveHelper.getPadding(context) * 2;

    if (noSearchResults) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off_rounded, size: 40, color: cs.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  t.businessesHubNoSearchResults,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (searchQuery != null && searchQuery!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    t.businessesHubNoSearchResultsFor(searchQuery!),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
                if (onClearSearch != null) ...[
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: onClearSearch,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: Text(t.businessesHubClearSearch),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(padding),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.storefront_outlined, size: 48, color: cs.primary.withValues(alpha: 0.85)),
              const SizedBox(height: 20),
              Text(
                t.businessesHubEmptyTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                t.businessesHubEmptySubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => context.go('/user/profile/new-business'),
                style: FilledButton.styleFrom(
                  minimumSize: Size(isMobile ? double.infinity : 200, 48),
                ),
                child: Text(t.createFirstBusiness),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => LegacyImportWizard.show(context),
                child: Text(t.businessesHubImportLegacy),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
