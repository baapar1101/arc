import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'business_panel_ui_store.dart';
import 'business_route_paths.dart';

String? redirectLegacyBusinessPath(BuildContext context, GoRouterState state) {
  final path = state.uri.path;
  if (BusinessRoutePaths.tabSegmentRegex.hasMatch(path)) return null;
  final bidStr = state.pathParameters['business_id'];
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

extension BusinessNavContext on BuildContext {
  int businessTabSlot(int businessId) {
    final path = GoRouterState.of(this).uri.path;
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
