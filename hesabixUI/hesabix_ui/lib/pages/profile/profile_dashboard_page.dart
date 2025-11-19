import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../models/business_dashboard_models.dart';
import '../../utils/date_formatters.dart';
import '../../services/profile_dashboard_service.dart';
import '../../services/announcements_service.dart';
import 'package:go_router/go_router.dart';

class ProfileDashboardPage extends StatefulWidget {
  const ProfileDashboardPage({super.key});

  @override
  State<ProfileDashboardPage> createState() => _ProfileDashboardPageState();
}

typedef ProfileWidgetBuilder = Widget Function(BuildContext, dynamic, DashboardLayoutItem, {VoidCallback? onRefresh});

class _ProfileDashboardPageState extends State<ProfileDashboardPage> {
  late final ProfileDashboardService _service;
  DashboardLayoutProfile? _layout;
  Map<String, dynamic> _data = <String, dynamic>{};
  bool _loading = true;
  String? _error;
  bool _editMode = false;
  static const double _gridSpacingPx = 12.0;
  // Announcements state
  final Set<int> _annBusyIds = <int>{};
  bool _annOnlyUnread = false;

  @override
  void initState() {
    super.initState();
    _service = ProfileDashboardService(ApiClient());
    _loadAll();
  }

  String _currentBreakpoint(double width) {
    if (width < 600) return 'xs';
    if (width < 904) return 'sm';
    if (width < 1240) return 'md';
    if (width < 1600) return 'lg';
    return 'xl';
  }

