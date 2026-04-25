import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth_store.dart';
import '../../core/locale_controller.dart';
import '../../core/calendar_controller.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/combined_user_menu_button.dart';
import '../../models/person_model.dart';
import '../../widgets/person/person_form_dialog.dart';
import '../../widgets/banking/bank_account_form_dialog.dart';
import '../../widgets/banking/cash_register_form_dialog.dart';
import '../../widgets/banking/petty_cash_form_dialog.dart';
import '../../widgets/product/product_form_dialog.dart';
import '../../widgets/category/category_tree_dialog.dart';
import '../../services/business_dashboard_service.dart';
import '../../services/marketplace_service.dart';
import '../../core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'receipts_payments_list_page.dart' show BulkSettlementDialog;
import '../../widgets/document/document_form_dialog.dart';
import '../../widgets/wallet/wallet_top_up_dialog.dart';
import '../../widgets/notification_bell_button.dart';
import '../../widgets/transfer/transfer_form_dialog.dart';
import '../../widgets/expense_income/expense_income_form_dialog.dart';
import '../../widgets/warehouse/warehouse_form_dialog.dart';
import '../../widgets/warehouse/warehouse_doc_wizard_dialog.dart';
import '../../widgets/warehouse/warehouse_document_form_dialog.dart';
import '../../services/invoice_service.dart';
import '../../widgets/ai/ai_chat_dialog.dart';
import '../../widgets/calculator/calculator_dialog.dart';
import '../../core/date_utils.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'check_form_page.dart';
import 'bank_accounts_page.dart';
import 'persons_page.dart';
import 'cash_registers_page.dart';
import 'petty_cash_page.dart';
import 'checks_page.dart';
import 'invoices_list_page.dart';
import 'receipts_payments_list_page.dart';
import 'expense_income_list_page.dart';
import 'transfers_page.dart';
import 'documents_page.dart';

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
  bool _isCrmExpanded = false;
  final BusinessDashboardService _businessService = BusinessDashboardService(ApiClient());
  final MarketplaceService _marketplaceService = MarketplaceService();
  List<Map<String, dynamic>> _businessPlugins = [];
  bool _pluginsLoaded = false;
  bool _isBusinessLoading = false;
  String? _businessLoadError;
  Timer? _dateTimeUpdateTimer;

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
    _loadBusinessPlugins();
    // به‌روزرسانی خودکار ساعت در نوار بالا هر دقیقه
    _dateTimeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _dateTimeUpdateTimer?.cancel();
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
        _refreshReceiptsPaymentsPageIfOpen();
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
        _refreshTransfersPageIfOpen();
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
        _refreshExpenseIncomePageIfOpen();
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
            _refreshChecksPageIfOpen();
          },
        ),
      );
      if (result == true) {
        _refreshChecksPageIfOpen();
      }
    }

    void _refreshCurrentPage() {
    // Force a rebuild of the current page
    setState(() {
      // This will cause the current page to rebuild
      // and if it's PettyCashPage, it will refresh its data
    });
  }

    /// Refresh the bank accounts page if it's currently open
    void _refreshBankAccountsPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final accountsPath = '/business/${widget.businessId}/accounts';
        if (currentPath == accountsPath) {
          // Try to get the page state and refresh the page
          final pageState = BankAccountsPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        // If we can't determine the current path or refresh, just refresh current page
        _refreshCurrentPage();
      }
    }

    /// Refresh the persons page if it's currently open
    void _refreshPersonsPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final personsPath = '/business/${widget.businessId}/persons';
        if (currentPath == personsPath) {
          final pageState = PersonsPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the cash registers page if it's currently open
    void _refreshCashRegistersPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final cashBoxPath = '/business/${widget.businessId}/cash-box';
        if (currentPath == cashBoxPath) {
          final pageState = CashRegistersPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the petty cash page if it's currently open
    void _refreshPettyCashPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final pettyCashPath = '/business/${widget.businessId}/petty-cash';
        if (currentPath == pettyCashPath) {
          final pageState = PettyCashPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the checks page if it's currently open
    void _refreshChecksPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final checksPath = '/business/${widget.businessId}/checks';
        if (currentPath == checksPath) {
          final pageState = ChecksPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the invoices page if it's currently open
    void _refreshInvoicesPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final invoicesPath = '/business/${widget.businessId}/invoice';
        if (currentPath == invoicesPath) {
          final pageState = InvoicesListPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the receipts payments page if it's currently open
    void _refreshReceiptsPaymentsPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final receiptsPaymentsPath = '/business/${widget.businessId}/receipts-payments';
        if (currentPath == receiptsPaymentsPath) {
          final pageState = ReceiptsPaymentsListPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the expense income page if it's currently open
    void _refreshExpenseIncomePageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final expenseIncomePath = '/business/${widget.businessId}/expense-income';
        if (currentPath == expenseIncomePath) {
          final pageState = ExpenseIncomeListPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the transfers page if it's currently open
    void _refreshTransfersPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final transfersPath = '/business/${widget.businessId}/transfers';
        if (currentPath == transfersPath) {
          final pageState = TransfersPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the documents page if it's currently open
    void _refreshDocumentsPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final documentsPath = '/business/${widget.businessId}/documents';
        if (currentPath == documentsPath) {
          final pageState = DocumentsPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
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

    if (mounted) {
      setState(() {
        _isBusinessLoading = true;
        _businessLoadError = null;
      });
    }

    try {
      final businessData = await _businessService.getBusinessWithPermissions(widget.businessId);
      await widget.authStore.setCurrentBusiness(businessData);
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        final msg = ErrorExtractor.extractErrorMessage(e, t);
        setState(() {
          _businessLoadError = msg;
        });
        SnackBarHelper.showError(
          context,
          message: msg,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusinessLoading = false;
        });
      }
    }
  }

  Future<void> _loadBusinessPlugins() async {
    if (_pluginsLoaded) return;
    
    try {
      final plugins = await _marketplaceService.listBusinessPlugins(businessId: widget.businessId);
      if (mounted) {
        setState(() {
          _businessPlugins = plugins.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _pluginsLoaded = true;
        });
      }
    } catch (e) {
      // خطا را نادیده می‌گیریم تا منو کار کند
      if (mounted) {
        setState(() {
          _pluginsLoaded = true;
        });
      }
    }
  }

  bool _isWarrantyPluginActive() {
    // پیدا کردن پلاگین گارانتی
    try {
      final warrantyPlugin = _businessPlugins.firstWhere(
        (plugin) => plugin['plugin_code'] == 'product_warranty',
        orElse: () => <String, dynamic>{},
      );
      return warrantyPlugin['is_active'] == true;
    } catch (e) {
      return false;
    }
  }

  bool _isRepairShopPluginActive() {
    // پیدا کردن پلاگین تعمیرگاه
    try {
      final repairShopPlugin = _businessPlugins.firstWhere(
        (plugin) => plugin['plugin_code'] == 'repair_shop_management',
        orElse: () => <String, dynamic>{},
      );
      return repairShopPlugin['is_active'] == true;
    } catch (e) {
      return false;
    }
  }

  bool _isCustomerClubPluginActive() {
    try {
      final plug = _businessPlugins.firstWhere(
        (plugin) => plugin['plugin_code'] == 'customer_club',
        orElse: () => <String, dynamic>{},
      );
      return plug['is_active'] == true;
    } catch (e) {
      return false;
    }
  }

  bool _isDistributionPluginActive() {
    try {
      final plug = _businessPlugins.firstWhere(
        (plugin) => plugin['plugin_code'] == 'distribution',
        orElse: () => <String, dynamic>{},
      );
      return plug['is_active'] == true;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final currentBusiness = widget.authStore.currentBusiness;
    final bool isCorrectBusiness = currentBusiness != null && currentBusiness.id == widget.businessId;
    final bool hasPermissions = widget.authStore.businessPermissions != null;

    // اگر در بارگذاری اطلاعات کسب‌وکار خطا داشتیم و هنوز کسب‌وکار فعلی با این صفحه هم‌خوان نیست،
    // به‌جای نمایش پیام «دسترسی ندارید»، یک صفحه خطای شفاف نمایش می‌دهیم.
    if (_businessLoadError != null && !isCorrectBusiness) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t.businessDashboard),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 24),
                Text(
                  'خطا در بارگذاری اطلاعات کسب و کار یا دسترسی‌ها.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _businessLoadError ?? '',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    _loadBusinessInfo();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('تلاش مجدد برای بارگذاری'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // تا زمانی که اطلاعات کسب‌وکار و دسترسی‌ها به‌طور کامل بارگذاری نشده‌اند،
    // صفحه اصلی را با یک لودر ساده نمایش می‌دهیم تا پیام «عدم دسترسی» به‌صورت موقت دیده نشود.
    if (_isBusinessLoading || !isCorrectBusiness || !hasPermissions) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'در حال بارگذاری اطلاعات کسب و کار و دسترسی‌ها...',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

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

    final workflowLabel = _workflowMenuLabel(t);
    
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
        label: 'فروش سریع',
        icon: Icons.point_of_sale,
        selectedIcon: Icons.point_of_sale,
        path: '/business/${widget.businessId}/quick-sales',
        type: _MenuItemType.simple,
        hasAddButton: false,
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
          _MenuItem(
            label: t.currencyRevaluation,
            icon: Icons.payments,
            selectedIcon: Icons.payments,
            path: '/business/${widget.businessId}/currency-revaluation',
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
          _MenuItem(
            label: 'انبار گردانی',
            icon: Icons.inventory,
            selectedIcon: Icons.inventory,
            path: '/business/${widget.businessId}/stock-count',
            type: _MenuItemType.simple,
            hasAddButton: false,
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
        label: workflowLabel,
        icon: Icons.hub_outlined,
        selectedIcon: Icons.hub,
        path: '/business/${widget.businessId}/workflows',
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        label: 'CRM',
        icon: Icons.handshake_outlined,
        selectedIcon: Icons.handshake,
        path: '/business/${widget.businessId}/crm/dashboard',
        type: _MenuItemType.expandable,
        children: [
          _MenuItem(
            label: 'داشبورد',
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            path: '/business/${widget.businessId}/crm/dashboard',
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            label: t.crmMenuNotesCalendar,
            icon: Icons.calendar_month_outlined,
            selectedIcon: Icons.calendar_month,
            path: '/business/${widget.businessId}/crm/notes-calendar',
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            label: 'چت وب',
            icon: Icons.chat_bubble_outline,
            selectedIcon: Icons.chat_bubble,
            path: '/business/${widget.businessId}/crm/web-chat',
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            label: 'فرایندها و زون ارجاعات',
            icon: Icons.account_tree_outlined,
            selectedIcon: Icons.account_tree,
            path: '/business/${widget.businessId}/crm/process-definitions',
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            label: 'سرنخ‌ها',
            icon: Icons.contact_phone_outlined,
            selectedIcon: Icons.contact_phone,
            path: '/business/${widget.businessId}/crm/leads',
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            label: 'فرصت‌های فروش',
            icon: Icons.trending_up_outlined,
            selectedIcon: Icons.trending_up,
            path: '/business/${widget.businessId}/crm/deals',
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            label: 'فعالیت‌ها',
            icon: Icons.history,
            selectedIcon: Icons.history,
            path: '/business/${widget.businessId}/crm/activities',
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            label: 'گزارشات',
            icon: Icons.assessment_outlined,
            selectedIcon: Icons.assessment,
            path: '/business/${widget.businessId}/crm/reports',
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
        ],
      ),
      _MenuItem(
        label: t.warranty ?? 'گارانتی',
        icon: Icons.verified_user,
        selectedIcon: Icons.verified_user,
        path: '/business/${widget.businessId}/warranty',
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        label: 'تعمیرگاه',
        icon: Icons.build_circle_outlined,
        selectedIcon: Icons.build_circle,
        path: '/business/${widget.businessId}/repair-shop',
        type: _MenuItemType.simple,
        hasAddButton: true,
      ),
      _MenuItem(
        label: t.customerClubMenu,
        icon: Icons.card_giftcard_outlined,
        selectedIcon: Icons.card_giftcard,
        path: '/business/${widget.businessId}/customer-club',
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        label: t.distributionMenu,
        icon: Icons.local_shipping_outlined,
        selectedIcon: Icons.local_shipping,
        path: '/business/${widget.businessId}/distribution',
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        label: 'استعلامات',
        icon: Icons.search_outlined,
        selectedIcon: Icons.search,
        path: '/business/${widget.businessId}/zohal/inquiries',
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
            if (item.label == 'CRM') _isCrmExpanded = true;
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
          if (item.label == 'CRM') _isCrmExpanded = !_isCrmExpanded;
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
      // از SnackBarHelper برای نمایش پیام خروج استفاده می‌کنیم تا روی همه لایه‌ها نمایش داده شود
      SnackBarHelper.showSuccess(
        context,
        message: t.logoutDone,
      );
      context.go('/login');
    }

    Future<void> showAddPersonDialog() async {
      final result = await showDialog<Person?>(
        context: context,
        builder: (context) => PersonFormDialog(
          businessId: widget.businessId,
          onSuccess: () {
            _refreshPersonsPageIfOpen();
          },
        ),
      );
      if (result != null) {
        _refreshPersonsPageIfOpen();
      }
    }

    void _refreshProductsPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final productsPath = '/business/${widget.businessId}/products';
        if (currentPath == productsPath) {
          // If we're on the products page, refresh it
          _refreshCurrentPage();
        }
      } catch (_) {
        // If GoRouterState is not available, try to refresh anyway
        _refreshCurrentPage();
      }
    }

    Future<void> showAddProductDialog() async {
      final result = await showDialog<Object?>(
        context: context,
        builder: (context) => ProductFormDialog(
          businessId: widget.businessId,
          authStore: widget.authStore,
          onSuccess: () {
            // Refresh the products page if it's currently open
            _refreshProductsPageIfOpen();
          },
        ),
      );
      if (result != null && result != false) {
        // Product was successfully added (returns true or int ID), refresh if products page is open
        _refreshProductsPageIfOpen();
      }
    }

    Future<void> showAddCashBoxDialog() async {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => CashRegisterFormDialog(
          businessId: widget.businessId,
          onSuccess: () {
            // Refresh the cash registers page if it's currently open
            _refreshCashRegistersPageIfOpen();
          },
        ),
      );
      if (result == true) {
        // Cash register was successfully added, refresh the cash registers page if open
        _refreshCashRegistersPageIfOpen();
      }
    }

    Future<void> showAddPettyCashDialog() async {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => PettyCashFormDialog(
          businessId: widget.businessId,
          onSuccess: () {
            // Refresh the petty cash page if it's currently open
            _refreshPettyCashPageIfOpen();
          },
        ),
      );
      if (result == true) {
        // Petty cash was successfully added, refresh the petty cash page if open
        _refreshPettyCashPageIfOpen();
      }
    }

    Future<void> showAddBankAccountDialog() async {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => BankAccountFormDialog(
          businessId: widget.businessId,
          onSuccess: () {
            // Refresh the bank accounts page if it's currently open
            _refreshBankAccountsPageIfOpen();
          },
        ),
      );
      if (result == true) {
        // Bank account was successfully added, refresh the bank accounts page if open
        _refreshBankAccountsPageIfOpen();
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
          fiscalYearId: null,
          currencyId: null, // از CurrencyPickerWidget (پیش‌فرض کسب‌وکار) دریافت می‌شود
        ),
      );
      if (result == true) {
        // Document was successfully added, refresh the documents page if open
        _refreshDocumentsPageIfOpen();
      }
    }

    Future<void> showAddWarehouseDialog() async {
      final result = await WarehouseFormDialog.show(
        context,
        businessId: widget.businessId,
        onSuccess: () {
          // Refresh the warehouses page if it's currently open
          _refreshCurrentPage();
        },
      );
      if (result == true) {
        // Warehouse was successfully added, refresh the current page
        _refreshCurrentPage();
      }
    }

  Future<void> showAddWarehouseDocumentDialog() async {
    if (!context.mounted) return;
    final calendarController = widget.calendarController ?? await CalendarController.load();
    final result = await showDialog<WarehouseDocWizardResult>(
      context: context,
      builder: (context) => WarehouseDocWizardDialog(
        businessId: widget.businessId,
        apiClient: ApiClient(),
        calendarController: calendarController,
      ),
    );
    if (result == null) return;
    
    if (result.isManual) {
      // Manual document creation
      final calendarController = widget.calendarController ?? await CalendarController.load();
      await showDialog(
        context: context,
        builder: (_) => WarehouseDocumentFormDialog(
          businessId: widget.businessId,
          calendarController: calendarController,
          onSuccess: () => _refreshCurrentPage(),
        ),
      );
      return;
    }
    
    // Handle invoice-based document creation
    await _handleInvoiceWizardResult(result);
  }


    bool isExpanded(_MenuItem item) {
      if (item.label == t.productsAndServices) return _isProductsAndServicesExpanded;
      if (item.label == t.banking) return _isBankingExpanded;
      if (item.label == t.accountingMenu) return _isAccountingMenuExpanded;
      if (item.label == t.warehouseManagement) return _isWarehouseManagementExpanded;
      if (item.label == 'هوش مصنوعی') return _isAIExpanded;
      if (item.label == 'CRM') return _isCrmExpanded;
      return false;
    }

    int getTotalMenuItemsCount() {
      int count = 0;
      for (final item in menuItems) {
        if (item.type == _MenuItemType.separator) {
          count++; // آیتم جداکننده هم شمرده می‌شود
        } else {
          count++; // آیتم اصلی
          // نمایش زیرمجموعه‌ها در همه حالت‌ها (Rail و Extended)
          if (item.type == _MenuItemType.expandable && isExpanded(item)) {
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
        NotificationBellButton(authStore: widget.authStore, iconColor: appBarFg),
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
        IconButton(
          tooltip: 'ماشین حساب',
          onPressed: () {
            CalculatorDialog.show(context);
          },
          icon: const Icon(Icons.calculate_outlined),
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

    // نوار باریک بالای AppBar: نام کسب‌وکار و (در نمای دسکتاپ/تبلت) تاریخ و زمان
    const double _businessTopBarHeight = 32;
    final bool isMobile = width < 700;
    final String businessName = currentBusiness?.name ?? '';
    final bool isJalali = widget.calendarController?.isJalali ?? true;
    final String dateTimeStr = HesabixDateUtils.formatDateTimeWithWeekday(
      DateTime.now(),
      isJalali,
      t.localeName,
    );
    const Color topBarBg = Color(0xFF020D1A);

    final Widget businessTopBar = Container(
      height: _businessTopBarHeight,
      width: double.infinity,
      color: topBarBg,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              businessName,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isMobile)
            Text(
              dateTimeStr,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );

    final PreferredSizeWidget preferredAppBar = PreferredSize(
      preferredSize: const Size.fromHeight(_businessTopBarHeight + kToolbarHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          businessTopBar,
          appBar,
        ],
      ),
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
        appBar: preferredAppBar,
        body: Row(
          children: [
            Container(
              width: railExtended ? 260 : 88,
              height: double.infinity,
              color: sideBg,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
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
                    
                    // نمایش زیرمجموعه‌ها در همه حالت‌ها (Rail و Extended)
                    if (item.type == _MenuItemType.expandable && isExpanded(item)) {
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
                    // زیرآیتم با انیمیشن و بهبود بصری
                    final child = item.children![childIndex];
                    final bool isChildSelected = child.path != null && location.startsWith(child.path!);
                    final bool isChildHovered = index == _hoverIndex;
                    final bool isChildActive = isChildSelected || isChildHovered;
                    final BorderRadius childBr = isChildSelected
                        ? BorderRadius.zero
                        : (isChildHovered ? BorderRadius.zero : BorderRadius.circular(8));
                    final Color childBgColor = isChildActive
                        ? (isChildHovered && !isChildSelected 
                            ? (isDark ? activeBg.withValues(alpha: 0.5) : activeBg.withValues(alpha: 0.7))
                            : activeBg)
                        : Colors.transparent;
                    
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _hoverIndex = index),
                        onExit: (_) => setState(() => _hoverIndex = -1),
                        child: InkWell(
                          borderRadius: childBr,
                          onTap: () => onSelectChild(menuIndex, childIndex),
                          child: Container(
                            margin: EdgeInsets.zero,
                            padding: EdgeInsets.symmetric(
                              horizontal: railExtended ? 32 : 20,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: childBgColor,
                              borderRadius: childBr,
                            ),
                            child: Tooltip(
                              message: child.label,
                              waitDuration: const Duration(milliseconds: 500),
                              child: Row(
                                mainAxisAlignment: railExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isChildActive ? child.selectedIcon : child.icon,
                                    color: isChildActive ? activeFg : sideFg,
                                    size: railExtended ? 20 : 22,
                                  ),
                                  if (railExtended) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        child.label,
                                        style: TextStyle(
                                          color: isChildActive ? activeFg : sideFg,
                                          fontWeight: isChildActive ? FontWeight.w600 : FontWeight.w400,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    if (child.hasAddButton && _canAddForSection(_sectionForLabel(child.label, t)))
                                      GestureDetector(
                                        onTap: () {
                                          // Navigate to add new item
                                          if (child.label == t.personsList) {
                                            showAddPersonDialog();
                                          } else if (child.label == t.products) {
                                            showAddProductDialog();
                                          } else if (child.label == t.categories) {
                                            // Navigate to add category
                                          } else if (child.label == t.productAttributes) {
                                            // Navigate to add product attribute
                                          } else if (child.label == t.accounts) {
                                            showAddBankAccountDialog();
                                          } else if (child.label == t.pettyCash) {
                                            showAddPettyCashDialog();
                                          } else if (child.label == t.cashBox) {
                                            showAddCashBoxDialog();
                                          } else if (child.label == t.wallet) {
                                            showWalletTopUpDialog();
                                          } else if (child.label == t.checks) {
                                            showAddCheckDialog();
                                          } else if (child.label == t.invoice) {
                                            context.go('/business/${widget.businessId}/invoice/new');
                                          } else if (child.label == t.receiptsAndPayments) {
                                            showAddReceiptPaymentDialog();
                                          } else if (child.label == t.expenseAndIncome) {
                                            showAddExpenseIncomeDialog();
                                          } else if (child.label == t.warehouses) {
                                            showAddWarehouseDialog();
                                          } else if (child.label == 'حواله‌های انبار') {
                                            showAddWarehouseDocumentDialog();
                                          } else if (child.label == 'فرایندها و زون ارجاعات') {
                                            context.go('/business/${widget.businessId}/crm/process-definitions?openAdd=1');
                                          } else if (child.label == 'سرنخ‌ها') {
                                            context.go('/business/${widget.businessId}/crm/leads?openAdd=1');
                                          } else if (child.label == 'فرصت‌های فروش') {
                                            context.go('/business/${widget.businessId}/crm/deals?openAdd=1');
                                          } else if (child.label == 'فعالیت‌ها') {
                                            context.go('/business/${widget.businessId}/crm/activities?openAdd=1');
                                          }
                                        },
                                        child: Container(
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            color: isChildActive 
                                                ? activeFg.withValues(alpha: 0.15)
                                                : sideFg.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Icon(
                                            Icons.add,
                                            size: 14,
                                            color: isChildActive ? activeFg : sideFg,
                                          ),
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
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
                          vertical: 12,
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
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
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
                      Widget menuItemWidget = MouseRegion(
                        onEnter: (_) => setState(() => _hoverIndex = index),
                        onExit: (_) => setState(() => _hoverIndex = -1),
                        child: InkWell(
                          borderRadius: br,
                          onTap: () {
                            if (item.type == _MenuItemType.expandable) {
                              // در همه حالت‌ها (Rail و Extended) expand/collapse می‌کنیم
                              setState(() {
                                if (item.label == t.productsAndServices) _isProductsAndServicesExpanded = !_isProductsAndServicesExpanded;
                                if (item.label == t.banking) _isBankingExpanded = !_isBankingExpanded;
                                if (item.label == t.accountingMenu) _isAccountingMenuExpanded = !_isAccountingMenuExpanded;
                                if (item.label == t.warehouseManagement) _isWarehouseManagementExpanded = !_isWarehouseManagementExpanded;
                                if (item.label == 'هوش مصنوعی') _isAIExpanded = !_isAIExpanded;
                                if (item.label == 'CRM') _isCrmExpanded = !_isCrmExpanded;
                              });
                            } else {
                              onSelect(menuIndex);
                            }
                          },
                          child: Container(
                            margin: EdgeInsets.zero,
                            padding: EdgeInsets.symmetric(
                              horizontal: railExtended ? 16 : 0,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: br,
                            ),
                            child: Row(
                              mainAxisAlignment: railExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Icon(
                                      active ? item.selectedIcon : item.icon,
                                      color: active ? activeFg : sideFg,
                                      size: railExtended ? 24 : 28,
                                    ),
                                    // آیکون expand/collapse کوچک در گوشه برای حالت Rail
                                    if (!railExtended && item.type == _MenuItemType.expandable)
                                      Positioned(
                                        right: -4,
                                        bottom: -4,
                                        child: Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: sideBg,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: sideFg.withValues(alpha: 0.3),
                                              width: 1,
                                            ),
                                          ),
                                          child: AnimatedRotation(
                                            turns: isExpanded(item) ? 0.5 : 0,
                                            duration: const Duration(milliseconds: 200),
                                            curve: Curves.easeInOut,
                                            child: Icon(
                                              Icons.expand_more,
                                              color: sideFg,
                                              size: 10,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                if (railExtended) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      item.label,
                                      style: TextStyle(
                                        color: active ? activeFg : sideFg,
                                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  if (item.type == _MenuItemType.expandable)
                                    AnimatedRotation(
                                      turns: isExpanded(item) ? 0.5 : 0,
                                      duration: const Duration(milliseconds: 200),
                                      curve: Curves.easeInOut,
                                      child: Icon(
                                        Icons.expand_more,
                                        color: sideFg,
                                        size: 20,
                                      ),
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
                                            context.go('/business/${widget.businessId}/invoice/new');
                                          } else if (item.label == t.receiptsAndPayments) {
                                            showAddReceiptPaymentDialog();
                                          } else if (item.label == t.expenseAndIncome) {
                                            showAddExpenseIncomeDialog();
                                          } else if (item.label == t.transfers) {
                                            showAddTransferDialog();
                                          } else if (item.label == t.checks) {
                                            showAddCheckDialog();
                                          } else if (item.label == t.documents) {
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
                      
                      // اضافه کردن Tooltip برای حالت Rail (عرض کم)
                      if (!railExtended) {
                        menuItemWidget = Tooltip(
                          message: item.label,
                          waitDuration: const Duration(milliseconds: 500),
                          child: menuItemWidget,
                        );
                      }
                      
                      return menuItemWidget;
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
        appBar: preferredAppBar,
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
                          if (item.label == 'CRM') _isCrmExpanded = expanded;
                        });
                      },
                      children: visibleChildren.map((child) {
                        final childSection = _sectionForLabel(child.label, t);
                        final childCanAdd = child.hasAddButton && _canAddForSection(childSection);
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
                            } else if (child.label == 'فرایندها و زون ارجاعات') {
                              context.go('/business/${widget.businessId}/crm/process-definitions?openAdd=1');
                            } else if (child.label == 'سرنخ‌ها') {
                              context.go('/business/${widget.businessId}/crm/leads?openAdd=1');
                            } else if (child.label == 'فرصت‌های فروش') {
                              context.go('/business/${widget.businessId}/crm/deals?openAdd=1');
                            } else if (child.label == 'فعالیت‌ها') {
                              context.go('/business/${widget.businessId}/crm/activities?openAdd=1');
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

  Future<void> _handleInvoiceWizardResult(WarehouseDocWizardResult wizardResult) async {
    if (wizardResult.invoiceId == null) return;
    
    final apiClient = ApiClient();
    final invoiceService = InvoiceService(apiClient: apiClient);
    
    bool loaderDismissed = false;
    void dismissLoader() {
      if (!loaderDismissed && mounted) {
        loaderDismissed = true;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ).then((_) => loaderDismissed = true);

    try {
      final invoiceData = await invoiceService.getInvoice(
        businessId: widget.businessId,
        invoiceId: wizardResult.invoiceId!,
      );
      dismissLoader();
      if (!mounted) return;
      
      final invoiceItem = Map<String, dynamic>.from(invoiceData['item'] ?? const {});
      final initialLines = _extractLinesFromInvoice(invoiceItem, wizardResult.docType ?? 'issue');
      
      if (initialLines.isEmpty) {
        SnackBarHelper.showInfo(
          context,
          message: 'هیچ کالایی برای این فاکتور ثبت نشده است',
        );
        return;
      }
      
      final dateStr = invoiceItem['document_date']?.toString();
      final initialDate = dateStr == null ? null : DateTime.tryParse(dateStr);

        final calendarController = widget.calendarController ?? await CalendarController.load();
        await showDialog(
          context: context,
          builder: (_) => WarehouseDocumentFormDialog(
            businessId: widget.businessId,
            calendarController: calendarController,
            initialDocType: wizardResult.docType,
            lockDocType: true,
            initialDocumentDate: initialDate,
            initialLines: initialLines,
            sourceInvoiceId: wizardResult.invoiceId,
            sourceInvoiceCode: wizardResult.invoiceCode,
            sourceInvoiceType: wizardResult.sourceLabel,
            onSuccess: () => _refreshCurrentPage(),
          ),
        );
    } catch (e) {
      dismissLoader();
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: 'خطا در دریافت فاکتور: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      dismissLoader();
    }
  }

  List<Map<String, dynamic>> _extractLinesFromInvoice(Map<String, dynamic> invoice, String docType) {
    final movementFallback = docType == 'receipt' ? 'in' : 'out';
    final rawLines = List<dynamic>.from(invoice['product_lines'] ?? const []);
    final List<Map<String, dynamic>> result = [];
    for (final raw in rawLines) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      if (map['product_id'] == null) continue;
      final qty = _toDouble(map['quantity']);
      if (qty <= 0) continue;
      final extra = Map<String, dynamic>.from(map['extra_info'] ?? const {});
      final warehouseId = _toInt(map['warehouse_id'] ?? extra['warehouse_id']);
      final movement = (extra['movement'] ?? movementFallback).toString();
      result.add({
        'product_id': map['product_id'],
        'quantity': qty,
        'warehouse_id': warehouseId,
        'movement': movement,
        'extra_info': extra,
      });
    }
    return result;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.isNotEmpty) return int.tryParse(value);
    return null;
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
    
    // بررسی فعال بودن پلاگین گارانتی
    if (section == 'warranty') {
      if (!_isWarrantyPluginActive()) {
        return false;
      }
    }
    
    // بررسی فعال بودن پلاگین تعمیرگاه
    if (section == 'repair_shop') {
      if (!_isRepairShopPluginActive()) {
        return false;
      }
    }

    // باشگاه مشتریان
    if (section == 'customer_club') {
      if (!_isCustomerClubPluginActive()) {
        return false;
      }
    }

    // پخش مویرگی
    if (section == 'distribution') {
      if (!_isDistributionPluginActive()) {
        return false;
      }
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
    
    // استعلامات: نیازمند دسترسی read برای settings
    if (section == 'settings' && (item.label == 'استعلامات' || item.label == 'Inquiries')) {
      final hasRead = widget.authStore.hasBusinessPermission('settings', 'read') || 
                      widget.authStore.hasBusinessPermission('settings', 'join');
      return hasRead;
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

  /// بررسی دسترسی افزودن برای یک سکشن (CRM از write و بقیه از add استفاده می‌کنند)
  bool _canAddForSection(String? section) {
    if (section == null) return false;
    if (section == 'crm') {
      return widget.authStore.hasBusinessPermission(section, 'write');
    }
    return widget.authStore.hasBusinessPermission(section, 'add');
  }

  // تبدیل برچسب محلی‌شده منو به کلید سکشن دسترسی
  String? _sectionForLabel(String label, AppLocalizations t) {
    if (label == t.people) return 'people';
    if (label == 'CRM' || label == 'داشبورد' || label == 'فرایندها و زون ارجاعات' || label == 'سرنخ‌ها' || label == 'فرصت‌های فروش' || label == 'فعالیت‌ها' || label == 'گزارشات' || label == t.crmMenuNotesCalendar || label == 'چت وب') return 'crm';
    if (label == t.products) return 'products';
    if (label == t.categories) return 'categories';
    if (label == t.productAttributes) return 'product_attributes';
    if (label == t.accounts) return 'bank_accounts';
    if (label == t.pettyCash) return 'petty_cash';
    if (label == t.cashBox) return 'cash';
    if (label == t.wallet) return 'wallet';
    if (label == t.checks) return 'checks';
    if (label == 'فروش سریع') return 'invoices'; // فروش سریع نیازمند دسترسی invoices.add است
    if (label == t.invoice) return 'invoices';
    if (label == t.receiptsAndPayments) return 'people_transactions';
    if (label == t.expenseAndIncome) return 'expenses_income';
    if (label == t.transfers) return 'transfers';
    if (label == t.documents) return 'accounting_documents';
    if (label == t.yearEndClosing) return 'fiscal_years';
    if (label == t.chartOfAccounts) return 'chart_of_accounts';
    if (label == t.openingBalance) return 'opening_balance';
    if (label == t.currencyRevaluation) return 'currency_revaluation';
    if (label == t.reports) return 'reports';
    if (label == t.warehouses) return 'warehouses';
    if (label == 'حواله‌های انبار') return 'warehouse_transfers';
    // انبارگردانی (Stock Count) در نهایت به ایجاد/مدیریت حواله‌های تعدیل منجر می‌شود؛
    // بنابراین در مدل دسترسی فعلی زیر مجموعه‌ی warehouse_transfers در نظر گرفته می‌شود.
    if (label == 'انبار گردانی' || label == 'انبارگردانی' || label == 'Stock Count') return 'warehouse_transfers';
    if (label == t.storageSpace) return 'storage';
    if (label == t.taxpayers) return 'settings';
    if (label == t.settings) return 'settings';
    if (label == t.pluginMarketplace) return 'marketplace';
    if (label == t.warranty || label == 'گارانتی' || label == 'Warranty') return 'warranty';
    if (label == 'تعمیرگاه' || label == 'Repair Shop') return 'repair_shop';
    if (label == t.customerClubMenu || label == 'Customer Club') return 'customer_club';
    if (label == t.distributionMenu || label == 'Field distribution') return 'distribution';
    if (label == 'هوش مصنوعی' || label == 'AI Tools') return 'ai';
    if (label == 'چت با AI' || label == 'AI Chat') return 'ai';
    if (label == 'اشتراک AI' || label == 'AI Subscription') return 'ai';
    if (label == 'آمار استفاده' || label == 'AI Usage') return 'ai';
    if (label == 'استعلامات' || label == 'Inquiries') return 'settings';
    if (label == _workflowMenuLabel(t)) return 'settings';
    return null;
  }

  String _workflowMenuLabel(AppLocalizations t) {
    return t.localeName.startsWith('fa') ? 'اتوماسیون‌ها' : 'Automations';
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