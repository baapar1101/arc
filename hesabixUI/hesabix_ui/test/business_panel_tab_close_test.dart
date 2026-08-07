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
    store.closeTab(7, closed, (loc) => navigatedTo = loc);

    final afterClose = store.tabsForBusiness(7)!;
    expect(afterClose.paths.length, 2);
    expect(
      afterClose.paths.map((p) => BusinessRoutePaths.stripBusinessPrefixAndTab(p, 7)),
      ['dashboard', 'products'],
    );
    expect(navigatedTo, BusinessRoutePaths.uri(7, 1, 'products'));
    expect(afterClose.activePath, BusinessRoutePaths.uri(7, 1, 'products'));

    // Simulate shell post-frame sync with the OLD router URL (closed tab).
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

    // Stale pre-repack active URL must not re-add a third tab.
    store.onBusinessRouteChanged(3, BusinessRoutePaths.uri(3, 2, 'products'), isDesktop: true);
    expect(store.tabsForBusiness(3)!.paths.length, 2);
  });
}
