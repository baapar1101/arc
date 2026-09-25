import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/config/brand_config.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../services/legacy_api_import_public_config.dart';
import '../../utils/responsive_helper.dart';
import 'new_business/new_business_paths_panel.dart';
import 'new_business/new_business_shared.dart';

class BusinessesEmptyState extends StatefulWidget {
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
  State<BusinessesEmptyState> createState() => _BusinessesEmptyStateState();
}

class _BusinessesEmptyStateState extends State<BusinessesEmptyState> {
  LegacyApiImportPublicConfig _legacyImportConfig =
      const LegacyApiImportPublicConfig();

  @override
  void initState() {
    super.initState();
    _loadLegacyImportConfig();
  }

  Future<void> _loadLegacyImportConfig() async {
    final cfg = await LegacyApiImportPublicConfig.fetch(ApiClient());
    if (!mounted) return;
    setState(() => _legacyImportConfig = cfg);
  }

  void _goFlow(BuildContext context, String flow) {
    context.go('/user/profile/new-business?flow=$flow');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final padding = ResponsiveHelper.getPadding(context) * 2;
    final isDesktop = ResponsiveHelper.isDesktop(context);
    final isTablet = ResponsiveHelper.isTablet(context);

    if (widget.noSearchResults) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: NewBusinessSurface(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 40,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t.businessesHubNoSearchResults,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.searchQuery != null &&
                      widget.searchQuery!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      t.businessesHubNoSearchResultsFor(widget.searchQuery!),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (widget.onClearSearch != null) ...[
                    const SizedBox(height: 20),
                    TextButton.icon(
                      onPressed: widget.onClearSearch,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: Text(t.businessesHubClearSearch),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return NewBusinessAmbientBackground(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(padding),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: NewBusinessFormShell(
                  maxWidth: isDesktop ? 880 : (isTablet ? 640 : 520),
                  child: NewBusinessPathsPanel(
                    isLoading: false,
                    onCreateManually: () => _goFlow(context, 'create'),
                    onImportBackup: () => _goFlow(context, 'backup'),
                    onImportLegacy: () => _goFlow(context, 'legacy'),
                    showLegacyImport: _legacyImportConfig.enabledForUsers,
                    title: t.businessesHubEmptyTitle,
                    subtitle: t.branded(t.businessesHubEmptySubtitle),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
