import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/core/business_panel_ui_store.dart';
import 'package:hesabix_ui/core/business_route_paths.dart';

void main() {
  tearDown(() {
    BusinessPanelUiStore.instance.reset();
  });

  test('closing middle active tab is not resurrected by stale route sync', () {
    final store = BusinessPanelUiStore.instance;
    store.applyServerPayload({
      'business_panel_navigation': 'tabs',
      'business_panel_sidebar_tab_behavior': 'reuse_across_tabs',
      'business_panel_tabs': {
        '7': {
          'paths': [
            BusinessRoutePaths.uri(7, 0, 'dashboard'),
            BusinessRoutePaths.uri(7, 1, 'persons'),
            BusinessRoutePaths.uri(7, 2, 'products'),
          ],
          'active_path': BusinessRoutePaths.uri(7, 1, 'persons'),
        },
      },
    });

    final closed = BusinessRoutePaths.uri(7, 1, 'persons');
    String? navigatedTo;
    expect(store.closeTab(7, closed, (loc) => navigatedTo = loc), isTrue);

    final afterClose = store.tabsForBusiness(7)!;
    expect(afterClose.paths.length, 2);
    expect(
      afterClose.paths.map((p) => BusinessRoutePaths.stripBusinessPrefixAndTab(p, 7)),
      ['dashboard', 'products'],
    );
    expect(navigatedTo, BusinessRoutePaths.uri(7, 1, 'products'));
    expect(afterClose.activePath, BusinessRoutePaths.uri(7, 1, 'products'));

    store.onBusinessRouteChanged(7, closed, isDesktop: true);

    final afterStale = store.tabsForBusiness(7)!;
    expect(afterStale.paths.length, 2);
    expect(
      afterStale.paths.map((p) => BusinessRoutePaths.stripBusinessPrefixAndTab(p, 7)),
      ['dashboard', 'products'],
      reason: 'stale closed URL must not overwrite the repacked slot',
    );
  });

  test('closing lower tab while higher is active always renavigates router', () {
    final store = BusinessPanelUiStore.instance;
    store.applyServerPayload({
      'business_panel_navigation': 'tabs',
      'business_panel_sidebar_tab_behavior': 'reuse_across_tabs',
      'business_panel_tabs': {
        '3': {
          'paths': [
            BusinessRoutePaths.uri(3, 0, 'dashboard'),
            BusinessRoutePaths.uri(3, 1, 'persons'),
            BusinessRoutePaths.uri(3, 2, 'products'),
          ],
          'active_path': BusinessRoutePaths.uri(3, 2, 'products'),
        },
      },
    });

    String? navigatedTo;
    store.closeTab(3, BusinessRoutePaths.uri(3, 0, 'dashboard'), (loc) => navigatedTo = loc);

    expect(navigatedTo, BusinessRoutePaths.uri(3, 1, 'products'));
    final session = store.tabsForBusiness(3)!;
    expect(session.paths.length, 2);
    expect(session.activePath, BusinessRoutePaths.uri(3, 1, 'products'));

    store.onBusinessRouteChanged(3, BusinessRoutePaths.uri(3, 2, 'products'), isDesktop: true);
    expect(store.tabsForBusiness(3)!.paths.length, 2);
  });

  test('pinned tab refuses close without force and survives sibling close', () {
    final store = BusinessPanelUiStore.instance;
    store.applyServerPayload({
      'business_panel_navigation': 'tabs',
      'business_panel_sidebar_tab_behavior': 'reuse_across_tabs',
      'business_panel_tabs': {
        '5': {
          'paths': [
            BusinessRoutePaths.uri(5, 0, 'dashboard'),
            BusinessRoutePaths.uri(5, 1, 'persons'),
            BusinessRoutePaths.uri(5, 2, 'products'),
          ],
          'active_path': BusinessRoutePaths.uri(5, 1, 'persons'),
          'pinned': [false, true, false],
        },
      },
    });

    final persons = BusinessRoutePaths.uri(5, 1, 'persons');
    expect(store.isTabPinned(5, persons), isTrue);
    expect(store.closeTab(5, persons, (_) {}), isFalse);
    expect(store.tabsForBusiness(5)!.paths.length, 3);

    expect(store.closeTab(5, persons, (_) {}, force: true), isTrue);
    final after = store.tabsForBusiness(5)!;
    expect(after.paths.length, 2);
    expect(after.alignedPinned(), [false, false]);
  });

  test('pin flag stays on slot when route inside tab changes', () {
    final store = BusinessPanelUiStore.instance;
    store.applyServerPayload({
      'business_panel_navigation': 'tabs',
      'business_panel_sidebar_tab_behavior': 'reuse_across_tabs',
      'business_panel_tabs': {
        '9': {
          'paths': [
            BusinessRoutePaths.uri(9, 0, 'dashboard'),
            BusinessRoutePaths.uri(9, 1, 'persons'),
          ],
          'active_path': BusinessRoutePaths.uri(9, 1, 'persons'),
          'pinned': [false, true],
        },
      },
    });

    final detail = BusinessRoutePaths.uri(9, 1, 'persons/42');
    store.onBusinessRouteChanged(9, detail, isDesktop: true);

    final s = store.tabsForBusiness(9)!;
    expect(s.paths[1], detail);
    expect(s.isPinnedAt(1), isTrue);
    expect(s.activePath, detail);
  });

  test('bulk close keeps pinned tabs and remaps pins after repack', () {
    final store = BusinessPanelUiStore.instance;
    store.applyServerPayload({
      'business_panel_navigation': 'tabs',
      'business_panel_sidebar_tab_behavior': 'reuse_across_tabs',
      'business_panel_tabs': {
        '11': {
          'paths': [
            BusinessRoutePaths.uri(11, 0, 'dashboard'),
            BusinessRoutePaths.uri(11, 1, 'persons'),
            BusinessRoutePaths.uri(11, 2, 'products'),
            BusinessRoutePaths.uri(11, 3, 'settings'),
          ],
          'active_path': BusinessRoutePaths.uri(11, 3, 'settings'),
          'pinned': [false, true, false, false],
        },
      },
    });

    String? nav;
    final kept = store.closeAllTabs(11, (loc) => nav = loc);
    expect(kept, 1);
    final s = store.tabsForBusiness(11)!;
    expect(s.paths.length, 1);
    expect(
      BusinessRoutePaths.stripBusinessPrefixAndTab(s.paths.first, 11),
      'persons',
    );
    expect(s.alignedPinned(), [true]);
    expect(nav, BusinessRoutePaths.uri(11, 0, 'persons'));
  });

  test('toggle pin persists in payload shape', () {
    final store = BusinessPanelUiStore.instance;
    store.applyServerPayload({
      'business_panel_navigation': 'tabs',
      'business_panel_sidebar_tab_behavior': 'reuse_across_tabs',
      'business_panel_tabs': {
        '2': {
          'paths': [
            BusinessRoutePaths.uri(2, 0, 'dashboard'),
            BusinessRoutePaths.uri(2, 1, 'persons'),
          ],
          'active_path': BusinessRoutePaths.uri(2, 0, 'dashboard'),
        },
      },
    });

    store.toggleTabPinned(2, BusinessRoutePaths.uri(2, 1, 'persons'));
    expect(store.tabsForBusiness(2)!.alignedPinned(), [false, true]);
    store.toggleTabPinned(2, BusinessRoutePaths.uri(2, 1, 'persons'));
    expect(store.tabsForBusiness(2)!.alignedPinned(), [false, false]);
  });
}
