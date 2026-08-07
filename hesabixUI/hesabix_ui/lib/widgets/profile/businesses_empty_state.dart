import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../utils/responsive_helper.dart';
import 'legacy_import_wizard.dart';

class BusinessesEmptyState extends StatelessWidget {
  final bool noSearchResults;
  final String? searchQuery;

  const BusinessesEmptyState({
    super.key,
    this.noSearchResults = false,
    this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isMobile = ResponsiveHelper.isMobile(context);

    if (noSearchResults) {
      return _centered(
        context,
        icon: Icons.search_off_rounded,
        iconColor: cs.onSurfaceVariant,
        title: t.businessesHubNoSearchResults,
        subtitle: searchQuery != null && searchQuery!.isNotEmpty
            ? t.businessesHubNoSearchResultsFor(searchQuery!)
            : null,
        actions: [
          OutlinedButton.icon(
            onPressed: () => context.go('/user/profile/new-business'),
            icon: const Icon(Icons.add_business_rounded),
            label: Text(t.newBusiness),
          ),
        ],
      );
    }

    return _centered(
      context,
      icon: Icons.storefront_rounded,
      iconColor: cs.primary,
      title: t.businessesHubEmptyTitle,
      subtitle: t.businessesHubEmptySubtitle,
      actions: [
        FilledButton.icon(
          onPressed: () => context.go('/user/profile/new-business'),
          icon: const Icon(Icons.add_rounded),
          label: Text(t.createFirstBusiness),
          style: FilledButton.styleFrom(
            minimumSize: Size(isMobile ? double.infinity : 0, 48),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => LegacyImportWizard.show(context),
          icon: const Icon(Icons.upload_file_rounded),
          label: Text(t.businessesHubImportLegacy),
          style: OutlinedButton.styleFrom(
            minimumSize: Size(isMobile ? double.infinity : 0, 44),
          ),
        ),
      ],
      bullets: [
        t.businessesHubEmptyBullet1,
        t.businessesHubEmptyBullet2,
        t.businessesHubEmptyBullet3,
      ],
    );
  }

  Widget _centered(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    List<Widget>? actions,
    List<String>? bullets,
  }) {
    final theme = Theme.of(context);
    final padding = ResponsiveHelper.getPadding(context) * 2;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(padding),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 48, color: iconColor),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
              if (bullets != null) ...[
                const SizedBox(height: 20),
                ...bullets.map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            b,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (actions != null) ...[
                const SizedBox(height: 28),
                ...actions,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