  Future<void> _loadAll() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final defs = await _service.getWidgetDefinitions();
      if (!context.mounted) return;
      final ctx = context;
      final bp = _currentBreakpoint(MediaQuery.of(ctx).size.width);
      var layout = await _service.getLayoutProfile(breakpoint: bp);
      // اطمینان از حضور ویجت‌های جدید پیش‌فرض در چیدمان
      final existingKeys = layout.items.map((e) => e.key).toSet();
      final missingDefaults = defs.items.where((d) => !existingKeys.contains(d.key)).toList();
      if (missingDefaults.isNotEmpty) {
        final items = List<DashboardLayoutItem>.from(layout.items);
        int maxOrder = items.fold<int>(0, (acc, it) => it.order > acc ? it.order : acc);
        for (final d in missingDefaults) {
          final dflt = d.defaults[bp] ?? const <String, int>{};
          final colSpan = (dflt['colSpan'] ?? (layout.columns / 2).floor()).clamp(1, layout.columns);
          final rowSpan = dflt['rowSpan'] ?? 2;
          items.add(DashboardLayoutItem(key: d.key, order: ++maxOrder, colSpan: colSpan, rowSpan: rowSpan, hidden: false));
        }
        // ذخیره و جایگزینی layout
        layout = await _service.putLayoutProfile(breakpoint: bp, items: items);
      }
      final keys = layout.items.where((e) => !e.hidden).map((e) => e.key).toList();
      var data = await _service.getWidgetsBatchData(widgetKeys: keys);
      // هیدرات خاص برای برخی ویجت‌ها
      data = await _service.hydrateSpecialWidgets(data, keys);
      if (!mounted) return;
      setState(() {
        _layout = layout;
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _reloadDataOnly() async {
    try {
      final layout = _layout;
      if (layout == null) return;
      final keys = layout.items.where((e) => !e.hidden).map((e) => e.key).toList();
      var data = await _service.getWidgetsBatchData(widgetKeys: keys);
      data = await _service.hydrateSpecialWidgets(data, keys);
      if (!mounted) return;
      setState(() {
        _data = data;
      });
    } catch (_) {}
  }

  Future<void> _reloadAnnouncements({required bool onlyUnread}) async {
    try {
      final ann = await AnnouncementsService(ApiClient()).listAnnouncements(page: 1, limit: 5, onlyUnread: onlyUnread);
      final items = (ann['items'] as List? ?? const <dynamic>[]) 
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _data['profile_announcements'] = {'items': items};
      });
    } catch (_) {
      await _reloadDataOnly();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 56, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('خطا در بارگذاری داشبورد پروفایل:\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadAll, child: const Text('تلاش مجدد')),
          ],
        ),
      );
    }

    final layout = _layout!;
    final items = List<DashboardLayoutItem>.from(layout.items)..sort((a, b) => a.order.compareTo(b.order));
    final visible = items.where((e) => !e.hidden).toList();
    final crossAxisCount = layout.columns;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildHeaderRow(),
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                double unit = (totalWidth - (crossAxisCount - 1) * _gridSpacingPx) / crossAxisCount;
                const double minTileUnit = 180;
                if (unit <= 0) unit = minTileUnit;
                if (unit < minTileUnit) unit = minTileUnit;
                final children = <Widget>[];
                for (final it in visible) {
                  final w = (unit * it.colSpan) + _gridSpacingPx * (it.colSpan - 1);
                  final cw = w > totalWidth ? totalWidth : (w < unit ? unit : w);
                  children.add(AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                    key: ValueKey('profile_dash_${it.key}'),
                    width: cw,
                    child: _buildGridTile(it, crossAxisCount),
                  ));
                }
                return SingleChildScrollView(
                  child: Wrap(
                    spacing: _gridSpacingPx,
                    runSpacing: _gridSpacingPx,
                    children: children,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'داشبورد پروفایل',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        IconButton(
          tooltip: _editMode ? 'خروج از ویرایش' : 'ویرایش چیدمان',
          onPressed: () => setState(() => _editMode = !_editMode),
          icon: Icon(_editMode ? Icons.check : Icons.edit),
        ),
      ],
    );
  }

  Widget _buildGridTile(DashboardLayoutItem item, int totalColumns) {
    final data = _data[item.key];
    if (data == null) {
      return _buildCard(
        title: _titleForKey(item.key),
        child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    final builder = _widgetFactory[item.key];
    if (builder == null) {
      return _buildCard(
        title: 'ویجت ناشناخته: ${item.key}',
        child: const Center(child: Text('این ویجت ثبت نشده است')),
      );
    }
    final trailing = _editMode
        ? PopupMenuButton<String>(
            tooltip: 'ویرایش',
            onSelected: (v) {
              if (v == 'w+1') _changeItemWidth(item, 1);
              if (v == 'w-1') _changeItemWidth(item, -1);
              if (v == 'up') _moveItemUp(item);
              if (v == 'down') _moveItemDown(item);
              if (v == 'hide') _hideItem(item, hidden: true);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'w+1', child: Row(children: [Icon(Icons.open_in_full, size: 18), SizedBox(width: 8), Text('افزایش عرض')])),
              PopupMenuItem(value: 'w-1', child: Row(children: [Icon(Icons.close_fullscreen, size: 18), SizedBox(width: 8), Text('کاهش عرض')])),
              PopupMenuDivider(),
              PopupMenuItem(value: 'up', child: Row(children: [Icon(Icons.arrow_upward, size: 18), SizedBox(width: 8), Text('بالا')])),
              PopupMenuItem(value: 'down', child: Row(children: [Icon(Icons.arrow_downward, size: 18), SizedBox(width: 8), Text('پایین')])),
              PopupMenuDivider(),
              PopupMenuItem(value: 'hide', child: Row(children: [Icon(Icons.visibility_off, size: 18), SizedBox(width: 8), Text('پنهان کردن')])),
            ],
            icon: const Icon(Icons.tune),
          )
        : IconButton(
            tooltip: 'بازخوانی',
            icon: const Icon(Icons.refresh),
            onPressed: _reloadDataOnly,
          );
    final card = _buildCard(
      title: _titleForKey(item.key),
      trailing: trailing,
      child: builder(context, data, item, onRefresh: _reloadDataOnly),
    );
    return card;
  }

  void _moveItemUp(DashboardLayoutItem item) {
    final profile = _layout;
    if (profile == null) return;
    final list = List<DashboardLayoutItem>.from(profile.items);
    final idx = list.indexWhere((e) => e.key == item.key);
    if (idx <= 0) return;
    final tmp = list[idx - 1];
    list[idx - 1] = list[idx];
    list[idx] = tmp;
    _reindexAndSave(list);
  }

  void _moveItemDown(DashboardLayoutItem item) {
    final profile = _layout;
    if (profile == null) return;
    final list = List<DashboardLayoutItem>.from(profile.items);
    final idx = list.indexWhere((e) => e.key == item.key);
    if (idx < 0 || idx >= list.length - 1) return;
    final tmp = list[idx + 1];
    list[idx + 1] = list[idx];
    list[idx] = tmp;
    _reindexAndSave(list);
  }

  void _changeItemWidth(DashboardLayoutItem item, int delta) {
    final profile = _layout;
    if (profile == null) return;
    final list = List<DashboardLayoutItem>.from(profile.items);
    final idx = list.indexWhere((e) => e.key == item.key);
    if (idx < 0) return;
    final newSpan = (item.colSpan + delta).clamp(1, profile.columns);
    list[idx] = item.copyWith(colSpan: newSpan);
    _applyItems(list);
  }

  void _hideItem(DashboardLayoutItem item, {required bool hidden}) {
    final profile = _layout;
    if (profile == null) return;
    final list = List<DashboardLayoutItem>.from(profile.items);
    final idx = list.indexWhere((e) => e.key == item.key);
    if (idx < 0) return;
    list[idx] = item.copyWith(hidden: hidden);
    _applyItems(list);
  }

  void _reindexAndSave(List<DashboardLayoutItem> items) {
    final sorted = <DashboardLayoutItem>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      sorted.add(it.copyWith(order: i + 1));
    }
    _applyItems(sorted);
  }

  void _applyItems(List<DashboardLayoutItem> items) async {
    final profile = _layout;
    if (profile == null) return;
    setState(() {
      _layout = DashboardLayoutProfile(
        breakpoint: profile.breakpoint,
        columns: profile.columns,
        items: items,
        version: profile.version,
        updatedAt: profile.updatedAt,
      );
    });
    try {
      final updated = await _service.putLayoutProfile(
        breakpoint: profile.breakpoint,
        items: items,
      );
      if (!mounted) return;
      setState(() {
        _layout = updated;
      });
    } catch (_) {}
  }

  String _titleForKey(String key) {
    switch (key) {
      case 'profile_recent_businesses':
        return 'کسب‌وکارهای شما';
      case 'profile_announcements':
        return 'اعلان‌ها';
      default:
        return key;
    }
  }

  // ====== Registry ======
  Map<String, ProfileWidgetBuilder> get _widgetFactory => <String, ProfileWidgetBuilder>{
        'profile_recent_businesses': _recentBusinessesWidget,
        'profile_announcements': _announcementsWidget,
        'profile_support_tickets': _supportTicketsWidget,
      };

  Widget _buildCard({required String title, Widget? trailing, required Widget child}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.08)),
              ),
            ),
            child: Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                if (trailing != null) trailing,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  // ====== Widgets ======
  Widget _recentBusinessesWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final theme = Theme.of(context);
    final items = (data is Map && data['items'] is List) ? List<Map<String, dynamic>>.from(data['items'] as List) : const <Map<String, dynamic>>[];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text('کسب‌وکاری یافت نشد', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
    }
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final it = items[index];
        final name = '${it['name'] ?? '-'}';
        final role = '${it['role'] ?? ''}';
        final isOwner = (it['is_owner'] ?? false) == true;
        return ListTile(
          dense: true,
          leading: const Icon(Icons.business),
          title: Text(name),
          subtitle: Text(isOwner ? 'مالک' : (role.isNotEmpty ? role : 'عضو')),
          trailing: TextButton.icon(
            onPressed: () {
              final id = it['id'];
              if (id is int) {
                context.go('/business/$id/dashboard');
              } else {
                final p = int.tryParse('$id');
                if (p != null) context.go('/business/$p/dashboard');
              }
            },
            icon: const Icon(Icons.arrow_forward),
            label: const Text('ورود'),
          ),
        );
      },
    );
  }

  Widget _announcementsWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final theme = Theme.of(context);
    final items = (data is Map && data['items'] is List) ? List<Map<String, dynamic>>.from(data['items'] as List) : const <Map<String, dynamic>>[];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text('اعلانی وجود ندارد', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('فقط خوانده‌نشده'),
                selected: _annOnlyUnread,
                onSelected: (v) async {
                  setState(() => _annOnlyUnread = v);
                  await _reloadAnnouncements(onlyUnread: _annOnlyUnread);
                },
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await _reloadAnnouncements(onlyUnread: _annOnlyUnread);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اعلان‌ها به‌روز شد')));
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('بازخوانی'),
              ),
              TextButton.icon(
                onPressed: () => context.go('/user/profile/announcements'),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('مشاهده همه'),
              ),
            ],
          ),
        ),
        ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final it = items[index];
            final id = it['id'];
            final title = '${it['title'] ?? '-'}';
            final body = '${it['body'] ?? ''}';
            final pinned = (it['is_pinned'] ?? false) == true;
            final isRead = (it['is_read'] ?? false) == true;
            final time = '${it['updated_at'] ?? it['time'] ?? ''}';
            final annId = (id is int) ? id : int.tryParse('$id');
            final busy = annId != null && _annBusyIds.contains(annId);
            return ListTile(
              dense: true,
              leading: Icon(pinned ? Icons.push_pin : Icons.notifications, color: pinned ? theme.colorScheme.primary : null),
              title: Row(
                children: [
                  if (!isRead)
                    Container(width: 8, height: 8, margin: const EdgeInsetsDirectional.only(end: 8), decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle)),
                  Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
              subtitle: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (time.isNotEmpty)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: Text(
                        DateFormatters.formatServerDateTime(time),
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  IconButton(
                    tooltip: 'خوانده شد',
                    icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.done_all, size: 20),
                    onPressed: busy
                        ? null
                        : () async {
                            try {
                              if (annId == null) return;
                              setState(() => _annBusyIds.add(annId));
                              await _markAnnouncementRead(annId);
                              await _reloadAnnouncements(onlyUnread: _annOnlyUnread);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('به‌عنوان خوانده‌شده علامت خورد')));
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
                            } finally {
                              if (mounted && annId != null) setState(() => _annBusyIds.remove(annId));
                            }
                          },
                  ),
                  IconButton(
                    tooltip: 'پنهان کردن',
                    icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.close, size: 20),
                    onPressed: busy
                        ? null
                        : () async {
                            try {
                              if (annId == null) return;
                              setState(() => _annBusyIds.add(annId));
                              await _dismissAnnouncement(annId);
                              await _reloadAnnouncements(onlyUnread: _annOnlyUnread);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اعلان پنهان شد')));
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
                            } finally {
                              if (mounted && annId != null) setState(() => _annBusyIds.remove(annId));
                            }
                          },
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _supportTicketsWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final theme = Theme.of(context);
    final items = (data is Map && data['items'] is List) ? List<Map<String, dynamic>>.from(data['items'] as List) : const <Map<String, dynamic>>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(child: Text('تیکتی یافت نشد', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          )
        else
          ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final it = items[index];
              final id = '${it['id'] ?? ''}';
              final subject = '${it['subject'] ?? '-'}';
              final status = '${it['status'] ?? ''}';
              final updatedAt = '${it['updated_at'] ?? ''}';
              return ListTile(
                dense: true,
                leading: const Icon(Icons.support_agent),
                title: Text(subject),
                subtitle: Text('شناسه: $id • وضعیت: $status'),
                trailing: Text(
                  updatedAt.isNotEmpty ? DateFormatters.formatServerDateTime(updatedAt) : '',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                onTap: () {
                  // در آینده: ناوبری به جزئیات تیکت
                },
              );
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              // رفتن به صفحه پشتیبانی
              context.go('/user/profile/support');
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('مشاهده همه'),
          ),
        ),
      ],
    );
  }

  // --- Announcement actions ---
  Future<void> _markAnnouncementRead(int id) async {
    try {
      await AnnouncementsService(ApiClient()).markRead(id);
    } catch (_) {}
  }

  Future<void> _dismissAnnouncement(int id) async {
    try {
      await AnnouncementsService(ApiClient()).dismiss(id);
    } catch (_) {}
  }
}


