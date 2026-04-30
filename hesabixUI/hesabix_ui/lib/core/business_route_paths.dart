import 'package:go_router/go_router.dart';

/// مسیرهای پنل کسب‌وکار با پیشوند `tabN` برای [StatefulShellRoute].
abstract final class BusinessRoutePaths {
  static const int tabBranchCount = 24;

  static final RegExp tabSegmentRegex = RegExp(r'/tab(\d+)/');

  static int? parseTabSlotFromPath(String path) {
    final m = tabSegmentRegex.firstMatch(path.split('?').first);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  static String stripBusinessPrefixAndTab(String path, int businessId) {
    final p = path.split('?').first;
    final prefix = '/business/$businessId/';
    var tail = p.startsWith(prefix) ? p.substring(prefix.length) : p.replaceFirst(RegExp(r'^/business/\d+/'), '');
    tail = tail.replaceFirst(RegExp(r'^tab\d+/'), '');
    return tail;
  }

  static String prefixFromRouterState(GoRouterState state) {
    final bid = state.pathParameters['business_id'] ?? '';
    final path = state.uri.path;
    final m = RegExp(r'^(/business/\d+/tab\d+)').firstMatch(path);
    if (m != null) return m.group(1)!;
    return '/business/$bid/tab0';
  }

  static String uri(int businessId, int tabSlot, String relativePath) {
    var rel = relativePath.trim();
    if (rel.startsWith('/')) rel = rel.substring(1);
    return '/business/$businessId/tab$tabSlot/$rel';
  }

  static List<String> migratePathsToTabSlots(int businessId, List<String> paths) {
    final out = <String>[];
    for (var i = 0; i < paths.length; i++) {
      final p = paths[i].split('?').first;
      if (parseTabSlotFromPath(p) != null) {
        out.add(p.startsWith('/') ? p : '/$p');
        continue;
      }
      final tail = stripBusinessPrefixAndTab(p, businessId);
      out.add(uri(businessId, i, tail));
    }
    return out;
  }

  static List<String> repackTabPathsAfterRemoval(int businessId, List<String> paths) {
    final tails = paths.map((p) => stripBusinessPrefixAndTab(p, businessId)).toList();
    return List.generate(tails.length, (i) => uri(businessId, i, tails[i]));
  }
}
