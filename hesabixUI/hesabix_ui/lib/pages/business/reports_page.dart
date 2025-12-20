import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/auth_store.dart';
import '../../widgets/permission/access_denied_page.dart';

class ReportsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const ReportsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  static const _kFavKeyPrefix = 'reports_favorites';
  static const _kRecentKeyPrefix = 'reports_recent';

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  String _selectedSectionId = 'all';
  _DesktopSort _desktopSort = _DesktopSort.recommended;

  bool _prefsLoaded = false;
  Set<String> _favorites = <String>{};
  List<String> _recent = <String>[];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final raw = _searchController.text;
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 180), () {
        final q = _normalizeQuery(raw);
        if (!mounted || q == _query) return;
        setState(() => _query = q);
      });
    });
    _loadPrefs();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _normalizeQuery(String input) {
    var s = input.trim().toLowerCase();

    // Normalize Arabic/Persian variants
    s = s
        .replaceAll('ي', 'ی')
        .replaceAll('ك', 'ک')
        .replaceAll('ة', 'ه')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ی')
        .replaceAll('ٔ', '');

    // Remove Arabic diacritics
    s = s.replaceAll(RegExp(r'[\u064B-\u0652\u0670]'), '');

    // Normalize digits (Persian/Arabic → English)
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    const ar = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
    }

    // Normalize whitespace & ZWNJ
    s = s.replaceAll('\u200c', ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ');

    return s;
  }

  String _prefsScopeSuffix() {
    final userId = widget.authStore.currentUserId;
    final userPart = (userId == null) ? 'anon' : 'u$userId';
    return '${userPart}_b${widget.businessId}';
  }

  String _favoritesPrefsKey() => '${_kFavKeyPrefix}_${_prefsScopeSuffix()}';
  String _recentPrefsKey() => '${_kRecentKeyPrefix}_${_prefsScopeSuffix()}';

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favRaw = prefs.getString(_favoritesPrefsKey());
      final recRaw = prefs.getString(_recentPrefsKey());

      final favList = (favRaw == null || favRaw.isEmpty)
          ? <dynamic>[]
          : (jsonDecode(favRaw) as List<dynamic>);
      final recList = (recRaw == null || recRaw.isEmpty)
          ? <dynamic>[]
          : (jsonDecode(recRaw) as List<dynamic>);

      final fav = favList.map((e) => '$e').where((e) => e.isNotEmpty).toSet();
      final rec = recList.map((e) => '$e').where((e) => e.isNotEmpty).toList();

      if (!mounted) return;
      setState(() {
        _favorites = fav;
        _recent = rec;
        _prefsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _favorites = <String>{};
        _recent = <String>[];
        _prefsLoaded = true;
      });
    }
  }

  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_favoritesPrefsKey(), jsonEncode(_favorites.toList()..sort()));
    } catch (_) {}
  }

  Future<void> _saveRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recentPrefsKey(), jsonEncode(_recent));
    } catch (_) {}
  }

  void _toggleFavorite(String reportKey) {
    setState(() {
      if (_favorites.contains(reportKey)) {
        _favorites.remove(reportKey);
      } else {
        _favorites.add(reportKey);
      }
    });
    _saveFavorites();
  }

  void _recordRecent(String reportKey) {
    setState(() {
      _recent.remove(reportKey);
      _recent.insert(0, reportKey);
      if (_recent.length > 8) {
        _recent = _recent.take(8).toList();
      }
    });
    _saveRecent();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (!widget.authStore.canReadSection('reports')) {
      return AccessDeniedPage(message: t.accessDenied);
    }

    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 900;

    final data = _buildData(context, t: t);
    final allItems = data.expand((s) => s.items).toList(growable: false);
    final itemsByKey = <String, _ReportLink>{
      for (final it in allItems) it.key: it,
    };

    final isSearching = _query.isNotEmpty;
    final filteredItems = isSearching ? _filterItems(allItems, query: _query) : allItems;

    final sectionTitleByItemKey = <String, String>{
      for (final s in data)
        for (final it in s.items) it.key: s.title,
    };

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                if (isDesktop)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _PinnedHeaderDelegate(
                      height: isSearching ? 64 : 120,
                      child: _buildDesktopPinnedHeader(context, data, isSearching: isSearching),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(child: _buildSearchBar(context)),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                ],

                if (_prefsLoaded && !isSearching) ...[
                  SliverToBoxAdapter(
                    child: _buildQuickAccessSection(
                      context,
                      title: t.reportsFavoritesTitle,
                      icon: Icons.star_outline,
                      emptyMessage: t.reportsFavoritesEmptyMessage,
                      items: _favorites.map((k) => itemsByKey[k]).whereType<_ReportLink>().toList(),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverToBoxAdapter(
                    child: _buildQuickAccessSection(
                      context,
                      title: t.reportsRecentTitle,
                      icon: Icons.history,
                      emptyMessage: t.reportsRecentEmptyMessage,
                      items: _recent.map((k) => itemsByKey[k]).whereType<_ReportLink>().toList(),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],

                if (isSearching) ...[
                  SliverToBoxAdapter(
                    child: _buildSearchResultsHeader(context, count: filteredItems.length),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  if (filteredItems.isEmpty)
                    SliverToBoxAdapter(
                      child: _buildEmptyState(context, message: t.reportsSearchNoResults),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _buildReportTile(ctx, filteredItems[i]),
                        childCount: filteredItems.length,
                      ),
                    ),
                ] else ...[
                  if (!isDesktop)
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _buildSectionTile(ctx, data[i]),
                        childCount: data.length,
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildListDelegate(
                        _buildDesktopSections(
                          context,
                          data,
                          sectionTitleByItemKey: sectionTitleByItemKey,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    final hasText = _searchController.text.trim().isNotEmpty;
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: t.reportsSearchHint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: !hasText
            ? null
            : IconButton(
                tooltip: t.clear,
                onPressed: () => _searchController.clear(),
                icon: const Icon(Icons.clear),
              ),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildSearchResultsHeader(BuildContext context, {required int count}) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    return Row(
      children: [
        Icon(Icons.manage_search, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          t.reportsSearchResults(count),
          style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, {required String message}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildQuickAccessSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String emptyMessage,
    required List<_ReportLink> items,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: cs.primary),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  emptyMessage,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              )
            else
              Column(
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    _buildReportTile(context, items[i], wrapInCard: false),
                    if (i != items.length - 1) Divider(color: cs.outlineVariant.withValues(alpha: 0.5), height: 1),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTile(BuildContext context, _ReportSection section) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    final width = MediaQuery.of(context).size.width;
    final columns = width >= 1200 ? 3 : (width >= 900 ? 2 : 1);

    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: section.initiallyExpanded,
          leading: Icon(section.icon, color: cs.primary),
          title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            t.reportsSectionCount(section.items.length),
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
              child: columns == 1
                  ? Column(children: section.items.map((e) => _buildReportTile(context, e)).toList())
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: section.items.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 3.2,
                      ),
                      itemBuilder: (ctx, i) => _buildReportCardCompact(ctx, section.items[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCardCompact(
    BuildContext context,
    _ReportLink item, {
    String? subtitleOverride,
  }) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    final canOpen = _canOpen(item);
    final disabledFg = cs.onSurfaceVariant.withValues(alpha: 0.75);
    final fg = canOpen ? cs.onSurface : disabledFg;
    final iconColor = canOpen ? cs.primary : disabledFg;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: canOpen ? () => _openReport(context, item) : () => _showAccessDenied(context, t),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(item.icon, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, color: fg),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitleOverride ?? item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: disabledFg, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (!canOpen) ...[
              Tooltip(message: t.accessDenied, child: Icon(Icons.lock_outline, color: disabledFg)),
              const SizedBox(width: 6),
            ],
            IconButton(
              tooltip: _favorites.contains(item.key) ? t.reportsRemoveFromFavorites : t.reportsAddToFavorites,
              onPressed: canOpen ? () => _toggleFavorite(item.key) : null,
              icon: Icon(_favorites.contains(item.key) ? Icons.star : Icons.star_border, color: cs.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportTile(BuildContext context, _ReportLink item, {bool wrapInCard = true}) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    final canOpen = _canOpen(item);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final chevron = isRtl ? Icons.chevron_left : Icons.chevron_right;
    final tile = ListTile(
      enabled: canOpen,
      dense: !wrapInCard,
      contentPadding: wrapInCard ? null : EdgeInsets.zero,
      leading: Icon(item.icon, color: canOpen ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.8)),
      title: Text(
        item.title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: canOpen ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.9),
        ),
      ),
      subtitle: Text(item.subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!canOpen) ...[
            Tooltip(message: t.accessDenied, child: Icon(Icons.lock_outline, size: 18, color: cs.onSurfaceVariant)),
            const SizedBox(width: 6),
          ],
          IconButton(
            tooltip: _favorites.contains(item.key) ? t.reportsRemoveFromFavorites : t.reportsAddToFavorites,
            onPressed: canOpen ? () => _toggleFavorite(item.key) : null,
            icon: Icon(_favorites.contains(item.key) ? Icons.star : Icons.star_border, color: cs.primary),
          ),
          Icon(chevron, size: 18, color: cs.onSurfaceVariant),
        ],
      ),
      onTap: canOpen ? () => _openReport(context, item) : () => _showAccessDenied(context, t),
    );

    if (!wrapInCard) return tile;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: tile,
    );
  }

  void _openReport(BuildContext context, _ReportLink item) {
    final t = AppLocalizations.of(context);
    if (!_canOpen(item)) return _showAccessDenied(context, t);
    _recordRecent(item.key);
    context.go(item.route);
  }

  Widget _buildSectionChips(BuildContext context, List<_ReportSection> sections) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    final chips = <Widget>[
      FilterChip(
        label: Text(t.all),
        selected: _selectedSectionId == 'all',
        onSelected: (_) => setState(() => _selectedSectionId = 'all'),
        selectedColor: cs.primaryContainer,
        checkmarkColor: cs.onPrimaryContainer,
      ),
      ...sections.map(
        (s) => FilterChip(
          label: Text(s.title),
          selected: _selectedSectionId == s.id,
          onSelected: (_) => setState(() => _selectedSectionId = s.id),
          selectedColor: cs.primaryContainer,
          checkmarkColor: cs.onPrimaryContainer,
        ),
      ),
    ];

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips,
      ),
    );
  }

  Widget _buildDesktopPinnedHeader(
    BuildContext context,
    List<_ReportSection> sections, {
    required bool isSearching,
  }) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildSearchBar(context)),
            const SizedBox(width: 8),
            PopupMenuButton<_DesktopSort>(
              tooltip: t.reportsSortTooltip,
              onSelected: (v) => setState(() => _desktopSort = v),
              itemBuilder: (ctx) => [
                PopupMenuItem(value: _DesktopSort.recommended, child: Text(t.reportsSortDefault)),
                PopupMenuItem(value: _DesktopSort.alphabetical, child: Text(t.reportsSortAlphabetical)),
              ],
              child: Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.sort, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!isSearching) _buildSectionChips(context, sections),
      ],
    );
  }

  List<Widget> _buildDesktopSections(
    BuildContext context,
    List<_ReportSection> sections, {
    required Map<String, String> sectionTitleByItemKey,
  }) {
    final selected = _selectedSectionId;
    if (selected == 'all') {
      final all = sections.expand((s) => s.items).toList(growable: false);
      final sorted = _sortForDesktop(all);
      return <Widget>[
        _buildDesktopSectionHeader(
          context,
          title: AppLocalizations.of(context).reports,
          icon: Icons.assessment,
          count: sorted.length,
        ),
        const SizedBox(height: 8),
        _buildDesktopAllGrid(context, sorted, sectionTitleByItemKey: sectionTitleByItemKey),
      ];
    }

    final s = sections.where((e) => e.id == selected).cast<_ReportSection?>().firstWhere(
          (e) => e != null,
          orElse: () => null,
        );
    if (s == null) {
      return <Widget>[
        _buildEmptyState(context, message: AppLocalizations.of(context).reportsSearchNoResults),
      ];
    }
    final sorted = _sortForDesktop(s.items);
    return <Widget>[
      _buildDesktopSectionHeader(context, title: s.title, icon: s.icon, count: sorted.length),
      const SizedBox(height: 8),
      _buildDesktopSectionGrid(context, sorted),
    ];
  }

  List<_ReportLink> _sortForDesktop(List<_ReportLink> items) {
    if (_desktopSort == _DesktopSort.recommended) return items;
    final copy = items.toList(growable: false);
    copy.sort((a, b) => _normalizeQuery(a.title).compareTo(_normalizeQuery(b.title)));
    return copy;
  }

  Widget _buildDesktopSectionHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
    required int count,
  }) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            t.reportsSectionCount(count),
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSectionGrid(BuildContext context, List<_ReportLink> items) {
    final width = MediaQuery.of(context).size.width;
    final columns = width >= 1200 ? 3 : 2;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 3.2,
      ),
      itemBuilder: (ctx, i) => _buildReportCardCompact(ctx, items[i]),
    );
  }

  Widget _buildDesktopAllGrid(
    BuildContext context,
    List<_ReportLink> items, {
    required Map<String, String> sectionTitleByItemKey,
  }) {
    final width = MediaQuery.of(context).size.width;
    final columns = width >= 1200 ? 3 : 2;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 3.2,
      ),
      itemBuilder: (ctx, i) {
        final it = items[i];
        final sec = sectionTitleByItemKey[it.key];
        final subtitle = (sec == null || sec.isEmpty) ? it.subtitle : '$sec • ${it.subtitle}';
        return _buildReportCardCompact(ctx, it, subtitleOverride: subtitle);
      },
    );
  }

  List<_ReportLink> _filterItems(List<_ReportLink> items, {required String query}) {
    final q = _normalizeQuery(query);
    final t = AppLocalizations.of(context);
    return items.where((e) {
      final hay = <String>[
        e.title,
        e.subtitle,
        ..._keywordsForSearch(e, t),
      ].join(' ');
      return _normalizeQuery(hay).contains(q);
    }).toList();
  }

  List<String> _keywordsForSearch(_ReportLink item, AppLocalizations t) {
    // در فارسی، جستجو را گسترده نگه می‌داریم (کاربر ممکن است اصطلاحات انگلیسی هم وارد کند)
    if (t.localeName.startsWith('fa')) {
      return item.keywords;
    }
    // در سایر زبان‌ها، کلیدواژه‌های فارسی را حذف می‌کنیم تا جستجو طبیعی‌تر باشد
    final faChars = RegExp(r'[\u0600-\u06FF]');
    return item.keywords.where((k) => !faChars.hasMatch(k)).toList(growable: false);
  }

  bool _canOpen(_ReportLink item) {
    // هماهنگ با سایر بخش‌ها: مالک همه دسترسی‌ها را دارد
    if (widget.authStore.currentBusiness?.isOwner == true) {
      return true;
    }

    final section = item.permissionSection;
    if (section == null || section.isEmpty) return true;

    // حالت امن برای جلوگیری از قفل اشتباه: اگر سکشن در permissions موجود نبود، قفل نکن
    final perms = widget.authStore.businessPermissions;
    if (perms == null || !perms.containsKey(section)) {
      return true;
    }

    return widget.authStore.hasBusinessPermission(section, item.permissionAction);
  }

  void _showAccessDenied(BuildContext context, AppLocalizations t) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.accessDenied)),
    );
  }

  List<_ReportSection> _buildData(BuildContext context, {required AppLocalizations t}) {
    final b = widget.businessId;
    return <_ReportSection>[
      _ReportSection(
        id: 'general',
        title: t.reportsGeneralSection,
        icon: Icons.assessment,
        initiallyExpanded: true,
        items: [
          _ReportLink(
            key: 'kardex',
            title: t.kardexDocuments,
            subtitle: t.reportsKardexSubtitle,
            icon: Icons.view_kanban,
            route: '/business/$b/reports/kardex',
            keywords: const ['کاردکس', 'kardex', 'ریز', 'تراکنش'],
            permissionSection: 'reports',
          ),
        ],
      ),
      _ReportSection(
        id: 'people',
        title: t.reportsPeopleSection,
        icon: Icons.people_outline,
        items: [
          _ReportLink(
            key: 'installments',
            title: t.installmentsReportTitle,
            subtitle: t.reportsInstallmentsSubtitle,
            icon: Icons.payments_outlined,
            route: '/business/$b/installments-report',
            keywords: const ['اقساط', 'سررسید'],
            permissionSection: 'invoices',
          ),
          _ReportLink(
            key: 'debtors',
            title: t.reportsDebtorsTitle,
            subtitle: t.reportsDebtorsSubtitle,
            icon: Icons.trending_down,
            route: '/business/$b/reports/debtors',
            keywords: const ['بدهکار', 'debtors'],
            permissionSection: 'people',
          ),
          _ReportLink(
            key: 'creditors',
            title: t.reportsCreditorsTitle,
            subtitle: t.reportsCreditorsSubtitle,
            icon: Icons.trending_up,
            route: '/business/$b/reports/creditors',
            keywords: const ['بستانکار', 'creditors'],
            permissionSection: 'people',
          ),
          _ReportLink(
            key: 'people_transactions',
            title: t.reportsPeopleTransactionsTitle,
            subtitle: t.reportsPeopleTransactionsSubtitle,
            icon: Icons.receipt_long,
            route: '/business/$b/reports/people-transactions',
            keywords: const ['تراکنش', 'دریافت', 'پرداخت'],
            permissionSection: 'people_transactions',
          ),
        ],
      ),
      _ReportSection(
        id: 'products',
        title: t.reportsProductsSection,
        icon: Icons.inventory_2_outlined,
        items: [
          _ReportLink(
            key: 'item_movements',
            title: t.reportsItemMovementsTitle,
            subtitle: t.reportsItemMovementsSubtitle,
            icon: Icons.sync_alt,
            route: '/business/$b/reports/item-movements',
            keywords: const ['گردش کالا', 'movements'],
            permissionSection: 'products',
          ),
          _ReportLink(
            key: 'inventory_kardex',
            title: t.reportsInventoryKardexTitle,
            subtitle: t.reportsInventoryKardexSubtitle,
            icon: Icons.storage,
            route: '/business/$b/reports/inventory-kardex',
            keywords: const ['کارتکس', 'انبار', 'fifo', 'lifo'],
            permissionSection: 'warehouses',
          ),
          _ReportLink(
            key: 'inventory_stock',
            title: t.reportsInventoryStockTitle,
            subtitle: t.reportsInventoryStockSubtitle,
            icon: Icons.inventory_2_outlined,
            route: '/business/$b/reports/inventory-stock',
            keywords: const ['موجودی', 'انبار'],
            permissionSection: 'warehouses',
          ),
          _ReportLink(
            key: 'stock_count',
            title: t.reportsStockCountTitle,
            subtitle: t.reportsStockCountSubtitle,
            icon: Icons.inventory,
            route: '/business/$b/reports/stock-count',
            keywords: const ['انبارگردانی', 'تعدیل'],
            permissionSection: 'warehouse_transfers',
          ),
          _ReportLink(
            key: 'sales_by_product',
            title: t.reportsSalesByProductTitle,
            subtitle: t.reportsSalesByProductSubtitle,
            icon: Icons.shopping_cart_checkout,
            route: '/business/$b/reports/sales-by-product',
            keywords: const ['فروش', 'کالا'],
            permissionSection: 'invoices',
          ),
        ],
      ),
      _ReportSection(
        id: 'warehouse',
        title: t.reportsWarehouseSection,
        icon: Icons.warehouse_outlined,
        items: [
          _ReportLink(
            key: 'warehouse_documents_summary',
            title: t.reportsWarehouseDocumentsSummaryTitle,
            subtitle: t.reportsWarehouseDocumentsSummarySubtitle,
            icon: Icons.summarize,
            route: '/business/$b/reports/warehouse-documents-summary',
            keywords: const ['حواله', 'خلاصه'],
            permissionSection: 'warehouse_transfers',
          ),
          _ReportLink(
            key: 'slow_moving_items',
            title: t.reportsSlowMovingItemsTitle,
            subtitle: t.reportsSlowMovingItemsSubtitle,
            icon: Icons.trending_down,
            route: '/business/$b/reports/slow-moving-items',
            keywords: const ['کم گردش', 'بی حرکت'],
            permissionSection: 'products',
          ),
          _ReportLink(
            key: 'critical_stock',
            title: t.reportsCriticalStockTitle,
            subtitle: t.reportsCriticalStockSubtitle,
            icon: Icons.warning_amber,
            route: '/business/$b/reports/critical-stock',
            keywords: const ['بحرانی', 'کمبود'],
            permissionSection: 'products',
          ),
          _ReportLink(
            key: 'inter_warehouse_transfers',
            title: t.reportsInterWarehouseTransfersTitle,
            subtitle: t.reportsInterWarehouseTransfersSubtitle,
            icon: Icons.swap_horiz,
            route: '/business/$b/reports/inter-warehouse-transfers',
            keywords: const ['انتقال', 'بین انبار'],
            permissionSection: 'warehouse_transfers',
          ),
          _ReportLink(
            key: 'adjustment_documents',
            title: t.reportsAdjustmentDocumentsTitle,
            subtitle: t.reportsAdjustmentDocumentsSubtitle,
            icon: Icons.tune,
            route: '/business/$b/reports/adjustment-documents',
            keywords: const ['تعدیل', 'اختلاف'],
            permissionSection: 'warehouse_transfers',
          ),
          _ReportLink(
            key: 'warehouse_performance',
            title: t.reportsWarehousePerformanceTitle,
            subtitle: t.reportsWarehousePerformanceSubtitle,
            icon: Icons.analytics,
            route: '/business/$b/reports/warehouse-performance',
            keywords: const ['عملکرد', 'انبار'],
            permissionSection: 'warehouses',
          ),
          _ReportLink(
            key: 'product_movement_history',
            title: t.reportsProductMovementHistoryTitle,
            subtitle: t.reportsProductMovementHistorySubtitle,
            icon: Icons.history,
            route: '/business/$b/reports/product-movement-history',
            keywords: const ['تاریخچه', 'حرکت کالا'],
            permissionSection: 'products',
          ),
          _ReportLink(
            key: 'inventory_valuation',
            title: t.reportsInventoryValuationTitle,
            subtitle: t.reportsInventoryValuationSubtitle,
            icon: Icons.attach_money,
            route: '/business/$b/reports/inventory-valuation',
            keywords: const ['ارزش', 'ریالی'],
            permissionSection: 'warehouses',
          ),
          _ReportLink(
            key: 'pending_documents',
            title: t.reportsPendingDocumentsTitle,
            subtitle: t.reportsPendingDocumentsSubtitle,
            icon: Icons.pending_actions,
            route: '/business/$b/reports/pending-documents',
            keywords: const ['draft', 'در انتظار'],
            permissionSection: 'warehouse_transfers',
          ),
          _ReportLink(
            key: 'inventory_turnover',
            title: t.reportsInventoryTurnoverTitle,
            subtitle: t.reportsInventoryTurnoverSubtitle,
            icon: Icons.autorenew,
            route: '/business/$b/reports/inventory-turnover',
            keywords: const ['گردش موجودی', 'turnover'],
            permissionSection: 'warehouses',
          ),
        ],
      ),
      _ReportSection(
        id: 'banking',
        title: t.reportsBankingSection,
        icon: Icons.account_balance_wallet_outlined,
        items: [
          _ReportLink(
            key: 'bank_accounts_turnover',
            title: t.reportsBankAccountsTurnoverTitle,
            subtitle: t.reportsBankAccountsTurnoverSubtitle,
            icon: Icons.account_balance,
            route: '/business/$b/reports/bank-accounts-turnover',
            keywords: const ['بانک', 'گردش'],
            permissionSection: 'bank_accounts',
          ),
          _ReportLink(
            key: 'cash_petty_turnover',
            title: t.reportsCashPettyTurnoverTitle,
            subtitle: t.reportsCashPettyTurnoverSubtitle,
            icon: Icons.savings,
            route: '/business/$b/reports/cash-petty-turnover',
            keywords: const ['صندوق', 'تنخواه'],
            permissionSection: 'cash',
          ),
          _ReportLink(
            key: 'checks',
            title: t.reportsChecksTitle,
            subtitle: t.reportsChecksSubtitle,
            icon: Icons.payments_outlined,
            route: '/business/$b/checks',
            keywords: const ['چک', 'checks'],
            permissionSection: 'checks',
          ),
        ],
      ),
      _ReportSection(
        id: 'sales',
        title: t.reportsSalesSection,
        icon: Icons.point_of_sale,
        items: [
          _ReportLink(
            key: 'daily_sales',
            title: t.reportsDailySalesTitle,
            subtitle: t.reportsDailySalesSubtitle,
            icon: Icons.today,
            route: '/business/$b/reports/daily-sales',
            keywords: const ['فروش', 'روزانه'],
            permissionSection: 'invoices',
          ),
          _ReportLink(
            key: 'monthly_sales',
            title: t.reportsMonthlySalesTitle,
            subtitle: t.reportsMonthlySalesSubtitle,
            icon: Icons.calendar_month,
            route: '/business/$b/reports/monthly-sales',
            keywords: const ['فروش', 'ماهانه'],
            permissionSection: 'invoices',
          ),
          _ReportLink(
            key: 'top_customers',
            title: t.reportsTopCustomersTitle,
            subtitle: t.reportsTopCustomersSubtitle,
            icon: Icons.emoji_events_outlined,
            route: '/business/$b/reports/top-customers',
            keywords: const ['مشتریان برتر', 'رتبه'],
            permissionSection: 'invoices',
          ),
        ],
      ),
      _ReportSection(
        id: 'purchases',
        title: t.reportsPurchasesSection,
        icon: Icons.shopping_bag_outlined,
        items: [
          _ReportLink(
            key: 'daily_purchases',
            title: t.reportsDailyPurchasesTitle,
            subtitle: t.reportsDailyPurchasesSubtitle,
            icon: Icons.today,
            route: '/business/$b/reports/daily-purchases',
            keywords: const ['خرید', 'روزانه'],
            permissionSection: 'accounting_documents',
          ),
          _ReportLink(
            key: 'top_suppliers',
            title: t.reportsTopSuppliersTitle,
            subtitle: t.reportsTopSuppliersSubtitle,
            icon: Icons.handshake,
            route: '/business/$b/reports/top-suppliers',
            keywords: const ['تامین کننده', 'برتر'],
            permissionSection: 'accounting_documents',
          ),
        ],
      ),
      _ReportSection(
        id: 'production',
        title: t.reportsProductionSection,
        icon: Icons.factory_outlined,
        items: [
          _ReportLink(
            key: 'materials_consumption',
            title: t.reportsMaterialsConsumptionTitle,
            subtitle: t.reportsMaterialsConsumptionSubtitle,
            icon: Icons.dataset_outlined,
            route: '/business/$b/reports/materials-consumption',
            keywords: const ['مصرف مواد', 'مواد اولیه'],
            permissionSection: 'products',
          ),
          _ReportLink(
            key: 'production_report',
            title: t.reportsProductionTitle,
            subtitle: t.reportsProductionSubtitle,
            icon: Icons.precision_manufacturing_outlined,
            route: '/business/$b/reports/production',
            keywords: const ['تولید', 'ضایعات'],
            permissionSection: 'products',
          ),
        ],
      ),
      _ReportSection(
        id: 'basic_accounting',
        title: t.reportsBasicAccountingSection,
        icon: Icons.calculate_outlined,
        items: [
          _ReportLink(
            key: 'trial_balance',
            title: t.reportsTrialBalanceTitle,
            subtitle: t.reportsTrialBalanceSubtitle,
            icon: Icons.grid_on,
            route: '/business/$b/reports/trial-balance',
            keywords: const ['تراز', 'آزمایشی'],
            permissionSection: 'accounting_documents',
          ),
          _ReportLink(
            key: 'general_ledger',
            title: t.reportsGeneralLedgerTitle,
            subtitle: t.reportsGeneralLedgerSubtitle,
            icon: Icons.menu_book_outlined,
            route: '/business/$b/reports/general-ledger',
            keywords: const ['دفتر کل', 'ledger'],
            permissionSection: 'accounting_documents',
          ),
          _ReportLink(
            key: 'journal_ledger',
            title: t.reportsJournalLedgerTitle,
            subtitle: t.reportsJournalLedgerSubtitle,
            icon: Icons.book_outlined,
            route: '/business/$b/reports/journal-ledger',
            keywords: const ['دفتر روزنامه', 'journal'],
            permissionSection: 'accounting_documents',
          ),
          _ReportLink(
            key: 'accounts_review',
            title: t.reportsAccountsReviewTitle,
            subtitle: t.reportsAccountsReviewSubtitle,
            icon: Icons.account_tree,
            route: '/business/$b/reports/accounts-review',
            keywords: const ['مرور حساب', 'درختی'],
          ),
        ],
      ),
      _ReportSection(
        id: 'profit_loss',
        title: t.reportsProfitLossSection,
        icon: Icons.assessment_outlined,
        items: [
          _ReportLink(
            key: 'pnl_period',
            title: t.reportsPnlPeriodTitle,
            subtitle: t.reportsPnlPeriodSubtitle,
            icon: Icons.show_chart,
            route: '/business/$b/reports/pnl-period',
            keywords: const ['سود و زیان', 'دوره'],
            permissionSection: 'accounting_documents',
          ),
          _ReportLink(
            key: 'pnl_cumulative',
            title: t.reportsPnlCumulativeTitle,
            subtitle: t.reportsPnlCumulativeSubtitle,
            icon: Icons.query_stats,
            route: '/business/$b/reports/pnl-cumulative',
            keywords: const ['سود و زیان', 'تجمیعی'],
            permissionSection: 'accounting_documents',
          ),
        ],
      ),
      _ReportSection(
        id: 'system',
        title: t.reportsSystemSection,
        icon: Icons.assignment_outlined,
        items: [
          _ReportLink(
            key: 'activity_logs',
            title: t.reportsActivityLogsTitle,
            subtitle: t.reportsActivityLogsSubtitle,
            icon: Icons.history,
            route: '/business/$b/reports/activity-logs',
            keywords: const ['لاگ', 'فعالیت', 'سیستم'],
            permissionSection: 'settings',
            permissionAction: 'read',
          ),
        ],
      ),
    ];
  }
}

class _ReportSection {
  final String id;
  final String title;
  final IconData icon;
  final bool initiallyExpanded;
  final List<_ReportLink> items;

  const _ReportSection({
    required this.id,
    required this.title,
    required this.icon,
    this.initiallyExpanded = false,
    required this.items,
  });
}

class _ReportLink {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final List<String> keywords;
  final String? permissionSection;
  final String permissionAction;

  const _ReportLink({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    this.keywords = const <String>[],
    this.permissionSection,
    this.permissionAction = 'view',
  });
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHeaderDelegate({
    required this.height,
    required this.child,
  });

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerLeft,
      color: cs.surface,
      padding: const EdgeInsets.symmetric(vertical: 6),
      foregroundDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: overlapsContent ? 0.7 : 0.0),
          ),
        ),
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

enum _DesktopSort {
  recommended,
  alphabetical,
}

