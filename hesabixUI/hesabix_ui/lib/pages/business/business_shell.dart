import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';

class BusinessShell extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;
  final Widget child;

  const BusinessShell({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
    required this.child,
  });

  @override
  State<BusinessShell> createState() => _BusinessShellState();
}

class _BusinessShellState extends State<BusinessShell> {

  @override
  void initState() {
    super.initState();
    // اضافه کردن listener برای AuthStore
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
    final String location = GoRouterState.of(context).uri.toString();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String logoAsset = isDark
        ? 'assets/images/logo-light.png'
        : 'assets/images/logo-light.png';

    final t = AppLocalizations.of(context);
    final destinations = <_Dest>[
      _Dest(t.businessDashboard, Icons.dashboard_outlined, Icons.dashboard, '/business/${widget.businessId}/dashboard'),
      _Dest(t.sales, Icons.sell, Icons.sell, '/business/${widget.businessId}/sales'),
      _Dest(t.accounting, Icons.account_balance, Icons.account_balance, '/business/${widget.businessId}/accounting'),
      _Dest(t.inventory, Icons.inventory, Icons.inventory, '/business/${widget.businessId}/inventory'),
      _Dest(t.reports, Icons.assessment, Icons.assessment, '/business/${widget.businessId}/reports'),
      _Dest(t.members, Icons.people, Icons.people, '/business/${widget.businessId}/members'),
      _Dest(t.settings, Icons.settings, Icons.settings, '/business/${widget.businessId}/settings'),
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

    Future<void> onBackToProfile() async {
      context.go('/user/profile/businesses');
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
      elevation: 0,
      title: Row(
        children: [
          Image.asset(
            logoAsset,
            height: 32,
            width: 32,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.business,
              color: appBarFg,
              size: 32,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Hesabix',
            style: TextStyle(
              color: appBarFg,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.arrow_back, color: appBarFg),
          onPressed: onBackToProfile,
          tooltip: t.backToProfile,
        ),
        const SizedBox(width: 8),
      ],
    );

    if (useRail) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelect,
              labelType: railExtended ? NavigationRailLabelType.selected : NavigationRailLabelType.all,
              extended: railExtended,
              destinations: destinations.map((dest) => NavigationRailDestination(
                icon: Icon(dest.icon),
                selectedIcon: Icon(dest.selectedIcon),
                label: Text(dest.label),
              )).toList(),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child: widget.child,
            ),
          ],
        ),
      );
    } else {
      return Scaffold(
        appBar: appBar,
        body: widget.child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelect,
          destinations: destinations.map((dest) => NavigationDestination(
            icon: Icon(dest.icon),
            selectedIcon: Icon(dest.selectedIcon),
            label: dest.label,
          )).toList(),
        ),
      );
    }
  }
}

class _Dest {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;

  const _Dest(this.label, this.icon, this.selectedIcon, this.path);
}
