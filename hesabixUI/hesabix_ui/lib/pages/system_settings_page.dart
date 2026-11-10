import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../core/api_client.dart';
import '../theme/tokens/extensions.dart';
import 'business/settings/business_settings_layout.dart';
import 'system_settings/models/settings_category.dart';
import 'system_settings/models/settings_item.dart';
import 'system_settings/services/settings_categorization_service.dart';
import 'system_settings/widgets/settings_card.dart';
import 'system_settings/widgets/settings_category_section.dart';
import 'system_settings/widgets/settings_search_bar.dart';
import 'system_settings/widgets/system_admin_quick_access.dart';

/// هاب پنل مدیر سیستم؛ چیدمان فشردهٔ مشترک با تنظیمات کسب‌وکار.
class SystemSettingsPage extends StatefulWidget {
  const SystemSettingsPage({super.key});

  @override
  State<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends State<SystemSettingsPage> {
  final Map<String, bool> _categoryExpansionStates = {};
  String _searchQuery = '';
  bool _isSearching = false;
  List<SettingsItem> _searchResults = [];
  late List<SettingsCategory> _categories;
  bool _isSuperAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
    _initializeCategories();
  }

  void _checkAdminAccess() {
    final authStore = ApiClient.getAuthStore();
    if (authStore != null) {
      _isSuperAdmin = authStore.isSuperAdmin;
    }
  }

  void _initializeCategories() {
    _categories = SettingsCategorizationService.visibleCategories(
      isSuperAdmin: _isSuperAdmin,
    );
    for (final category in _categories) {
      _categoryExpansionStates[category.id] =
          SettingsCategorizationService.isExpandedByDefault(category.id);
    }
  }

  void _onSearchChanged(String query) {
    if (!mounted) return;
    final t = AppLocalizations.of(context);
    setState(() {
      _searchQuery = query;
      _isSearching = query.trim().isNotEmpty;
      _searchResults = _isSearching
          ? SettingsCategorizationService.searchItems(
              query,
              t: t,
              categories: _categories,
            )
          : [];
    });
  }

  void _onCategoryExpansionChanged(String categoryId, bool isExpanded) {
    setState(() => _categoryExpansionStates[categoryId] = isExpanded);
  }

  void _expandAllCategories() {
    setState(() {
      for (final category in _categories) {
        _categoryExpansionStates[category.id] = true;
      }
    });
  }

