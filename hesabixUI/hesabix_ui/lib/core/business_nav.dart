import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'business_panel_ui_store.dart';
import 'business_route_paths.dart';

String? redirectLegacyBusinessPath(BuildContext context, GoRouterState state) {
  final path = state.uri.path;
  if (BusinessRoutePaths.tabSegmentRegex.hasMatch(path)) return null;
  var bidStr = state.pathParameters['business_id'];
  if (bidStr == null || bidStr.isEmpty) {
    bidStr = RegExp(r'^/business/(\d+)').firstMatch(path)?.group(1);
  }
  if (bidStr == null) return null;
  final bid = int.tryParse(bidStr);
  if (bid == null) return null;
  var tail = path.substring('/business/$bidStr'.length);
  if (tail.startsWith('/')) tail = tail.substring(1);
  var slot = 0;
  if (BusinessPanelUiStore.instance.mode == BusinessPanelNavigationMode.tabs) {
    final session = BusinessPanelUiStore.instance.tabsForBusiness(bid);
    slot = BusinessRoutePaths.parseTabSlotFromPath(session?.activePath ?? '') ?? 0;
  }
  final String newLoc;
  if (tail.isEmpty) {
    newLoc = BusinessRoutePaths.uri(bid, slot, 'dashboard');
  } else {
    newLoc = BusinessRoutePaths.uri(bid, slot, tail);
  }
  if (!state.uri.hasQuery) return newLoc;
  final base = Uri.parse(newLoc);
  return base.replace(queryParameters: state.uri.queryParameters).toString();
}

/// مسیر URI فعلی برای ناوبری کسب‌وکار؛ از [GoRouter] در صورت موجود بودن استفاده می‌کند
/// تا زمانی که [GoRouterState] در دسترس نباشد (مثل context پس از بستن دیالوگ).
String _currentGoRouterPath(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    return router.state.uri.path;
  }
  return GoRouterState.of(context).uri.path;
}

extension BusinessNavContext on BuildContext {
  int businessTabSlot(int businessId) {
    // GoRouterState فقط زیر RouteBase.builder است؛ context ریشهٔ Navigator
    // (مثلاً بعد از بستن دیالوگ با navigatorKey) معمولاً GoRouterState ندارد.
    final path = _currentGoRouterPath(this);
    final fromUrl = BusinessRoutePaths.parseTabSlotFromPath(path);
    if (fromUrl != null) return fromUrl;
    final session = BusinessPanelUiStore.instance.tabsForBusiness(businessId);
    return BusinessRoutePaths.parseTabSlotFromPath(session?.activePath ?? '') ?? 0;
  }

  String businessPanelUrl(int businessId, String relativePath) {
    final slot = businessTabSlot(businessId);
    return BusinessRoutePaths.uri(businessId, slot, relativePath);
  }
}
