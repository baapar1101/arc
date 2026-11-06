import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../system_settings/models/settings_category.dart';
import '../system_settings/models/settings_item.dart';
import '../system_settings/widgets/settings_search_bar.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../models/business_user_model.dart';
import '../../services/business_user_service.dart';
import '../../services/marketplace_service.dart';
import '../../theme/tokens/extensions.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'settings/business_settings_categorization_service.dart';
import 'settings/business_settings_context.dart';
import 'settings/business_settings_localization_helper.dart';
import 'settings/widgets/business_settings_card.dart';
import 'settings/widgets/business_settings_category_section.dart';
import 'settings/business_settings_layout.dart';
import 'settings/widgets/business_settings_setup_checklist.dart';

class SettingsPage extends StatefulWidget {
  final int businessId;

  const SettingsPage({
    super.key,
    required this.businessId,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final BusinessUserService _userService = BusinessUserService(ApiClient());
  final MarketplaceService _marketplaceService = MarketplaceService();

  final Map<String, bool> _categoryExpansionStates = {};
  String _searchQuery = '';
  bool _isSearching = false;
  List<SettingsItem> _searchResults = [];

  bool _isLeaving = false;
  List<Map<String, dynamic>> _businessPlugins = [];
  bool _pluginsLoaded = false;
  bool _pluginsLoadFailed = false;
  List<SettingsCategory> _categories = const [];

  AuthStore? get _authStore => ApiClient.getAuthStore();

  @override
  void initState() {
    super.initState();
    final authStore = _authStore;
    if (authStore != null) {
      authStore.addListener(_onAuthStoreChanged);
    }
    _loadBusinessPlugins();
  }

  @override
  void dispose() {
    final authStore = _authStore;
    if (authStore != null) {
      authStore.removeListener(_onAuthStoreChanged);
    }
    super.dispose();
  }

  void _onAuthStoreChanged() {
    if (!mounted) return;
    final current = _authStore?.currentBusiness;
    if (current?.id != widget.businessId) return;
    _refreshCategories();
    setState(() {});
  }

  Future<void> _loadBusinessPlugins() async {
    if (_pluginsLoaded) return;
    try {
      final plugins = await _marketplaceService.listBusinessPlugins(
        businessId: widget.businessId,
      );
      if (!mounted) return;
      setState(() {
        _businessPlugins =
            plugins.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _pluginsLoaded = true;
        _pluginsLoadFailed = false;
      });
      _initializeExpansionStates();
      if (_isSearching) _onSearchChanged(_searchQuery);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pluginsLoaded = true;
        _pluginsLoadFailed = true;
      });
      _initializeExpansionStates();
      if (_isSearching) _onSearchChanged(_searchQuery);
    }
  }

  BusinessSettingsContext _buildContext() {
    return BusinessSettingsContext(
      businessId: widget.businessId,
      authStore: _authStore!,
      plugins: _businessPlugins,
      pluginsLoaded: _pluginsLoaded,
      pluginsLoadFailed: _pluginsLoadFailed,
    );
  }

  void _refreshCategories() {
    final authStore = _authStore;
    if (authStore == null) return;
    _categories = BusinessSettingsCategorizationService.buildCategories(
      _buildContext(),
    );
    for (final category in _categories) {
      _categoryExpansionStates.putIfAbsent(
        category.id,
        () => category.id != 'danger_zone',
      );
    }
  }

  void _initializeExpansionStates() {
    _refreshCategories();
  }

