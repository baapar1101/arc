import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth_store.dart';
import '../../core/locale_controller.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/language_switcher.dart';
import '../../widgets/theme_mode_switcher.dart';
import '../../widgets/logout_button.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class ProfileShell extends StatefulWidget {
  final Widget child;
  final AuthStore authStore;
  final LocaleController? localeController;
  final ThemeController? themeController;
  const ProfileShell({super.key, required this.child, required this.authStore, this.localeController, this.themeController});

  @override
  State<ProfileShell> createState() => _ProfileShellState();
}

class _ProfileShellState extends State<ProfileShell> {
  int _hoverIndex = -1;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool useRail = width >= 700;
    final bool railExtended = width >= 1100;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String location = GoRouterState.of(context).uri.toString();
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
      _Dest(t.changePassword, Icons.password, Icons.password, '/user/profile/change-password'),
    ];

    int selectedIndex = 0;
    for (int i = 0; i < destinations.length; i++) {
      if (location.startsWith(destinations[i].path)) {
        selectedIndex = i;
        break;
      }
    }

    Future<void> onSelect(int index) async {
      final path = destinations[index].path;
      if (GoRouterState.of(context).uri.toString() != path) {
        context.go(path);
      }
    }

    Future<void> onLogout() async {
      await widget.authStore.saveApiKey(null);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('خروج انجام شد')));
      context.go('/login');
    }

    // Brand top bar with contrast color
    final Color appBarBg = Theme.of(context).brightness == Brightness.dark
        ? scheme.surfaceVariant
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
        if (widget.themeController != null) ...[
          ThemeModeSwitcher(controller: widget.themeController!),
          const SizedBox(width: 8),
        ],
        if (widget.localeController != null) ...[
          LanguageSwitcher(controller: widget.localeController!),
          const SizedBox(width: 8),
        ],
        LogoutButton(authStore: widget.authStore),
      ],
    );

    final content = Container(
      color: scheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: widget.child,
        ),
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
                itemCount: destinations.length,
                itemBuilder: (ctx, i) {
                  final d = destinations[i];
                  final bool isHovered = i == _hoverIndex;
                  final bool isSelected = i == selectedIndex;
                  final bool active = isSelected || isHovered;
                  final double radius = (isHovered && !isSelected) ? 0 : 8;
                  return MouseRegion(
                    onEnter: (_) => setState(() => _hoverIndex = i),
                    onExit: (_) => setState(() => _hoverIndex = -1),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(radius),
                      onTap: () => onSelect(i),
                      child: Container(
                        margin: EdgeInsets.zero,
                        padding: EdgeInsets.symmetric(horizontal: railExtended ? 12 : 0, vertical: 10),
                        decoration: BoxDecoration(
                          color: active ? activeBg : Colors.transparent,
                          borderRadius: BorderRadius.circular(radius),
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
              for (int i = 0; i < destinations.length; i++) ...[
                Builder(builder: (ctx) {
                  final d = destinations[i];
                  final bool active = i == selectedIndex;
                  return ListTile(
                    leading: Icon(d.selectedIcon, color: active ? activeFg : sideFg),
                    title: Text(d.label, style: TextStyle(color: active ? activeFg : sideFg, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
                    selected: active,
                    selectedTileColor: activeBg,
                    onTap: () {
                      Navigator.of(context).pop();
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


