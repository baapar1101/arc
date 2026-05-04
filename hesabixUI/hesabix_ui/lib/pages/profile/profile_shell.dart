import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth_store.dart';
import '../../core/locale_controller.dart';
import '../../core/calendar_controller.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/language_switcher.dart';
import '../../widgets/calendar_switcher.dart';
import '../../widgets/theme_mode_switcher.dart';
import '../../widgets/logout_button.dart';
import '../../widgets/notification_bell_button.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

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
  /// هم‌تراز با [BusinessShell] — نوار بالای پنل کاربر.
  static const double _kProfileAppBarToolbarHeight = 44;

  int _hoverIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.authStore.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
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
      _Dest(t.accountSettingsTitle, Icons.settings_outlined, Icons.settings, '/user/profile/account-settings'),
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

    final Color appBarBg = scheme.primary;
    final Color appBarFg = scheme.onPrimary;

    final appBar = AppBar(
      toolbarHeight: _kProfileAppBarToolbarHeight,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: appBarBg,
      foregroundColor: appBarFg,
      iconTheme: IconThemeData(color: appBarFg, size: 21),
      actionsIconTheme: IconThemeData(color: appBarFg, size: 21),
      automaticallyImplyLeading: !useRail,
      titleSpacing: 0,
      title: Row(
        children: [
          SizedBox(width: useRail ? 12 : 8),
          Image.asset(logoAsset, height: 22),
          const SizedBox(width: 10),
          Text(
            t.appTitle,
            style: TextStyle(color: appBarFg, fontWeight: FontWeight.w700, fontSize: 15, height: 1.1),
          ),
        ],
      ),
      leading: useRail
          ? null
          : Builder(
              builder: (ctx) => IconButton(
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(Icons.menu_rounded, color: appBarFg, size: 21),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                tooltip: t.menu,
              ),
            ),
      actions: [
        if (widget.calendarController != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: CalendarSwitcher(controller: widget.calendarController!, toolbarCompact: true),
          ),
        ],
        if (widget.localeController != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: LanguageSwitcher(controller: widget.localeController!, toolbarCompact: true),
          ),
        ],
        if (widget.themeController != null) ...[
          ThemeModeSwitcher(controller: widget.themeController!, toolbarCompact: true),
          const SizedBox(width: 6),
        ],
        NotificationBellButton(authStore: widget.authStore, iconColor: appBarFg, denseToolbar: true),
        LogoutButton(authStore: widget.authStore, toolbarCompact: true),
        const SizedBox(width: 2),
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


