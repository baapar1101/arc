import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth_store.dart';
import '../../core/locale_controller.dart';
import '../../core/calendar_controller.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/combined_user_menu_button.dart';
import '../../widgets/person/person_form_dialog.dart';
import '../../services/business_dashboard_service.dart';
import '../../core/api_client.dart';
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
  bool _isProductsAndServicesExpanded = false;
  bool _isBankingExpanded = false;
  bool _isAccountingMenuExpanded = false;
  bool _isWarehouseManagementExpanded = false;
  final BusinessDashboardService _businessService = BusinessDashboardService(ApiClient());

  @override
  void initState() {
    super.initState();
    // اضافه کردن listener برای AuthStore
    widget.authStore.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    
    // بارگذاری اطلاعات کسب و کار و دسترسی‌ها
    _loadBusinessInfo();
  }

  Future<void> _loadBusinessInfo() async {
    if (widget.authStore.currentBusiness?.id == widget.businessId) {
      return; // اطلاعات قبلاً بارگذاری شده
    }

    try {
      final businessData = await _businessService.getBusinessWithPermissions(widget.businessId);
      await widget.authStore.setCurrentBusiness(businessData);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در بارگذاری اطلاعات کسب و کار: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
    final allMenuItems = <_MenuItem>[
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
        path: '/business/${widget.businessId}/persons',
        type: _MenuItemType.simple,
        hasAddButton: true,
      ),
      _MenuItem(
        label: t.productsAndServices,
        icon: Icons.inventory_2,
        selectedIcon: Icons.inventory_2,
        path: null, // برای منوی بازشونده
        type: _MenuItemType.expandable,
        children: [
          _MenuItem(
            label: t.products,
            icon: Icons.shopping_cart,
            selectedIcon: Icons.shopping_cart,
            path: '/business/${widget.businessId}/products',
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            label: t.priceLists,
            icon: Icons.list_alt,
            selectedIcon: Icons.list_alt,
            path: '/business/${widget.businessId}/price-lists',
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            label: t.categories,
            icon: Icons.category,
            selectedIcon: Icons.category,
            path: '/business/${widget.businessId}/categories',
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            label: t.productAttributes,
            icon: Icons.tune,
            selectedIcon: Icons.tune,
            path: '/business/${widget.businessId}/product-attributes',
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
        ],
      ),
      _MenuItem(
        label: t.banking,
        icon: Icons.account_balance,
        selectedIcon: Icons.account_balance,
        path: null, // برای منوی بازشونده
        type: _MenuItemType.expandable,
        children: [
          _MenuItem(
            label: t.accounts,
            icon: Icons.account_balance_wallet,
            selectedIcon: Icons.account_balance_wallet,
            path: '/business/${widget.businessId}/accounts',
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            label: t.pettyCash,
            icon: Icons.money,
            selectedIcon: Icons.money,
            path: '/business/${widget.businessId}/petty-cash',
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            label: t.cashBox,
            icon: Icons.savings,
            selectedIcon: Icons.savings,
            path: '/business/${widget.businessId}/cash-box',
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            label: t.wallet,
            icon: Icons.wallet,
            selectedIcon: Icons.wallet,
            path: '/business/${widget.businessId}/wallet',
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            label: t.checks,
            icon: Icons.receipt_long,
            selectedIcon: Icons.receipt_long,
            path: '/business/${widget.businessId}/checks',
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
        ],
      ),
      _MenuItem(
        label: t.accounting,
        icon: Icons.calculate,
        selectedIcon: Icons.calculate,
        path: null, // آیتم جداکننده
        type: _MenuItemType.separator,
      ),
      _MenuItem(
        label: t.invoice,
        icon: Icons.receipt,
        selectedIcon: Icons.receipt,
        path: '/business/${widget.businessId}/invoice',
        type: _MenuItemType.simple,
        hasAddButton: true,
      ),
      _MenuItem(
        label: t.receiptsAndPayments,
        icon: Icons.account_balance_wallet,
        selectedIcon: Icons.account_balance_wallet,
        path: '/business/${widget.businessId}/receipts-payments',
        type: _MenuItemType.simple,
        hasAddButton: true,
      ), 
      _MenuItem(
        label: t.expenseAndIncome,
        icon: Icons.account_balance_wallet,
        selectedIcon: Icons.account_balance_wallet,
        path: '/business/${widget.businessId}/expense-income',
        type: _MenuItemType.simple,
        hasAddButton: true,
      ),
      _MenuItem(
        label: t.transfers,
        icon: Icons.swap_horiz,
        selectedIcon: Icons.swap_horiz,
        path: '/business/${widget.businessId}/transfers',
        type: _MenuItemType.simple,
        hasAddButton: true,
      ),
      _MenuItem(
        label: t.documents,
        icon: Icons.description,
        selectedIcon: Icons.description,
        path: '/business/${widget.businessId}/documents',
        type: _MenuItemType.simple,
        hasAddButton: true,
      ),
      _MenuItem(
        label: t.accountingMenu,
        icon: Icons.calculate,
        selectedIcon: Icons.calculate,
        path: null, // برای منوی بازشونده
        type: _MenuItemType.expandable,
        children: [
          _MenuItem(
            label: t.chartOfAccounts,
            icon: Icons.table_chart,
            selectedIcon: Icons.table_chart,
            path: '/business/${widget.businessId}/chart-of-accounts',
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            label: t.openingBalance,
            icon: Icons.play_arrow,
            selectedIcon: Icons.play_arrow,
            path: '/business/${widget.businessId}/opening-balance',
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            label: t.yearEndClosing,
            icon: Icons.stop,
            selectedIcon: Icons.stop,
            path: '/business/${widget.businessId}/year-end-closing',
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            label: t.accountingSettings,
            icon: Icons.settings,
            selectedIcon: Icons.settings,
            path: '/business/${widget.businessId}/accounting-settings',
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
        ],
      ),
      _MenuItem(
        label: t.reports,
        icon: Icons.assessment,
        selectedIcon: Icons.assessment,
        path: '/business/${widget.businessId}/reports',
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        label: t.servicesAndPlugins,
        icon: Icons.extension,
        selectedIcon: Icons.extension,
        path: null, // آیتم جداکننده
        type: _MenuItemType.separator,
      ),
      _MenuItem(
        label: t.warehouseManagement,
        icon: Icons.warehouse,
        selectedIcon: Icons.warehouse,
        path: null, // برای منوی بازشونده
        type: _MenuItemType.expandable,
        children: [
          _MenuItem(
            label: t.warehouses,
            icon: Icons.store,
            selectedIcon: Icons.store,
            path: '/business/${widget.businessId}/warehouses',
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            label: t.shipments,
            icon: Icons.local_shipping,
            selectedIcon: Icons.local_shipping,
            path: '/business/${widget.businessId}/shipments',
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
        ],
      ),
      _MenuItem(
        label: t.inquiries,
        icon: Icons.search,
        selectedIcon: Icons.search,
        path: '/business/${widget.businessId}/inquiries',
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        label: t.storageSpace,
        icon: Icons.storage,
        selectedIcon: Icons.storage,
        path: '/business/${widget.businessId}/storage-space',
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        label: t.taxpayers,
        icon: Icons.account_balance,
        selectedIcon: Icons.account_balance,
        path: '/business/${widget.businessId}/taxpayers',
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        label: t.others,
        icon: Icons.more_horiz,
        selectedIcon: Icons.more_horiz,
        path: null, // آیتم جداکننده
        type: _MenuItemType.separator,
      ),
      _MenuItem(
        label: t.settings,
        icon: Icons.settings,
        selectedIcon: Icons.settings,
        path: '/business/${widget.businessId}/settings',
        type: _MenuItemType.simple,
      ),
      _MenuItem(
        label: t.pluginMarketplace,
        icon: Icons.store,
        selectedIcon: Icons.store,
        path: '/business/${widget.businessId}/plugin-marketplace',
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
    ];

    // فیلتر کردن منو بر اساس دسترسی‌ها
    final menuItems = _getFilteredMenuItems(allMenuItems);

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
            if (i == 2) _isProductsAndServicesExpanded = true; // کالا و خدمات در ایندکس 2
            if (i == 3) _isBankingExpanded = true; // بانکداری در ایندکس 3
            if (i == 5) _isAccountingMenuExpanded = true; // حسابداری در ایندکس 5
            if (i == 7) _isWarehouseManagementExpanded = true; // انبارداری در ایندکس 7
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
        if (item.label == t.productsAndServices) _isProductsAndServicesExpanded = !_isProductsAndServicesExpanded;
        if (item.label == t.banking) _isBankingExpanded = !_isBankingExpanded;
        if (item.label == t.accountingMenu) _isAccountingMenuExpanded = !_isAccountingMenuExpanded;
        if (item.label == t.warehouseManagement) _isWarehouseManagementExpanded = !_isWarehouseManagementExpanded;
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

    Future<void> _showAddPersonDialog() async {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => PersonFormDialog(
          businessId: widget.businessId,
        ),
      );
      if (result == true) {
        // Refresh the persons page if it's currently open
        // This will be handled by the PersonsPage itself
      }
    }

    bool isExpanded(_MenuItem item) {
      if (item.label == t.productsAndServices) return _isProductsAndServicesExpanded;
      if (item.label == t.banking) return _isBankingExpanded;
      if (item.label == t.accountingMenu) return _isAccountingMenuExpanded;
      if (item.label == t.warehouseManagement) return _isWarehouseManagementExpanded;
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
        CombinedUserMenuButton(
          authStore: widget.authStore,
          localeController: widget.localeController,
          calendarController: widget.calendarController,
          themeController: widget.themeController,
        ),
        const SizedBox(width: 4),
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
                  // محاسبه ایندکس منو و تشخیص نوع آیتم
                  int menuIndex = 0;
                  int childIndex = -1;
                  bool isChildItem = false;
                  
                  int currentIndex = 0;
                  for (int i = 0; i < menuItems.length; i++) {
                    final item = menuItems[i];
                    
                    if (currentIndex == index) {
                      menuIndex = i;
                      break;
                    }
                    currentIndex++;
                    
                    if (item.type == _MenuItemType.expandable && isExpanded(item) && railExtended) {
                      final childrenCount = item.children?.length ?? 0;
                      if (index >= currentIndex && index < currentIndex + childrenCount) {
                        menuIndex = i;
                        childIndex = index - currentIndex;
                        isChildItem = true;
                        break;
                      }
                      currentIndex += childrenCount;
                    }
                  }
                  
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
                  
                  if (isChildItem && item.children != null && childIndex >= 0 && childIndex < item.children!.length) {
                    // زیرآیتم
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
                                  GestureDetector(
                                    onTap: () {
                                      // Navigate to add new item
                                      if (child.label == t.personsList) {
                                        // Navigate to add person
                                        _showAddPersonDialog();
                                      } else if (child.label == t.products) {
                                        // Navigate to add product
                                      } else if (child.label == t.priceLists) {
                                        // Navigate to add price list
                                      } else if (child.label == t.categories) {
                                        // Navigate to add category
                                      } else if (child.label == t.productAttributes) {
                                        // Navigate to add product attribute
                                      } else if (child.label == t.accounts) {
                                        // Navigate to add account
                                      } else if (child.label == t.pettyCash) {
                                        // Navigate to add petty cash
                                      } else if (child.label == t.cashBox) {
                                        // Navigate to add cash box
                                      } else if (child.label == t.wallet) {
                                        // Navigate to add wallet
                                      } else if (child.label == t.checks) {
                                        // Navigate to add check
                                      } else if (child.label == t.invoice) {
                                        // Navigate to add invoice
                                      } else if (child.label == t.expenseAndIncome) {
                                        // Navigate to add expense/income
                                      } else if (child.label == t.warehouses) {
                                        // Navigate to add warehouse
                                      } else if (child.label == t.shipments) {
                                        // Navigate to add shipment
                                      }
                                    },
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: sideFg.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Icon(
                                        Icons.add,
                                        size: 14,
                                        color: sideFg,
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  } else {
                    // آیتم اصلی (ساده، بازشونده، یا جداکننده)
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
                      // آیتم ساده یا آیتم بازشونده
                      return MouseRegion(
                        onEnter: (_) => setState(() => _hoverIndex = index),
                        onExit: (_) => setState(() => _hoverIndex = -1),
                        child: InkWell(
                          borderRadius: br,
                          onTap: () {
                            if (item.type == _MenuItemType.expandable) {
                              setState(() {
                                if (item.label == t.productsAndServices) _isProductsAndServicesExpanded = !_isProductsAndServicesExpanded;
                                if (item.label == t.banking) _isBankingExpanded = !_isBankingExpanded;
                                if (item.label == t.accountingMenu) _isAccountingMenuExpanded = !_isAccountingMenuExpanded;
                                if (item.label == t.warehouseManagement) _isWarehouseManagementExpanded = !_isWarehouseManagementExpanded;
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
                                    )
                                  else if (item.hasAddButton)
                                    GestureDetector(
                                      onTap: () {
                                        // Navigate to add new item
                                        if (item.label == t.people) {
                                          // Navigate to add person
                                          _showAddPersonDialog();
                                        } else if (item.label == t.invoice) {
                                          // Navigate to add invoice
                                        } else if (item.label == t.receiptsAndPayments) {
                                          // Navigate to add receipt/payment
                                        } else if (item.label == t.transfers) {
                                          // Navigate to add transfer
                                        } else if (item.label == t.documents) {
                                          // Navigate to add document
                                        } else if (item.label == t.expenseAndIncome) {
                                          // Navigate to add expense/income
                                        } else if (item.label == t.reports) {
                                          // Navigate to add report
                                        } else if (item.label == t.inquiries) {
                                          // Navigate to add inquiry
                                        } else if (item.label == t.storageSpace) {
                                          // Navigate to add storage space
                                        } else if (item.label == t.taxpayers) {
                                          // Navigate to add taxpayer
                                        } else if (item.label == t.pluginMarketplace) {
                                          // Navigate to add plugin
                                        }
                                      },
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: sideFg.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Icon(
                                          Icons.add,
                                          size: 16,
                                          color: sideFg,
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                  }
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
                          if (item.label == t.productsAndServices) _isProductsAndServicesExpanded = expanded;
                          if (item.label == t.banking) _isBankingExpanded = expanded;
                          if (item.label == t.accountingMenu) _isAccountingMenuExpanded = expanded;
                          if (item.label == t.warehouseManagement) _isWarehouseManagementExpanded = expanded;
                        });
                      },
                      children: item.children?.map((child) => ListTile(
                        leading: const SizedBox(width: 24),
                        title: Text(child.label),
                        trailing: child.hasAddButton ? GestureDetector(
                          onTap: () {
                            context.pop();
                            // Navigate to add new item
                            if (child.label == t.products) {
                              // Navigate to add product
                            } else if (child.label == t.priceLists) {
                              // Navigate to add price list
                            } else if (child.label == t.categories) {
                              // Navigate to add category
                            } else if (child.label == t.productAttributes) {
                              // Navigate to add product attribute
                            } else if (child.label == t.accounts) {
                              // Navigate to add account
                            } else if (child.label == t.pettyCash) {
                              // Navigate to add petty cash
                            } else if (child.label == t.cashBox) {
                              // Navigate to add cash box
                            } else if (child.label == t.wallet) {
                              // Navigate to add wallet
                            } else if (child.label == t.checks) {
                              // Navigate to add check
                            } else if (child.label == t.invoice) {
                              // Navigate to add invoice
                            } else if (child.label == t.expenseAndIncome) {
                              // Navigate to add expense/income
                            } else if (child.label == t.warehouses) {
                              // Navigate to add warehouse
                            } else if (child.label == t.shipments) {
                              // Navigate to add shipment
                            }
                          },
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: sideFg.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              Icons.add,
                              size: 16,
                              color: sideFg,
                            ),
                          ),
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

  // فیلتر کردن منو بر اساس دسترسی‌ها
  List<_MenuItem> _getFilteredMenuItems(List<_MenuItem> allItems) {
    return allItems.where((item) {
      if (item.type == _MenuItemType.separator) return true;
      
      if (item.type == _MenuItemType.simple) {
        return _hasAccessToMenuItem(item);
      }
      
      if (item.type == _MenuItemType.expandable) {
        return _hasAccessToExpandableMenuItem(item);
      }
      
      return false;
    }).toList();
  }

  bool _hasAccessToMenuItem(_MenuItem item) {
    final sectionMap = {
      'people': 'people',
      'products': 'products',
      'priceLists': 'price_lists',
      'categories': 'categories',
      'productAttributes': 'product_attributes',
      'accounts': 'bank_accounts',
      'pettyCash': 'petty_cash',
      'cashBox': 'cash',
      'wallet': 'wallet',
      'checks': 'checks',
      'invoice': 'invoices',
      'receiptsAndPayments': 'accounting_documents',
      'expenseAndIncome': 'expenses_income',
      'transfers': 'transfers',
      'documents': 'accounting_documents',
      'chartOfAccounts': 'chart_of_accounts',
      'openingBalance': 'opening_balance',
      'yearEndClosing': 'opening_balance',
      'accountingSettings': 'settings',
      'reports': 'reports',
      'warehouses': 'warehouses',
      'shipments': 'warehouse_transfers',
      'inquiries': 'reports',
      'storageSpace': 'storage',
      'taxpayers': 'settings',
      'settings': 'settings',
      'pluginMarketplace': 'marketplace',
    };
    
    final section = sectionMap[item.label];
    if (section == null) return true; // اگر بخشی تعریف نشده، نمایش داده شود
    
    return widget.authStore.canReadSection(section);
  }

  bool _hasAccessToExpandableMenuItem(_MenuItem item) {
    if (item.children == null) return false;
    
    // اگر حداقل یکی از زیرآیتم‌ها قابل دسترسی باشد، منو نمایش داده شود
    return item.children!.any((child) => _hasAccessToMenuItem(child));
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