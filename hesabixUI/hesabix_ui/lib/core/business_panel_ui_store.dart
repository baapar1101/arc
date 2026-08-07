import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'business_route_paths.dart';
import '../services/user_ui_preferences_service.dart';

enum BusinessPanelNavigationMode { single, tabs }

/// رفتار باز شدن مسیر از منوی کناری در حالت تب (فقط دسکتاپ با ریل).
enum BusinessPanelSidebarTabBehavior {
  /// همان منطق پیش‌فرض: اگر همان مقصد در تب‌ها بود به آن برو، وگرنه تب جدید.
  reuseAcrossTabsOnTap,
  /// کلیک معمولی فقط تب فعال را عوض می‌کند؛ لانگ‌پرس همان منطق [reuseAcrossTabsOnTap] را اعمال می‌کند.
  newTabViaLongPress,
}

class BusinessPanelTabSession {
  final List<String> paths;
  final String activePath;
  /// هم‌طول با [paths]؛ پین به اسلات تب وابسته است نه به URL کامل (بعد از navigate داخل تب می‌ماند).
  final List<bool> pinned;

  const BusinessPanelTabSession({
    required this.paths,
    required this.activePath,
    this.pinned = const [],
  });

  bool isPinnedAt(int index) {
    if (index < 0 || index >= paths.length) return false;
    if (index >= pinned.length) return false;
    return pinned[index];
  }

  bool isPathPinned(String path) {
    final key = path.split('?').first;
    final i = paths.indexWhere((p) => p.split('?').first == key);
    return isPinnedAt(i);
  }

  List<bool> alignedPinned() => BusinessPanelUiStore.alignPinned(paths.length, pinned);
}

/// ترجیحات نمایش پنل کسب‌وکار (تکی / تب در دسکتاپ) + همگام‌سازی با سرور.
class BusinessPanelUiStore extends ChangeNotifier {
  BusinessPanelUiStore._();
  static final BusinessPanelUiStore instance = BusinessPanelUiStore._();

  BusinessPanelNavigationMode _mode = BusinessPanelNavigationMode.single;
  BusinessPanelSidebarTabBehavior _sidebarTabBehavior =
      BusinessPanelSidebarTabBehavior.reuseAcrossTabsOnTap;
  final Map<int, BusinessPanelTabSession> _tabsByBusiness = {};
  /// پس از ناوبری از سمت store، تا رسیدن روتر به همین مسیر، sync کهنه را نادیده بگیر.
  /// بدون این، `repack` + post-frame با URL قبلی تب بسته‌شده را زنده می‌کند.
  final Map<int, String> _awaitingRouterPath = {};
  bool _hydrated = false;
  Future<void>? _hydrateFuture;
  Timer? _persistDebounce;
  int _pluginsRefreshNonce = 0;

  /// برای به‌روزرسانی منوی shell پس از خرید/تریال افزونه.
  int get pluginsRefreshNonce => _pluginsRefreshNonce;

  void requestBusinessPluginsReload() {
    _pluginsRefreshNonce++;
    notifyListeners();
  }

  BusinessPanelNavigationMode get mode => _mode;

  BusinessPanelSidebarTabBehavior get sidebarTabBehavior => _sidebarTabBehavior;

  bool get isHydrated => _hydrated;

  BusinessPanelTabSession? tabsForBusiness(int businessId) => _tabsByBusiness[businessId];

  bool shouldShowTabStrip(int businessId, {required bool isDesktop}) {
    if (!isDesktop || _mode != BusinessPanelNavigationMode.tabs) return false;
    final s = _tabsByBusiness[businessId];
    return s != null && s.paths.isNotEmpty;
  }

  static List<bool> alignPinned(int length, List<bool>? pinned) {
    if (length <= 0) return const [];
    if (pinned == null || pinned.isEmpty) {
      return List<bool>.filled(length, false);
    }
    if (pinned.length == length) return List<bool>.from(pinned);
    if (pinned.length > length) return pinned.sublist(0, length);
    return [...pinned, ...List<bool>.filled(length - pinned.length, false)];
  }

  static BusinessPanelTabSession _session({
    required List<String> paths,
    required String activePath,
    List<bool>? pinned,
  }) {
    return BusinessPanelTabSession(
      paths: paths,
      activePath: activePath,
      pinned: alignPinned(paths.length, pinned),
    );
  }

