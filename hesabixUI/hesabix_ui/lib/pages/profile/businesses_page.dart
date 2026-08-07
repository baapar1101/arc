import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/businesses_hub_prefs.dart';
import '../../core/mobile_launcher_prefs.dart';
import '../../models/business_dashboard_models.dart';
import '../../services/business_dashboard_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/profile/business_hub_card.dart';
import '../../widgets/profile/business_hub_swipe_wrapper.dart';
import '../../widgets/profile/business_hub_actions.dart';
import '../../widgets/profile/business_hub_stats_preview.dart';
import '../../widgets/profile/businesses_empty_state.dart';
import '../../widgets/profile/businesses_hub_skeleton.dart';
import '../../widgets/profile/businesses_hub_utils.dart';

class BusinessesPage extends StatefulWidget {
  const BusinessesPage({super.key});

  @override
  State<BusinessesPage> createState() => _BusinessesPageState();
}

class _BusinessesPageState extends State<BusinessesPage> {
  static const int _pageSize = 12;
  static const double _contentMaxWidth = 1360;
  static const double _pickerMaxWidth = 720;
  /// زیر این تعداد، ابزارهای جستجو/فیلتر به‌صورت پیش‌فرض مخفی می‌مانند.
  static const int _hubToolsThreshold = 3;

  final BusinessDashboardService _service = BusinessDashboardService(ApiClient());
  final AuthStore _authStore = AuthStore();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<BusinessWithPermission> _businesses = [];
  Set<int> _pinnedIds = {};
  List<int> _recentIds = [];
  bool _loading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _skip = 0;
  bool _hasMore = true;

