import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'pages/profile/notifications_settings_page.dart';
import 'pages/profile/user_notifications_page.dart';
import 'pages/profile/notification_history_page.dart';
import 'pages/profile/notification_templates_admin_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'l10n/app_localizations.dart';

import 'pages/login_page.dart';
import 'pages/profile/profile_shell.dart';
import 'pages/profile/profile_dashboard_page.dart';
import 'pages/profile/new_business_page.dart';
import 'pages/profile/businesses_page.dart';
import 'pages/profile/user_signature_page.dart';
import 'pages/profile/support_page.dart';
import 'pages/profile/change_password_page.dart';
import 'pages/profile/api_keys_page.dart';
import 'pages/profile/sessions_page.dart';
import 'pages/profile/marketing_page.dart';
import 'pages/profile/account_settings_page.dart';
import 'pages/profile/verification_page.dart';
import 'pages/profile/operator/operator_tickets_page.dart';
import 'pages/profile/announcements_page.dart';
import 'pages/system_settings_page.dart';
import 'pages/admin/storage_management_page.dart';
import 'pages/admin/system_configuration_page.dart';
import 'pages/admin/user_management_page.dart';
import 'pages/admin/system_logs_page.dart';
import 'pages/admin/email_settings_page.dart';
import 'pages/admin/redis_settings_page.dart';
import 'pages/admin/system_monitoring_page.dart';
import 'pages/admin/service_logs_page.dart';
import 'pages/admin/database_backup_page.dart';
import 'pages/admin/system_scripts_page.dart';
import 'pages/admin/announcements_admin_page.dart';
import 'pages/admin/businesses_list_page.dart';
import 'pages/admin/support_operators_page.dart';
import 'pages/admin/notification_moderation_queue_page.dart';
import 'pages/admin/notification_sms_pricing_page.dart';
import 'pages/business/business_shell.dart';
import 'pages/business/dashboard/business_dashboard_page.dart';
import 'pages/business/users_permissions_page.dart';
import 'pages/business/accounts_page.dart';
import 'pages/business/bank_accounts_page.dart';
import 'pages/business/wallet_page.dart';
import 'pages/business/wallet_payment_result_page.dart';
import 'pages/admin/wallet_settings_page.dart';
import 'pages/admin/payment_gateways_page.dart';
import 'pages/admin/storage_plans_admin_page.dart';
import 'pages/admin/document_monetization_page.dart';
import 'pages/admin/share_link_settings_page.dart';
import 'pages/admin/marketplace_plugins_admin_page.dart';
import 'pages/admin/wallet_payouts_admin_page.dart';
import 'pages/business/invoices_list_page.dart';
import 'pages/business/tax_workspace_page.dart';
import 'pages/business/new_invoice_page.dart';
import 'pages/business/edit_invoice_page.dart';
import 'pages/business/settings_page.dart';
import 'pages/business/business_info_settings_page.dart';
import 'pages/business/business_currencies_settings_page.dart';
import 'pages/business/reports_page.dart';
import 'pages/business/kardex_page.dart';
import 'pages/business/debtors_report_page.dart';
import 'pages/business/creditors_report_page.dart';
import 'pages/business/people_transactions_report_page.dart';
import 'pages/business/item_movements_report_page.dart';
import 'pages/business/sales_by_product_report_page.dart';
import 'pages/business/inventory_kardex_report_page.dart';
import 'pages/business/inventory_stock_report_page.dart';
import 'pages/business/stock_count_report_page.dart';
import 'pages/business/warehouse_documents_summary_report_page.dart';
import 'pages/business/slow_moving_items_report_page.dart';
import 'pages/business/critical_stock_report_page.dart';
import 'pages/business/inter_warehouse_transfers_report_page.dart';
import 'pages/business/adjustment_documents_report_page.dart';
import 'pages/business/warehouse_performance_report_page.dart';
import 'pages/business/product_movement_history_report_page.dart';
import 'pages/business/inventory_valuation_report_page.dart';
import 'pages/business/pending_documents_report_page.dart';
import 'pages/business/inventory_turnover_report_page.dart';
import 'pages/business/bank_accounts_turnover_report_page.dart';
import 'pages/business/cash_petty_turnover_report_page.dart';
import 'pages/business/activity_logs_page.dart';
import 'pages/business/daily_sales_report_page.dart';
import 'pages/business/monthly_sales_report_page.dart';
import 'pages/business/top_customers_report_page.dart';
import 'pages/business/daily_purchases_report_page.dart';
import 'pages/business/top_suppliers_report_page.dart';
import 'pages/business/materials_consumption_report_page.dart';
import 'pages/business/production_report_page.dart';
import 'pages/business/trial_balance_report_page.dart';
import 'pages/business/general_ledger_report_page.dart';
import 'pages/business/journal_ledger_report_page.dart';
import 'pages/business/pnl_period_report_page.dart';
import 'pages/business/pnl_cumulative_report_page.dart';
import 'pages/business/account_review_report_page.dart';
import 'pages/business/persons_page.dart';
import 'pages/business/product_attributes_page.dart';
import 'pages/business/products_page.dart';
import 'pages/business/projects_page.dart';
import 'pages/business/warranty_management_page.dart';
import 'pages/business/warranty_settings_page.dart';
import 'pages/business/repair_shop/repair_orders_list_page.dart';
import 'pages/business/repair_shop/repair_order_form_page.dart';
import 'pages/business/repair_shop/repair_order_detail_page.dart';
import 'pages/business/repair_shop/repair_technicians_page.dart';
import 'pages/business/repair_shop/repair_settings_page.dart';
import 'pages/business/notification_templates_page.dart';
import 'pages/business/notification_template_form_page.dart';
import 'pages/public/public_warranty_activation_page.dart';
import 'pages/public/public_warranty_tracking_page.dart';
import 'pages/business/price_lists_page.dart';
import 'pages/business/price_list_items_page.dart';
import 'pages/business/cash_registers_page.dart';
import 'pages/business/petty_cash_page.dart';
import 'pages/business/checks_page.dart';
import 'pages/business/plugin_marketplace_page.dart';
import 'pages/business/marketplace_invoices_page.dart';
import 'pages/business/check_form_page.dart';
import 'pages/business/check_reconciliation_page.dart';
import 'pages/business/receipts_payments_list_page.dart';
import 'pages/business/expense_income_list_page.dart';
import 'pages/business/transfers_page.dart';
import 'pages/business/documents_page.dart';
import 'pages/business/warehouses_page.dart';
import 'pages/warehouse/warehouse_docs_page.dart';
import 'pages/warehouse/warehouse_document_details_page.dart';
import 'pages/warehouse/stock_count_page.dart';
import 'pages/business/installments_report_page.dart';
import 'pages/business/credit_settings_page.dart';
import 'pages/business/quick_sales_settings_page.dart';
import 'pages/business/quick_sales_page.dart';
import 'pages/business/document_numbering_settings_page.dart';
import 'pages/business/print_settings_page.dart';
import 'pages/business/tax_settings_page.dart';
import 'pages/business/fiscal_year_settings_page.dart';
import 'pages/business/installment_plans_page.dart';
import 'pages/error_404_page.dart';
import 'core/locale_controller.dart';
import 'core/calendar_controller.dart';
import 'core/api_client.dart';
import 'theme/theme_controller.dart';
import 'theme/app_theme.dart';
import 'core/auth_store.dart';
import 'core/permission_guard.dart';
import 'core/keyboard_shortcut_listener.dart';
import 'core/route_registry.dart';
import 'widgets/simple_splash_screen.dart';
import 'widgets/url_tracker.dart';
import 'utils/route_prefetcher.dart';
import 'pages/business/opening_balance_page.dart';
import 'pages/business/year_end_closing_page.dart';
import 'pages/business/report_templates_page.dart';
import 'pages/business/storage_files_page.dart';
import 'pages/business/storage_file_manager_page.dart';
import 'pages/business/document_monetization_page.dart';
import 'pages/business/backup/backup_page.dart';
import 'pages/business/backup/restore_page.dart';
import 'pages/profile/delete_business_page.dart';
import 'pages/public/public_person_share_link_page.dart';
import 'pages/admin/ai_settings_page.dart';
import 'pages/admin/ai_plans_admin_page.dart';
import 'pages/admin/ai_prompts_admin_page.dart';
import 'pages/admin/tax_product_codes_page.dart';
import 'pages/admin/zohal_settings_page.dart';
import 'pages/admin/zohal_services_admin_page.dart';
import 'pages/admin/zohal_statistics_page.dart';
import 'pages/business/ai_subscription_page.dart';
import 'pages/business/ai_usage_page.dart';
import 'pages/business/zohal_inquiries_page.dart';
import 'pages/business/workflows_page.dart';
import 'pages/business/workflow_visual_editor_page.dart';
import 'pages/business/crm/crm_dashboard_page.dart';
import 'pages/business/crm/crm_process_definitions_page.dart';
import 'pages/business/crm/crm_leads_page.dart';
import 'pages/business/crm/crm_deals_page.dart';
import 'pages/business/crm/crm_activities_page.dart';
import 'pages/business/crm/crm_reports_page.dart';

