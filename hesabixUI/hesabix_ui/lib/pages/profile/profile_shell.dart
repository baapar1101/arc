import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth_store.dart';
import '../../core/locale_controller.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/language_switcher.dart';
import '../../widgets/theme_mode_switcher.dart';
import '../../widgets/logout_button.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class ProfileShell extends StatelessWidget {
  final Widget child;
  final AuthStore authStore;
  final LocaleController? localeController;
  final ThemeController? themeController;
  const ProfileShell({super.key, required this.child, required this.authStore, this.localeController, this.themeController});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool useRail = width >= 700;
    final bool railExtended = width >= 1100;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String location = GoRouterState.of(context).uri.toString();

    final t = AppLocalizations.of(context);
    final destinations = <_Dest>[
      _Dest(t.dashboard, Icons.dashboard_outlined, Icons.dashboard, '/user/profile/dashboard'),
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
      await authStore.saveApiKey(null);
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
          // Logo placeholder (can replace with AssetImage)
          CircleAvatar(backgroundColor: appBarFg.withOpacity(0.15), child: Icon(Icons.account_balance, color: appBarFg)),
          const SizedBox(width: 12),
          Text(t.appTitle, style: TextStyle(color: appBarFg, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text(destinations[selectedIndex].label, style: TextStyle(color: appBarFg.withOpacity(0.85))),
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
        if (themeController != null) ...[
          ThemeModeSwitcher(controller: themeController!),
          const SizedBox(width: 8),
        ],
        if (localeController != null) ...[
          LanguageSwitcher(controller: localeController!),
          const SizedBox(width: 8),
        ],
        LogoutButton(authStore: authStore),
      ],
    );

    final content = Container(
      color: scheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );

    if (useRail) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              extended: railExtended,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: CircleAvatar(
                  backgroundColor: scheme.primary,
                  child: const Icon(Icons.person, color: Colors.white),
                ),
              ),
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
              onDestinationSelected: onSelect,
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
        child: SafeArea(
          child: Column(
            children: [
              UserAccountsDrawerHeader(
                currentAccountPicture: CircleAvatar(
                  backgroundColor: scheme.primary,
                  child: const Icon(Icons.person, color: Colors.white),
                ),
                accountName: const Text(''),
                accountEmail: const Text(''),
              ),
              for (int i = 0; i < destinations.length; i++)
                ListTile(
                  leading: Icon(destinations[i].selectedIcon),
                  title: Text(destinations[i].label),
                  selected: i == selectedIndex,
                  onTap: () {
                    Navigator.of(context).pop();
                    onSelect(i);
                  },
                ),
              const Spacer(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('خروج'),
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


