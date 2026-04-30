import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'business_route_paths.dart';
import '../services/user_ui_preferences_service.dart';

enum BusinessPanelNavigationMode { single, tabs }

class BusinessPanelTabSession {
  final List<String> paths;
  final String activePath;

  const BusinessPanelTabSession({
    required this.paths,
    required this.activePath,
  });
}

/// ترجیحات نمایش پنل کسب‌وکار (تکی / تب در دسکتاپ) + همگام‌سازی با سرور.
class BusinessPanelUiStore extends ChangeNotifier {
  BusinessPanelUiStore._();
  static final BusinessPanelUiStore instance = BusinessPanelUiStore._();

  BusinessPanelNavigationMode _mode = BusinessPanelNavigationMode.single;
  final Map<int, BusinessPanelTabSession> _tabsByBusiness = {};
  bool _hydrated = false;
  Future<void>? _hydrateFuture;
  Timer? _persistDebounce;

  BusinessPanelNavigationMode get mode => _mode;

  bool get isHydrated => _hydrated;

  BusinessPanelTabSession? tabsForBusiness(int businessId) => _tabsByBusiness[businessId];

  bool shouldShowTabStrip(int businessId, {required bool isDesktop}) {
    if (!isDesktop || _mode != BusinessPanelNavigationMode.tabs) return false;
    final s = _tabsByBusiness[businessId];
    return s != null && s.paths.isNotEmpty;
  }

  void reset() {
    _persistDebounce?.cancel();
    _persistDebounce = null;
    _hydrated = false;
    _hydrateFuture = null;
    _mode = BusinessPanelNavigationMode.single;
    _tabsByBusiness.clear();
    notifyListeners();
  }

  void applyServerPayload(Map<String, dynamic> raw) {
    final nav = raw['business_panel_navigation'];
    if (nav == 'tabs') {
      _mode = BusinessPanelNavigationMode.tabs;
    } else {
      _mode = BusinessPanelNavigationMode.single;
    }
    _tabsByBusiness.clear();
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
        var ap = (active != null && active.isNotEmpty)
            ? (active.startsWith('/') ? active : '/$active')
            : paths.last;
        if (!paths.contains(ap)) ap = paths.last;
        final apIdx = paths.indexWhere((p) => p.split('?').first == ap.split('?').first);
        paths = BusinessRoutePaths.migratePathsToTabSlots(bid, paths);
        if (apIdx >= 0 && apIdx < paths.length) {
          ap = paths[apIdx];
        } else {
          ap = paths.last;
        }
        _tabsByBusiness[bid] = BusinessPanelTabSession(paths: paths, activePath: ap);
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
      tabs['${e.key}'] = {
        'paths': e.value.paths,
        'active_path': e.value.activePath,
      };
    }
    return {
      'business_panel_navigation':
          _mode == BusinessPanelNavigationMode.tabs ? 'tabs' : 'single',
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

  Future<void> setNavigationMode(BusinessPanelNavigationMode next) async {
    _mode = next;
    notifyListeners();
    await persistImmediate();
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

    final existing = _tabsByBusiness[businessId];
    var paths = existing != null ? List<String>.from(existing.paths) : <String>[];

    if (slot < paths.length) {
      paths[slot] = norm;
    } else if (slot == paths.length) {
      paths.add(norm);
    } else {
      return;
    }

    const maxTabs = BusinessRoutePaths.tabBranchCount;
    if (paths.length > maxTabs) {
      paths = paths.sublist(paths.length - maxTabs);
    }

    final updated = BusinessPanelTabSession(paths: paths, activePath: norm);
    final changed = existing == null ||
        existing.activePath != updated.activePath ||
        existing.paths.length != updated.paths.length ||
        !_listEq(existing.paths, updated.paths);

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

  void selectTab(int businessId, String path, void Function(String location) go) {
    final s = _tabsByBusiness[businessId];
    if (s == null || !s.paths.contains(path)) return;
    if (s.activePath == path) return;
    _tabsByBusiness[businessId] = BusinessPanelTabSession(paths: s.paths, activePath: path);
    notifyListeners();
    go(path);
    _schedulePersist();
  }

  void closeTab(int businessId, String path, void Function(String location) go) {
    final s = _tabsByBusiness[businessId];
    if (s == null) return;

    var paths = List<String>.from(s.paths);
    paths.remove(path);
    paths = BusinessRoutePaths.repackTabPathsAfterRemoval(businessId, paths);
    final dash = BusinessRoutePaths.uri(businessId, 0, 'dashboard');

    if (paths.isEmpty) {
      _tabsByBusiness[businessId] = BusinessPanelTabSession(paths: [dash], activePath: dash);
      notifyListeners();
      go(dash);
      _schedulePersist();
      return;
    }

    final wasActive = s.activePath == path;
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
    _tabsByBusiness[businessId] = BusinessPanelTabSession(paths: paths, activePath: nextActive);
    notifyListeners();
    if (wasActive) {
      go(nextActive);
    }
    _schedulePersist();
  }

  /// ترتیب مسیرها با ایندکس ۰ نزدیک‌تر به «شروع» نوار در RTL (سمت راست صفحه) است.
  void closeTabsToTheRightOf(int businessId, String anchorPath, void Function(String location) go) {
    final s = _tabsByBusiness[businessId];
    if (s == null) return;
    final paths = List<String>.from(s.paths);
    final i = paths.indexOf(anchorPath);
    if (i <= 0) return;
    paths.removeRange(0, i);
    _applyBulkTabPathsAfterRemoval(businessId, paths, anchorPath, go);
  }

  /// ایندکس بالاتر = در RTL به‌سمت چپ نوار.
  void closeTabsToTheLeftOf(int businessId, String anchorPath, void Function(String location) go) {
    final s = _tabsByBusiness[businessId];
    if (s == null) return;
    final paths = List<String>.from(s.paths);
    final i = paths.indexOf(anchorPath);
    if (i < 0 || i >= paths.length - 1) return;
    paths.removeRange(i + 1, paths.length);
    _applyBulkTabPathsAfterRemoval(businessId, paths, anchorPath, go);
  }

  void closeAllTabs(int businessId, void Function(String location) go) {
    final dash = BusinessRoutePaths.uri(businessId, 0, 'dashboard');
    _tabsByBusiness[businessId] = BusinessPanelTabSession(paths: [dash], activePath: dash);
    notifyListeners();
    go(dash);
    _schedulePersist();
  }

  void _applyBulkTabPathsAfterRemoval(
    int businessId,
    List<String> paths,
    String anchorPath,
    void Function(String location) go,
  ) {
    if (paths.isEmpty) {
      closeAllTabs(businessId, go);
      return;
    }
    final repacked = BusinessRoutePaths.repackTabPathsAfterRemoval(businessId, paths);
    final anchorTail = BusinessRoutePaths.stripBusinessPrefixAndTab(anchorPath, businessId);
    final nextActive = repacked.firstWhere(
      (p) => BusinessRoutePaths.stripBusinessPrefixAndTab(p, businessId) == anchorTail,
      orElse: () => repacked.last,
    );
    _tabsByBusiness[businessId] = BusinessPanelTabSession(paths: repacked, activePath: nextActive);
    notifyListeners();
    go(nextActive);
    _schedulePersist();
  }
}