  void reset() {
    _persistDebounce?.cancel();
    _persistDebounce = null;
    _hydrated = false;
    _hydrateFuture = null;
    _mode = BusinessPanelNavigationMode.single;
    _sidebarTabBehavior = BusinessPanelSidebarTabBehavior.reuseAcrossTabsOnTap;
    _tabsByBusiness.clear();
    _awaitingRouterPath.clear();
    notifyListeners();
  }

  void applyServerPayload(Map<String, dynamic> raw) {
    final nav = raw['business_panel_navigation'];
    if (nav == 'tabs') {
      _mode = BusinessPanelNavigationMode.tabs;
    } else {
      _mode = BusinessPanelNavigationMode.single;
    }
    final sb = raw['business_panel_sidebar_tab_behavior'];
    if (sb == 'long_press_new_tab') {
      _sidebarTabBehavior = BusinessPanelSidebarTabBehavior.newTabViaLongPress;
    } else {
      _sidebarTabBehavior = BusinessPanelSidebarTabBehavior.reuseAcrossTabsOnTap;
    }
    _tabsByBusiness.clear();
    _awaitingRouterPath.clear();
    final tabsRaw = raw['business_panel_tabs'];
    if (tabsRaw is Map) {
      for (final e in tabsRaw.entries) {
        final bid = int.tryParse(e.key.toString());
        if (bid == null) continue;
        final m = e.value;
        if (m is! Map) continue;
        final pathsList = m['paths'];
        final active = m['active_path']?.toString();
        if (pathsList is! List || pathsList.isEmpty) continue;
        var paths = <String>[];
        for (final p in pathsList) {
          final s = p?.toString().trim() ?? '';
          if (s.isEmpty) continue;
          paths.add(s.startsWith('/') ? s : '/$s');
        }
        if (paths.isEmpty) continue;
        final pinnedRaw = m['pinned'];
        var pinnedFlags = <bool>[];
        if (pinnedRaw is List) {
          for (var i = 0; i < paths.length; i++) {
            pinnedFlags.add(i < pinnedRaw.length ? pinnedRaw[i] == true : false);
          }
        } else {
          pinnedFlags = List<bool>.filled(paths.length, false);
        }
        var ap = (active != null && active.isNotEmpty)
            ? (active.startsWith('/') ? active : '/$active')
            : paths.last;
        if (!paths.contains(ap)) ap = paths.last;
        final apIdx = paths.indexWhere((p) => p.split('?').first == ap.split('?').first);
        paths = BusinessRoutePaths.migratePathsToTabSlots(bid, paths);
        pinnedFlags = alignPinned(paths.length, pinnedFlags);
        if (apIdx >= 0 && apIdx < paths.length) {
          ap = paths[apIdx];
        } else {
          ap = paths.last;
        }
        _tabsByBusiness[bid] = _session(paths: paths, activePath: ap, pinned: pinnedFlags);
      }
    }
    notifyListeners();
  }