void main() {
  // Use path-based routing instead of hash routing
  usePathUrlStrategy();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

// Global navigator key for accessing Navigator from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Route observer for pages that need to react when they become visible again (e.g. list refresh on return).
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

class _MyAppState extends State<MyApp> {
  LocaleController? _controller;
  CalendarController? _calendarController;
  ThemeController? _themeController;
  AuthStore? _authStore;
  bool _isLoading = true;
  DateTime? _loadStartTime;

  @override
  void initState() {
    super.initState();
    _loadStartTime = DateTime.now();
    _loadControllers();
  }

  Future<void> _loadControllers() async {
    // بارگذاری تمام کنترلرها
    final localeController = await LocaleController.load();
    final calendarController = await CalendarController.load();
    final themeController = ThemeController();
    await themeController.load();
    final authStore = AuthStore();
    // بایند کردن AuthStore قبل از load برای ارسال هدر Authorization در درخواست‌های اولیه
    ApiClient.bindAuthStore(authStore);
    await authStore.load();
    
    // تنظیم کنترلرها
    setState(() {
      _controller = localeController;
      _calendarController = calendarController;
      _themeController = themeController;
      _authStore = authStore;
    });
    
    // اضافه کردن listeners
    _controller!.addListener(() {
      ApiClient.setCurrentLocale(_controller!.locale);
      setState(() {});
    });
    
    _calendarController!.addListener(() {
      setState(() {});
    });
    
    _themeController!.addListener(() {
      setState(() {});
    });
    
    _authStore!.addListener(() {
      setState(() {});
    });
    
    // تنظیم API Client
    ApiClient.setCurrentLocale(_controller!.locale);
    ApiClient.bindCalendarController(_calendarController!);
    ApiClient.bindAuthStore(_authStore!);
    
    // Preload تمام صفحات برای جلوگیری از تاخیر در navigation
    // این کار باعث می‌شود کد تمام صفحات در bundle اصلی قرار گیرد
    // استفاده از Route Registry برای preload خودکار صفحات
    _preloadPages(authStore, localeController, calendarController, themeController);
    
    // همچنین صفحات از Route Registry را preload کن
    RouteRegistry().preloadAll();
    
    // اطمینان از حداقل 1 ثانیه نمایش splash screen
    final elapsed = DateTime.now().difference(_loadStartTime!);
    const minimumDuration = Duration(seconds: 1);
    if (elapsed < minimumDuration) {
      await Future.delayed(minimumDuration - elapsed);
    }
    
    // ذخیره URL فعلی قبل از اتمام loading
    if (_authStore != null) {
      try {
        final currentUrl = Uri.base.path;
        
        if (currentUrl.isNotEmpty && 
            currentUrl != '/' && 
            currentUrl != '/login' &&
            (currentUrl.startsWith('/user/profile/') || currentUrl.startsWith('/business/'))) {
          await _authStore!.saveLastUrl(currentUrl);
        }
      } catch (e) {
        // صرفاً لاگ برای خطای غیر بحرانی ذخیره آدرس - ignore error
        debugPrint('Error saving URL: $e');
      }
    }
    
    // اتمام loading
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
    
    // در Flutter Web، تمام صفحات به صورت eager load می‌شوند
    // (همه import شده‌اند) بنابراین کد تمام صفحات در bundle اولیه موجود است
    // این باعث می‌شود که تأخیر در جابجایی بین صفحات از بین برود
    RoutePrefetcher.initialize();
  }

  /// Preload تمام صفحات برای جلوگیری از تاخیر در navigation
  /// این کار باعث می‌شود کد تمام صفحات در bundle اصلی قرار گیرد
  void _preloadPages(
    AuthStore authStore,
    LocaleController localeController,
    CalendarController calendarController,
    ThemeController themeController,
  ) {
    try {
      // Preload Shell ها
      ProfileShell(
        authStore: authStore,
        localeController: localeController,
        calendarController: calendarController,
        themeController: themeController,
        child: const SizedBox(),
      );
      BusinessShell(
        businessId: 0,
        authStore: authStore,
        localeController: localeController,
        calendarController: calendarController,
        themeController: themeController,
        child: const SizedBox(),
      );
      
      // Preload صفحات Public
      PublicPersonShareLinkPage(code: 'preload');
      
      // Preload صفحات Login و Wallet
      LoginPage(
        localeController: localeController,
        calendarController: calendarController,
        themeController: themeController,
        authStore: authStore,
      );
      WalletPaymentResultPage(authStore: authStore);
      
      // Preload صفحات Profile
      ProfileDashboardPage(calendarController: calendarController);
      const AnnouncementsPage();
      NewBusinessPage(calendarController: calendarController);
      const BusinessesPage();
      SupportPage(calendarController: calendarController);
      MarketingPage(calendarController: calendarController);
      const UserSignaturePage();
      const ChangePasswordPage();
      UserNotificationsPage(calendarController: calendarController);
      OperatorTicketsPage(calendarController: calendarController);
      const SystemSettingsPage();
      const WalletSettingsPage();
      const PaymentGatewaysPage();
      const AdminStorageManagementPage();
      const SystemConfigurationPage();
      const ShareLinkSettingsPage();
      const UserManagementPage();
      const SystemLogsPage();
      const EmailSettingsPage();
      const AISettingsPage();
      const AIPlansAdminPage();
      const AIPromptsAdminPage();
      const AnnouncementsAdminPage();
      const NotificationsSettingsPage();
      const NotificationTemplatesAdminPage();
      const StoragePlansAdminPage();
      const DocumentMonetizationAdminPage();
      const BusinessesListPage();
      ZohalSettingsPage();
      ZohalServicesAdminPage();
      ZohalStatisticsPage();
      
      // Preload صفحات Business (با dummy businessId)
      const dummyBusinessId = 0;
      BusinessDashboardPage(
        businessId: dummyBusinessId,
        authStore: authStore,
        calendarController: calendarController,
      );
      UsersPermissionsPage(
        businessId: dummyBusinessId.toString(),
        authStore: authStore,
        calendarController: calendarController,
      );
      OpeningBalancePage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      AccountsPage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      BankAccountsPage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      PettyCashPage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      CashRegistersPage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      WalletPage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      AISubscriptionPage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      AIUsagePage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      ZohalInquiriesPage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      InvoicesListPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
        authStore: authStore,
        apiClient: ApiClient(),
      );
      TaxWorkspacePage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
        authStore: authStore,
        apiClient: ApiClient(),
      );
      NewInvoicePage(
        businessId: dummyBusinessId,
        authStore: authStore,
        calendarController: calendarController,
      );
      EditInvoicePage(
        businessId: dummyBusinessId,
        invoiceId: 0,
        authStore: authStore,
        calendarController: calendarController,
      );
      ReportsPage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      KardexPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
        initialPersonIds: [],
      );
      DebtorsReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      CreditorsReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      PeopleTransactionsReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      ItemMovementsReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      SalesByProductReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      InventoryKardexReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      BankAccountsTurnoverReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      CashPettyTurnoverReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      DailySalesReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      DailyPurchasesReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      MonthlySalesReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      TopCustomersReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      TopSuppliersReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      MaterialsConsumptionReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      ProductionReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      TrialBalanceReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      GeneralLedgerReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      PnlPeriodReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      PnlCumulativeReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      AccountReviewReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
      );
      SettingsPage(
        businessId: dummyBusinessId,
        localeController: localeController,
        calendarController: calendarController,
        themeController: themeController,
      );
      BusinessBackupPage(businessId: dummyBusinessId);
      BusinessRestorePage(businessId: dummyBusinessId);
      BusinessInfoSettingsPage(businessId: dummyBusinessId);
      CreditSettingsPage(businessId: dummyBusinessId);
      BusinessPrintSettingsPage(businessId: dummyBusinessId);
      InstallmentPlansPage(businessId: dummyBusinessId);
      DocumentMonetizationBusinessPage(businessId: dummyBusinessId);
      ProductAttributesPage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      ProductsPage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      PriceListsPage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      PriceListItemsPage(
        businessId: dummyBusinessId,
        priceListId: 0,
        authStore: authStore,
      );
      PersonsPage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      ReceiptsPaymentsListPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
        authStore: authStore,
        apiClient: ApiClient(),
      );
      InstallmentsReportPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
        apiClient: ApiClient(),
      );
      ExpenseIncomeListPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
        authStore: authStore,
        apiClient: ApiClient(),
      );
      TransfersPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
        authStore: authStore,
        apiClient: ApiClient(),
      );
      WarehousesPage(
        businessId: dummyBusinessId,
      );
      WarehouseDocsPage(
        businessId: dummyBusinessId,
      );
      DocumentsPage(
        businessId: dummyBusinessId,
        calendarController: calendarController,
        authStore: authStore,
        apiClient: ApiClient(),
      );
      StorageFilesPage(
        businessId: dummyBusinessId,
      );
      StorageFileManagerPage(
        businessId: dummyBusinessId,
      );
      ReportTemplatesPage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      PluginMarketplacePage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      MarketplaceInvoicesPage(
        businessId: dummyBusinessId,
        authStore: authStore,
      );
      ChecksPage(
        businessId: dummyBusinessId,
        authStore: authStore,
        calendarController: calendarController,
      );
      CheckFormPage(
        businessId: dummyBusinessId,
        authStore: authStore,
        calendarController: calendarController,
      );
      CheckReconciliationPage(
        businessId: dummyBusinessId,
        authStore: authStore,
        calendarController: calendarController,
      );
      
      // Preload صفحه Error
      const Error404Page();
    } catch (e) {
      // خطا در preload نباید برنامه را متوقف کند
      // فقط log می‌کنیم (در production می‌توانیم debug print کنیم)
      debugPrint('Error preloading pages: $e');
    }
  }

  // Root of application with GoRouter
  @override
  Widget build(BuildContext context) {
    
    // اگر هنوز loading است، splash screen نمایش بده
    if (_isLoading || 
        _controller == null || 
        _calendarController == null || 
        _themeController == null || 
        _authStore == null) {
      final loadingRouter = GoRouter(
        redirect: (context, state) {
          // در حین loading، هیچ redirect نکن - URL را حفظ کن
          return null;
        },
        routes: <RouteBase>[
          // برای تمام مسیرها splash screen نمایش بده
          GoRoute(
            path: '/:path(.*)',
            builder: (context, state) {
              // تشخیص نوع loading بر اساس controller های موجود
              String loadingMessage = 'Initializing...';
              if (_controller == null) {
                loadingMessage = 'Loading language settings...';
              } else if (_calendarController == null) {
                loadingMessage = 'Loading calendar settings...';
              } else if (_themeController == null) {
                loadingMessage = 'Loading theme settings...';
              } else if (_authStore == null) {
                loadingMessage = 'Loading authentication...';
              }
              
              // اگر controller موجود است، از locale آن استفاده کن
              if (_controller != null) {
                final isFa = _controller!.locale.languageCode == 'fa';
                if (isFa) {
                  if (_calendarController == null) {
                    loadingMessage = 'loadingCalendarSettings';
                  } else if (_themeController == null) {
                    loadingMessage = 'loadingThemeSettings';
                  } else if (_authStore == null) {
                    loadingMessage = 'loadingAuthentication';
                  } else {
                    loadingMessage = 'initializing';
                  }
                }
              }
              
              return Builder(
                builder: (context) {
                  final t = AppLocalizations.of(context);
                  String localizedMessage = loadingMessage;
                  
                  // تبدیل کلیدهای ترجمه به متن
                  switch (loadingMessage) {
                    case 'loadingLanguageSettings':
                      localizedMessage = t.loadingLanguageSettings;
                      break;
                    case 'loadingCalendarSettings':
                      localizedMessage = t.loadingCalendarSettings;
                      break;
                    case 'loadingThemeSettings':
                      localizedMessage = t.loadingThemeSettings;
                      break;
                    case 'loadingAuthentication':
                      localizedMessage = t.loadingAuthentication;
                      break;
                    case 'initializing':
                      localizedMessage = t.initializing;
                      break;
                    default:
                      localizedMessage = loadingMessage;
                  }
                  
                  return SimpleSplashScreen(
                    message: localizedMessage,
                    showLogo: true,
                    displayDuration: const Duration(seconds: 1),
                    locale: _controller?.locale,
                    authStore: _authStore,
                    onComplete: () {
                      // این callback زمانی فراخوانی می‌شود که splash screen تمام شود
                      // اما ما از splash controller استفاده می‌کنیم
                    },
                  );
                },
              );
            },
          ),
        ],
      );

      return MaterialApp.router(
        title: 'Hesabix',
        routerConfig: loadingRouter,
        locale: _controller?.locale ?? const Locale('fa'),
        supportedLocales: const [Locale('en'), Locale('fa')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
      );
    }

    final controller = _controller!;
    final themeController = _themeController!;

    // حفظ URL فعلی مرورگر هنگام سوئیچ از لودینگ به روتر اصلی
    final currentInitialLocation = () {
      final base = Uri.base;
      final path = base.path.isNotEmpty ? base.path : '/';
      final query = base.hasQuery ? '?${base.query}' : '';
      final fragment = base.fragment.isNotEmpty ? '#${base.fragment}' : '';
      return '$path$query$fragment';
    }();

    final router = GoRouter(
      navigatorKey: navigatorKey,
      observers: [routeObserver],
      initialLocation: currentInitialLocation,
      redirect: (context, state) async {
        final currentPath = state.uri.path;
        final isPublicRoute = currentPath.startsWith('/public');
        
        // اگر authStore هنوز load نشده، منتظر بمان
        if (_authStore == null) {
          return null;
        }
        
        final hasKey = _authStore!.apiKey != null && _authStore!.apiKey!.isNotEmpty;
        
        // اگر API key ندارد
        if (!hasKey) {
          if (isPublicRoute) {
            return null;
          }
          if (currentPath != '/login') {
            return '/login';
          }
          return null;
        }
        
        // اگر API key دارد
        
        // اگر در login است، به dashboard برود
        if (currentPath == '/login') {
          return '/user/profile/dashboard';
        }
        
        // اگر در root است، آخرین URL را بررسی کن
        if (currentPath == '/') {
          // اگر آخرین URL موجود است و معتبر است، به آن برود
          final lastUrl = await _authStore!.getLastUrl();
          
          if (lastUrl != null && 
              lastUrl.isNotEmpty && 
              lastUrl != '/' && 
              lastUrl != '/login' &&
              (lastUrl.startsWith('/user/profile/') || lastUrl.startsWith('/business/'))) {
            return lastUrl;
          }
          // وگرنه به dashboard برود (فقط اگر در root باشیم)
          return '/user/profile/dashboard';
        }
        
        // برای سایر صفحات (شامل صفحات profile و business)، redirect نکن (بماند)
        // این مهم است: اگر کاربر در صفحات profile یا business است، بماند
        // ذخیره مسیر فعلی به عنوان آخرین URL معتبر
        if (!isPublicRoute &&
            currentPath.isNotEmpty &&
            currentPath != '/' &&
            currentPath != '/login' &&
            (currentPath.startsWith('/user/profile/') || currentPath.startsWith('/business/'))) {
          try {
            await _authStore!.saveLastUrl(currentPath);
          } catch (e) {
            // صرفاً لاگ برای خطای غیر بحرانی ذخیره آدرس
          }
        }
        return null;
      },
      routes: <RouteBase>[
        GoRoute(
          path: '/public/person-link/:code',
          name: 'public_person_share_link',
          builder: (context, state) => PublicPersonShareLinkPage(
            code: state.pathParameters['code'] ?? '',
          ),
        ),
        GoRoute(
          path: '/public/warranty/activate/:business_id',
          name: 'public_warranty_activate',
          builder: (context, state) {
            final businessId = int.tryParse(state.pathParameters['business_id'] ?? '');
            if (businessId == null) {
              return const Scaffold(
                body: Center(child: Text('شناسه کسب و کار نامعتبر است')),
              );
            }
            return PublicWarrantyActivationPage(
              businessId: businessId,
            );
          },
        ),
        GoRoute(
          path: '/public/warranty/track',
          name: 'public_warranty_track',
          builder: (context, state) {
            final codeOrSerial = state.uri.queryParameters['code'];
            final linkCode = state.uri.queryParameters['link'];
            return PublicWarrantyTrackingPage(
              codeOrSerial: codeOrSerial,
              linkCode: linkCode,
            );
          },
        ),
        GoRoute(
          path: '/public/warranty/track/:code',
          name: 'public_warranty_track_code',
          builder: (context, state) {
            final code = state.pathParameters['code'] ?? '';
            return PublicWarrantyTrackingPage(
              codeOrSerial: code,
            );
          },
        ),
        GoRoute(
          path: '/public/warranty/track/link/:linkCode',
          name: 'public_warranty_track_link',
          builder: (context, state) {
            final linkCode = state.pathParameters['linkCode'] ?? '';
            return PublicWarrantyTrackingPage(
              linkCode: linkCode,
            );
          },
        ),
        GoRoute(
          path: '/login',
          name: 'login',
          builder: (context, state) {
            // ثبت صفحه برای preload خودکار
            registerRoutePage(() => LoginPage(
              localeController: controller,
              calendarController: _calendarController!,
              themeController: themeController,
              authStore: _authStore!,
            ));
            return LoginPage(
              localeController: controller,
              calendarController: _calendarController!,
              themeController: themeController,
              authStore: _authStore!,
            );
          },
        ),
        GoRoute(
          path: '/wallet/payment-result',
          name: 'wallet_payment_result',
          builder: (context, state) {
            // ثبت صفحه برای preload خودکار
            registerRoutePage(() => WalletPaymentResultPage(authStore: _authStore!));
            return WalletPaymentResultPage(authStore: _authStore!);
          },
        ),
        ShellRoute(
          builder: (context, state, child) => ProfileShell(
            authStore: _authStore!,
            localeController: controller,
            calendarController: _calendarController!,
            themeController: themeController,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/user/profile/dashboard',
              name: 'profile_dashboard',
              builder: (context, state) {
                // ثبت صفحه برای preload خودکار
                registerRoutePage(() => ProfileDashboardPage(calendarController: _calendarController!));
                return ProfileDashboardPage(calendarController: _calendarController!);
              },
            ),
            GoRoute(
              path: '/user/profile/announcements',
              name: 'profile_announcements',
              builder: (context, state) => const AnnouncementsPage(),
            ),
            GoRoute(
              path: '/user/profile/new-business',
              name: 'profile_new_business',
              builder: (context, state) => NewBusinessPage(calendarController: _calendarController!),
            ),
            GoRoute(
              path: '/user/profile/businesses',
              name: 'profile_businesses',
              builder: (context, state) => const BusinessesPage(),
            ),
            GoRoute(
              path: '/user/profile/support',
              name: 'profile_support',
              builder: (context, state) => SupportPage(calendarController: _calendarController),
            ),
            GoRoute(
              path: '/user/profile/account-settings',
              name: 'profile_account_settings',
              builder: (context, state) => AccountSettingsPage(
                calendarController: _calendarController!,
                authStore: _authStore!,
              ),
            ),
            GoRoute(
              path: '/user/profile/marketing',
              name: 'profile_marketing',
              builder: (context, state) => MarketingPage(calendarController: _calendarController!),
            ),
            GoRoute(
              path: '/user/profile/signature',
              name: 'profile_signature',
              builder: (context, state) => const UserSignaturePage(),
            ),
            GoRoute(
              path: '/user/profile/change-password',
              name: 'profile_change_password',
              builder: (context, state) => const ChangePasswordPage(),
            ),
            GoRoute(
              path: '/user/profile/verification',
              name: 'profile_verification',
              builder: (context, state) => const VerificationPage(),
            ),
            GoRoute(
              path: '/user/profile/api-keys',
              name: 'profile_api_keys',
              builder: (context, state) => ApiKeysPage(calendarController: _calendarController!),
            ),
            GoRoute(
              path: '/user/profile/sessions',
              name: 'profile_sessions',
              builder: (context, state) => const SessionsPage(),
            ),
            GoRoute(
              path: '/user/profile/notifications',
              name: 'profile_notifications',
              builder: (context, state) => UserNotificationsPage(calendarController: _calendarController!),
            ),
            GoRoute(
              path: '/user/profile/notification-history',
              name: 'profile_notification_history',
              builder: (context, state) => NotificationHistoryPage(calendarController: _calendarController!),
            ),
            GoRoute(
              path: '/user/profile/operator',
              name: 'profile_operator',
              builder: (context, state) {
                // بررسی دسترسی اپراتور پشتیبانی
                if (_authStore == null) {
                  return PermissionGuard.buildAccessDeniedPage();
                }
                
                if (!_authStore!.canAccessSupportOperator) {
                  return PermissionGuard.buildAccessDeniedPage();
                }
                return OperatorTicketsPage(calendarController: _calendarController);
              },
            ),
            GoRoute(
              path: '/user/profile/system-settings',
              name: 'profile_system_settings',
              builder: (context, state) {
                // بررسی دسترسی تنظیمات سیستم (SuperAdmin یا مجوز system_settings)
                if (_authStore == null) {
                  return PermissionGuard.buildAccessDeniedPage();
                }
                final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                if (!allowed) {
                  return PermissionGuard.buildAccessDeniedPage();
                }
                return const SystemSettingsPage();
              },
              routes: [
                GoRoute(
                  path: 'wallet',
                  name: 'system_settings_wallet',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const WalletSettingsPage();
                  },
                ),
                GoRoute(
                  path: 'wallet-payouts',
                  name: 'system_settings_wallet_payouts',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const WalletPayoutsAdminPage();
                  },
                ),
                GoRoute(
                  path: 'payment-gateways',
                  name: 'system_settings_payment_gateways',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const PaymentGatewaysPage();
                  },
                ),
                GoRoute(
                  path: 'storage',
                  name: 'system_settings_storage',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const AdminStorageManagementPage();
                  },
                ),
                GoRoute(
                  path: 'configuration',
                  name: 'system_settings_configuration',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const SystemConfigurationPage();
                  },
                ),
                GoRoute(
                  path: 'share-links',
                  name: 'system_settings_share_links',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const ShareLinkSettingsPage();
                  },
                ),
                GoRoute(
                  path: 'users',
                  name: 'system_settings_users',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const UserManagementPage();
                  },
                ),
                GoRoute(
                  path: 'support-operators',
                  name: 'system_settings_support_operators',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin;
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const SupportOperatorsPage();
                  },
                ),
                // Notification Moderation Queue
                GoRoute(
                  path: 'notification-moderation',
                  name: 'notification_moderation_queue',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin;
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const NotificationModerationQueuePage();
                  },
                ),
                // Notification SMS Pricing
                GoRoute(
                  path: 'notification-sms-pricing',
                  name: 'notification_sms_pricing',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const NotificationSmsPricingPage();
                  },
                ),
                GoRoute(
                  path: 'logs',
                  name: 'system_settings_logs',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const SystemLogsPage();
                  },
                ),
                GoRoute(
                  path: 'email',
                  name: 'system_settings_email',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const EmailSettingsPage();
                  },
                ),
                GoRoute(
                  path: 'ai-settings',
                  name: 'system_settings_ai_settings',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const AISettingsPage();
                  },
                ),
                GoRoute(
                  path: 'ai-plans',
                  name: 'system_settings_ai_plans',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const AIPlansAdminPage();
                  },
                ),
                GoRoute(
                  path: 'ai-prompts',
                  name: 'system_settings_ai_prompts',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const AIPromptsAdminPage();
                  },
                ),
                GoRoute(
                  path: 'announcements',
                  name: 'system_settings_announcements',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const AnnouncementsAdminPage();
                  },
                ),
                GoRoute(
                  path: 'notifications',
                  name: 'system_settings_notifications',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const NotificationsSettingsPage();
                  },
                ),
                GoRoute(
                  path: 'notification-templates',
                  name: 'system_settings_notification_templates',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const NotificationTemplatesAdminPage();
                  },
                ),
                GoRoute(
                  path: 'tax-product-codes',
                  name: 'system_settings_tax_product_codes',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const TaxProductCodesPage();
                  },
                ),
                GoRoute(
                  path: 'storage-plans',
                  name: 'system_settings_storage_plans',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const StoragePlansAdminPage();
                  },
                ),
                GoRoute(
                  path: 'marketplace-plugins',
                  name: 'system_settings_marketplace_plugins',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const MarketplacePluginsAdminPage();
                  },
                ),
                GoRoute(
                  path: 'document-monetization',
                  name: 'system_settings_document_monetization',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const DocumentMonetizationAdminPage();
                  },
                ),
                GoRoute(
                  path: 'zohal-settings',
                  name: 'system_settings_zohal_settings',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return ZohalSettingsPage();
                  },
                ),
                GoRoute(
                  path: 'zohal-services',
                  name: 'system_settings_zohal_services',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return ZohalServicesAdminPage();
                  },
                ),
                GoRoute(
                  path: 'zohal-statistics',
                  name: 'system_settings_zohal_statistics',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return ZohalStatisticsPage();
                  },
                ),
                GoRoute(
                  path: 'businesses',
                  name: 'system_settings_businesses',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin;
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const BusinessesListPage();
                  },
                ),
                GoRoute(
                  path: 'redis',
                  name: 'system_settings_redis',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const RedisSettingsPage();
                  },
                ),
                GoRoute(
                  path: 'monitoring',
                  name: 'system_settings_monitoring',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const SystemMonitoringPage();
                  },
                ),
                GoRoute(
                  path: 'service-logs',
                  name: 'system_settings_service_logs',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const ServiceLogsPage();
                  },
                ),
                GoRoute(
                  path: 'database-backup',
                  name: 'system_settings_database_backup',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const DatabaseBackupPage();
                  },
                ),
                GoRoute(
                  path: 'scripts',
                  name: 'system_settings_scripts',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin;
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const SystemScriptsPage();
                  },
                ),
              ],
            ),
          ],
        ),
        ShellRoute(
          builder: (context, state, child) {
            final businessId = int.parse(state.pathParameters['business_id']!);
            return BusinessShell(
              businessId: businessId,
              authStore: _authStore!,
              localeController: controller,
              calendarController: _calendarController!,
              themeController: themeController,
              child: child,
            );
          },
          routes: [
            GoRoute(
              path: '/business/:business_id/dashboard',
              name: 'business_dashboard',
              pageBuilder: (context, state) => NoTransitionPage(
                child: BusinessDashboardPage(
                  businessId: int.parse(state.pathParameters['business_id']!),
                  authStore: _authStore!,
                  calendarController: _calendarController!,
                ),
              ),
            ),
            GoRoute(
              path: '/business/:business_id/users-permissions',
              name: 'business_users_permissions',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: UsersPermissionsPage(
                    businessId: businessId.toString(),
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/opening-balance',
              name: 'business_opening_balance',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: OpeningBalancePage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/year-end-closing',
              name: 'business_year_end_closing',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: YearEndClosingPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/chart-of-accounts',
              name: 'business_chart_of_accounts',
              pageBuilder: (context, state) => NoTransitionPage(
                child: AccountsPage(
                  businessId: int.parse(state.pathParameters['business_id']!),
                  authStore: _authStore!,
                ),
              ),
            ),
            GoRoute(
              path: '/business/:business_id/accounts',
              name: 'business_accounts',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: BankAccountsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/petty-cash',
              name: 'business_petty_cash',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: PettyCashPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/cash-box',
              name: 'business_cash_box',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: CashRegistersPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/wallet',
              name: 'business_wallet',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: WalletPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/ai/subscription',
              name: 'business_ai_subscription',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: AISubscriptionPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/ai/usage',
              name: 'business_ai_usage',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: AIUsagePage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/zohal/inquiries',
              name: 'business_zohal_inquiries',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ZohalInquiriesPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/workflows/new',
              name: 'business_new_workflow',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                // workflow از extra می‌آید یا null است برای افزودن جدید
                final workflow = state.extra as Map<String, dynamic>?;
                return MaterialPage(
                  key: state.pageKey,
                  child: WorkflowVisualEditorPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    workflow: workflow,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/workflows/:workflow_id/edit',
              name: 'business_edit_workflow',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                // workflow از extra می‌آید
                final workflow = state.extra as Map<String, dynamic>?;
                return MaterialPage(
                  key: state.pageKey,
                  child: WorkflowVisualEditorPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    workflow: workflow,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/warranty',
              name: 'business_warranty',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: WarrantyManagementPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/warranty/settings',
              name: 'business_warranty_settings',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: WarrantySettingsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/repair-shop',
              name: 'business_repair_shop',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: RepairOrdersListPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/repair-shop/new',
              name: 'business_repair_shop_new',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: RepairOrderFormPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/repair-shop/:order_id',
              name: 'business_repair_shop_detail',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final orderId = int.parse(state.pathParameters['order_id']!);
                return NoTransitionPage(
                  child: RepairOrderDetailPage(
                    businessId: businessId,
                    orderId: orderId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/repair-shop-technicians',
              name: 'business_repair_shop_technicians',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: RepairTechniciansPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/repair-shop-settings',
              name: 'business_repair_shop_settings',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: RepairSettingsPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/notification-templates',
              name: 'business_notification_templates',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: NotificationTemplatesPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/notification-templates/new',
              name: 'business_notification_template_new',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: NotificationTemplateFormPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/notification-templates/:template_id/edit',
              name: 'business_notification_template_edit',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final templateId = int.parse(state.pathParameters['template_id']!);
                return NoTransitionPage(
                  child: NotificationTemplateFormPage(
                    businessId: businessId,
                    templateId: templateId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/workflows',
              name: 'business_workflows',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return MaterialPage(
                  key: state.pageKey,
                  child: WorkflowsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/crm',
              name: 'business_crm_dashboard',
              redirect: (context, state) => '/business/${state.pathParameters['business_id']}/crm/dashboard',
            ),
            GoRoute(
              path: '/business/:business_id/crm/dashboard',
              name: 'business_crm_dashboard_page',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return MaterialPage(
                  key: state.pageKey,
                  child: CrmDashboardPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/crm/process-definitions',
              name: 'business_crm_process_definitions',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return MaterialPage(
                  key: state.pageKey,
                  child: CrmProcessDefinitionsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/crm/leads',
              name: 'business_crm_leads',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return MaterialPage(
                  key: state.pageKey,
                  child: CrmLeadsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/crm/deals',
              name: 'business_crm_deals',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return MaterialPage(
                  key: state.pageKey,
                  child: CrmDealsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/crm/activities',
              name: 'business_crm_activities',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return MaterialPage(
                  key: state.pageKey,
                  child: CrmActivitiesPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/crm/reports',
              name: 'business_crm_reports',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return MaterialPage(
                  key: state.pageKey,
                  child: CrmReportsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/user/profile/system-settings/wallet',
              name: 'system_wallet_settings',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: WalletSettingsPage(),
              ),
            ),
            GoRoute(
              path: '/business/:business_id/invoice',
              name: 'business_invoice',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: InvoicesListPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                    routeObserver: routeObserver,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/tax-workspace',
              name: 'business_tax_workspace',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: TaxWorkspacePage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/invoice/new',
              name: 'business_new_invoice',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: NewInvoicePage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/invoice/:invoice_id/edit',
              name: 'business_edit_invoice',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final invoiceId = int.parse(state.pathParameters['invoice_id']!);
                return NoTransitionPage(
                  child: EditInvoicePage(
                    businessId: businessId,
                    invoiceId: invoiceId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports',
              name: 'business_reports',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ReportsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/kardex',
              name: 'business_reports_kardex',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                // Parse person_id(s) from query
                final qp = state.uri.queryParameters;
                final qpAll = state.uri.queryParametersAll;
                final Set<int> initialPersonIds = <int>{};
                final single = int.tryParse(qp['person_id'] ?? '');
                if (single != null) initialPersonIds.add(single);
                final multi = (qpAll['person_id'] ?? const <String>[]) 
                    .map((e) => int.tryParse(e))
                    .whereType<int>();
                initialPersonIds.addAll(multi);
                // Also parse from extra
                try {
                  if (state.extra is Map) {
                    final extra = state.extra as Map;
                    final list = extra['person_ids'];
                    if (list is List) {
                      for (final v in list) {
                        if (v is int) {
                          initialPersonIds.add(v);
                        } else {
                          final p = int.tryParse('$v');
                          if (p != null) {
                            initialPersonIds.add(p);
                          }
                        }
                      }
                    }
                  }
                } catch (_) {}
                return NoTransitionPage(
                  child: KardexPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    initialPersonIds: initialPersonIds.toList(),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/debtors',
              name: 'business_reports_debtors',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: DebtorsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/creditors',
              name: 'business_reports_creditors',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: CreditorsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/people-transactions',
              name: 'business_reports_people_transactions',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: PeopleTransactionsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/item-movements',
              name: 'business_reports_item_movements',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ItemMovementsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/sales-by-product',
              name: 'business_reports_sales_by_product',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: SalesByProductReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/inventory-kardex',
              name: 'business_reports_inventory_kardex',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: InventoryKardexReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/inventory-stock',
              name: 'business_reports_inventory_stock',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: InventoryStockReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/stock-count',
              name: 'business_reports_stock_count',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: StockCountReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/warehouse-documents-summary',
              name: 'business_reports_warehouse_documents_summary',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: WarehouseDocumentsSummaryReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/slow-moving-items',
              name: 'business_reports_slow_moving_items',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: SlowMovingItemsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/critical-stock',
              name: 'business_reports_critical_stock',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: CriticalStockReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/inter-warehouse-transfers',
              name: 'business_reports_inter_warehouse_transfers',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: InterWarehouseTransfersReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/adjustment-documents',
              name: 'business_reports_adjustment_documents',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: AdjustmentDocumentsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/warehouse-performance',
              name: 'business_reports_warehouse_performance',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: WarehousePerformanceReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/product-movement-history',
              name: 'business_reports_product_movement_history',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ProductMovementHistoryReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/inventory-valuation',
              name: 'business_reports_inventory_valuation',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: InventoryValuationReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/pending-documents',
              name: 'business_reports_pending_documents',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: PendingDocumentsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/inventory-turnover',
              name: 'business_reports_inventory_turnover',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: InventoryTurnoverReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/bank-accounts-turnover',
              name: 'business_reports_bank_accounts_turnover',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: BankAccountsTurnoverReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/cash-petty-turnover',
              name: 'business_reports_cash_petty_turnover',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: CashPettyTurnoverReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/daily-sales',
              name: 'business_reports_daily_sales',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: DailySalesReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/daily-purchases',
              name: 'business_reports_daily_purchases',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: DailyPurchasesReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/monthly-sales',
              name: 'business_reports_monthly_sales',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: MonthlySalesReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/top-customers',
              name: 'business_reports_top_customers',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: TopCustomersReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/top-suppliers',
              name: 'business_reports_top_suppliers',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: TopSuppliersReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/materials-consumption',
              name: 'business_reports_materials_consumption',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: MaterialsConsumptionReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/production',
              name: 'business_reports_production',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ProductionReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/trial-balance',
              name: 'business_reports_trial_balance',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: TrialBalanceReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/general-ledger',
              name: 'business_reports_general_ledger',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: GeneralLedgerReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/journal-ledger',
              name: 'business_reports_journal_ledger',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: JournalLedgerReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/pnl-period',
              name: 'business_reports_pnl_period',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: PnlPeriodReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/pnl-cumulative',
              name: 'business_reports_pnl_cumulative',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: PnlCumulativeReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/accounts-review',
              name: 'business_reports_accounts_review',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: AccountReviewReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/activity-logs',
              name: 'business_reports_activity_logs',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ActivityLogsPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings',
              name: 'business_settings',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                // گارد دسترسی: فقط کاربرانی که دسترسی join دارند
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: SettingsPage(
                    businessId: businessId,
                    localeController: controller,
                    calendarController: _calendarController!,
                    themeController: themeController,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings/backup',
              name: 'business_settings_backup',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return NoTransitionPage(child: PermissionGuard.buildAccessDeniedPage());
                }
                return NoTransitionPage(child: BusinessBackupPage(businessId: businessId));
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings/restore',
              name: 'business_settings_restore',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return NoTransitionPage(child: PermissionGuard.buildAccessDeniedPage());
                }
                return NoTransitionPage(child: BusinessRestorePage(businessId: businessId));
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings/delete',
              name: 'business_settings_delete',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                // فقط مالک می‌تواند حذف کند
                if (_authStore!.currentBusiness?.isOwner != true) {
                  return NoTransitionPage(child: PermissionGuard.buildAccessDeniedPage());
                }
                return NoTransitionPage(child: DeleteBusinessPage(businessId: businessId));
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings/business',
              name: 'business_settings_business',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: BusinessInfoSettingsPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings/currencies',
              name: 'business_settings_currencies',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'business')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: BusinessCurrenciesSettingsPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings/quick-sales',
              name: 'business_settings_quick_sales',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'business')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: QuickSalesSettingsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/quick-sales',
              name: 'business_quick_sales',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('invoices', 'add')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: QuickSalesPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings/credit',
              name: 'business_settings_credit',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: CreditSettingsPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings/document-numbering',
              name: 'business_settings_document_numbering',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: DocumentNumberingSettingsPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings/tax',
              name: 'business_settings_tax',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: TaxSettingsPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings/fiscal-year',
              name: 'business_settings_fiscal_year',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('fiscal_years', 'edit')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: FiscalYearSettingsPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings/print',
              name: 'business_settings_print',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: BusinessPrintSettingsPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings/installments',
              name: 'business_settings_installments',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: InstallmentPlansPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/document-monetization',
              name: 'business_document_monetization',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: DocumentMonetizationBusinessPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/product-attributes',
              name: 'business_product_attributes',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ProductAttributesPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/products',
              name: 'business_products',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ProductsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/price-lists',
              name: 'business_price_lists',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: PriceListsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/price-lists/:price_list_id/items',
              name: 'business_price_list_items',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final priceListId = int.parse(state.pathParameters['price_list_id']!);
                return NoTransitionPage(
                  child: PriceListItemsPage(
                    businessId: businessId,
                    priceListId: priceListId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/persons',
              name: 'business_persons',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: PersonsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/projects',
              name: 'business_projects',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ProjectsPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            // Receipts & Payments: list with data table
            GoRoute(
              path: '/business/:business_id/receipts-payments',
              name: 'business_receipts_payments',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ReceiptsPaymentsListPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            // Installments report
            GoRoute(
              path: '/business/:business_id/installments-report',
              name: 'business_installments_report',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: InstallmentsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/expense-income',
              name: 'business_expense_income',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ExpenseIncomeListPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/transfers',
              name: 'business_transfers',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: TransfersPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/warehouses',
              name: 'business_warehouses',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: WarehousesPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/warehouse-docs',
              name: 'business_warehouse_docs',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: WarehouseDocsPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/warehouse-docs/:doc_id',
              name: 'business_warehouse_doc_details',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final docId = int.parse(state.pathParameters['doc_id']!);
                return NoTransitionPage(
                  child: WarehouseDocumentDetailsPage(
                    businessId: businessId,
                    documentId: docId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/stock-count',
              name: 'business_stock_count',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final calendarController = ApiClient.getCalendarController();
                return NoTransitionPage(
                  child: StockCountPage(
                    businessId: businessId,
                    calendarController: calendarController,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/documents',
              name: 'business_documents',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: DocumentsPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/storage-files',
              name: 'business_storage_files',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: StorageFilesPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/storage-files/file-manager',
              name: 'business_storage_file_manager',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: StorageFileManagerPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/report-templates',
              name: 'business_report_templates',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ReportTemplatesPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/plugin-marketplace',
              name: 'business_plugin_marketplace',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                // گارد دسترسی مشاهده بازار
                if (!_authStore!.hasBusinessPermission('marketplace', 'view')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: PluginMarketplacePage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/plugin-marketplace/invoices',
              name: 'business_plugin_marketplace_invoices',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final allowed = _authStore!.hasBusinessPermission('marketplace', 'invoices') ||
                    _authStore!.hasBusinessPermission('marketplace', 'view');
                if (!allowed) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: MarketplaceInvoicesPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/checks',
              name: 'business_checks',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ChecksPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/checks/new',
              name: 'business_new_check',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: CheckFormPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/checks/:check_id/edit',
              name: 'business_edit_check',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final checkId = int.tryParse(state.pathParameters['check_id'] ?? '0');
                return NoTransitionPage(
                  child: CheckFormPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    checkId: checkId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/checks/reconciliation',
              name: 'business_checks_reconciliation',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: CheckReconciliationPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            // TODO: Add other business routes (sales, accounting, etc.)
          ],
        ),
        // صفحه 404 برای مسیرهای نامعتبر
        GoRoute(
          path: '/404',
          name: 'error_404',
          builder: (context, state) => const Error404Page(),
        ),
      ],
      errorBuilder: (context, state) => const Error404Page(),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([controller, themeController]),
      builder: (context, _) {
        return UrlTracker(
          authStore: _authStore!,
          child: MaterialApp.router(
            title: 'Hesabix',
            theme: AppTheme.build(
              isDark: false,
              locale: controller.locale,
              seed: themeController.seedColor,
            ),
            darkTheme: AppTheme.build(
              isDark: true,
              locale: controller.locale,
              seed: themeController.seedColor,
            ),
            themeMode: themeController.mode,
            routerConfig: router,
            locale: controller.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            builder: (context, child) {
              // KeyboardShortcutListener باید داخل MaterialApp باشد تا context معتبر داشته باشد
              return KeyboardShortcutListener(
                child: child ?? const SizedBox(),
              );
            },
          ),
        );
      },
    );
  }
}