  void _onSearchChanged(String query) {
    if (!mounted) return;
    final t = AppLocalizations.of(context);
    setState(() {
      _searchQuery = query;
      _isSearching = query.trim().isNotEmpty;
      _searchResults = _isSearching
          ? BusinessSettingsLocalizationHelper.searchItems(
              query: query,
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
      for (final id in _categoryExpansionStates.keys) {
        _categoryExpansionStates[id] = true;
      }
    });
  }

  void _collapseAllCategories() {
    setState(() {
      for (final id in _categoryExpansionStates.keys) {
        _categoryExpansionStates[id] = false;
      }
    });
  }

  void _handleItemTap(SettingsItem item) {
    if (item.id == 'leave_business') {
      if (!_isLeaving) _handleLeave(context);
      return;
    }
    if (item.route.isNotEmpty) {
      context.push(item.route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authStore = _authStore;

    if (authStore == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final ctx = _buildContext();
    _refreshCategories();
    final categories = _categories;
    final setupItems = BusinessSettingsCategorizationService.buildSetupChecklist(ctx);
    final totalItems = categories.fold<int>(0, (sum, c) => sum + c.items.length);

    if (_categoryExpansionStates.isEmpty && categories.isNotEmpty) {
      _initializeExpansionStates();
    }

    final businessTitle = ctx.businessName ?? t.settings;
    final businessSubtitle = ctx.businessName != null
        ? (ctx.isOwner
            ? t.businessSettingsHubDescriptionOwner
            : t.businessSettingsHubDescriptionMember)
        : t.businessSettingsHubDescriptionGeneric;

    final width = MediaQuery.sizeOf(context).width;
    final hub = context.settingsHub;
    final isWide = hub.isWide(width);

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
              title: businessTitle,
              subtitle: businessSubtitle,
              isOwner: ctx.isOwner,
              categoryCount: categories.length,
              itemCount: totalItems,
              width: width,
            ),
            SizedBox(height: hub.sectionGapFor(width)),
            SettingsSearchBar(
              key: const ValueKey('business_settings_search'),
              onSearchChanged: _onSearchChanged,
              initialQuery: _searchQuery,
              dense: true,
            ),
            if (!_isSearching) _buildControlButtons(theme, colorScheme, t),
            if (!_isSearching && setupItems.isNotEmpty)
              BusinessSettingsSetupChecklist(items: setupItems),
            if (_pluginsLoadFailed)
              _buildPluginsErrorBanner(theme, colorScheme, t),
            SizedBox(height: hub.innerGap),
            _isSearching
                ? _buildSearchResults(theme, colorScheme, t)
                : _buildCategoriesList(
                    categories: categories,
                    ctx: ctx,
                    theme: theme,
                    colorScheme: colorScheme,
                    t: t,
                  ),
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
    required String title,
    required String subtitle,
    required bool isOwner,
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

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: hub.pageTitleStyle(theme.textTheme, color: colorScheme.onSurface),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: hub.headerTitleGap),
        Text(
          subtitle,
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
        color: (isOwner ? colorScheme.primary : colorScheme.secondary)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOwner ? Icons.verified_user : Icons.person_outline,
            size: hub.roleBadgeIconSize,
            color: isOwner ? colorScheme.primary : colorScheme.secondary,
          ),
          SizedBox(width: hub.roleBadgeGap),
          Text(
            isOwner ? t.businessSettingsOwnerRole : t.businessSettingsMemberRole,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isOwner ? colorScheme.primary : colorScheme.secondary,
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

  Widget _buildPluginsErrorBanner(
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations t,
  ) {
    final hub = context.settingsHub;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: hub.innerGap),
      padding: hub.cardPadding,
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(hub.cardRadius),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: hub.cardIconSize, color: colorScheme.error),
          SizedBox(width: hub.cardIconGap),
          Expanded(
            child: Text(
              t.businessSettingsPluginsLoadFailed,
              style: hub.cardSubtitleStyle(
                theme.textTheme,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _pluginsLoaded = false;
                _pluginsLoadFailed = false;
              });
              _loadBusinessPlugins();
            },
            style: TextButton.styleFrom(
              padding: hub.controlButtonPadding,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              t.retry,
              style: TextStyle(fontSize: hub.controlButtonFontSize, height: hub.labelHeight),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons(
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations t,
  ) {
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

  Widget _buildCategoriesList({
    required List<SettingsCategory> categories,
    required BusinessSettingsContext ctx,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required AppLocalizations t,
  }) {
    final hub = context.settingsHub;
    if (categories.isEmpty) {
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
        ...categories.map((category) {
          return BusinessSettingsCategorySection(
            key: ValueKey(category.id),
            category: category,
            isExpanded: _categoryExpansionStates[category.id] ?? true,
            onExpansionChanged: (isExpanded) =>
                _onCategoryExpansionChanged(category.id, isExpanded),
            onItemTap: _handleItemTap,
            loadingItemId: _isLeaving ? 'leave_business' : null,
            pluginsLoading: !ctx.pluginsLoaded &&
                (category.id == 'integrations' || category.id == 'modules'),
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
            final isDanger = item.tags.contains('danger');
            return BusinessSettingsCard(
              item: item,
              isHighlighted: true,
              isDanger: isDanger,
              isLoading: _isLeaving && item.id == 'leave_business',
              onTap: () => _handleItemTap(item),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _handleLeave(BuildContext context) async {
    final t = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.businessSettingsLeaveBusiness),
        content: Text(t.businessSettingsLeaveBusinessConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(t.businessSettingsLeaveBusinessAction),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLeaving = true);

    try {
      final request = LeaveBusinessRequest(businessId: widget.businessId);
      final response = await _userService.leaveBusiness(request);

      if (response.success && mounted) {
        SnackBarHelper.showSuccess(context, message: response.message);
        final authStore = _authStore;
        if (authStore != null &&
            authStore.currentBusiness?.id == widget.businessId) {
          await authStore.clearCurrentBusiness();
        }
        if (mounted) context.go('/user/profile/businesses');
      } else if (mounted) {
        SnackBarHelper.showError(context, message: response.message);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message:
              '${t.businessSettingsLeaveBusinessFailed}: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    } finally {
      if (mounted) setState(() => _isLeaving = false);
    }
  }
}
