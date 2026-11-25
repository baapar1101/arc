/// Tabs visible to distribution users, ordered to match the TabBar and TabBarView.
///
/// Read-only users can inspect visits and returns without being offered
/// field operations. Managers receive the Manage tab in addition to
/// operative tabs, while commercial and van features remain settings-gated.
List<String> distributionVisibleTabKeys({
  required bool canOperate,
  required bool canManage,
  required bool enableVanSales,
  required bool enablePresell,
}) {
  final keys = <String>[];
  if (canOperate) keys.add('field');
  keys.addAll(const ['visits', 'returns']);

  if (canOperate) {
    keys.add('settlement');
    if (enableVanSales) keys.add('van');
    if (enablePresell || canManage) keys.add('commercial');
  }
  if (canManage) keys.add('manage');
  return keys;
}