  Future<void> hydrateIfNeeded() async {
    if (_hydrated) return;
    if (_hydrateFuture != null) {
      await _hydrateFuture;
      return;
    }
    final auth = ApiClient.getAuthStore();
    final key = auth?.apiKey;
    if (key == null || key.isEmpty) return;

    _hydrateFuture = () async {
      try {
        final svc = UserUiPreferencesService(ApiClient());
        final data = await svc.getPreferences();
        applyServerPayload(data);
        _hydrated = true;
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('BusinessPanelUiStore hydrate failed: $e\n$st');
        }
      } finally {
        _hydrateFuture = null;
      }
    }();
    await _hydrateFuture;
  }

  Map<String, dynamic> _toPersistencePayload() {
    final tabs = <String, dynamic>{};
    for (final e in _tabsByBusiness.entries) {
      final s = e.value;
      tabs['${e.key}'] = {
        'paths': s.paths,
        'active_path': s.activePath,
        'pinned': s.alignedPinned(),
      };
    }
    return {
      'business_panel_navigation':
          _mode == BusinessPanelNavigationMode.tabs ? 'tabs' : 'single',
      'business_panel_sidebar_tab_behavior':
          _sidebarTabBehavior == BusinessPanelSidebarTabBehavior.newTabViaLongPress
              ? 'long_press_new_tab'
              : 'reuse_across_tabs',
      'business_panel_tabs': tabs,
    };
  }

  void _schedulePersist() {
    final auth = ApiClient.getAuthStore();
    final key = auth?.apiKey;
    if (key == null || key.isEmpty) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final svc = UserUiPreferencesService(ApiClient());
        await svc.putPreferences(_toPersistencePayload());
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('BusinessPanelUiStore persist failed: $e\n$st');
        }
      }
    });
  }

  Future<void> persistImmediate() async {
    _persistDebounce?.cancel();
    _persistDebounce = null;
    final auth = ApiClient.getAuthStore();
    final key = auth?.apiKey;
    if (key == null || key.isEmpty) return;
    final svc = UserUiPreferencesService(ApiClient());
    final data = await svc.putPreferences(_toPersistencePayload());
    applyServerPayload(data);
  }

  Future<void> updateAppearancePreferences({
    required BusinessPanelNavigationMode navigationMode,
    required BusinessPanelSidebarTabBehavior sidebarTabBehavior,
  }) async {
    _mode = navigationMode;
    _sidebarTabBehavior = sidebarTabBehavior;
    notifyListeners();
    await persistImmediate();
  }

  /// ناوبری از store: مسیر هدف را ثبت می‌کند تا sync کهنه قبل از اعمال go، جلسه تب را خراب نکند.
  void _goAndAwaitRouter(int businessId, String location, void Function(String location) go) {
    _awaitingRouterPath[businessId] = location.split('?').first;
    go(location);
  }

  static String _pathKey(String path) => path.split('?').first;

  bool isTabPinned(int businessId, String path) {
    return _tabsByBusiness[businessId]?.isPathPinned(path) ?? false;
  }

  void toggleTabPinned(int businessId, String path) {
    final s = _tabsByBusiness[businessId];
    if (s == null) return;
    final key = _pathKey(path);
    final i = s.paths.indexWhere((p) => _pathKey(p) == key);
    if (i < 0) return;
    final pinned = s.alignedPinned();
    pinned[i] = !pinned[i];
    _tabsByBusiness[businessId] = _session(
      paths: s.paths,
      activePath: s.activePath,
      pinned: pinned,
    );
    notifyListeners();
    _schedulePersist();
  }

  /// همگام‌سازی با مسیر فعلی روتر (فقط دسکتاپ + حالت تب).
  void onBusinessRouteChanged(int businessId, String pathOnly, {required bool isDesktop}) {
    final norm = pathOnly.split('?').first;
    if (!norm.startsWith('/business/')) return;

    if (!isDesktop || _mode != BusinessPanelNavigationMode.tabs) {
      return;
    }

    final bidPrefix = '/business/$businessId/';
    if (!norm.startsWith(bidPrefix) && norm != '/business/$businessId') {
      return;
    }

    final slot = BusinessRoutePaths.parseTabSlotFromPath(norm);
    if (slot == null) return;

    final awaiting = _awaitingRouterPath[businessId];
    if (awaiting != null) {
      if (norm != awaiting) {
        // URL کهنه (مثلاً تب بسته‌شده قبل از go) — جلسه را بازنویسی نکن.
        return;
      }
      _awaitingRouterPath.remove(businessId);
    }

    final existing = _tabsByBusiness[businessId];
    var paths = existing != null ? List<String>.from(existing.paths) : <String>[];
    var pinned = existing != null ? existing.alignedPinned() : <bool>[];

    if (slot < paths.length) {
      paths[slot] = norm;
    } else if (slot == paths.length) {
      paths.add(norm);
      pinned.add(false);
    } else {
      return;
    }

    const maxTabs = BusinessRoutePaths.tabBranchCount;
    if (paths.length > maxTabs) {
      final drop = paths.length - maxTabs;
      paths = paths.sublist(drop);
      pinned = pinned.sublist(drop);
    }

    final updated = _session(paths: paths, activePath: norm, pinned: pinned);
    final changed = existing == null ||
        existing.activePath != updated.activePath ||
        existing.paths.length != updated.paths.length ||
        !_listEq(existing.paths, updated.paths) ||
        !_boolListEq(existing.alignedPinned(), updated.alignedPinned());

    _tabsByBusiness[businessId] = updated;
    if (changed) {
      notifyListeners();
      _schedulePersist();
    }
  }

  bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _boolListEq(List<bool> a, List<bool> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _appendQueryFromMenuUri(String pathWithoutQuery, Uri menuUri) {
    if (!menuUri.hasQuery) return pathWithoutQuery;
    return '$pathWithoutQuery?${menuUri.query}';
  }

  /// در حالت «تب» (منوی کناری دسکتاپ): با [reuseAcrossTabs]==true همان منطق قبلی؛
  /// با false فقط اسلات تب فعال جایگزین می‌شود (در صورت نبود جلسهٔ تب، به منطق قبلی می‌افتد).
  /// در حالت تک‌صفحه یا وقتی [fallbackOnly]، همان [menuUrl] با [go] زده می‌شود.
  void navigateSidebarFromMenuUrl({
    required int businessId,
    required String menuUrl,
    required void Function(String location) go,
    bool fallbackOnly = false,
    bool reuseAcrossTabs = true,
  }) {
    if (fallbackOnly || _mode != BusinessPanelNavigationMode.tabs) {
      go(menuUrl);
      return;
    }

    final uri = Uri.tryParse(menuUrl);
    if (uri == null) {
      go(menuUrl);
      return;
    }
    final pathOnly = uri.path;
    if (!pathOnly.startsWith('/business/$businessId/')) {
      go(menuUrl);
      return;
    }

    final tailKey = BusinessRoutePaths.stripBusinessPrefixAndTab(pathOnly, businessId);

    if (!reuseAcrossTabs) {
      final replaced = _tryReplaceActiveTabSlot(
        businessId: businessId,
        menuUri: uri,
        tailKey: tailKey,
        go: go,
      );
      if (replaced) return;
    }

    _navigateSidebarReuseAcrossTabs(
      businessId: businessId,
      menuUri: uri,
      tailKey: tailKey,
      go: go,
    );
  }

  bool _tryReplaceActiveTabSlot({
    required int businessId,
    required Uri menuUri,
    required String tailKey,
    required void Function(String location) go,
  }) {
    final session = _tabsByBusiness[businessId];
    if (session == null || session.paths.isEmpty) return false;

    final slot = BusinessRoutePaths.parseTabSlotFromPath(session.activePath.split('?').first);
    if (slot == null) return false;

    final paths = List<String>.from(session.paths);
    if (slot < 0 || slot >= paths.length) return false;

    final newBase = BusinessRoutePaths.uri(businessId, slot, tailKey);
    final newFull = _appendQueryFromMenuUri(newBase, menuUri);

    paths[slot] = newFull;
    _tabsByBusiness[businessId] = _session(
      paths: paths,
      activePath: newFull,
      pinned: session.alignedPinned(),
    );
    _goAndAwaitRouter(businessId, newFull, go);
    notifyListeners();
    _schedulePersist();
    return true;
  }

  void _navigateSidebarReuseAcrossTabs({
    required int businessId,
    required Uri menuUri,
    required String tailKey,
    required void Function(String location) go,
  }) {
    final tailCmp = tailKey.split('?').first;
    final existing = _tabsByBusiness[businessId];

    var paths = List<String>.from(existing?.paths ?? const []);
    var pinned = existing?.alignedPinned() ?? <bool>[];

    for (var i = 0; i < paths.length; i++) {
      final p = paths[i];
      final existingTail = BusinessRoutePaths.stripBusinessPrefixAndTab(p.split('?').first, businessId);
      if (existingTail.split('?').first != tailCmp) continue;
      final slot = BusinessRoutePaths.parseTabSlotFromPath(p.split('?').first);
      if (slot == null) continue;
      final newBase = BusinessRoutePaths.uri(businessId, slot, tailKey);
      final newFull = _appendQueryFromMenuUri(newBase, menuUri);
      paths[i] = newFull;
      _tabsByBusiness[businessId] = _session(paths: paths, activePath: newFull, pinned: pinned);
      _goAndAwaitRouter(businessId, newFull, go);
      notifyListeners();
      _schedulePersist();
      return;
    }

    var didDrop = false;
    while (paths.length >= BusinessRoutePaths.tabBranchCount) {
      var dropAt = pinned.indexWhere((p) => !p);
      if (dropAt < 0) dropAt = 0;
      paths.removeAt(dropAt);
      pinned.removeAt(dropAt);
      didDrop = true;
    }
    if (didDrop && paths.isNotEmpty) {
      paths = BusinessRoutePaths.repackTabPathsAfterRemoval(businessId, paths);
    }

    final slot = paths.length;
    final newBase = BusinessRoutePaths.uri(businessId, slot, tailKey);
    final newFull = _appendQueryFromMenuUri(newBase, menuUri);
    paths.add(newFull);
    pinned.add(false);

    _tabsByBusiness[businessId] = _session(paths: paths, activePath: newFull, pinned: pinned);
    _goAndAwaitRouter(businessId, newFull, go);
    notifyListeners();
    _schedulePersist();
  }

  void selectTab(int businessId, String path, void Function(String location) go) {
    final s = _tabsByBusiness[businessId];
    if (s == null || !s.paths.contains(path)) return;
    if (s.activePath == path) return;
    _tabsByBusiness[businessId] = _session(
      paths: s.paths,
      activePath: path,
      pinned: s.alignedPinned(),
    );
    _goAndAwaitRouter(businessId, path, go);
    notifyListeners();
    _schedulePersist();
  }

  /// بستن تب. اگر پین باشد و [force] نباشد، بدون تغییر `false` برمی‌گرداند تا UI تأیید بگیرد.
  bool closeTab(
    int businessId,
    String path,
    void Function(String location) go, {
    bool force = false,
  }) {
    final s = _tabsByBusiness[businessId];
    if (s == null) return false;

    final pathKey = _pathKey(path);
    var paths = List<String>.from(s.paths);
    var pinned = s.alignedPinned();
    final removeIdx = paths.indexWhere((p) => _pathKey(p) == pathKey);
    if (removeIdx < 0) return false;

    if (pinned[removeIdx] && !force) {
      return false;
    }

    paths.removeAt(removeIdx);
    pinned.removeAt(removeIdx);
    paths = BusinessRoutePaths.repackTabPathsAfterRemoval(businessId, paths);
    final dash = BusinessRoutePaths.uri(businessId, 0, 'dashboard');

    if (paths.isEmpty) {
      _tabsByBusiness[businessId] = _session(
        paths: [dash],
        activePath: dash,
        pinned: const [false],
      );
      _goAndAwaitRouter(businessId, dash, go);
      notifyListeners();
      _schedulePersist();
      return true;
    }

    final wasActive = _pathKey(s.activePath) == pathKey;
    final String nextActive;
    if (wasActive) {
      nextActive = paths.last;
    } else {
      final tail = BusinessRoutePaths.stripBusinessPrefixAndTab(s.activePath, businessId);
      nextActive = paths.firstWhere(
        (p) => BusinessRoutePaths.stripBusinessPrefixAndTab(p, businessId) == tail,
        orElse: () => paths.last,
      );
    }
    _tabsByBusiness[businessId] = _session(
      paths: paths,
      activePath: nextActive,
      pinned: pinned,
    );
    _goAndAwaitRouter(businessId, nextActive, go);
    notifyListeners();
    _schedulePersist();
    return true;
  }

  /// ترتیب مسیرها با ایندکس ۰ نزدیک‌تر به «شروع» نوار در RTL (سمت راست صفحه) است.
  /// تب‌های پین در محدودهٔ حذف حفظ می‌شوند. تعداد پین‌های حفظ‌شده را برمی‌گرداند.
  int closeTabsToTheRightOf(int businessId, String anchorPath, void Function(String location) go) {
    final s = _tabsByBusiness[businessId];
    if (s == null) return 0;
    final paths = List<String>.from(s.paths);
    final pinned = s.alignedPinned();
    final i = paths.indexOf(anchorPath);
    if (i <= 0) return 0;

    final keptPaths = <String>[];
    final keptPinned = <bool>[];
    var preservedPinned = 0;
    for (var j = 0; j < i; j++) {
      if (pinned[j]) {
        keptPaths.add(paths[j]);
        keptPinned.add(true);
        preservedPinned++;
      }
    }
    for (var j = i; j < paths.length; j++) {
      keptPaths.add(paths[j]);
      keptPinned.add(pinned[j]);
    }

    if (keptPaths.length == paths.length) {
      return 0;
    }
    _applyBulkTabPathsAfterRemoval(businessId, keptPaths, keptPinned, anchorPath, go);
    return preservedPinned;
  }

  /// ایندکس بالاتر = در RTL به‌سمت چپ نوار.
  int closeTabsToTheLeftOf(int businessId, String anchorPath, void Function(String location) go) {
    final s = _tabsByBusiness[businessId];
    if (s == null) return 0;
    final paths = List<String>.from(s.paths);
    final pinned = s.alignedPinned();
    final i = paths.indexOf(anchorPath);
    if (i < 0 || i >= paths.length - 1) return 0;

    final keptPaths = <String>[];
    final keptPinned = <bool>[];
    var preservedPinned = 0;
    for (var j = 0; j <= i; j++) {
      keptPaths.add(paths[j]);
      keptPinned.add(pinned[j]);
    }
    for (var j = i + 1; j < paths.length; j++) {
      if (pinned[j]) {
        keptPaths.add(paths[j]);
        keptPinned.add(true);
        preservedPinned++;
      }
    }

    if (keptPaths.length == paths.length) {
      return 0;
    }
    _applyBulkTabPathsAfterRemoval(businessId, keptPaths, keptPinned, anchorPath, go);
    return preservedPinned;
  }

  /// تب‌های غیرپین را می‌بندد؛ پین‌ها می‌مانند. تعداد پین‌های باقی‌مانده را برمی‌گرداند.
  int closeAllTabs(int businessId, void Function(String location) go) {
    final s = _tabsByBusiness[businessId];
    final dash = BusinessRoutePaths.uri(businessId, 0, 'dashboard');

    if (s == null || s.paths.isEmpty) {
      _tabsByBusiness[businessId] = _session(
        paths: [dash],
        activePath: dash,
        pinned: const [false],
      );
      _goAndAwaitRouter(businessId, dash, go);
      notifyListeners();
      _schedulePersist();
      return 0;
    }

    final pinned = s.alignedPinned();
    final keptPaths = <String>[];
    final keptPinned = <bool>[];
    for (var i = 0; i < s.paths.length; i++) {
      if (!pinned[i]) continue;
      keptPaths.add(s.paths[i]);
      keptPinned.add(true);
    }

    if (keptPaths.isEmpty) {
      _tabsByBusiness[businessId] = _session(
        paths: [dash],
        activePath: dash,
        pinned: const [false],
      );
      _goAndAwaitRouter(businessId, dash, go);
      notifyListeners();
      _schedulePersist();
      return 0;
    }

    if (keptPaths.length == s.paths.length) {
      return 0;
    }

    final repacked = BusinessRoutePaths.repackTabPathsAfterRemoval(businessId, keptPaths);
    final activeTail = BusinessRoutePaths.stripBusinessPrefixAndTab(s.activePath, businessId);
    final nextActive = repacked.firstWhere(
      (p) => BusinessRoutePaths.stripBusinessPrefixAndTab(p, businessId) == activeTail,
      orElse: () => repacked.last,
    );
    _tabsByBusiness[businessId] = _session(
      paths: repacked,
      activePath: nextActive,
      pinned: keptPinned,
    );
    _goAndAwaitRouter(businessId, nextActive, go);
    notifyListeners();
    _schedulePersist();
    return keptPaths.length;
  }

  void _applyBulkTabPathsAfterRemoval(
    int businessId,
    List<String> paths,
    List<bool> pinned,
    String anchorPath,
    void Function(String location) go,
  ) {
    if (paths.isEmpty) {
      closeAllTabs(businessId, go);
      return;
    }
    final repacked = BusinessRoutePaths.repackTabPathsAfterRemoval(businessId, paths);
    final aligned = alignPinned(repacked.length, pinned);
    final anchorTail = BusinessRoutePaths.stripBusinessPrefixAndTab(anchorPath, businessId);
    final nextActive = repacked.firstWhere(
      (p) => BusinessRoutePaths.stripBusinessPrefixAndTab(p, businessId) == anchorTail,
      orElse: () => repacked.last,
    );
    _tabsByBusiness[businessId] = _session(
      paths: repacked,
      activePath: nextActive,
      pinned: aligned,
    );
    _goAndAwaitRouter(businessId, nextActive, go);
    notifyListeners();
    _schedulePersist();
  }
}
