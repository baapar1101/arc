import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth_store.dart';
import '../../core/locale_controller.dart';
import '../../core/calendar_controller.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/settings_menu_button.dart';
import '../../widgets/user_account_menu_button.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class BusinessShell extends StatefulWidget {
  final int businessId;
  final Widget child;
  final AuthStore authStore;
  final LocaleController? localeController;
  final CalendarController? calendarController;
  final ThemeController? themeController;

  const BusinessShell({
    super.key,
    required this.businessId,
    required this.child,
    required this.authStore,
    this.localeController,
    this.calendarController,
    this.themeController,
  });

  @override
  State<BusinessShell> createState() => _BusinessShellState();
}

class _BusinessShellState extends State<BusinessShell> {
  int _hoverIndex = -1;
  bool _isBasicToolsExpanded = false;
  bool _isPeopleExpanded = false;

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
    String location = '/business/${widget.businessId}/dashboard'; // default location
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
    
    // ساختار متمرکز منو
    final menuItems = <_MenuItem>[
      _MenuItem(
        label: t.businessDashboard,
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        path: '/business/${widget.businessId}/dashboard',
        type: _MenuItemType.simple,
      ),
      _MenuItem(
        label: t.practicalTools,
        icon: Icons.category,
        selectedIcon: Icons.category,
        path: null, // آیتم جداکننده
        type: _MenuItemType.separator,
      ),
      _MenuItem(
        label: t.people,
        icon: Icons.people,
        selectedIcon: Icons.people,
        path: null, // برای منوی بازشونده
        type: _MenuItemType.expandable,
        children: [
          _MenuItem(
            label: t.peopleList,
            icon: Icons.list,
            selectedIcon: Icons.list,
            path: '/business/${widget.businessId}/people-list',
            type: _MenuItemType.simple,
          ),
          _MenuItem(
            label: t.receipts,
            icon: Icons.receipt,
            selectedIcon: Icons.receipt,
            path: '/business/${widget.businessId}/receipts',
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            label: t.payments,
            icon: Icons.payment,
            selectedIcon: Icons.payment,
            path: '/business/${widget.businessId}/payments',
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
        ],
      ),
      _MenuItem(
        label: t.settings,
        icon: Icons.settings,
        selectedIcon: Icons.settings,
        path: null, // برای منوی بازشونده
        type: _MenuItemType.expandable,
        children: [
          _MenuItem(
            label: t.businessSettings,
            icon: Icons.business,
            selectedIcon: Icons.business,
            path: '/business/${widget.businessId}/business-settings',
            type: _MenuItemType.simple,
          ),
          _MenuItem(
            label: t.printDocuments,
            icon: Icons.print,
            selectedIcon: Icons.print,
            path: '/business/${widget.businessId}/print-documents',
            type: _MenuItemType.simple,
          ),
          _MenuItem(
            label: t.usersAndPermissions,
            icon: Icons.people_outline,
            selectedIcon: Icons.people,
            path: '/business/${widget.businessId}/users-permissions',
            type: _MenuItemType.simple,
          ),
        ],
      ),
    ];

    int selectedIndex = 0;
    for (int i = 0; i < menuItems.length; i++) {
      final item = menuItems[i];
      if (item.type == _MenuItemType.separator) continue; // نادیده گرفتن آیتم جداکننده
      
      if (item.type == _MenuItemType.simple && item.path != null && location.startsWith(item.path!)) {
        selectedIndex = i;
        break;
      } else if (item.type == _MenuItemType.expandable && item.children != null) {
        for (int j = 0; j < item.children!.length; j++) {
          final child = item.children![j];
          if (child.path != null && location.startsWith(child.path!)) {
            selectedIndex = i;
            // تنظیم وضعیت باز بودن منو
            if (i == 2) _isPeopleExpanded = true; // اشخاص در ایندکس 2
            if (i == 3) _isBasicToolsExpanded = true; // تنظیمات در ایندکس 3
            break;
          }
        }
      }
    }

    Future<void> onSelect(int index) async {
      final item = menuItems[index];
      if (item.type == _MenuItemType.separator) return; // آیتم جداکننده قابل کلیک نیست
      
      if (item.type == _MenuItemType.simple && item.path != null) {
        try {
          if (GoRouterState.of(context).uri.toString() != item.path!) {
            context.go(item.path!);
          }
        } catch (e) {
          // اگر GoRouterState در دسترس نیست، مستقیماً به مسیر برود
          context.go(item.path!);
        }
      } else if (item.type == _MenuItemType.expandable) {
        // تغییر وضعیت باز/بسته بودن منو
        if (item.label == t.people) _isPeopleExpanded = !_isPeopleExpanded;
        if (item.label == t.settings) _isBasicToolsExpanded = !_isBasicToolsExpanded;
        setState(() {});
      }
    }

    Future<void> onSelectChild(int parentIndex, int childIndex) async {
      final parent = menuItems[parentIndex];
      if (parent.type == _MenuItemType.expandable && parent.children != null) {
        final child = parent.children![childIndex];
        if (child.path != null) {
          try {
            if (GoRouterState.of(context).uri.toString() != child.path!) {
              context.go(child.path!);
            }
          } catch (e) {
            // اگر GoRouterState در دسترس نیست، مستقیماً به مسیر برود
            context.go(child.path!);
          }
        }
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

    bool isExpanded(_MenuItem item) {
      if (item.label == t.people) return _isPeopleExpanded;
      if (item.label == t.settings) return _isBasicToolsExpanded;
      return false;
    }

    int getTotalMenuItemsCount() {
      int count = 0;
      for (final item in menuItems) {
        if (item.type == _MenuItemType.separator) {
          count++; // آیتم جداکننده هم شمرده می‌شود
        } else {
          count++; // آیتم اصلی
          if (item.type == _MenuItemType.expandable && isExpanded(item) && railExtended) {
            count += item.children?.length ?? 0;
          }
        }
      }
      return count;
    }

    int getMenuIndexFromTotalIndex(int totalIndex) {
      int currentIndex = 0;
      for (int i = 0; i < menuItems.length; i++) {
        if (currentIndex == totalIndex) return i;
        currentIndex++;
        
        final item = menuItems[i];
        if (item.type == _MenuItemType.expandable && isExpanded(item) && railExtended) {
          final childrenCount = item.children?.length ?? 0;
          if (totalIndex >= currentIndex && totalIndex < currentIndex + childrenCount) {
            return i;
          }
          currentIndex += childrenCount;
        }
      }
      return 0;
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
      automaticallyImplyLeading: !useRail,
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
        SettingsMenuButton(
          localeController: widget.localeController,
          calendarController: widget.calendarController,
          themeController: widget.themeController,
        ),
        const SizedBox(width: 8),
        UserAccountMenuButton(authStore: widget.authStore),
        const SizedBox(width: 8),
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
                itemCount: getTotalMenuItemsCount(),
                itemBuilder: (ctx, index) {
                  final menuIndex = getMenuIndexFromTotalIndex(index);
                  final item = menuItems[menuIndex];
                  final bool isHovered = index == _hoverIndex;
                  final bool isSelected = menuIndex == selectedIndex;
                  final bool active = isSelected || isHovered;
                  final BorderRadius br = (isSelected && useRail)
                      ? BorderRadius.zero
                      : (isHovered ? BorderRadius.zero : BorderRadius.circular(8));
                  final Color bgColor = active
                      ? (isHovered && !isSelected ? activeBg.withValues(alpha: 0.85) : activeBg)
                      : Colors.transparent;
                  
                  // اگر آیتم بازشونده است و در حالت باز است، زیرآیتم‌ها را نمایش بده
                  if (item.type == _MenuItemType.expandable && isExpanded(item) && railExtended) {
                    if (index == getMenuIndexFromTotalIndex(index)) {
                      // آیتم اصلی
                      return MouseRegion(
                        onEnter: (_) => setState(() => _hoverIndex = index),
                        onExit: (_) => setState(() => _hoverIndex = -1),
                        child: InkWell(
                          borderRadius: br,
                          onTap: () {
                            setState(() {
                              if (item.label == t.people) _isPeopleExpanded = !_isPeopleExpanded;
                              if (item.label == t.settings) _isBasicToolsExpanded = !_isBasicToolsExpanded;
                            });
                          },
                          child: Container(
                            margin: EdgeInsets.zero,
                            padding: EdgeInsets.symmetric(
                              horizontal: railExtended ? 16 : 8,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: br,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  active ? item.selectedIcon : item.icon,
                                  color: active ? activeFg : sideFg,
                                  size: 24,
                                ),
                                if (railExtended) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      item.label,
                                      style: TextStyle(
                                        color: active ? activeFg : sideFg,
                                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    isExpanded(item) ? Icons.expand_less : Icons.expand_more,
                                    color: sideFg,
                                    size: 20,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    } else {
                      // زیرآیتم‌ها
                      final childIndex = index - getMenuIndexFromTotalIndex(index) - 1;
                      if (childIndex < (item.children?.length ?? 0)) {
                        final child = item.children![childIndex];
                        return MouseRegion(
                          onEnter: (_) => setState(() => _hoverIndex = index),
                          onExit: (_) => setState(() => _hoverIndex = -1),
                          child: InkWell(
                            borderRadius: br,
                            onTap: () => onSelectChild(menuIndex, childIndex),
                            child: Container(
                              margin: EdgeInsets.zero,
                              padding: EdgeInsets.symmetric(
                                horizontal: railExtended ? 24 : 16, // بیشتر indent برای زیرآیتم
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: br,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    child.icon,
                                    color: sideFg,
                                    size: 20,
                                  ),
                                  if (railExtended) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        child.label,
                                        style: TextStyle(
                                          color: sideFg,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                    if (child.hasAddButton)
                                      IconButton(
                                        icon: const Icon(Icons.add, size: 16),
                                        onPressed: () {
                                          // Navigate to add new receipt/payment
                                          if (child.label == t.receipts) {
                                            // Navigate to add receipt
                                          } else if (child.label == t.payments) {
                                            // Navigate to add payment
                                          }
                                        },
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                    }
                  } else {
                    // آیتم ساده، آیتم بازشونده در حالت بسته، یا آیتم جداکننده
                    if (item.type == _MenuItemType.separator) {
                      // آیتم جداکننده
                      return Container(
                        margin: EdgeInsets.symmetric(
                          horizontal: railExtended ? 16 : 8,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            if (railExtended) ...[
                              Expanded(
                                child: Divider(
                                  color: sideFg.withValues(alpha: 0.3),
                                  thickness: 1,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                item.label,
                                style: TextStyle(
                                  color: sideFg.withValues(alpha: 0.7),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Divider(
                                  color: sideFg.withValues(alpha: 0.3),
                                  thickness: 1,
                                ),
                              ),
                            ] else ...[
                              Expanded(
                                child: Divider(
                                  color: sideFg.withValues(alpha: 0.3),
                                  thickness: 1,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    } else {
                      // آیتم ساده یا آیتم بازشونده در حالت بسته
                      return MouseRegion(
                        onEnter: (_) => setState(() => _hoverIndex = index),
                        onExit: (_) => setState(() => _hoverIndex = -1),
                        child: InkWell(
                          borderRadius: br,
                          onTap: () {
                            if (item.type == _MenuItemType.expandable) {
                              setState(() {
                                if (item.label == t.people) _isPeopleExpanded = !_isPeopleExpanded;
                                if (item.label == t.settings) _isBasicToolsExpanded = !_isBasicToolsExpanded;
                              });
                            } else {
                              onSelect(menuIndex);
                            }
                          },
                          child: Container(
                            margin: EdgeInsets.zero,
                            padding: EdgeInsets.symmetric(
                              horizontal: railExtended ? 16 : 8,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: br,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  active ? item.selectedIcon : item.icon,
                                  color: active ? activeFg : sideFg,
                                  size: 24,
                                ),
                                if (railExtended) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      item.label,
                                      style: TextStyle(
                                        color: active ? activeFg : sideFg,
                                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                  if (item.type == _MenuItemType.expandable)
                                    Icon(
                                      isExpanded(item) ? Icons.expand_less : Icons.expand_more,
                                      color: sideFg,
                                      size: 20,
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            const VerticalDivider(thickness: 1, width: 1),
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
              // آیتم‌های منو
              for (int i = 0; i < menuItems.length; i++) ...[
                Builder(builder: (ctx) {
                  final item = menuItems[i];
                  final bool active = i == selectedIndex;
                  
                  if (item.type == _MenuItemType.separator) {
                    // آیتم جداکننده در منوی موبایل
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: sideFg.withValues(alpha: 0.3),
                              thickness: 1,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            item.label,
                            style: TextStyle(
                              color: sideFg.withValues(alpha: 0.7),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Divider(
                              color: sideFg.withValues(alpha: 0.3),
                              thickness: 1,
                            ),
                          ),
                        ],
                      ),
                    );
                  } else if (item.type == _MenuItemType.simple) {
                    return ListTile(
                      leading: Icon(item.selectedIcon, color: active ? activeFg : sideFg),
                      title: Text(item.label, style: TextStyle(color: active ? activeFg : sideFg, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
                      selected: active,
                      selectedTileColor: activeBg,
                      onTap: () {
                        context.pop();
                        onSelect(i);
                      },
                    );
                  } else if (item.type == _MenuItemType.expandable) {
                    return ExpansionTile(
                      leading: Icon(item.icon, color: sideFg),
                      title: Text(item.label, style: TextStyle(color: sideFg)),
                      initiallyExpanded: isExpanded(item),
                      onExpansionChanged: (expanded) {
                        setState(() {
                          if (item.label == t.people) _isPeopleExpanded = expanded;
                          if (item.label == t.settings) _isBasicToolsExpanded = expanded;
                        });
                      },
                      children: item.children?.map((child) => ListTile(
                        leading: const SizedBox(width: 24),
                        title: Text(child.label),
                        trailing: child.hasAddButton ? IconButton(
                          icon: const Icon(Icons.add, size: 20),
                          onPressed: () {
                            context.pop();
                            // Navigate to add new receipt/payment
                            if (child.label == t.receipts) {
                              // Navigate to add receipt
                            } else if (child.label == t.payments) {
                              // Navigate to add payment
                            }
                          },
                        ) : null,
                        onTap: () {
                          context.pop();
                          onSelectChild(i, item.children!.indexOf(child));
                        },
                      )).toList() ?? [],
                    );
                  }
                  return const SizedBox.shrink();
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

enum _MenuItemType { simple, expandable, separator }

class _MenuItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String? path;
  final _MenuItemType type;
  final List<_MenuItem>? children;
  final bool hasAddButton;
  
  const _MenuItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.path,
    required this.type,
    this.children,
    this.hasAddButton = false,
  });
}