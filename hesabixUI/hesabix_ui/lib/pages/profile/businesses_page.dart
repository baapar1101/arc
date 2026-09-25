import 'package:hesabix_ui/theme/glass.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/business_switcher_prefs.dart';
import '../../core/mobile_launcher_prefs.dart';
import '../../models/business_dashboard_models.dart';
import '../../services/business_dashboard_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/profile/business_switcher_widgets.dart';
import '../../widgets/profile/businesses_empty_state.dart';
import '../../widgets/profile/businesses_hub_utils.dart';

/// صفحه انتخاب فضای کاری — سوییچر خلوت، نه هاب مدیریت.
class BusinessesPage extends StatefulWidget {
  final AuthStore authStore;

  const BusinessesPage({super.key, required this.authStore});

  @override
  State<BusinessesPage> createState() => _BusinessesPageState();
}

class _BusinessesPageState extends State<BusinessesPage> {
  static const int _pageSize = 24;
  static const double _contentMaxWidth = 560;
  /// جست‌وجو از دو کسب‌وکار به بالا؛ با کوئری فعال همیشه نمایش داده می‌شود.
  static const int _searchThreshold = 2;

  final BusinessDashboardService _service = BusinessDashboardService(ApiClient());
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<BusinessWithPermission> _businesses = [];
  bool _loading = true;
  bool _softRefreshing = false;
  bool _isLoadingMore = false;
  String? _error;
  int _skip = 0;
  bool _hasMore = true;
  int? _totalCount;
  String _searchQuery = '';
  Timer? _searchDebounce;
  int _searchRequestId = 0;

  BusinessSwitcherSort _sort = BusinessSwitcherSort.recent;
  List<int> _lastUsedIds = const [];