  void _collapseAllCategories() {
    setState(() {
      for (final category in _categories) {
        _categoryExpansionStates[category.id] = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final t = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final hub = context.settingsHub;
    final isWide = hub.isWide(width);
    final totalItems = _categories.fold<int>(0, (sum, category) => sum + category.items.length);
    final quickAccess = SettingsCategorizationService.quickAccessItems(_categories);

    return ColoredBox(
      color: colorScheme.surface,
      child: SingleChildScrollView(
        padding: hub.pagePaddingFor(width),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(
              theme: theme,
              colorScheme: colorScheme,
              t: t,
              categoryCount: _categories.length,
              itemCount: totalItems,
              width: width,
            ),
            SizedBox(height: hub.sectionGapFor(width)),
            SettingsSearchBar(
              key: const ValueKey('system_admin_search'),
              onSearchChanged: _onSearchChanged,
              initialQuery: _searchQuery,
              dense: true,
            ),
            if (!_isSearching) _buildControlButtons(colorScheme, t),
            if (!_isSearching) SystemAdminQuickAccess(items: quickAccess),
            SizedBox(height: hub.innerGap),
            _isSearching
                ? _buildSearchResults(theme, colorScheme, t)
                : _buildCategoriesList(theme, colorScheme, t),
            SizedBox(height: isWide ? hub.bottomGap : hub.sectionGapNarrow),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required AppLocalizations t,
    required int categoryCount,
    required int itemCount,
    required double width,
  }) {
    const kNarrowWelcome = 560.0;
    final hub = context.settingsHub;
    final statsText = '$categoryCount ${t.settingsCategoriesCount} • $itemCount ${t.settingsCount}';
    final statsStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurface.withValues(alpha: 0.6),
      fontSize: hub.cardSubtitleFontSize,
      height: hub.labelHeight,
    );
    final roleColor = _isSuperAdmin ? colorScheme.primary : colorScheme.secondary;

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.systemAdministration,
          style: hub.pageTitleStyle(theme.textTheme, color: colorScheme.onSurface),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: hub.headerTitleGap),
        Text(
          t.systemSettingsDescription,
          style: hub.pageSubtitleStyle(
            theme.textTheme,
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    final roleBadge = Container(
      padding: hub.roleBadgePadding,
      decoration: BoxDecoration(
        color: roleColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isSuperAdmin ? Icons.verified_user : Icons.admin_panel_settings_outlined,
            size: hub.roleBadgeIconSize,
            color: roleColor,
          ),
          SizedBox(width: hub.roleBadgeGap),
          Text(
            _isSuperAdmin ? t.systemAdminSuperAdminRole : t.systemAdminLimitedRole,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: roleColor,
              fontSize: hub.roleBadgeFontSize,
              height: hub.labelHeight,
            ),
          ),
        ],
      ),
    );

    if (width < kNarrowWelcome) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleBlock,
          SizedBox(height: hub.listTitleGap),
          roleBadge,
          SizedBox(height: hub.headerTitleGap + 2),
          Text(statsText, style: statsStyle),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleBlock),
        SizedBox(width: hub.cardIconGap),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            roleBadge,
            SizedBox(height: hub.headerTitleGap + 2),
            Text(statsText, style: statsStyle, textAlign: TextAlign.end),
          ],
        ),
      ],
    );
  }

  Widget _buildControlButtons(ColorScheme colorScheme, AppLocalizations t) {
    final hub = context.settingsHub;
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: colorScheme.primary,
      padding: hub.controlButtonPadding,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    final labelStyle = TextStyle(fontSize: hub.controlButtonFontSize, height: hub.labelHeight);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _expandAllCategories,
          style: buttonStyle,
          child: Text(t.expandAllCategories, style: labelStyle),
        ),
        SizedBox(width: hub.roleBadgeGap),
        TextButton(
          onPressed: _collapseAllCategories,
          style: buttonStyle,
          child: Text(t.collapseAllCategories, style: labelStyle),
        ),
      ],
    );
  }

  Widget _buildCategoriesList(
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations t,
  ) {
    final hub = context.settingsHub;
    if (_categories.isEmpty) {
      return Center(
        child: Padding(
          padding: hub.emptyStatePadding,
          child: Text(
            t.noSettingsFound,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.availableSettings,
          style: hub.listTitleStyle(theme.textTheme, color: colorScheme.onSurface),
        ),
        SizedBox(height: hub.listTitleGap),
        ..._categories.map((category) {
          return SettingsCategorySection(
            key: ValueKey(category.id),
            category: category,
            isExpanded: _categoryExpansionStates[category.id] ?? false,
            onExpansionChanged: (isExpanded) =>
                _onCategoryExpansionChanged(category.id, isExpanded),
          );
        }),
      ],
    );
  }

  Widget _buildSearchResults(
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations t,
  ) {
    final hub = context.settingsHub;
    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: hub.emptyStatePadding,
          child: Column(
            children: [
              Icon(
                Icons.search_off,
                size: hub.emptyStateIconSize,
                color: colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              SizedBox(height: hub.listTitleGap),
              Text(
                t.noSearchResults(_searchQuery),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.searchResults,
          style: hub.listTitleStyle(theme.textTheme, color: colorScheme.onSurface),
        ),
        SizedBox(height: hub.listTitleGap),
        BusinessSettingsLayout.buildResponsiveGrid(
          context: context,
          children: _searchResults.map((item) {
            return SettingsCard(
              item: item,
              isHighlighted: true,
              isDanger: item.tags.contains('danger'),
            );
          }).toList(),
        ),
      ],
    );
  }
}
