import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'system_settings/models/settings_category.dart';
import 'system_settings/models/settings_item.dart';
import 'system_settings/services/settings_categorization_service.dart';
import 'system_settings/widgets/settings_search_bar.dart';
import 'system_settings/widgets/settings_category_section.dart';

/// صفحه اصلی پنل مدیریت تنظیمات سیستم
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
    _categories = SettingsCategorizationService.getCategories();
    
    // فیلتر دسته‌ها و آیتم‌ها بر اساس دسترسی
    if (!_isSuperAdmin) {
      _categories = _categories
          .where((category) => !category.requiresSuperAdmin)
          .map((category) {
            // فیلتر کردن آیتم‌های هر دسته
            final filteredItems = category.items
                .where((item) => !item.requiresSuperAdmin)
                .toList();
            return category.copyWith(items: filteredItems);
          })
          .toList();
    }

    // همه دسته‌ها به صورت پیش‌فرض باز هستند
    for (var category in _categories) {
      _categoryExpansionStates[category.id] = true;
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _isSearching = query.trim().isNotEmpty;

      if (_isSearching) {
        // جستجو در همه آیتم‌ها
        _searchResults = SettingsCategorizationService.searchItems(
          query,
          categories: _categories,
        );
      } else {
        _searchResults = [];
      }
    });
  }

  void _onCategoryExpansionChanged(String categoryId, bool isExpanded) {
    setState(() {
      _categoryExpansionStates[categoryId] = isExpanded;
    });
  }

  void _expandAllCategories() {
    setState(() {
      for (var category in _categories) {
        _categoryExpansionStates[category.id] = true;
      }
    });
  }

  void _collapseAllCategories() {
    setState(() {
      for (var category in _categories) {
        _categoryExpansionStates[category.id] = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final t = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // بخش Welcome
            _buildWelcomeSection(theme, colorScheme, t),

            const SizedBox(height: 20),

            // نوار جستجو
            SettingsSearchBar(
              onSearchChanged: _onSearchChanged,
              initialQuery: _searchQuery,
            ),

            // دکمه‌های کنترل (Expand All / Collapse All)
            if (!_isSearching) _buildControlButtons(theme, colorScheme, t),

            const SizedBox(height: 16),

            // لیست دسته‌ها یا نتایج جستجو
            _isSearching
                ? _buildSearchResults(theme, colorScheme, t)
                : _buildCategoriesList(theme, colorScheme, t),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeSection(
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations t,
  ) {
    final totalItems = _categories.fold<int>(
      0,
      (sum, category) => sum + category.items.length,
    );

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.systemAdministration,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t.systemSettingsDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        Text(
          '${_categories.length} ${t.settingsCategoriesCount} • $totalItems ${t.settingsCount}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildControlButtons(
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations t,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _expandAllCategories,
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            t.expandAllCategories,
            style: TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _collapseAllCategories,
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            t.collapseAllCategories,
            style: TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoriesList(
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations t,
  ) {
    if (_categories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            t.noSettingsFound,
            style: theme.textTheme.bodyLarge?.copyWith(
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
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        ..._categories.map((category) {
          return SettingsCategorySection(
            key: ValueKey(category.id),
            category: category,
            isExpanded: _categoryExpansionStates[category.id] ?? true,
            onExpansionChanged: (isExpanded) =>
                _onCategoryExpansionChanged(category.id, isExpanded),
            searchQuery: null,
            showSearchResults: false,
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
    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                t.noSearchResults(_searchQuery),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // نمایش نتایج جستجو به صورت دسته‌بندی شده
    final Map<String, List<SettingsItem>> groupedResults = {};
    for (var item in _searchResults) {
      if (!groupedResults.containsKey(item.categoryId)) {
        groupedResults[item.categoryId] = [];
      }
      groupedResults[item.categoryId]!.add(item);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              t.searchResults,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                t.searchResultCount(_searchResults.length),
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...groupedResults.entries.map((entry) {
          final categoryId = entry.key;
          final items = entry.value;
          final category = _categories.firstWhere(
            (cat) => cat.id == categoryId,
            orElse: () => _categories.first,
          );

          // ایجاد یک دسته موقت فقط با آیتم‌های جستجو شده
          final searchCategory = SettingsCategory(
            id: category.id,
            title: category.title,
            description: category.description,
            icon: category.icon,
            color: category.color,
            items: items,
            order: category.order,
            requiresSuperAdmin: category.requiresSuperAdmin,
          );

          return SettingsCategorySection(
            key: ValueKey('search_${category.id}'),
            category: searchCategory,
            isExpanded: true,
            searchQuery: _searchQuery,
            showSearchResults: true,
          );
        }),
      ],
    );
  }
}