  AuthStore get _authStore => widget.authStore;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchTextChanged);
    _authStore.addListener(_onAuthChanged);
    _init();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _authStore.removeListener(_onAuthChanged);
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      final next = _searchController.text.trim();
      if (next == _searchQuery) return;
      setState(() => _searchQuery = next);
      _loadBusinesses(reset: true, soft: _businesses.isNotEmpty || next.isNotEmpty);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    if (_searchQuery.isEmpty) return;
    setState(() => _searchQuery = '');
    _loadBusinesses(reset: true, soft: true);
  }

  void _onScroll() {
    if (_isLoadingMore || !_hasMore || _loading || _softRefreshing) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240 && pos.maxScrollExtent > 0) {
      _loadMore();
    }
  }

  Future<void> _init() async {
    // از AuthStore مشترک اپ استفاده می‌کنیم؛ نباید store خالی جدید bind شود
    // (باعث race روی Authorization و پاک شدن سشن می‌شود).
    final bound = ApiClient.getAuthStore();
    if (bound != _authStore) {
      ApiClient.bindAuthStore(_authStore);
    }
    final uid = _authStore.currentUserId;
    final sort = await BusinessSwitcherPrefs.sortMode(uid);
    final lastUsed = await BusinessSwitcherPrefs.lastUsedIds(uid);
    if (!mounted) return;
    setState(() {
      _sort = sort;
      _lastUsedIds = lastUsed;
    });
    await _loadBusinesses();
  }

  ({String sortBy, bool sortDesc}) get _apiSort {
    switch (_sort) {
      case BusinessSwitcherSort.name:
        return (sortBy: 'name', sortDesc: false);
      case BusinessSwitcherSort.created:
        return (sortBy: 'created_at', sortDesc: true);
      case BusinessSwitcherSort.recent:
        return (sortBy: 'created_at', sortDesc: true);
    }
  }

  List<BusinessWithPermission> _orderForDisplay(List<BusinessWithPermission> items) {
    if (_sort != BusinessSwitcherSort.recent || items.length < 2) return items;

    final activeId = _activeBusinessId;
    final rank = <int, int>{};
    for (var i = 0; i < _lastUsedIds.length; i++) {
      rank[_lastUsedIds[i]] = i;
    }

    int score(BusinessWithPermission b) {
      if (activeId != null && b.id == activeId) return -2;
      final r = rank[b.id];
      if (r != null) return r;
      return 100000 + b.id;
    }

    final copy = List<BusinessWithPermission>.of(items);
    copy.sort((a, b) => score(a).compareTo(score(b)));
    return copy;
  }

  Future<void> _loadBusinesses({bool reset = true, bool soft = false}) async {
    final requestId = ++_searchRequestId;
    try {
      setState(() {
        if (reset) {
          _skip = 0;
          _hasMore = true;
          if (soft && (_businesses.isNotEmpty || _searchQuery.isNotEmpty)) {
            _softRefreshing = true;
            _loading = false;
          } else {
            _loading = true;
            _softRefreshing = false;
            _businesses = [];
          }
        }
        _error = null;
      });

      final currentSkip = reset ? 0 : _skip;
      final apiSort = _apiSort;
      final result = await _service.getUserBusinessesPaginated(
        take: _pageSize,
        skip: currentSkip,
        sortBy: apiSort.sortBy,
        sortDesc: apiSort.sortDesc,
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );

      if (!mounted || requestId != _searchRequestId) return;
      final newBusinesses = (result['items'] as List<BusinessWithPermission>)
          .where((b) => !b.isDeleted || b.isDeletionPending)
          .toList();
      final pagination = result['pagination'] as Map<String, dynamic>?;

      setState(() {
        if (reset) {
          _businesses = _orderForDisplay(newBusinesses);
          _skip = newBusinesses.length;
        } else {
          final merged = [..._businesses, ...newBusinesses];
          _businesses = _orderForDisplay(merged);
          _skip += newBusinesses.length;
        }
        _loading = false;
        _softRefreshing = false;
        if (pagination != null) {
          _hasMore = pagination['has_next'] as bool? ?? false;
          final total = pagination['total'];
          if (total is int) {
            _totalCount = total;
          } else if (total is num) {
            _totalCount = total.toInt();
          }
        } else {
          _hasMore = newBusinesses.length >= _pageSize;
          if (reset) _totalCount = newBusinesses.length;
        }
      });
    } catch (e) {
      if (!mounted || requestId != _searchRequestId) return;
      final err = ErrorExtractor.forContext(e, context);
      setState(() {
        _loading = false;
        _softRefreshing = false;
        _error = err;
      });
      SnackBarHelper.showError(
        context,
        message: '${AppLocalizations.of(context).dataLoadingError}: $err',
      );
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _loading || _softRefreshing) return;
    setState(() => _isLoadingMore = true);
    try {
      final apiSort = _apiSort;
      final result = await _service.getUserBusinessesPaginated(
        take: _pageSize,
        skip: _skip,
        sortBy: apiSort.sortBy,
        sortDesc: apiSort.sortDesc,
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );
      if (!mounted) return;
      final newBusinesses = (result['items'] as List<BusinessWithPermission>)
          .where((b) => !b.isDeleted || b.isDeletionPending)
          .toList();
      final pagination = result['pagination'] as Map<String, dynamic>?;

      setState(() {
        final merged = [..._businesses, ...newBusinesses];
        _businesses = _orderForDisplay(merged);
        _skip += newBusinesses.length;
        _isLoadingMore = false;
        if (pagination != null) {
          _hasMore = pagination['has_next'] as bool? ?? false;
          final total = pagination['total'];
          if (total is int) {
            _totalCount = total;
          } else if (total is num) {
            _totalCount = total.toInt();
          }
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
    final lastUsed = await BusinessSwitcherPrefs.lastUsedIds(_authStore.currentUserId);
    if (mounted) setState(() => _lastUsedIds = lastUsed);
    await _loadBusinesses(reset: true, soft: _businesses.isNotEmpty);
  }

  Future<void> _changeSort(BusinessSwitcherSort next) async {
    if (next == _sort) return;
    setState(() => _sort = next);
    await BusinessSwitcherPrefs.setSortMode(_authStore.currentUserId, next);
    if (!mounted) return;
    await _loadBusinesses(reset: true, soft: _businesses.isNotEmpty);
  }

  bool get _isSearching => _searchQuery.isNotEmpty;

  bool get _showSearch {
    if (_isSearching) return true;
    if (_loading && _businesses.isEmpty) return false;
    final count = _totalCount ?? _businesses.length;
    return count >= _searchThreshold;
  }

  bool get _showSort {
    if (_loading && _businesses.isEmpty) return false;
    if (_error != null) return false;
    final count = _totalCount ?? _businesses.length;
    return count >= _searchThreshold || _isSearching;
  }

  int? get _activeBusinessId => _authStore.currentBusiness?.id;

  Future<void> _recordAndEnter(int businessId, Future<void> Function() enter) async {
    try {
      await BusinessSwitcherPrefs.recordLastUsed(_authStore.currentUserId, businessId);
      final lastUsed = await BusinessSwitcherPrefs.lastUsedIds(_authStore.currentUserId);
      if (mounted) setState(() => _lastUsedIds = lastUsed);
    } catch (e, st) {
      // ثبت محلی نباید جلوی ورود به کسب‌وکار را بگیرد.
      assert(() {
        debugPrint('BusinessSwitcherPrefs.recordLastUsed failed: $e\n$st');
        return true;
      }());
    }
    await enter();
  }

  Future<void> _navigateToBusiness(
    int businessId, {
    bool forceChooseMode = false,
  }) async {
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

    if (!ResponsiveHelper.isMobile(context)) {
      await MobileLauncherPrefs.clearResumeLauncher(_authStore.currentUserId);
      if (!mounted) return;
      await _recordAndEnter(businessId, () async {
        if (!mounted) return;
        context.go('/business/$businessId/dashboard');
      });
      return;
    }

    final preferred = forceChooseMode
        ? null
        : await MobileLauncherPrefs.preferredEntryMode(_authStore.currentUserId);
    if (!mounted) return;

    if (preferred == MobileBusinessEntryMode.standard) {
      await _enterStandard(businessId);
      return;
    }
    if (preferred == MobileBusinessEntryMode.launcher) {
      await _enterLauncher(businessId);
      return;
    }

    await _showEntryModeSheet(businessId);
  }

  Future<void> _enterStandard(int businessId) async {
    await MobileLauncherPrefs.clearResumeLauncher(_authStore.currentUserId);
    if (!mounted) return;
    await _recordAndEnter(businessId, () async {
      if (!mounted) return;
      context.go('/business/$businessId/dashboard');
    });
  }

  Future<void> _enterLauncher(int businessId) async {
    await MobileLauncherPrefs.setResumeLauncher(
      _authStore.currentUserId,
      businessId,
    );
    if (!mounted) return;
    await _recordAndEnter(businessId, () async {
      if (!mounted) return;
      // یک فریم صبر تا bottom sheet / route قبلی کاملاً بسته شود (رفع race روی اندروید).
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      context.go(MobileLauncherPrefs.launcherHomePath(businessId));
    });
  }

  Future<void> _showEntryModeSheet(int businessId) async {
    final t = AppLocalizations.of(context);

    final mode = await showGlassModalBottomSheet<MobileBusinessEntryMode>(
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    t.mobileLauncherChooseModeHint,
                    style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  title: Text(t.mobileLauncherModeStandard),
                  onTap: () => Navigator.of(sheetCtx).pop(
                    MobileBusinessEntryMode.standard,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.apps_outlined),
                  title: Text(t.mobileLauncherModeLauncher),
                  onTap: () => Navigator.of(sheetCtx).pop(
                    MobileBusinessEntryMode.launcher,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || mode == null) return;
    await MobileLauncherPrefs.setPreferredEntryMode(
      _authStore.currentUserId,
      mode,
    );
    if (!mounted) return;
    if (mode == MobileBusinessEntryMode.standard) {
      await _enterStandard(businessId);
    } else {
      await _enterLauncher(businessId);
    }
  }

  void _goNewBusiness() => context.go('/user/profile/new-business');

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final padding = ResponsiveHelper.getPadding(context);
    final showToolsChrome = !_loading && _error == null && (_showSearch || _showSort);
    final showInitialSkeleton = _loading && _businesses.isEmpty;
    final noBusinessesAtAll = !_isSearching && _businesses.isEmpty;
    final noSearchResults = _isSearching && _businesses.isEmpty;

    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.slash): () {
            if (_showSearch && !_loading && _error == null) {
              _searchFocusNode.requestFocus();
            }
          },
        },
        child: Focus(
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
                      constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(padding, padding + 8, padding, 0),
                        child: _buildHeader(context, t),
                      ),
                    ),
                  ),
                ),
                if (showToolsChrome)
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(padding, 12, padding, 4),
                          child: _buildToolsRow(context, t),
                        ),
                      ),
                    ),
                  ),
                if (showToolsChrome && _softRefreshing)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  ),
                if (showInitialSkeleton)
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                        child: Padding(
                          padding: EdgeInsets.all(padding),
                          child: const BusinessSwitcherSkeleton(),
                        ),
                      ),
                    ),
                  )
                else if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildErrorState(t, padding),
                  )
                else if (noBusinessesAtAll)
                  const SliverFillRemaining(
                    hasScrollBody: true,
                    child: BusinessesEmptyState(),
                  )
                else if (noSearchResults)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: BusinessesEmptyState(
                      noSearchResults: true,
                      searchQuery: _searchQuery,
                      onClearSearch: _clearSearch,
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(padding, 4, padding, padding + 24),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                          child: Column(
                            children: [
                              for (var i = 0; i < _businesses.length; i++)
                                BusinessSwitcherRow(
                                  business: _businesses[i],
                                  authStore: _authStore,
                                  isActive: _activeBusinessId == _businesses[i].id,
                                  showDivider: i < _businesses.length - 1,
                                  onEnter: () => _navigateToBusiness(_businesses[i].id),
                                  onLongPress: ResponsiveHelper.isMobile(context)
                                      ? () => _navigateToBusiness(
                                            _businesses[i].id,
                                            forceChooseMode: true,
                                          )
                                      : null,
                                  onRefresh: _refresh,
                                ),
                              if (_isLoadingMore)
                                const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(child: CircularProgressIndicator()),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations t) {
    final theme = Theme.of(context);
    final canAdd = !_loading && _error == null && (_businesses.isNotEmpty || _isSearching);
    final count = _totalCount ?? _businesses.length;
    final String? subtitle;
    if (_loading || _error != null) {
      subtitle = null;
    } else if (_businesses.isNotEmpty || _isSearching) {
      if (count > 1 || _isSearching) {
        subtitle = t.businessesHubCount(count);
      } else {
        subtitle = t.businessesSwitcherSubtitle;
      }
    } else {
      subtitle = null;
    }

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
                  fontWeight: FontWeight.w700,
                  fontSize: ResponsiveHelper.isMobile(context) ? 26 : 30,
                  letterSpacing: -0.3,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (canAdd)
          TextButton.icon(
            onPressed: _goNewBusiness,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(t.newBusiness),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }

  Widget _buildToolsRow(BuildContext context, AppLocalizations t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showSearch)
          Expanded(child: _buildSearchField(context, t))
        else
          const Spacer(),
        if (_showSort) ...[
          if (_showSearch) const SizedBox(width: 4),
          _buildSortButton(context, t),
        ],
      ],
    );
  }

  Widget _buildSortButton(BuildContext context, AppLocalizations t) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<BusinessSwitcherSort>(
      tooltip: t.businessesHubSortTooltip,
      initialValue: _sort,
      onSelected: _changeSort,
      itemBuilder: (ctx) => [
        CheckedPopupMenuItem(
          value: BusinessSwitcherSort.recent,
          checked: _sort == BusinessSwitcherSort.recent,
          child: Text(t.businessesHubSortRecent),
        ),
        CheckedPopupMenuItem(
          value: BusinessSwitcherSort.name,
          checked: _sort == BusinessSwitcherSort.name,
          child: Text(t.businessesHubSortName),
        ),
        CheckedPopupMenuItem(
          value: BusinessSwitcherSort.created,
          checked: _sort == BusinessSwitcherSort.created,
          child: Text(t.businessesHubSortCreated),
        ),
      ],
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, top: 2),
        child: Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.sort_rounded,
              size: 22,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context, AppLocalizations t) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: t.businessesHubSearchHint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: ListenableBuilder(
          listenable: _searchController,
          builder: (context, _) {
            if (_searchController.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              tooltip: t.businessesHubClearSearch,
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: _clearSearch,
            );
          },
        ),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        isDense: true,
        helperText: ResponsiveHelper.isDesktop(context) ? t.businessesHubSearchShortcut : null,
      ),
    );
  }

  Widget _buildErrorState(AppLocalizations t, double padding) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(padding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: Theme.of(context).colorScheme.error),
            SizedBox(height: padding),
            Text(_error!, textAlign: TextAlign.center),
            SizedBox(height: padding),
            FilledButton.icon(
              onPressed: () => _loadBusinesses(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(t.retry),
            ),
          ],
        ),
      ),
    );
  }
}