  String _searchQuery = '';
  BusinessesOwnershipFilter _ownershipFilter = BusinessesOwnershipFilter.all;
  BusinessesSortMode _sortMode = BusinessesSortMode.newest;
  BusinessesViewMode _viewMode = BusinessesViewMode.list;
  Timer? _searchDebounce;
  bool _toolsForced = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    _init();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  void _onScroll() {
    if (_isLoadingMore || !_hasMore || _loading) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240 && pos.maxScrollExtent > 0) {
      _loadMore();
    }
  }

  Future<void> _init() async {
    ApiClient.bindAuthStore(_authStore);
    await _authStore.load();
    await _loadPrefs();
    await _loadBusinesses();
  }

  Future<void> _loadPrefs() async {
    final userId = _authStore.currentUserId;
    final pinned = await BusinessesHubPrefs.getPinnedIds(userId);
    final recent = await BusinessesHubPrefs.getRecentIds(userId);
    if (!mounted) return;
    setState(() {
      _pinnedIds = pinned;
      _recentIds = recent;
    });
  }

  Future<void> _loadBusinesses({bool reset = true}) async {
    try {
      setState(() {
        if (reset) {
          _loading = true;
          _skip = 0;
          _hasMore = true;
          _businesses = [];
        }
        _error = null;
      });

      final currentSkip = reset ? 0 : _skip;
      final result = await _service.getUserBusinessesPaginated(
        take: _pageSize,
        skip: currentSkip,
        sortBy: 'created_at',
        sortDesc: true,
      );

      if (!mounted) return;
      final newBusinesses = (result['items'] as List<BusinessWithPermission>)
          .where((b) => !b.isDeleted || b.isDeletionPending)
          .toList();
      final pagination = result['pagination'] as Map<String, dynamic>?;

      setState(() {
        if (reset) {
          _businesses = newBusinesses;
          _skip = newBusinesses.length;
        } else {
          _businesses.addAll(newBusinesses);
          _skip += newBusinesses.length;
        }
        _loading = false;
        if (pagination != null) {
          _hasMore = pagination['has_next'] as bool? ?? false;
        } else {
          _hasMore = newBusinesses.length >= _pageSize;
        }
      });
    } catch (e) {
      if (!mounted) return;
      final err = ErrorExtractor.forContext(e, context);
      setState(() {
        _loading = false;
        _error = err;
      });
      SnackBarHelper.showError(
        context,
        message: '${AppLocalizations.of(context).dataLoadingError}: $err',
      );
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _loading) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await _service.getUserBusinessesPaginated(
        take: _pageSize,
        skip: _skip,
        sortBy: 'created_at',
        sortDesc: true,
      );
      if (!mounted) return;
      final newBusinesses = (result['items'] as List<BusinessWithPermission>)
          .where((b) => !b.isDeleted || b.isDeletionPending)
          .toList();
      final pagination = result['pagination'] as Map<String, dynamic>?;

      setState(() {
        _businesses.addAll(newBusinesses);
        _skip += newBusinesses.length;
        _isLoadingMore = false;
        if (pagination != null) {
          _hasMore = pagination['has_next'] as bool? ?? false;
        } else {
          _hasMore = newBusinesses.length >= _pageSize;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      SnackBarHelper.showError(
        context,
        message: AppLocalizations.of(context).businessesHubLoadMoreFailed,
      );
    }
  }

  Future<void> _refresh() async {
    await _loadPrefs();
    await _loadBusinesses();
  }

  List<BusinessWithPermission> _applyFilters(List<BusinessWithPermission> source) {
    var list = source.toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((b) => b.name.toLowerCase().contains(q)).toList();
    }

    switch (_ownershipFilter) {
      case BusinessesOwnershipFilter.owner:
        list = list.where((b) => b.isOwner).toList();
      case BusinessesOwnershipFilter.member:
        list = list.where((b) => !b.isOwner).toList();
      case BusinessesOwnershipFilter.pendingDeletion:
        list = list.where((b) => b.isDeletionPending).toList();
      case BusinessesOwnershipFilter.all:
        break;
    }

    list.sort((a, b) {
      final aPinned = _pinnedIds.contains(a.id);
      final bPinned = _pinnedIds.contains(b.id);
      if (aPinned != bPinned) return aPinned ? -1 : 1;

      switch (_sortMode) {
        case BusinessesSortMode.newest:
          return _compareDate(b.createdAt, a.createdAt);
        case BusinessesSortMode.oldest:
          return _compareDate(a.createdAt, b.createdAt);
        case BusinessesSortMode.nameAsc:
          return a.name.compareTo(b.name);
        case BusinessesSortMode.nameDesc:
          return b.name.compareTo(a.name);
      }
    });

    return list;
  }

  int _compareDate(String a, String b) {
    try {
      return DateTime.parse(a).compareTo(DateTime.parse(b));
    } catch (_) {
      return a.compareTo(b);
    }
  }

  List<BusinessWithPermission> get _recentBusinesses {
    final byId = {for (final b in _businesses) b.id: b};
    return _recentIds
        .map((id) => byId[id])
        .whereType<BusinessWithPermission>()
        .where((b) => !businessBlocksAccess(b.isDeleted, b.isDeletionPending))
        .take(6)
        .toList();
  }

  Future<void> _navigateToBusiness(int businessId) async {
    final business = _businesses.cast<BusinessWithPermission?>().firstWhere(
          (b) => b?.id == businessId,
          orElse: () => null,
        );
    if (business == null) return;

    if (businessBlocksAccess(business.isDeleted, business.isDeletionPending)) {
      SnackBarHelper.showError(
        context,
        message: business.isDeletionPending
            ? AppLocalizations.of(context).businessesHubDeletionPending
            : AppLocalizations.of(context).accessDenied,
      );
      return;
    }

    await BusinessesHubPrefs.recordAccess(_authStore.currentUserId, businessId);
    await _loadPrefs();
    if (!mounted) return;

    final t = AppLocalizations.of(context);
    if (!ResponsiveHelper.isMobile(context)) {
      await MobileLauncherPrefs.clearResumeLauncher(_authStore.currentUserId);
      if (!mounted) return;
      context.go('/business/$businessId/dashboard');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text(
                    t.mobileLauncherChooseModeTitle,
                    style: Theme.of(sheetCtx).textTheme.titleMedium,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  title: Text(t.mobileLauncherModeStandard),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    await MobileLauncherPrefs.clearResumeLauncher(_authStore.currentUserId);
                    if (!mounted) return;
                    context.go('/business/$businessId/dashboard');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.apps_outlined),
                  title: Text(t.mobileLauncherModeLauncher),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    await MobileLauncherPrefs.setResumeLauncher(
                      _authStore.currentUserId,
                      businessId,
                    );
                    if (!mounted) return;
                    context.go(MobileLauncherPrefs.launcherHomePath(businessId));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _togglePin(int businessId, bool pinned) async {
    await BusinessesHubPrefs.togglePin(_authStore.currentUserId, businessId);
    await _loadPrefs();
    if (mounted) setState(() {});
  }

  bool get _useListLayout {
    if (ResponsiveHelper.isMobile(context)) return true;
    if (!_showHubTools) return true;
    return _viewMode == BusinessesViewMode.list;
  }

  /// حالت هاب کامل فقط وقتی تعداد زیاد است یا کاربر ابزارها را باز کرده.
  bool get _showHubTools =>
      _toolsForced || _businesses.length >= _hubToolsThreshold;

  double get _activeContentMaxWidth {
    if (_showHubTools || _loading) return _contentMaxWidth;
    return _businesses.length <= 1 ? _pickerMaxWidth : 880;
  }

  void _toggleTools() {
    setState(() {
      _toolsForced = !_toolsForced;
      if (!_toolsForced) {
        _searchController.clear();
        _searchQuery = '';
        _ownershipFilter = BusinessesOwnershipFilter.all;
        _sortMode = BusinessesSortMode.newest;
        _viewMode = BusinessesViewMode.list;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final padding = ResponsiveHelper.getPadding(context);
    final contentMax = _activeContentMaxWidth;
    final horizontalPad = _horizontalPadding(context, padding, contentMax);
    final filtered = _applyFilters(_businesses);
    final hasActiveFilters = _searchQuery.isNotEmpty || _ownershipFilter != BusinessesOwnershipFilter.all;
    final showHubChrome = _showHubTools;
    final showRecent = showHubChrome &&
        !hasActiveFilters &&
        _recentBusinesses.isNotEmpty &&
        !_loading &&
        _error == null;
    final simplifiedCards = !showHubChrome;
    final prominentCard = simplifiedCards && _businesses.length == 1;

    return Scaffold(
      floatingActionButton: isMobile && !_loading && _error == null && _businesses.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/user/profile/new-business'),
              icon: const Icon(Icons.add_rounded),
              label: Text(t.newBusiness),
            )
          : null,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.slash): () {
            if (!_loading && _error == null && _businesses.isNotEmpty && showHubChrome) {
              _searchFocusNode.requestFocus();
            }
          },
        },
        child: Focus(
          autofocus: false,
          child: RefreshIndicator(
            onRefresh: _refresh,
            edgeOffset: 8,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: contentMax),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(horizontalPad, padding, horizontalPad, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildPageHeader(context, t, filtered.length, isMobile, showHubChrome),
                            SizedBox(height: padding),
                            if (!_loading && _error == null && _businesses.isNotEmpty)
                              AnimatedSize(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: showHubChrome
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          _buildToolbar(context, t, isMobile),
                                          SizedBox(height: padding),
                                        ],
                                      )
                                    : _buildSimpleToolsToggle(context, t),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_loading)
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: contentMax),
                        child: Padding(
                          padding: EdgeInsets.all(horizontalPad),
                          child: BusinessesHubSkeleton(listMode: _useListLayout),
                        ),
                      ),
                    ),
                  )
                else if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildErrorState(t, padding),
                  )
                else if (_businesses.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: BusinessesEmptyState(),
                  )
                else if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: BusinessesEmptyState(
                      noSearchResults: true,
                      searchQuery: _searchQuery,
                    ),
                  )
                else ...[
                  if (showRecent)
                    SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: contentMax),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad, padding),
                            child: _buildRecentSection(context, t),
                          ),
                        ),
                      ),
                    ),
                  if (showHubChrome)
                    SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: contentMax),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad, 8),
                            child: Text(
                              t.businessesHubAllSection,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_useListLayout)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPad,
                        0,
                        horizontalPad,
                        padding + (isMobile ? 72 : 16),
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index >= filtered.length) {
                              return const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final business = filtered[index];
                            return Padding(
                              padding: EdgeInsets.only(bottom: index < filtered.length - 1 ? 10 : 0),
                              child: _buildBusinessListItem(
                                context,
                                t,
                                business,
                                isMobile,
                                simplified: simplifiedCards,
                                prominent: prominentCard,
                              ),
                            );
                          },
                          childCount: filtered.length + (_isLoadingMore ? 1 : 0),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad, padding + 16),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _gridColumns(context),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          mainAxisExtent: 228,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index >= filtered.length) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final business = filtered[index];
                            return BusinessHubCard(
                              business: business,
                              authStore: _authStore,
                              isPinned: _pinnedIds.contains(business.id),
                              listLayout: false,
                              simplified: simplifiedCards,
                              prominent: false,
                              dashboardService: _service,
                              onEnter: () => _navigateToBusiness(business.id),
                              onPinChanged: (pinned) => _togglePin(business.id, pinned),
                              onRefresh: _refresh,
                            );
                          },
                          childCount: filtered.length + (_isLoadingMore ? _gridColumns(context) : 0),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _horizontalPadding(BuildContext context, double basePadding, double contentMax) {
    // Center + ConstrainedBox عرض را محدود و وسط‌چین می‌کند.
    return basePadding;
  }

  int _gridColumns(BuildContext context) {
    final bp = ResponsiveHelper.breakpoint(context);
    return switch (bp) {
      'sm' => 2,
      'md' => 2,
      'lg' => 3,
      _ => 4,
    };
  }

  Widget _buildPageHeader(
    BuildContext context,
    AppLocalizations t,
    int count,
    bool isMobile,
    bool showHubChrome,
  ) {
    final theme = Theme.of(context);
    final subtitle = _businesses.isEmpty
        ? t.businessesHubSubtitle
        : showHubChrome
            ? t.businessesHubCount(count)
            : t.businessesHubPickSubtitle;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.businesses,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: isMobile ? 24 : (showHubChrome ? 28 : 30),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (!isMobile) ...[
          const SizedBox(width: 12),
          if (_businesses.isNotEmpty && _businesses.length < _hubToolsThreshold)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: TextButton.icon(
                onPressed: _toggleTools,
                icon: Icon(showHubChrome ? Icons.tune_rounded : Icons.search_rounded, size: 18),
                label: Text(showHubChrome ? t.businessesHubHideTools : t.businessesHubShowTools),
              ),
            ),
          FilledButton.icon(
            onPressed: () => context.go('/user/profile/new-business'),
            icon: const Icon(Icons.add_rounded),
            label: Text(t.newBusiness),
          ),
        ],
      ],
    );
  }

  Widget _buildSimpleToolsToggle(BuildContext context, AppLocalizations t) {
    if (!ResponsiveHelper.isMobile(context)) {
      return const SizedBox.shrink();
    }
    if (_businesses.length >= _hubToolsThreshold) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: _toggleTools,
          icon: const Icon(Icons.search_rounded, size: 18),
          label: Text(t.businessesHubShowTools),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, AppLocalizations t, bool isMobile) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_toolsForced && _businesses.length < _hubToolsThreshold && isMobile)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _toggleTools,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(t.businessesHubHideTools),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          decoration: InputDecoration(
            hintText: t.businessesHubSearchHint,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            helperText: ResponsiveHelper.isDesktop(context) ? t.businessesHubSearchShortcut : null,
          ),
        ),
        const SizedBox(height: 10),
        if (isMobile) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(t.businessesHubFilterAll, BusinessesOwnershipFilter.all),
                _filterChip(t.businessesHubFilterOwner, BusinessesOwnershipFilter.owner),
                _filterChip(t.businessesHubFilterMember, BusinessesOwnershipFilter.member),
                _filterChip(t.businessesHubFilterPendingDeletion, BusinessesOwnershipFilter.pendingDeletion),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _sortMenu(context, t, expanded: true),
        ] else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(t.businessesHubFilterAll, BusinessesOwnershipFilter.all),
                _filterChip(t.businessesHubFilterOwner, BusinessesOwnershipFilter.owner),
                _filterChip(t.businessesHubFilterMember, BusinessesOwnershipFilter.member),
                _filterChip(t.businessesHubFilterPendingDeletion, BusinessesOwnershipFilter.pendingDeletion),
                const SizedBox(width: 8),
                _sortMenu(context, t),
                const SizedBox(width: 4),
                _viewToggle(context, t),
              ],
            ),
          ),
      ],
    );
  }

  Widget _filterChip(String label, BusinessesOwnershipFilter value) {
    final selected = _ownershipFilter == value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _ownershipFilter = value),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _sortMenu(BuildContext context, AppLocalizations t, {bool expanded = false}) {
    return SizedBox(
      width: expanded ? double.infinity : 200,
      child: DropdownMenu<BusinessesSortMode>(
        key: ValueKey(_sortMode),
        initialSelection: _sortMode,
        leadingIcon: const Icon(Icons.sort_rounded, size: 20),
        expandedInsets: EdgeInsets.zero,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          isDense: true,
        ),
        dropdownMenuEntries: [
          DropdownMenuEntry(value: BusinessesSortMode.newest, label: t.businessesHubSortNewest),
          DropdownMenuEntry(value: BusinessesSortMode.oldest, label: t.businessesHubSortOldest),
          DropdownMenuEntry(value: BusinessesSortMode.nameAsc, label: t.businessesHubSortNameAsc),
          DropdownMenuEntry(value: BusinessesSortMode.nameDesc, label: t.businessesHubSortNameDesc),
        ],
        onSelected: (v) {
          if (v != null) setState(() => _sortMode = v);
        },
      ),
    );
  }

  Widget _viewToggle(BuildContext context, AppLocalizations t) {
    return SegmentedButton<BusinessesViewMode>(
      segments: [
        ButtonSegment(
          value: BusinessesViewMode.list,
          icon: const Icon(Icons.view_list_rounded, size: 18),
          label: Text(t.businessesHubViewList),
        ),
        ButtonSegment(
          value: BusinessesViewMode.grid,
          icon: const Icon(Icons.grid_view_rounded, size: 18),
          label: Text(t.businessesHubViewGrid),
        ),
      ],
      selected: {_viewMode},
      onSelectionChanged: (s) => setState(() => _viewMode = s.first),
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }

  Widget _buildRecentSection(BuildContext context, AppLocalizations t) {
    final theme = Theme.of(context);
    final recent = _recentBusinesses;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              t.businessesHubRecentSection,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recent.length,
            separatorBuilder: (_, i) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final business = recent[index];
              final cs = theme.colorScheme;
              final avatarColor = businessAvatarColor(business.name, cs);
              return Material(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _navigateToBusiness(business.id),
                  child: Container(
                    width: 148,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: avatarColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            businessAvatarInitial(business.name),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          business.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          business.isOwner ? t.owner : t.member,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBusinessListItem(
    BuildContext context,
    AppLocalizations t,
    BusinessWithPermission business,
    bool isMobile, {
    bool simplified = false,
    bool prominent = false,
  }) {
    final card = BusinessHubCard(
      business: business,
      authStore: _authStore,
      isPinned: _pinnedIds.contains(business.id),
      listLayout: true,
      simplified: simplified,
      prominent: prominent,
      dashboardService: _service,
      onEnter: () => _navigateToBusiness(business.id),
      onPinChanged: (pinned) => _togglePin(business.id, pinned),
      onRefresh: _refresh,
    );

    if (!isMobile) return card;

    final cs = Theme.of(context).colorScheme;
    final pinned = _pinnedIds.contains(business.id);
    final actions = <BusinessHubSwipeAction>[
      BusinessHubSwipeAction(
        icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
        background: cs.primaryContainer,
        foreground: cs.onPrimaryContainer,
        label: pinned ? t.businessesHubUnpin : t.businessesHubPin,
        onTap: () => _togglePin(business.id, !pinned),
      ),
      BusinessHubSwipeAction(
        icon: Icons.insights_outlined,
        background: Colors.blue.shade600,
        foreground: Colors.white,
        label: t.businessesHubStatsTitle,
        onTap: () => BusinessHubStatsSheet.show(
          context,
          businessName: business.name,
          businessId: business.id,
          service: _service,
        ),
      ),
    ];

    if (business.isDeletionPending && business.isOwner) {
      actions.add(BusinessHubSwipeAction(
        icon: Icons.restore_rounded,
        background: Colors.green.shade600,
        foreground: Colors.white,
        label: t.businessesHubRestore,
        onTap: () => BusinessHubActions.restore(
          context,
          business: business,
          onRefresh: _refresh,
        ),
      ));
    } else if (!business.isOwner) {
      actions.add(BusinessHubSwipeAction(
        icon: Icons.exit_to_app_rounded,
        background: cs.errorContainer,
        foreground: cs.onErrorContainer,
        label: t.businessesHubLeave,
        onTap: () => BusinessHubActions.leave(
          context,
          business: business,
          authStore: _authStore,
          onRefresh: _refresh,
        ),
      ));
    } else {
      actions.add(BusinessHubSwipeAction(
        icon: Icons.login_rounded,
        background: Colors.teal.shade600,
        foreground: Colors.white,
        label: t.businessesHubEnter,
        onTap: () => _navigateToBusiness(business.id),
      ));
    }

    return BusinessHubSwipeWrapper(
      enabled: isMobile,
      actions: actions,
      child: card,
    );
  }

  Widget _buildErrorState(AppLocalizations t, double padding) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(padding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 72, color: Theme.of(context).colorScheme.error),
            SizedBox(height: padding),
            Text(_error!, textAlign: TextAlign.center),
            SizedBox(height: padding),
            FilledButton.icon(
              onPressed: _loadBusinesses,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(t.retry),
            ),
          ],
        ),
      ),
    );
  }
}
