import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:go_router/go_router.dart';
import '../../core/auth_store.dart';
import '../../core/locale_controller.dart';
import '../../core/calendar_controller.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/combined_user_menu_button.dart';
import '../../widgets/person/person_form_dialog.dart';
import '../../widgets/banking/bank_account_form_dialog.dart';
import '../../widgets/banking/cash_register_form_dialog.dart';
import '../../widgets/banking/petty_cash_form_dialog.dart';
import '../../widgets/product/product_form_dialog.dart';
import '../../widgets/category/category_tree_dialog.dart';
import '../../services/business_dashboard_service.dart';
import '../../core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'receipts_payments_list_page.dart' show BulkSettlementDialog;
import '../../widgets/document/document_form_dialog.dart';
import '../../widgets/wallet/wallet_top_up_dialog.dart';
import '../../services/announcements_service.dart';
import '../../services/notifications_ws_client.dart';
import '../../widgets/transfer/transfer_form_dialog.dart';
import '../../widgets/expense_income/expense_income_form_dialog.dart';
import '../../widgets/warehouse/warehouse_form_dialog.dart';
import '../../widgets/warehouse/warehouse_doc_wizard_dialog.dart';
import '../../widgets/ai/ai_chat_dialog.dart';
import 'check_form_page.dart';
import '../../utils/snackbar_helper.dart';

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
  bool _isAIExpanded = false;
  final BusinessDashboardService _businessService = BusinessDashboardService(ApiClient());
  final List<Map<String, dynamic>> _notifications = <Map<String, dynamic>>[];
  int _unreadCount = 0;
  final Set<int> _busyAnnIds = <int>{};
  NotificationsWsClient? _ws;

  @override
  void initState() {
    super.initState();
    // اطمینان از bind بودن AuthStore برای ApiClient (جهت هدرها و تنظیمات)
    try {
      ApiClient.bindAuthStore(widget.authStore);
    } catch (_) {}
    // اضافه کردن listener برای AuthStore
    widget.authStore.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    
    // بارگذاری اطلاعات کسب و کار و دسترسی‌ها
    _loadBusinessInfo();
    _initNotifications();
  }

  @override
  void dispose() {
    try {
      _ws?.disconnect();
    } catch (_) {}
    super.dispose();
  }

    Future<void> showAddReceiptPaymentDialog() async {
      if (!context.mounted) return;
      final ctx = context;
      final calendarController = widget.calendarController ?? await CalendarController.load();
      if (!ctx.mounted) return;
      final result = await showDialog<bool>(
        context: ctx,
        builder: (context) => BulkSettlementDialog(
          businessId: widget.businessId,
          calendarController: calendarController,
          isReceipt: true, // پیش‌فرض دریافت
          businessInfo: widget.authStore.currentBusiness,
          apiClient: ApiClient(),
        ),
      );
      if (result == true) {
        // Refresh the receipts payments page if it's currently open
        _refreshCurrentPage();
      }
    }

    Future<void> showAddTransferDialog() async {
      if (!context.mounted) return;
      final ctx = context;
      final calendarController = widget.calendarController ?? await CalendarController.load();
      if (!ctx.mounted) return;
      final result = await showDialog<bool>(
        context: ctx,
        builder: (context) => TransferFormDialog(
          businessId: widget.businessId,
          calendarController: calendarController,
          authStore: widget.authStore,
          apiClient: ApiClient(),
        ),
      );
      if (result == true) {
        _refreshCurrentPage();
      }
    }

    Future<void> showAddExpenseIncomeDialog() async {
      if (!context.mounted) return;
      final ctx = context;
      final calendarController = widget.calendarController ?? await CalendarController.load();
      if (!ctx.mounted) return;
      final result = await showDialog<bool>(
        context: ctx,
        builder: (context) => ExpenseIncomeFormDialog(
          businessId: widget.businessId,
          calendarController: calendarController,
          isIncome: false, // پیش‌فرض هزینه؛ قابل تغییر داخل دیالوگ
          businessInfo: widget.authStore.currentBusiness,
          apiClient: ApiClient(),
        ),
      );
      if (result == true) {
        _refreshCurrentPage();
      }
    }

    Future<void> showAddCheckDialog() async {
      if (!context.mounted) return;
      final ctx = context;
      final calendarController = widget.calendarController ?? await CalendarController.load();
      if (!ctx.mounted) return;
      final result = await showDialog<bool>(
        context: ctx,
        builder: (context) => CheckFormDialog(
          businessId: widget.businessId,
          authStore: widget.authStore,
          calendarController: calendarController,
          onSuccess: () {
            _refreshCurrentPage();
          },
        ),
      );
      if (result == true) {
        _refreshCurrentPage();
      }
    }

    void _refreshCurrentPage() {
    // Force a rebuild of the current page
    setState(() {
      // This will cause the current page to rebuild
      // and if it's PettyCashPage, it will refresh its data
    });
  }

    Future<void> showWalletTopUpDialog() async {
      if (!context.mounted) return;
      await WalletTopUpDialog.show(
        context: context,
        businessId: widget.businessId,
        onSuccess: () {
          // در صورت نیاز می‌توانید callback اضافه کنید
        },
        onError: (error) {
          // خطا در ویجت مدیریت می‌شود
        },
      );
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
        label: t.checks,
        icon: Icons.receipt_long,
        selectedIcon: Icons.receipt_long,
        path: '/business/${widget.businessId}/checks',
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
            label: 'حواله‌های انبار',
            icon: Icons.description,
            selectedIcon: Icons.description,
            path: '/business/${widget.businessId}/warehouse-docs',
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
        ],
      ),
      _MenuItem(
        label: t.storageSpace,
        icon: Icons.storage,
        selectedIcon: Icons.storage,
        path: '/business/${widget.businessId}/storage-files',
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        label: t.taxpayers,
        icon: Icons.account_balance,
        selectedIcon: Icons.account_balance,
        path: '/business/${widget.businessId}/tax-workspace',
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        label: 'هوش مصنوعی',
        icon: Icons.smart_toy_outlined,
        selectedIcon: Icons.smart_toy,
        path: null, // برای منوی بازشونده
        type: _MenuItemType.expandable,
        children: [
          _MenuItem(
            label: 'اشتراک AI',
            icon: Icons.subscriptions_outlined,
            selectedIcon: Icons.subscriptions,
            path: '/business/${widget.businessId}/ai/subscription',
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            label: 'آمار استفاده',
            icon: Icons.bar_chart_outlined,
            selectedIcon: Icons.bar_chart,
            path: '/business/${widget.businessId}/ai/usage',
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
        ],
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
        label: t.templates,
        icon: Icons.picture_as_pdf,
        selectedIcon: Icons.picture_as_pdf,
        path: '/business/${widget.businessId}/report-templates',
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
            // تنظیم وضعیت باز بودن منو بر اساس برچسب آیتم
            if (item.label == t.productsAndServices) _isProductsAndServicesExpanded = true;
            if (item.label == t.banking) _isBankingExpanded = true;
            if (item.label == t.accountingMenu) _isAccountingMenuExpanded = true;
            if (item.label == t.warehouseManagement) _isWarehouseManagementExpanded = true;
            if (item.label == 'هوش مصنوعی') _isAIExpanded = true;
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
          if (!context.mounted) return;
          final ctx = context;
          if (GoRouterState.of(ctx).uri.toString() != item.path!) {
            if (item.label == t.categories) {
              // باز کردن دیالوگ دسته‌بندی‌ها به جای ناوبری
              if (widget.authStore.canReadSection('categories')) {
                if (!ctx.mounted) return;
                await showDialog<bool>(
                  context: ctx,
                  builder: (dialogCtx) => CategoryTreeDialog(
                    businessId: widget.businessId,
                    authStore: widget.authStore,
                  ),
                );
              }
            } else {
              ctx.go(item.path!);
            }
          }
        } catch (e) {
          // اگر GoRouterState در دسترس نیست، مستقیماً به مسیر برود
          if (!context.mounted) return;
          final ctx = context;
            if (item.label == t.categories) {
              if (widget.authStore.canReadSection('categories')) {
                if (!ctx.mounted) return;
                await showDialog<bool>(
                  context: ctx,
                  builder: (dialogCtx) => CategoryTreeDialog(
                    businessId: widget.businessId,
                    authStore: widget.authStore,
                  ),
                );
              }
            } else {
              ctx.go(item.path!);
            }
        }
      } else if (item.type == _MenuItemType.expandable) {
        // تغییر وضعیت باز/بسته بودن منو
        setState(() {
          if (item.label == t.productsAndServices) _isProductsAndServicesExpanded = !_isProductsAndServicesExpanded;
          if (item.label == t.banking) _isBankingExpanded = !_isBankingExpanded;
          if (item.label == t.accountingMenu) _isAccountingMenuExpanded = !_isAccountingMenuExpanded;
          if (item.label == t.warehouseManagement) _isWarehouseManagementExpanded = !_isWarehouseManagementExpanded;
          if (item.label == 'هوش مصنوعی') _isAIExpanded = !_isAIExpanded;
        });
      }
    }

    Future<void> onSelectChild(int parentIndex, int childIndex) async {
      final parent = menuItems[parentIndex];
      if (parent.type == _MenuItemType.expandable && parent.children != null) {
        final child = parent.children![childIndex];
        if (child.label == t.categories) {
          if (widget.authStore.canReadSection('categories')) {
            await showDialog<bool>(
              context: context,
              builder: (ctx) => CategoryTreeDialog(
                businessId: widget.businessId,
                authStore: widget.authStore,
              ),
            );
          }
          return;
        }
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

    Future<void> showAddPersonDialog() async {
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

    Future<void> showAddProductDialog() async {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => ProductFormDialog(
          businessId: widget.businessId,
          authStore: widget.authStore,
          onSuccess: () {
            // Refresh the products page if it's currently open
            // This will be handled by the ProductsPage itself
          },
        ),
      );
      if (result == true) {
        // Product was successfully added
      }
    }

    Future<void> showAddCashBoxDialog() async {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => CashRegisterFormDialog(
          businessId: widget.businessId,
          onSuccess: () {
            // Refresh the cash registers page if it's currently open
            _refreshCurrentPage();
          },
        ),
      );
      if (result == true) {
        // Cash register was successfully added, refresh the current page
        _refreshCurrentPage();
      }
    }

    Future<void> showAddPettyCashDialog() async {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => PettyCashFormDialog(
          businessId: widget.businessId,
          onSuccess: () {
            // Refresh the petty cash page if it's currently open
            _refreshCurrentPage();
          },
        ),
      );
      if (result == true) {
        // Petty cash was successfully added, refresh the current page
        _refreshCurrentPage();
      }
    }

    Future<void> showAddBankAccountDialog() async {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => BankAccountFormDialog(
          businessId: widget.businessId,
          onSuccess: () {
            // Refresh the bank accounts page if it's currently open
            _refreshCurrentPage();
          },
        ),
      );
      if (result == true) {
        // Bank account was successfully added, refresh the current page
        _refreshCurrentPage();
      }
    }

    Future<void> showAddDocumentDialog() async {
      if (!context.mounted) return;
      final ctx = context;
      final calendarController = widget.calendarController ?? await CalendarController.load();
      if (!ctx.mounted) return;
      final result = await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (context) => DocumentFormDialog(
          businessId: widget.businessId,
          calendarController: calendarController,
          authStore: widget.authStore,
          apiClient: ApiClient(),
          fiscalYearId: null, // TODO: از context یا state بگیریم
          currencyId: 1, // TODO: از تنظیمات بگیریم
        ),
      );
      if (result == true) {
        // Document was successfully added, refresh the current page
        _refreshCurrentPage();
      }
    }

    Future<void> showAddWarehouseDialog() async {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => WarehouseFormDialog(
          businessId: widget.businessId,
          onSuccess: () {
            // Refresh the warehouses page if it's currently open
            _refreshCurrentPage();
          },
        ),
      );
      if (result == true) {
        // Warehouse was successfully added, refresh the current page
        _refreshCurrentPage();
      }
    }

    Future<void> showAddWarehouseDocumentDialog() async {
      if (!context.mounted) return;
      final result = await showDialog<WarehouseDocWizardResult>(
        context: context,
        builder: (context) => WarehouseDocWizardDialog(
          businessId: widget.businessId,
          apiClient: ApiClient(),
        ),
      );
      if (result != null) {
        // Warehouse document wizard was completed, refresh the current page
        _refreshCurrentPage();
      }
    }


    bool isExpanded(_MenuItem item) {
      if (item.label == t.productsAndServices) return _isProductsAndServicesExpanded;
      if (item.label == t.banking) return _isBankingExpanded;
      if (item.label == t.accountingMenu) return _isAccountingMenuExpanded;
      if (item.label == t.warehouseManagement) return _isWarehouseManagementExpanded;
      if (item.label == 'هوش مصنوعی') return _isAIExpanded;
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
    final Color appBarBg = const Color(0xFF0D47A1); // آبی تیره
    final Color appBarFg = Colors.white;

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
        // Notification Center
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
        IconButton(
          tooltip: 'چت سریع با AI',
          onPressed: () {
            AIChatDialog.show(
              context,
              authStore: widget.authStore,
              businessId: widget.businessId,
              calendarController: widget.calendarController,
            );
          },
          icon: const Icon(Icons.smart_toy_outlined),
        ),
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
                                        showAddPersonDialog();
                                      } else if (child.label == t.products) {
                                        // Show add product dialog
                                        showAddProductDialog();
                                      } else if (child.label == t.categories) {
                                        // Navigate to add category
                                      } else if (child.label == t.productAttributes) {
                                        // Navigate to add product attribute
                                      } else if (child.label == t.accounts) {
                                        // Open add bank account dialog
                                        showAddBankAccountDialog();
                                      } else if (child.label == t.pettyCash) {
                                        // Open add petty cash dialog
                                        showAddPettyCashDialog();
                                      } else if (child.label == t.cashBox) {
                                        // Open add cash register dialog
                                        showAddCashBoxDialog();
                                      } else if (child.label == t.wallet) {
                                        // Show wallet top-up dialog
                                        showWalletTopUpDialog();
                                      } else if (child.label == t.checks) {
                                        // Navigate to add check
                                      } else if (child.label == t.invoice) {
                                        // Navigate to add invoice
                                        context.go('/business/${widget.businessId}/invoice/new');
                                      } else if (child.label == t.receiptsAndPayments) {
                                        // Show add receipt payment dialog
                                        showAddReceiptPaymentDialog();
                                      } else if (child.label == t.expenseAndIncome) {
                                        // Show add expense/income dialog
                                        showAddExpenseIncomeDialog();
                                      } else if (child.label == t.warehouses) {
                                        // Show add warehouse dialog
                                        showAddWarehouseDialog();
                                      } else if (child.label == 'حواله‌های انبار') {
                                        // Show add warehouse document dialog
                                        showAddWarehouseDocumentDialog();
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
                                if (item.label == 'هوش مصنوعی') _isAIExpanded = !_isAIExpanded;
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
                                    Builder(builder: (ctx) {
                                      final section = _sectionForLabel(item.label, t);
                                      final canAdd = section != null && (widget.authStore.hasBusinessPermission(section, 'add'));
                                      if (!canAdd) return const SizedBox.shrink();
                                      return GestureDetector(
                                        onTap: () {
                                          if (item.label == t.people) {
                                            showAddPersonDialog();
                                          } else if (item.label == t.accounts) {
                                            showAddBankAccountDialog();
                                          } else if (item.label == t.cashBox) {
                                            showAddCashBoxDialog();
                                          } else if (item.label == t.invoice) {
                                            // Navigate to add invoice
                                            context.go('/business/${widget.businessId}/invoice/new');
                                          } else if (item.label == t.receiptsAndPayments) {
                                            // Show add receipt payment dialog
                                            showAddReceiptPaymentDialog();
                                      } else if (item.label == t.expenseAndIncome) {
                                        // Show add expense/income dialog
                                        showAddExpenseIncomeDialog();
                                      } else if (item.label == t.transfers) {
                                        // Show add transfer dialog
                                        showAddTransferDialog();
                                          } else if (item.label == t.checks) {
                                            // Show add check dialog
                                            showAddCheckDialog();
                                          } else if (item.label == t.documents) {
                                            // Show add document dialog
                                            showAddDocumentDialog();
                                          }
                                          // سایر مسیرهای افزودن در آینده متصل می‌شوند
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
                                      );
                                    }),
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
                    final section = _sectionForLabel(item.label, t);
                    final canAdd = section != null && (widget.authStore.hasBusinessPermission(section, 'add'));
                    return ListTile(
                      leading: Icon(item.selectedIcon, color: active ? activeFg : sideFg),
                      title: Text(item.label, style: TextStyle(color: active ? activeFg : sideFg, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
                      selected: active,
                      selectedTileColor: activeBg,
                      trailing: (item.hasAddButton && canAdd)
                          ? GestureDetector(
                              onTap: () {
                                context.pop();
                                // در حال حاضر فقط اشخاص پشتیبانی می‌شود
                                if (item.label == t.people) {
                                  showAddPersonDialog();
                                } else if (item.label == t.invoice) {
                                  // Navigate to add invoice
                                  context.go('/business/${widget.businessId}/invoice/new');
                                } else if (item.label == t.expenseAndIncome) {
                                  // Show add expense/income dialog
                                  showAddExpenseIncomeDialog();
                                } else if (item.label == t.transfers) {
                                  // Show add transfer dialog
                                  showAddTransferDialog();
                                } else if (item.label == t.checks) {
                                  // Show add check dialog
                                  showAddCheckDialog();
                                } else if (item.label == t.documents) {
                                  // Show add document dialog
                                  showAddDocumentDialog();
                                }
                              },
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: sideFg.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Icon(Icons.add, size: 16, color: sideFg),
                              ),
                            )
                          : null,
                      onTap: () {
                        context.pop();
                        onSelect(i);
                      },
                    );
                  } else if (item.type == _MenuItemType.expandable) {
                    // فیلتر کردن زیرآیتم‌ها بر اساس دسترسی
                    final visibleChildren = (item.children ?? []).where((child) => _hasAccessToMenuItem(child)).toList();
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
                          if (item.label == 'هوش مصنوعی') _isAIExpanded = expanded;
                        });
                      },
                      children: visibleChildren.map((child) {
                        final childSection = _sectionForLabel(child.label, t);
                        final childCanAdd = child.hasAddButton && (childSection != null && widget.authStore.hasBusinessPermission(childSection, 'add'));
                        return ListTile(
                        leading: const SizedBox(width: 24),
                        title: Text(child.label),
                        trailing: childCanAdd ? GestureDetector(
                          onTap: () {
                            context.pop();
                            // Navigate to add new item
                            if (child.label == t.products) {
                              // Show add product dialog
                              showAddProductDialog();
                            } else if (child.label == t.categories) {
                              // Navigate to add category
                            } else if (child.label == t.productAttributes) {
                              // Navigate to add product attribute
                            } else if (child.label == t.accounts) {
                              // Open add bank account dialog
                              showAddBankAccountDialog();
                            } else if (child.label == t.pettyCash) {
                              // Open add petty cash dialog
                              showAddPettyCashDialog();
                            } else if (child.label == t.cashBox) {
                              // Open add cash register dialog
                              showAddCashBoxDialog();
                            } else if (child.label == t.wallet) {
                              // Show wallet top-up dialog
                              showWalletTopUpDialog();
                            } else if (child.label == t.checks) {
                              // Navigate to add check
                            } else if (child.label == t.invoice) {
                              // Navigate to add invoice
                              context.go('/business/${widget.businessId}/invoice/new');
                            } else if (child.label == t.receiptsAndPayments) {
                              // Show add receipt payment dialog
                              showAddReceiptPaymentDialog();
                            } else if (child.label == t.expenseAndIncome) {
                              // Show add expense/income dialog
                              showAddExpenseIncomeDialog();
                            } else if (child.label == t.warehouses) {
                              // Show add warehouse dialog
                              showAddWarehouseDialog();
                            } else if (child.label == 'حواله‌های انبار') {
                              // Show add warehouse document dialog
                              showAddWarehouseDocumentDialog();
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
                        );
                      }).toList(),
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
    
    final filteredItems = allItems.where((item) {
      if (item.type == _MenuItemType.separator) {
        return true;
      }
      
      if (item.type == _MenuItemType.simple) {
        final hasAccess = _hasAccessToMenuItem(item);
        return hasAccess;
      }
      
      if (item.type == _MenuItemType.expandable) {
        final hasAccess = _hasAccessToExpandableMenuItem(item);
        return hasAccess;
      }
      
      return false;
    }).toList();
    
    return filteredItems;
  }

  bool _hasAccessToMenuItem(_MenuItem item) {
    final section = _sectionForLabel(item.label, AppLocalizations.of(context));
    
    // داشبورد همیشه قابل مشاهده است
    if (item.path != null && item.path!.endsWith('/dashboard')) {
      return true;
    }
    
    // اگر سکشن تعریف نشده، نمایش داده نشود
    if (section == null) {
      return false;
    }
    
    // بررسی دسترسی‌های مختلف برای نمایش منو
    // اگر کاربر مالک است، همه منوها قابل مشاهده هستند
    if (widget.authStore.currentBusiness?.isOwner == true) {
      return true;
    }
    
    // برای کاربران عضو، بررسی دسترسی
    // تنظیمات: نیازمند دسترسی join
    if (section == 'settings' && item.label == AppLocalizations.of(context).settings) {
      final hasJoin = widget.authStore.hasBusinessPermission('settings', 'join');
      return hasJoin;
    }

    // سایر سکشن‌ها: بررسی دسترسی view
    final hasAccess = widget.authStore.canReadSection(section);
    
    // Debug: بررسی دقیق‌تر دسترسی‌ها
    // viewPerm is checked implicitly through hasAccess
    
    return hasAccess;
  }

  bool _hasAccessToExpandableMenuItem(_MenuItem item) {
    if (item.children == null) {
      return false;
    }
    
    
    // اگر حداقل یکی از زیرآیتم‌ها قابل دسترسی باشد، منو نمایش داده شود
    final hasAccess = item.children!.any((child) => _hasAccessToMenuItem(child));
    
    return hasAccess;
  }

  // تبدیل برچسب محلی‌شده منو به کلید سکشن دسترسی
  String? _sectionForLabel(String label, AppLocalizations t) {
    if (label == t.people) return 'people';
    if (label == t.products) return 'products';
    if (label == t.categories) return 'categories';
    if (label == t.productAttributes) return 'product_attributes';
    if (label == t.accounts) return 'bank_accounts';
    if (label == t.pettyCash) return 'petty_cash';
    if (label == t.cashBox) return 'cash';
    if (label == t.wallet) return 'wallet';
    if (label == t.checks) return 'checks';
    if (label == t.invoice) return 'invoices';
    if (label == t.receiptsAndPayments) return 'people_transactions';
    if (label == t.expenseAndIncome) return 'expenses_income';
    if (label == t.transfers) return 'transfers';
    if (label == t.documents) return 'accounting_documents';
    if (label == t.chartOfAccounts) return 'chart_of_accounts';
    if (label == t.openingBalance) return 'opening_balance';
    if (label == t.reports) return 'reports';
    if (label == t.warehouses) return 'warehouses';
    if (label == t.storageSpace) return 'storage';
    if (label == t.taxpayers) return 'settings';
    if (label == t.settings) return 'settings';
    if (label == t.pluginMarketplace) return 'marketplace';
    if (label == 'هوش مصنوعی' || label == 'AI Tools') return 'ai';
    if (label == 'چت با AI' || label == 'AI Chat') return 'ai';
    if (label == 'اشتراک AI' || label == 'AI Subscription') return 'ai';
    if (label == 'آمار استفاده' || label == 'AI Usage') return 'ai';
    return null;
  }

  // ==== Notifications (shared simplified with profile) ====
  Future<void> _initNotifications() async {
    // Load unread announcements for badge
    try {
      final data = await AnnouncementsService(ApiClient()).listAnnouncements(page: 1, limit: 5, onlyUnread: true);
      final items = (data['items'] as List? ?? const <dynamic>[])
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
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
    // Optional: connect WS (reuse existing apiKey)
    // WebSocket connection is optional - failures should not break the UI
    final apiKey = widget.authStore.apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        _ws = createNotificationsWsClient();
        _ws?.connect(
          apiKey: apiKey,
          onMessage: (msg) {
            try {
              final type = '${msg['type'] ?? ''}';
              if (type == 'notification') {
                final title = '${msg['title'] ?? 'پیام'}';
                final body = '${msg['body'] ?? ''}';
                if (!mounted) return;
                setState(() {
                  _notifications.insert(0, <String, dynamic>{
                    'title': title,
                    'body': body,
                    'level': '${msg['level'] ?? 'info'}',
                  });
                  _unreadCount = (_unreadCount + 1).clamp(0, 99);
                });
              }
            } catch (_) {
              // Ignore message processing errors
            }
          },
        );
      } catch (_) {
        // Silently ignore WebSocket connection failures - it's optional
        _ws = null;
      }
    }
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
            final cs = Theme.of(context).colorScheme;
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
                  children: const [
                    Icon(Icons.notifications_active, color: Colors.white),
                    SizedBox(width: 8),
                    Text('مرکز اعلان‌ها', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    void refreshDialog() => dialogSetState?.call(() {});
    setState(() => _busyAnnIds.add(id));
    refreshDialog();
    try {
      await AnnouncementsService(ApiClient()).markRead(id);
      setState(() {
        _notifications.removeWhere((e) => (e['id'] is int ? e['id'] == id : int.tryParse('${e['id']}') == id));
      });
      refreshDialog();
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _busyAnnIds.remove(id));
      } else {
        _busyAnnIds.remove(id);
      }
      refreshDialog();
    }
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