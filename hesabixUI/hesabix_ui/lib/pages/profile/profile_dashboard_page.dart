import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reorderables/reorderables.dart';
import '../../core/api_client.dart';
import '../../models/business_dashboard_models.dart';
import '../../utils/date_formatters.dart';
import '../../services/profile_dashboard_service.dart';
import '../../services/support_tickets_public_config.dart';
import '../../services/announcements_service.dart';
import '../../services/support_service.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../utils/snackbar_helper.dart';
import '../../core/auth_store.dart';
import '../../core/mobile_launcher_prefs.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';
import '../../theme/tokens/extensions.dart';
import '../../widgets/support/ticket_details_dialog.dart';

class ProfileDashboardPage extends StatefulWidget {
  final CalendarController calendarController;
  final AuthStore authStore;
  const ProfileDashboardPage({
    super.key,
    required this.calendarController,
    required this.authStore,
  });

  @override
  State<ProfileDashboardPage> createState() => _ProfileDashboardPageState();
}

typedef ProfileWidgetBuilder = Widget Function(
  BuildContext,
  dynamic,
  DashboardLayoutItem, {
  VoidCallback? onRefresh,
});

class _ProfileDashboardPageState extends State<ProfileDashboardPage> with WidgetsBindingObserver {
  late final ProfileDashboardService _service;
  DashboardLayoutProfile? _layout;
  Map<String, dynamic> _data = <String, dynamic>{};
  bool _loading = true;
  String? _error;
  bool _editMode = false;
  final Set<int> _annBusyIds = <int>{};
  bool _annOnlyUnread = false;
  SupportTicketsPublicConfig _supportPublic = const SupportTicketsPublicConfig();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = ProfileDashboardService(ApiClient());
    _loadAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAfterAppResume());
    }
    super.didChangeAppLifecycleState(state);
  }

  Future<void> _refreshAfterAppResume() async {
    if (!mounted || _loading) return;
    if (_error != null) {
      await _loadAll();
      return;
    }
    final layout = _layout;
    try {
      final supportCfg = await SupportTicketsPublicConfig.fetch(ApiClient());
      if (!mounted) return;
      Map<String, dynamic> nextData = _data;
      if (layout != null) {
        final keys = layout.items.where((e) => !e.hidden).map((e) => e.key).toList();
        var data = await _service.getWidgetsBatchData(
          widgetKeys: keys,
          filters: _dashboardFilters(keys),
        );
        data = await _service.hydrateSpecialWidgets(
          data,
          keys,
          onlyUnread: _annOnlyUnread,
        );
        if (!mounted) return;
        nextData = data;
      }
      setState(() {
        _supportPublic = supportCfg;
        if (layout != null) {
          _data = nextData;
        }
      });
    } catch (_) {}
  }

  double _getPadding(BuildContext context) => ResponsiveHelper.getPadding(context);

  double _getGridSpacing(BuildContext context) => ResponsiveHelper.getGridSpacing(context);

  double _getMinTileUnit(BuildContext context) {
    final bp = ResponsiveHelper.breakpoint(context);
    switch (bp) {
      case 'xs':
        return 120.0;
      case 'sm':
        return 135.0;
      case 'md':
        return 150.0;
      case 'lg':
        return 165.0;
      case 'xl':
        return 180.0;
      default:
        return 150.0;
    }
  }

  /// عرض هر ستون گرید — بدون floor اجباری که باعث فضای خالی کناری می‌شود.
  double _computeColumnUnit(double totalWidth, int crossAxisCount, BuildContext context) {
    final spacing = _getGridSpacing(context);
    final minTileUnit = _getMinTileUnit(context);
    if (crossAxisCount <= 0 || totalWidth <= 0) return minTileUnit;
    final naturalUnit = (totalWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
    if (naturalUnit <= 0) return minTileUnit;
    if (_isMobile(context)) return naturalUnit;
    return naturalUnit;
  }

  TextStyle? _getHeaderTextStyle(BuildContext context) {
    final theme = Theme.of(context);
    if (_isMobile(context)) {
      return theme.textTheme.titleMedium;
    }
    return theme.textTheme.titleLarge;
  }

  bool _isMobile(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return ResponsiveHelper.breakpointFromWidth(width) == 'xs';
  }

  Map<String, dynamic> _dashboardFilters(List<String> keys) {
    final filters = <String, dynamic>{};
    if (keys.contains('profile_announcements')) {
      filters['only_unread'] = _annOnlyUnread;
    }
    return filters;
  }

  Future<void> _openBusinessFromDashboard(int businessId) async {
    final t = AppLocalizations.of(context);
    if (!_isMobile(context)) {
      await MobileLauncherPrefs.clearResumeLauncher(widget.authStore.currentUserId);
      if (!mounted) return;
      context.go('/business/$businessId/dashboard');
      return;
    }
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
                    await MobileLauncherPrefs.clearResumeLauncher(
                      widget.authStore.currentUserId,
                    );
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
                      widget.authStore.currentUserId,
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

  Future<void> _openTicketDetail(int ticketId) async {
    try {
      final ticket = await SupportService(ApiClient()).getTicket(ticketId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => TicketDetailsDialog(
          ticket: ticket,
          calendarController: widget.calendarController,
          onTicketUpdated: () => _reloadWidget('profile_support_tickets'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _loadAll() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final supportCfg = await SupportTicketsPublicConfig.fetch(ApiClient());
      final defs = await _service.getWidgetDefinitions();
      if (!context.mounted) return;
      final ctx = context;
      final bp = ResponsiveHelper.breakpointFromWidth(MediaQuery.of(ctx).size.width);
      var layout = await _service.getLayoutProfile(breakpoint: bp);
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
        layout = await _service.putLayoutProfile(breakpoint: bp, items: items);
      }
      final keys = layout.items.where((e) => !e.hidden).map((e) => e.key).toList();
      var data = await _service.getWidgetsBatchData(
        widgetKeys: keys,
        filters: _dashboardFilters(keys),
      );
      data = await _service.hydrateSpecialWidgets(
        data,
        keys,
        onlyUnread: _annOnlyUnread,
      );
      if (!mounted) return;
      setState(() {
        _layout = layout;
        _data = data;
        _loading = false;
        _supportPublic = supportCfg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<void> _reloadDataOnly() async {
    try {
      final layout = _layout;
      if (layout == null) return;
      final keys = layout.items.where((e) => !e.hidden).map((e) => e.key).toList();
      var data = await _service.getWidgetsBatchData(
        widgetKeys: keys,
        filters: _dashboardFilters(keys),
      );
      data = await _service.hydrateSpecialWidgets(
        data,
        keys,
        onlyUnread: _annOnlyUnread,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
      });
    } catch (_) {}
  }

  Future<void> _reloadWidget(String key) async {
    try {
      var data = await _service.getWidgetsBatchData(
        widgetKeys: [key],
        filters: _dashboardFilters([key]),
      );
      data = await _service.hydrateSpecialWidgets(
        data,
        [key],
        onlyUnread: _annOnlyUnread,
      );
      if (!mounted) return;
      setState(() {
        if (data.containsKey(key)) {
          _data[key] = data[key];
        }
      });
    } catch (_) {
      await _reloadDataOnly();
    }
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
      await _reloadWidget('profile_announcements');
    }
  }

  List<Widget> _buildGridChildren({
    required List<DashboardLayoutItem> visible,
    required int crossAxisCount,
    required double totalWidth,
    required double unit,
    required double spacing,
  }) {
    final children = <Widget>[];
    for (final it in visible) {
      final w = (unit * it.colSpan) + spacing * (it.colSpan - 1);
      final cw = w > totalWidth ? totalWidth : (w < unit ? unit : w);
      children.add(
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          key: ValueKey('profile_dash_${it.key}'),
          width: cw,
          child: _buildGridTile(it, crossAxisCount),
        ),
      );
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final padding = _getPadding(context);
    final dashBg = context.shellColors.dashboardBackground;

    if (_loading) {
      return Container(
        color: dashBg,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfileDashboardSkeleton.header(context),
              SizedBox(height: _isMobile(context) ? 12 : 16),
              Expanded(child: _ProfileDashboardSkeleton.grid(context)),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Container(
        color: dashBg,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 56, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(t.profileDashboardLoadError(_error!), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadAll, child: Text(t.retry)),
            ],
          ),
        ),
      );
    }

    final layout = _layout!;
    final items = List<DashboardLayoutItem>.from(layout.items)..sort((a, b) => a.order.compareTo(b.order));
    final visible = items.where((e) => !e.hidden).toList();
    final crossAxisCount = layout.columns;

    return Container(
      color: dashBg,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          children: [
            _buildHeaderRow(t),
            SizedBox(height: _isMobile(context) ? 12 : 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  final spacing = _getGridSpacing(context);
                  final unit = _computeColumnUnit(totalWidth, crossAxisCount, context);
                  final children = _buildGridChildren(
                    visible: visible,
                    crossAxisCount: crossAxisCount,
                    totalWidth: totalWidth,
                    unit: unit,
                    spacing: spacing,
                  );
                  if (!_editMode) {
                    return SingleChildScrollView(
                      child: Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: children,
                      ),
                    );
                  }
                  return SingleChildScrollView(
                    child: ReorderableWrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      needsLongPressDraggable: true,
                      onReorder: (oldIndex, newIndex) {
                        final list = List<DashboardLayoutItem>.from(visible);
                        final moved = list.removeAt(oldIndex);
                        list.insert(newIndex, moved);
                        final profile = _layout!;
                        final newItems = <DashboardLayoutItem>[];
                        final visibleKeys = list.map((e) => e.key).toSet();
                        newItems.addAll(list);
                        for (final it in profile.items) {
                          if (!visibleKeys.contains(it.key) && !it.hidden) continue;
                          if (it.hidden) newItems.add(it);
                        }
                        _reindexAndSave(newItems);
                      },
                      children: children,
                    ),
                  );
                },
              ),
            ),
            if (_editMode) ...[
              const SizedBox(height: 12),
              _buildHiddenSection(t),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow(AppLocalizations t) {
    final isMobile = _isMobile(context);
    final headerStyle = _getHeaderTextStyle(context);

    final editToggleButton = IconButton(
      tooltip: _editMode ? t.profileDashboardExitEdit : t.profileDashboardEditLayout,
      onPressed: () => setState(() => _editMode = !_editMode),
      icon: Icon(_editMode ? Icons.check : Icons.edit),
      iconSize: isMobile ? 20 : 24,
    );

    return Row(
      children: [
        Expanded(
          child: Text(
            t.profileDashboardTitle,
            style: headerStyle,
          ),
        ),
        editToggleButton,
      ],
    );
  }

  Widget _buildHiddenSection(AppLocalizations t) {
    final profile = _layout;
    if (profile == null) return const SizedBox.shrink();
    final hidden = profile.items.where((e) => e.hidden).toList();
    if (hidden.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.profileDashboardHiddenWidgets, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: hidden.map((it) {
                return InputChip(
                  label: Text(_titleForKey(it.key, t)),
                  avatar: const Icon(Icons.widgets, size: 18),
                  onPressed: () => _hideItem(it, hidden: false),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridTile(DashboardLayoutItem item, int totalColumns) {
    final data = _data[item.key];
    final l10n = AppLocalizations.of(context);
    if (data == null) {
      return _buildCard(
        title: _titleForKey(item.key, l10n),
        child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    final builder = _widgetFactory[item.key];
    if (builder == null) {
      return _buildCard(
        title: l10n.profileDashboardUnknownWidget(item.key),
        child: Center(child: Text(l10n.profileDashboardWidgetNotRegistered)),
      );
    }
    final trailing = _editMode
        ? PopupMenuButton<String>(
            tooltip: l10n.profileDashboardEditLayout,
            onSelected: (v) {
              if (v == 'w+1') _changeItemWidth(item, 1);
              if (v == 'w-1') _changeItemWidth(item, -1);
              if (v == 'up') _moveItemUp(item);
              if (v == 'down') _moveItemDown(item);
              if (v == 'hide') _hideItem(item, hidden: true);
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'w+1', child: Row(children: [const Icon(Icons.open_in_full, size: 18), const SizedBox(width: 8), Text(l10n.profileDashboardIncreaseWidth)])),
              PopupMenuItem(value: 'w-1', child: Row(children: [const Icon(Icons.close_fullscreen, size: 18), const SizedBox(width: 8), Text(l10n.profileDashboardDecreaseWidth)])),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'up', child: Row(children: [const Icon(Icons.arrow_upward, size: 18), const SizedBox(width: 8), Text(l10n.profileDashboardMoveUp)])),
              PopupMenuItem(value: 'down', child: Row(children: [const Icon(Icons.arrow_downward, size: 18), const SizedBox(width: 8), Text(l10n.profileDashboardMoveDown)])),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'hide', child: Row(children: [const Icon(Icons.visibility_off, size: 18), const SizedBox(width: 8), Text(l10n.profileDashboardHide)])),
            ],
            icon: const Icon(Icons.tune),
          )
        : IconButton(
            tooltip: l10n.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => _reloadWidget(item.key),
          );
    final card = _buildCard(
      title: _titleForKey(item.key, l10n),
      trailing: trailing,
      child: builder(context, data, item, onRefresh: () => _reloadWidget(item.key)),
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
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      SnackBarHelper.showError(
        context,
        message: t.profileDashboardLayoutSaveFailed(ErrorExtractor.forContext(e, context)),
      );
    }
  }

  String _titleForKey(String key, AppLocalizations l10n) {
    switch (key) {
      case 'profile_recent_businesses':
        return l10n.profileDashboardYourBusinesses;
      case 'profile_announcements':
        return l10n.profileDashboardAnnouncements;
      case 'profile_support_tickets':
        return l10n.supportTickets;
      default:
        return key;
    }
  }

  Map<String, ProfileWidgetBuilder> get _widgetFactory => <String, ProfileWidgetBuilder>{
        'profile_recent_businesses': _recentBusinessesWidget,
        'profile_announcements': _announcementsWidget,
        'profile_support_tickets': _supportTicketsWidget,
      };

  Widget _buildCard({required String title, Widget? trailing, required Widget child}) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.08)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _recentBusinessesWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final items = (data is Map && data['items'] is List) ? List<Map<String, dynamic>>.from(data['items'] as List) : const <Map<String, dynamic>>[];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              t.profileDashboardNoBusinesses,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => context.go('/user/profile/new-business'),
              icon: const Icon(Icons.add_business),
              label: Text(t.profileDashboardCreateBusiness),
            ),
          ],
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
          subtitle: Text(isOwner ? t.owner : (role.isNotEmpty ? role : t.profileDashboardMemberRole)),
          trailing: TextButton.icon(
            onPressed: () async {
              final id = it['id'];
              if (id is int) {
                await _openBusinessFromDashboard(id);
              } else {
                final p = int.tryParse('$id');
                if (p != null) {
                  await _openBusinessFromDashboard(p);
                }
              }
            },
            icon: const Icon(Icons.arrow_forward),
            label: Text(t.profileDashboardEnterBusiness),
          ),
        );
      },
    );
  }

  Widget _announcementsWidget(BuildContext context, dynamic data, DashboardLayoutItem item, {VoidCallback? onRefresh}) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final items = (data is Map && data['items'] is List) ? List<Map<String, dynamic>>.from(data['items'] as List) : const <Map<String, dynamic>>[];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              t.profileDashboardNoAnnouncements,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.go('/user/profile/announcements'),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(t.profileDashboardViewAllAnnouncements),
            ),
          ],
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
                label: Text(t.profileDashboardOnlyUnread),
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
                  SnackBarHelper.show(context, message: t.profileDashboardAnnouncementsRefreshed);
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(t.refresh),
              ),
              TextButton.icon(
                onPressed: () => context.go('/user/profile/announcements'),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(t.profileDashboardViewAllAnnouncements),
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
            final timeRaw = it['updated_at'] ?? it['time'];
            final time = timeRaw is Map ? (timeRaw['formatted'] ?? timeRaw['date_only'] ?? timeRaw.toString()) : '${timeRaw ?? ''}';
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
                        _formatNotificationTime(time),
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  if (!isRead)
                    IconButton(
                      tooltip: t.profileDashboardMarkAsRead,
                      icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.done_all, size: 20),
                      onPressed: busy
                          ? null
                          : () async {
                            try {
                              if (annId == null) return;
                              setState(() => _annBusyIds.add(annId));
                              await _markAnnouncementRead(annId);
                              if (_annOnlyUnread) {
                                final current = (_data['profile_announcements'] as Map?)?['items'];
                                if (current is List) {
                                  final nextItems = current
                                      .where((e) {
                                        if (e is! Map) return true;
                                        final eid = e['id'];
                                        final parsed = eid is int ? eid : int.tryParse('$eid');
                                        return parsed != annId;
                                      })
                                      .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
                                      .toList();
                                  setState(() {
                                    _data['profile_announcements'] = {'items': nextItems};
                                  });
                                  if (nextItems.isEmpty) {
                                    await _reloadAnnouncements(onlyUnread: true);
                                  }
                                }
                              } else {
                                setState(() {
                                  final current = (_data['profile_announcements'] as Map?)?['items'];
                                  if (current is List) {
                                    final nextItems = current.map<Map<String, dynamic>>((e) {
                                      final map = Map<String, dynamic>.from(e as Map);
                                      final eid = map['id'];
                                      final parsed = eid is int ? eid : int.tryParse('$eid');
                                      if (parsed == annId) {
                                        map['is_read'] = true;
                                      }
                                      return map;
                                    }).toList();
                                    _data['profile_announcements'] = {'items': nextItems};
                                  }
                                });
                              }
                              if (!context.mounted) return;
                              SnackBarHelper.show(context, message: t.profileDashboardMarkedAsRead);
                            } catch (e) {
                              if (!context.mounted) return;
                              SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
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
    final t = AppLocalizations.of(context);
    if (!_supportPublic.enabledForUsers) {
      final msg = _supportPublic.disabledMessage.trim().isEmpty
          ? t.supportTicketsUnavailableBody
          : _supportPublic.disabledMessage;
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: SelectableText(
          msg,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.35),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  t.profileDashboardNoTickets,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => context.go('/user/profile/support'),
                  icon: const Icon(Icons.support_agent),
                  label: Text(t.profileDashboardCreateTicket),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final it = items[index];
              final idRaw = it['id'];
              final id = '${idRaw ?? ''}';
              final subject = '${it['subject'] ?? '-'}';
              final status = '${it['status'] ?? ''}';
              final updatedAt = '${it['updated_at'] ?? ''}';
              final ticketId = idRaw is int ? idRaw : int.tryParse(id);
              return ListTile(
                dense: true,
                leading: const Icon(Icons.support_agent),
                title: Text(subject),
                subtitle: Text('شناسه: $id • وضعیت: $status'),
                trailing: Text(
                  updatedAt.isNotEmpty ? DateFormatters.formatServerDateTime(updatedAt) : '',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                onTap: ticketId != null ? () => _openTicketDetail(ticketId) : null,
              );
            },
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => context.go('/user/profile/support'),
            icon: const Icon(Icons.open_in_new),
            label: Text(t.profileDashboardViewAllTickets),
          ),
        ),
      ],
    );
  }

  Future<void> _markAnnouncementRead(int id) async {
    await AnnouncementsService(ApiClient()).markRead(id);
  }

  String _formatNotificationTime(dynamic timeData) {
    if (timeData == null) return '-';

    if (timeData is Map) {
      final formatted = timeData['formatted'];
      if (formatted != null) {
        return formatted.toString();
      }
      final dateOnly = timeData['date_only'];
      if (dateOnly != null) {
        return dateOnly.toString();
      }
      final raw = timeData['raw'] ?? timeData['updated_at'] ?? timeData['time'];
      if (raw != null) {
        return _formatNotificationTime(raw);
      }
    }

    final timeStr = timeData.toString();
    if (timeStr.isEmpty) return '-';

    try {
      final dateTime = DateTime.tryParse(timeStr);
      if (dateTime != null) {
        return HesabixDateUtils.formatDateTime(dateTime, widget.calendarController.isJalali);
      }
      return DateFormatters.formatServerDateTime(timeStr);
    } catch (_) {
      return DateFormatters.formatServerDateTime(timeStr);
    }
  }
}

class _ProfileDashboardSkeleton {
  static Widget header(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _ShimmerBox(height: 28, width: 180, color: cs.surfaceContainerHighest);
  }

  static Widget grid(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = ResponsiveHelper.isMobile(context);
    final count = isMobile ? 2 : 3;
    return Column(
      children: List.generate(count, (i) {
        return Padding(
          padding: EdgeInsets.only(bottom: i < count - 1 ? 12 : 0),
          child: _ShimmerBox(height: isMobile ? 140 : 180, color: cs.surfaceContainerHighest),
        );
      }),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final double height;
  final double? width;
  final Color color;

  const _ShimmerBox({required this.height, required this.color, this.width});

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.45 + _controller.value * 0.35,
          child: child,
        );
      },
      child: Container(
        height: widget.height,
        width: widget.width ?? double.infinity,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
