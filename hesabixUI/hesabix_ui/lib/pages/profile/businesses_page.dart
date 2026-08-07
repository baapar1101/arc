import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
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
  const BusinessesPage({super.key});

  @override
  State<BusinessesPage> createState() => _BusinessesPageState();
}

class _BusinessesPageState extends State<BusinessesPage> {
  static const int _pageSize = 24;
  static const double _contentMaxWidth = 560;
  static const int _searchThreshold = 5;

  final BusinessDashboardService _service = BusinessDashboardService(ApiClient());
  final AuthStore _authStore = AuthStore();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<BusinessWithPermission> _businesses = [];
  bool _loading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _skip = 0;
  bool _hasMore = true;
  String _searchQuery = '';
  Timer? _searchDebounce;

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
    await _loadBusinesses();
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
    await _loadBusinesses();
  }

  List<BusinessWithPermission> get _visibleBusinesses {
    if (_searchQuery.isEmpty) return _businesses;
    final q = _searchQuery.toLowerCase();
    return _businesses.where((b) => b.name.toLowerCase().contains(q)).toList();
  }

  bool get _useGateMode {
    if (_searchQuery.isNotEmpty) return false;
    return _businesses.length == 1;
  }

  bool get _showSearch => _businesses.length >= _searchThreshold;

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

    if (!ResponsiveHelper.isMobile(context)) {
      await MobileLauncherPrefs.clearResumeLauncher(_authStore.currentUserId);
      if (!mounted) return;
      context.go('/business/$businessId/dashboard');
      return;
    }

    final t = AppLocalizations.of(context);

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

  void _goNewBusiness() => context.go('/user/profile/new-business');

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final padding = ResponsiveHelper.getPadding(context);
    final visible = _visibleBusinesses;
    final gateMode = !_loading && _error == null && _useGateMode;

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
                        child: _buildHeader(context, t, gateMode),
                      ),
                    ),
                  ),
                ),
                if (_loading)
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                        child: Padding(
                          padding: EdgeInsets.all(padding),
                          child: BusinessSwitcherSkeleton(single: true),
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
                else if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: BusinessesEmptyState(
                      noSearchResults: true,
                      searchQuery: _searchQuery,
                    ),
                  )
                else if (gateMode)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(padding, 8, padding, padding + 24),
                          child: BusinessSwitcherGate(
                            business: _businesses.first,
                            authStore: _authStore,
                            onEnter: () => _navigateToBusiness(_businesses.first.id),
                            onCreateNew: _goNewBusiness,
                            onRefresh: _refresh,
                          ),
                        ),
                      ),
                    ),
                  )
                else ...[
                  if (_showSearch)
                    SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(padding, 4, padding, 8),
                            child: _buildSearchField(context, t),
                          ),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(padding, 0, padding, padding + 24),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                          child: Column(
                            children: [
                              for (var i = 0; i < visible.length; i++)
                                BusinessSwitcherRow(
                                  business: visible[i],
                                  authStore: _authStore,
                                  showDivider: i < visible.length - 1,
                                  onEnter: () => _navigateToBusiness(visible[i].id),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations t, bool gateMode) {
    final theme = Theme.of(context);
    final showAddInHeader = !_loading && _error == null && _businesses.isNotEmpty && !gateMode;

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
              if (!gateMode && _businesses.isNotEmpty && !_loading) ...[
                const SizedBox(height: 6),
                Text(
                  t.businessesSwitcherSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (showAddInHeader)
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

  Widget _buildSearchField(BuildContext context, AppLocalizations t) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      decoration: InputDecoration(
        hintText: t.businessesHubSearchHint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
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
