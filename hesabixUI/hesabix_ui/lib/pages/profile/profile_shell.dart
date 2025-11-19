import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:go_router/go_router.dart';
import '../../core/auth_store.dart';
import '../../core/locale_controller.dart';
import '../../core/calendar_controller.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/language_switcher.dart';
import '../../widgets/calendar_switcher.dart';
import '../../widgets/theme_mode_switcher.dart';
import '../../widgets/logout_button.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/notifications_ws_client.dart';
import '../../core/api_client.dart';
import '../../services/announcements_service.dart';

class ProfileShell extends StatefulWidget {
  final Widget child;
  final AuthStore authStore;
  final LocaleController? localeController;
  final CalendarController? calendarController;
  final ThemeController? themeController;
  const ProfileShell({super.key, required this.child, required this.authStore, this.localeController, this.calendarController, this.themeController});

  @override
  State<ProfileShell> createState() => _ProfileShellState();
}

class _ProfileShellState extends State<ProfileShell> {
  int _hoverIndex = -1;
  NotificationsWsClient? _ws;
  final List<Map<String, dynamic>> _notifications = <Map<String, dynamic>>[];
  int _unreadCount = 0;
  final Set<int> _busyAnnIds = <int>{};

  @override
  void initState() {
    super.initState();
    // اضافه کردن listener برای AuthStore
    widget.authStore.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    // بارگذاری اولیه اعلان‌های خوانده‌نشده
    _loadInitialNotifications();
    // اتصال خودکار وب‌سوکت برای دریافت نوتیفیکیشن‌های بلادرنگ (mobile/desktop)
    final apiKey = widget.authStore.apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      _ws = createNotificationsWsClient();
      _ws!.connect(
        apiKey: apiKey,
        onMessage: (msg) {
          try {
            final type = '${msg['type'] ?? ''}';
            if (type == 'notification') {
              final title = '${msg['title'] ?? 'پیام'}';
              final body = '${msg['body'] ?? ''}';
              setState(() {
                _notifications.insert(0, <String, dynamic>{
                  'title': title,
                  'body': body,
                  'level': '${msg['level'] ?? 'info'}',
                });
                _unreadCount = (_unreadCount + 1).clamp(0, 99);
              });
              if (mounted) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text('$title: $body'), duration: const Duration(seconds: 4)));
              }
            }
          } catch (_) {}
        },
      );
    }
  }

  Future<void> _loadInitialNotifications() async {
    try {
      final annSvc = AnnouncementsService(ApiClient());
      final data = await annSvc.listAnnouncements(page: 1, limit: 5, onlyUnread: true);
      final items = (data['items'] as List? ?? const <dynamic>[])
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        // تبدیل به ساختار یکسان برای مرکز اعلان
        _notifications.clear();
        for (final it in items) {
          _notifications.add(<String, dynamic>{
            'title': '${it['title'] ?? 'اعلان'}',
            'body': '${it['body'] ?? ''}',
            'level': '${it['level'] ?? 'info'}',
            'id': it['id'],
          });
        }
        _unreadCount = _notifications.length.clamp(0, 99);
      });
    } catch (_) {}
  }

  void _openNotificationCenter() {
    setState(() {
      _unreadCount = 0;
    });
    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            final items = _notifications.take(10).toList();
            final ColorScheme cs = Theme.of(context).colorScheme;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: EdgeInsets.zero,
              title: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [cs.primary, cs.primary.withValues(alpha: 0.8)]),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text('مرکز اعلان‌ها', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      tooltip: 'بستن',
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              content: LayoutBuilder(
                builder: (ctx, _) {
                  final double dialogWidth = math.min(MediaQuery.of(ctx).size.width - 96, 900);
                  return ConstrainedBox(
                    constraints: BoxConstraints(minWidth: dialogWidth, maxWidth: dialogWidth, maxHeight: 420),
                    child: items.isEmpty
                        ? const SizedBox(height: 140, child: Center(child: Text('اعلانی وجود ندارد')))
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemBuilder: (_, i) {
                              final it = items[i];
                              final level = '${it['level'] ?? 'info'}';
                              IconData icon;
                              Color levelColor;
                              switch (level) {
                                case 'warning':
                                  icon = Icons.warning_amber_rounded;
                                  levelColor = Colors.orange;
                                  break;
                                case 'critical':
                                  icon = Icons.error_outline;
                                  levelColor = Colors.red;
                                  break;
                                default:
                                  icon = Icons.notifications_none;
                                  levelColor = cs.primary;
                              }
                              final int? annId = it['id'] is int ? it['id'] as int : int.tryParse('${it['id']}');
                              final bool busy = annId != null && _busyAnnIds.contains(annId);
                              return Container(
                                decoration: BoxDecoration(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                                  border: Border(left: BorderSide(color: levelColor, width: 3)),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(color: levelColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                                      child: Icon(icon, color: levelColor),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('${it['title'] ?? 'اعلان'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Text('${it['body'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: levelColor.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(level, style: TextStyle(color: levelColor, fontSize: 11)),
                                              ),
                                              const Spacer(),
                                              TextButton.icon(
                                                onPressed: () {
                                                  Navigator.of(context).pop();
                                                  context.go('/user/profile/announcements');
                                                },
                                                icon: const Icon(Icons.open_in_new, size: 16),
                                                label: const Text('جزئیات'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (annId != null)
                                      IconButton(
                                        tooltip: 'خوانده شد',
                                        icon: busy
                                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                            : const Icon(Icons.done_all, size: 20),
                                        onPressed: busy ? null : () async => _markNotificationRead(annId, dialogSetState: dialogSetState),
                                      ),
                                  ],
                                ),
                              );
                            },
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemCount: items.length,
                          ),
                  );
                },
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('بستن'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.go('/user/profile/announcements');
                  },
                  icon: const Icon(Icons.notifications, size: 18),
                  label: const Text('مشاهده همه اعلان‌ها'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _markNotificationRead(int id, {StateSetter? dialogSetState}) async {
    void refreshDialog() {
      if (dialogSetState != null) {
        dialogSetState(() {});
      }
    }
    setState(() => _busyAnnIds.add(id));
    refreshDialog();
    try {
      await AnnouncementsService(ApiClient()).markRead(id);
      // حذف از لیست مرکز اعلان
      setState(() {
        _notifications.removeWhere((e) => (e['id'] is int ? e['id'] == id : int.tryParse('${e['id']}') == id));
      });
      refreshDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('به‌عنوان خوانده‌شده علامت خورد')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _busyAnnIds.remove(id));
      } else {
        _busyAnnIds.remove(id);
      }
      refreshDialog();
    }
  }

  @override
  void dispose() {
    try {
      _ws?.disconnect();
    } catch (_) {}
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool useRail = width >= 700;
    final bool railExtended = width >= 1100;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    String location = '/user/profile/dashboard'; // default location
    try {
      location = GoRouterState.of(context).uri.toString();
    } catch (e) {
      // اگر GoRouterState در دسترس نیست، از default استفاده کن
    }
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String logoAsset = isDark
        ? 'assets/images/logo-light.png'
        : 'assets/images/logo-light.png';

    final t = AppLocalizations.of(context);
    final destinations = <_Dest>[
      _Dest(t.dashboard, Icons.dashboard_outlined, Icons.dashboard, '/user/profile/dashboard'),
      _Dest(t.newBusiness, Icons.add_business, Icons.add_business, '/user/profile/new-business'),
      _Dest(t.businesses, Icons.business, Icons.business, '/user/profile/businesses'),
      _Dest(t.support, Icons.support_agent, Icons.support_agent, '/user/profile/support'),
      _Dest(t.marketing, Icons.campaign, Icons.campaign, '/user/profile/marketing'),
      _Dest('امضا و تصویر کاربر', Icons.border_color, Icons.border_color, '/user/profile/signature'),
      _Dest(t.changePassword, Icons.password, Icons.password, '/user/profile/change-password'),
    ];

    // اضافه کردن منوی اپراتور پشتیبانی
    final operatorDestinations = <_Dest>[
      _Dest(t.operatorPanel, Icons.support_agent, Icons.support_agent, '/user/profile/operator'),
    ];

    // اضافه کردن منوی تنظیمات سیستم برای ادمین‌ها
    final adminDestinations = <_Dest>[
      _Dest(t.systemSettings, Icons.admin_panel_settings, Icons.admin_panel_settings, '/user/profile/system-settings'),
    ];

    // ترکیب منوهای عادی، اپراتور و ادمین
    final allDestinations = <_Dest>[
      ...destinations,
      if (widget.authStore.canAccessSupportOperator) ...operatorDestinations,
      if (widget.authStore.isSuperAdmin || widget.authStore.hasAppPermission('system_settings')) ...adminDestinations,
    ];

    int selectedIndex = 0;
    for (int i = 0; i < allDestinations.length; i++) {
      if (location.startsWith(allDestinations[i].path)) {
        selectedIndex = i;
        break;
      }
    }

    Future<void> onSelect(int index) async {
      final path = allDestinations[index].path;
      try {
        if (GoRouterState.of(context).uri.toString() != path) {
          context.go(path);
        }
      } catch (e) {
        // اگر GoRouterState در دسترس نیست، مستقیماً به مسیر برود
        context.go(path);
      }
    }

    Future<void> onLogout() async {
      await widget.authStore.saveApiKey(null);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t.logoutDone)));
      context.go('/login');
    }

    // Brand top bar with contrast color
    final Color appBarBg = Theme.of(context).brightness == Brightness.dark
        ? scheme.surfaceContainerHighest
        : scheme.primary;
    final Color appBarFg = Theme.of(context).brightness == Brightness.dark
        ? scheme.onSurfaceVariant
        : scheme.onPrimary;

    final appBar = AppBar(
      backgroundColor: appBarBg,
      foregroundColor: appBarFg,
      titleSpacing: 0,
      title: Row(
        children: [
          const SizedBox(width: 12),
          Image.asset(logoAsset, height: 28),
          const SizedBox(width: 12),
          Text(t.appTitle, style: TextStyle(color: appBarFg, fontWeight: FontWeight.w700)),
        ],
      ),
      leading: useRail
          ? null
          : Builder(
              builder: (ctx) => IconButton(
                icon: Icon(Icons.menu, color: appBarFg),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                tooltip: t.menu,
              ),
            ),
      actions: [
        if (widget.calendarController != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: CalendarSwitcher(controller: widget.calendarController!),
          ),
        ],
        if (widget.localeController != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: LanguageSwitcher(controller: widget.localeController!),
          ),
        ],
        if (widget.themeController != null) ...[
          ThemeModeSwitcher(controller: widget.themeController!),
          const SizedBox(width: 8),
        ],
        // Notification Center button with badge
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 4),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'اعلان‌ها',
                onPressed: _openNotificationCenter,
                icon: const Icon(Icons.notifications_none),
                color: appBarFg,
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 4,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(minWidth: 18),
                    child: Text(
                      _unreadCount > 9 ? '9+' : '$_unreadCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
        LogoutButton(authStore: widget.authStore),
      ],
    );

    final content = Container(
      color: scheme.surface,
      child: SafeArea(
        child: widget.child,
      ),
    );

    // Side colors and styles
    final Color sideBg = Theme.of(context).brightness == Brightness.dark
        ? scheme.surfaceContainerHighest
        : scheme.surfaceContainerLow;
    final Color sideFg = scheme.onSurfaceVariant;
    final Color activeBg = scheme.primaryContainer;
    final Color activeFg = scheme.onPrimaryContainer;

    if (useRail) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            Container(
              width: railExtended ? 240 : 88,
              height: double.infinity,
              color: sideBg,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: allDestinations.length,
                itemBuilder: (ctx, i) {
                  final d = allDestinations[i];
                  final bool isHovered = i == _hoverIndex;
                  final bool isSelected = i == selectedIndex;
                  final bool active = isSelected || isHovered;
                  final BorderRadius br = (isSelected && useRail)
                      ? BorderRadius.zero
                      : (isHovered ? BorderRadius.zero : BorderRadius.circular(8));
                  final Color bgColor = active
                      ? (isHovered && !isSelected ? activeBg.withValues(alpha: 0.85) : activeBg)
                      : Colors.transparent;
                  return MouseRegion(
                    onEnter: (_) => setState(() => _hoverIndex = i),
                    onExit: (_) => setState(() => _hoverIndex = -1),
                    child: InkWell(
                      borderRadius: br,
                      onTap: () => onSelect(i),
                      child: Container(
                        margin: EdgeInsets.zero,
                        padding: EdgeInsets.symmetric(horizontal: railExtended ? 12 : 0, vertical: 10),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: br,
                        ),
                        child: Row(
                          mainAxisAlignment: railExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
                          children: [
                            Icon(d.icon, color: active ? activeFg : sideFg),
                            if (railExtended) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  d.label,
                                  style: TextStyle(
                                    color: active ? activeFg : sideFg,
                                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      drawer: Drawer(
        backgroundColor: sideBg,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (int i = 0; i < allDestinations.length; i++) ...[
                Builder(builder: (ctx) {
                  final d = allDestinations[i];
                  final bool active = i == selectedIndex;
                  return ListTile(
                    leading: Icon(d.selectedIcon, color: active ? activeFg : sideFg),
                    title: Text(d.label, style: TextStyle(color: active ? activeFg : sideFg, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
                    selected: active,
                    selectedTileColor: activeBg,
                    onTap: () {
                      context.pop();
                      onSelect(i);
                    },
                  );
                }),
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(t.logout),
                onTap: onLogout,
              ),
            ],
          ),
        ),
      ),
      body: content,
    );
  }
}

class _Dest {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
  const _Dest(this.label, this.icon, this.selectedIcon, this.path);
}


