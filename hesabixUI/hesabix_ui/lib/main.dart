import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/hesabix_router_pages.dart';
import 'core/business_route_paths.dart';
import 'core/business_nav.dart';
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
import 'pages/profile/appearance_settings_page.dart';
import 'pages/profile/verification_page.dart';
import 'pages/profile/operator/operator_tickets_page.dart';
import 'pages/profile/announcements_page.dart';
import 'pages/system_settings_page.dart';
import 'pages/admin/storage_management_page.dart';
import 'pages/admin/system_configuration_page.dart';
import 'pages/admin/user_management_page.dart';
import 'pages/admin/email_settings_page.dart';
import 'pages/admin/redis_settings_page.dart';
import 'pages/admin/firewall_admin_page.dart';
import 'pages/admin/system_monitoring_page.dart';
import 'pages/admin/service_logs_page.dart';
import 'pages/admin/business_activity_logs_admin_page.dart';
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
import 'pages/admin/currencies_admin_page.dart';
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
import 'pages/business/fx_revaluation_settings_page.dart';
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
import 'pages/business/basalam_reports_pages.dart';
import 'pages/business/woocommerce_reports_pages.dart';
import 'pages/business/daily_sales_report_page.dart';
import 'pages/business/distribution_reports_dashboard_page.dart';
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
import 'pages/business/product_bulk_prices_sheet_page.dart';
import 'pages/business/projects_page.dart';
import 'pages/business/warranty_management_page.dart';
import 'pages/business/warranty_settings_page.dart';
import 'pages/business/repair_shop/repair_orders_list_page.dart';
import 'pages/business/repair_shop/repair_order_form_page.dart';
import 'pages/business/repair_shop/repair_order_detail_page.dart';
import 'pages/business/repair_shop/repair_technicians_page.dart';
import 'pages/business/repair_shop/repair_settings_page.dart';
import 'pages/business/customer_club/customer_club_main_page.dart';
import 'pages/business/customer_club/customer_club_settings_page.dart';
import 'pages/business/distribution/distribution_main_page.dart';
import 'pages/business/basalam/basalam_integration_page.dart';
import 'pages/business/basalam/basalam_settings_page.dart';
import 'pages/business/woocommerce/woocommerce_integration_page.dart';
import 'pages/business/woocommerce/woocommerce_opening_inventory_bridge_page.dart';
import 'pages/business/woocommerce/woocommerce_settings_page.dart';
import 'pages/business/notification_templates_page.dart';
import 'pages/business/notification_template_form_page.dart';
import 'pages/public/public_warranty_activation_page.dart';
import 'pages/public/public_warranty_tracking_page.dart';
import 'pages/business/price_lists_page.dart';
import 'pages/business/price_list_items_page.dart';
import 'pages/business/cash_registers_page.dart';
import 'pages/business/petty_cash_page.dart';
import 'pages/business/loan_facilities_page.dart';
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
import 'pages/business/warehouse_locations_page.dart';
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
import 'core/mobile_launcher_prefs.dart';
import 'core/permission_guard.dart';
import 'core/keyboard_shortcut_listener.dart';
import 'core/route_registry.dart';
import 'widgets/simple_splash_screen.dart';
import 'widgets/url_tracker.dart';
import 'widgets/user_activity_heartbeat.dart';
import 'utils/responsive_helper.dart';
import 'utils/route_prefetcher.dart';
import 'pages/business/opening_balance_page.dart';
import 'pages/business/year_end_closing_page.dart';
import 'pages/business/currency_revaluation_page.dart';
import 'pages/business/report_templates_page.dart';
import 'pages/business/storage_files_page.dart';
import 'pages/business/storage_file_manager_page.dart';
import 'pages/business/document_monetization_page.dart';
import 'pages/business/backup/backup_page.dart';
import 'pages/business/backup/business_ftp_backup_settings_page.dart';
import 'pages/business/backup/restore_page.dart';
import 'pages/mobile_launcher/mobile_launcher_page.dart';
import 'pages/mobile_launcher/mobile_launcher_shell.dart';
import 'pages/mobile_launcher/mobile_launcher_appearance_page.dart';
import 'pages/profile/delete_business_page.dart';
import 'pages/business/fiscal_year_rollback_page.dart';
import 'pages/public/public_person_share_link_page.dart';
import 'pages/public/public_invoice_share_link_page.dart';
import 'pages/public/public_storage_file_share_page.dart';
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
import 'pages/business/workflow_marketplace_page.dart';
import 'pages/business/workflow_visual_editor_page.dart';
import 'pages/business/crm/crm_dashboard_page.dart';
import 'pages/business/crm/crm_process_definitions_page.dart';
import 'pages/business/crm/crm_leads_page.dart';
import 'pages/business/crm/crm_deals_page.dart';
import 'pages/business/crm/crm_activities_page.dart';
import 'pages/business/crm/crm_reports_page.dart';
import 'pages/business/crm/crm_notes_calendar_page.dart';
import 'pages/business/crm/crm_web_chat_page.dart';
import 'pages/business/crm/business_crm_settings_page.dart';

void main() {
  // Use path-based routing instead of hash routing
  usePathUrlStrategy();
  // با push/replace؛ آدرس مرورگر باید آخرین صفحهٔ پشته را نشان دهد؛ وگرنه URL روی مسیر قبلی می‌ماند و دکمهٔ بازگشت درست عمل نمی‌کند.
  GoRouter.optionURLReflectsImperativeAPIs = true;
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
            (currentUrl.startsWith('/user/profile/') ||
                currentUrl.startsWith('/business/') ||
                currentUrl.startsWith('/mobile-launcher/'))) {
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
      ProfileDashboardPage(
        calendarController: calendarController,
        authStore: authStore,
      );
      const AnnouncementsPage();
      NewBusinessPage(calendarController: calendarController);
      const BusinessesPage();
      MobileLauncherHomePage(businessId: 1, authStore: authStore);
      MobileLauncherAppearancePage(businessId: 1, authStore: authStore);
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
        copyFromInvoiceId: null,
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
      DistributionReportsDashboardPage(
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
        final isShortPublicSharePath =
            currentPath.startsWith('/i/') || currentPath.startsWith('/p/');
        
        // اگر authStore هنوز load نشده، منتظر بمان
        if (_authStore == null) {
          return null;
        }
        
        final hasKey = _authStore!.apiKey != null && _authStore!.apiKey!.isNotEmpty;
        
        // اگر API key ندارد
        if (!hasKey) {
          if (isPublicRoute || isShortPublicSharePath) {
            return null;
          }
          if (currentPath != '/login') {
            return '/login';
          }
          return null;
        }
        
        // اگر API key دارد
        
        // اگر در login است، ترجیح لانچر یا داشبورد پروفایل
        if (currentPath == '/login') {
          final launcherLoc =
              await MobileLauncherPrefs.resumeHomeLocation(_authStore!.currentUserId);
          return launcherLoc ?? '/user/profile/dashboard';
        }

        // مسیرهای قدیمی پنل بدون segment «tabN» با StatefulShellRoute هم‌خوان نیستند؛ اینجا نرمال می‌شوند.
        if (currentPath.startsWith('/business/')) {
          final normalized = redirectLegacyBusinessPath(context, state);
          if (normalized != null) return normalized;
        }

        // اگر در root است؛ ابتدا لانچر موبایل در صورت فعال بودن، سپس آخرین URL
        if (currentPath == '/') {
          final launcherLoc =
              await MobileLauncherPrefs.resumeHomeLocation(_authStore!.currentUserId);
          if (launcherLoc != null) {
            return launcherLoc;
          }
          final lastUrl = await _authStore!.getLastUrl();
          
          if (lastUrl != null && 
              lastUrl.isNotEmpty && 
              lastUrl != '/' && 
              lastUrl != '/login' &&
              (lastUrl.startsWith('/user/profile/') ||
                  lastUrl.startsWith('/business/') ||
                  lastUrl.startsWith('/mobile-launcher/'))) {
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
            (currentPath.startsWith('/user/profile/') ||
                currentPath.startsWith('/business/') ||
                currentPath.startsWith('/mobile-launcher/'))) {
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
          path: '/public/invoice-link/:code',
          name: 'public_invoice_share_link',
          builder: (context, state) => PublicInvoiceShareLinkPage(
            code: state.pathParameters['code'] ?? '',
          ),
        ),
        GoRoute(
          path: '/i/:code',
          name: 'short_invoice_link_redirect',
          redirect: (context, state) {
            final c = state.pathParameters['code'] ?? '';
            if (c.isEmpty) {
              return '/';
            }
            return '/public/invoice-link/${Uri.encodeComponent(c)}';
          },
        ),
        GoRoute(
          path: '/public/storage-file/:token',
          name: 'public_storage_file_share',
          builder: (context, state) => PublicStorageFileSharePage(
            token: state.pathParameters['token'] ?? '',
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
        GoRoute(
          path: '/mobile-launcher/:businessId',
          name: 'mobile_launcher',
          redirect: (context, state) {
            final businessId = int.tryParse(state.pathParameters['businessId'] ?? '');
            if (businessId == null || businessId <= 0) return null;
            if (!ResponsiveHelper.isMobile(context)) {
              return '/business/$businessId/dashboard';
            }
            if (state.uri.path == '/mobile-launcher/$businessId') {
              return MobileLauncherPrefs.launcherHomePath(businessId);
            }
            return null;
          },
          routes: [
            ShellRoute(
              builder: (context, state, child) {
                final businessId = int.tryParse(state.pathParameters['businessId'] ?? '');
                if (businessId == null || businessId <= 0) {
                  return Scaffold(
                    body: Center(
                      child: Text(AppLocalizations.of(context).mobileLauncherInvalidBusiness),
                    ),
                  );
                }
                return MobileLauncherShell(
                  businessId: businessId,
                  authStore: _authStore!,
                  child: child,
                );
              },
              routes: [
                GoRoute(
                  path: 'home',
                  name: 'mobile_launcher_home',
                  builder: (context, state) {
                    final businessId = int.tryParse(state.pathParameters['businessId'] ?? '');
                    if (businessId == null || businessId <= 0) {
                      return Scaffold(
                        body: Center(
                          child: Text(AppLocalizations.of(context).mobileLauncherInvalidBusiness),
                        ),
                      );
                    }
                    registerRoutePage(
                      () => MobileLauncherHomePage(
                        businessId: businessId,
                        authStore: _authStore!,
                      ),
                    );
                    return MobileLauncherHomePage(
                      businessId: businessId,
                      authStore: _authStore!,
                    );
                  },
                ),
                GoRoute(
                  path: 'appearance',
                  name: 'mobile_launcher_appearance',
                  builder: (context, state) {
                    final businessId = int.tryParse(state.pathParameters['businessId'] ?? '');
                    if (businessId == null || businessId <= 0) {
                      return Scaffold(
                        body: Center(
                          child: Text(AppLocalizations.of(context).mobileLauncherInvalidBusiness),
                        ),
                      );
                    }
                    registerRoutePage(
                      () => MobileLauncherAppearancePage(
                        businessId: businessId,
                        authStore: _authStore!,
                      ),
                    );
                    return MobileLauncherAppearancePage(
                      businessId: businessId,
                      authStore: _authStore!,
                    );
                  },
                ),
                GoRoute(
                  path: 'quick-sales',
                  name: 'mobile_launcher_quick_sales',
                  pageBuilder: (context, state) {
                    final businessId = int.tryParse(state.pathParameters['businessId'] ?? '');
                    if (businessId == null || businessId <= 0) {
                      return hesabixNoTransitionPage(
                        state,
                        Scaffold(
                          body: Center(
                            child: Text(AppLocalizations.of(context).mobileLauncherInvalidBusiness),
                          ),
                        ),
                      );
                    }
                    if (!_authStore!.hasBusinessPermission('invoices', 'add')) {
                      return hesabixNoTransitionPage(
                        state,
                        PermissionGuard.buildAccessDeniedPage(),
                      );
                    }
                    final homePath = MobileLauncherPrefs.launcherHomePath(businessId);
                    registerRoutePage(
                      () => QuickSalesPage(
                        businessId: businessId,
                        authStore: _authStore!,
                        calendarController: _calendarController!,
                        mobileLauncherHomePath: homePath,
                      ),
                    );
                    return hesabixNoTransitionPage(
                      state,
                      QuickSalesPage(
                        businessId: businessId,
                        authStore: _authStore!,
                        calendarController: _calendarController!,
                        mobileLauncherHomePath: homePath,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
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
                registerRoutePage(
                  () => ProfileDashboardPage(
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                  ),
                );
                return ProfileDashboardPage(
                  calendarController: _calendarController!,
                  authStore: _authStore!,
                );
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
              path: '/user/profile/appearance-settings',
              name: 'profile_appearance_settings',
              builder: (context, state) => const AppearanceSettingsPage(),
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
                  pageBuilder: (context, state) {
                    if (_authStore == null) {
                      return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage());
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage());
                    }
                    return hesabixNoTransitionPage(state, const WalletSettingsPage());
                  },
                ),
                GoRoute(
                  path: 'currencies',
                  name: 'system_settings_currencies',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const CurrenciesAdminPage();
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
                    final allowed = _authStore!.isSuperAdmin ||
                        _authStore!.hasAppPermission('system_settings') ||
                        _authStore!.hasAppPermission('user_management');
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
                  path: 'firewall',
                  name: 'system_settings_firewall',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const FirewallAdminPage();
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
                  path: 'business-activity-logs',
                  name: 'system_settings_business_activity_logs',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const BusinessActivityLogsAdminPage();
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
        GoRoute(
          path: '/business/:business_id',
          redirect: redirectLegacyBusinessPath,
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (context, state, navigationShell) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return BusinessShell(
                  businessId: businessId,
                  authStore: _authStore!,
                  localeController: controller,
                  calendarController: _calendarController!,
                  themeController: themeController,
                  child: navigationShell,
                );
              },
              branches: [
                for (var i = 0; i < BusinessRoutePaths.tabBranchCount; i++)
                  StatefulShellBranch(
                    routes: [
                      GoRoute(
                        path: 'tab$i',
                        redirect: (context, state) {
                          final segs = state.uri.pathSegments;
                          if (segs.isNotEmpty && segs.last == 'tab$i') {
                            return '${state.uri.path}/dashboard';
                          }
                          return null;
                        },
                        routes: [
            GoRoute(
              path: 'dashboard',
              pageBuilder: (context, state) => hesabixNoTransitionPage(state, BusinessDashboardPage(
                  businessId: int.parse(state.pathParameters['business_id']!),
                  authStore: _authStore!,
                  calendarController: _calendarController!,
                ),
              ),
            ),
            GoRoute(
              path: 'users-permissions',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, UsersPermissionsPage(
                    businessId: businessId.toString(),
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'opening-balance',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, OpeningBalancePage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'year-end-closing',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, YearEndClosingPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'currency-revaluation',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, CurrencyRevaluationPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'chart-of-accounts',
              pageBuilder: (context, state) => hesabixNoTransitionPage(state, AccountsPage(
                  businessId: int.parse(state.pathParameters['business_id']!),
                  authStore: _authStore!,
                ),
              ),
            ),
            GoRoute(
              path: 'accounts',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, BankAccountsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'petty-cash',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, PettyCashPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'cash-box',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, CashRegistersPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'wallet',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, WalletPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'loan-facilities',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(
                  state,
                  LoanFacilitiesPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'ai/subscription',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, AISubscriptionPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'ai/usage',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, AIUsagePage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'zohal/inquiries',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, ZohalInquiriesPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'workflows/new',
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
              path: 'workflows/:workflow_id/edit',
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
              path: 'warranty',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, WarrantyManagementPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'warranty/settings',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, WarrantySettingsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'repair-shop',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, RepairOrdersListPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'repair-shop/new',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, RepairOrderFormPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'repair-shop/:order_id',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final orderId = int.parse(state.pathParameters['order_id']!);
                return hesabixNoTransitionPage(state, RepairOrderDetailPage(
                    businessId: businessId,
                    orderId: orderId,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'repair-shop-technicians',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, RepairTechniciansPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'repair-shop-settings',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, RepairSettingsPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'customer-club',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, CustomerClubMainPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'distribution',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, DistributionMainPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'basalam',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, BasalamIntegrationPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'woocommerce',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, WoocommerceIntegrationPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'woocommerce/opening-inventory',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final canWoo = _authStore!.hasBusinessPermission('woocommerce', 'view') ||
                    _authStore!.currentBusiness?.isOwner == true;
                if (!canWoo) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage());
                }
                return hesabixNoTransitionPage(
                  state,
                  WoocommerceOpeningInventoryBridgePage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'notification-templates',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, NotificationTemplatesPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'notification-templates/new',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, NotificationTemplateFormPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'notification-templates/:template_id/edit',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final templateId = int.parse(state.pathParameters['template_id']!);
                return hesabixNoTransitionPage(state, NotificationTemplateFormPage(
                    businessId: businessId,
                    templateId: templateId,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'workflows',
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
              path: 'workflows/marketplace',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return MaterialPage(
                  key: state.pageKey,
                  child: WorkflowMarketplacePage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'crm',
              redirect: (context, state) => '${BusinessRoutePaths.prefixFromRouterState(state)}/crm/dashboard',
            ),
            GoRoute(
              path: 'crm/dashboard',
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
              path: 'crm/process-definitions',
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
              path: 'crm/leads',
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
              path: 'crm/deals',
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
              path: 'crm/activities',
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
              path: 'crm/reports',
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
              path: 'crm/notes-calendar',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return MaterialPage(
                  key: state.pageKey,
                  child: CrmNotesCalendarPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'crm/web-chat',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return MaterialPage(
                  key: state.pageKey,
                  child: CrmWebChatPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: 'invoice',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, InvoicesListPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: 'tax-workspace',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, TaxWorkspacePage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: 'invoice/new',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final copyFromRaw = state.uri.queryParameters['copy_from'];
                final copyFromId =
                    copyFromRaw != null && copyFromRaw.trim().isNotEmpty
                        ? int.tryParse(copyFromRaw.trim())
                        : null;
                return hesabixNoTransitionPage(state, NewInvoicePage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                    copyFromInvoiceId: copyFromId,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'invoice/:invoice_id/edit',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final invoiceId = int.parse(state.pathParameters['invoice_id']!);
                return hesabixNoTransitionPage(state, EditInvoicePage(
                    businessId: businessId,
                    invoiceId: invoiceId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, ReportsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/kardex',
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
                return hesabixNoTransitionPage(state, KardexPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    initialPersonIds: initialPersonIds.toList(),
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/debtors',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, DebtorsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/creditors',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, CreditorsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/people-transactions',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, PeopleTransactionsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/item-movements',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, ItemMovementsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/sales-by-product',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, SalesByProductReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/inventory-kardex',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, InventoryKardexReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/inventory-stock',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, InventoryStockReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/stock-count',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, StockCountReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/warehouse-documents-summary',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, WarehouseDocumentsSummaryReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/slow-moving-items',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, SlowMovingItemsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/critical-stock',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, CriticalStockReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/inter-warehouse-transfers',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, InterWarehouseTransfersReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/adjustment-documents',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, AdjustmentDocumentsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/warehouse-performance',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, WarehousePerformanceReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/product-movement-history',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, ProductMovementHistoryReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/inventory-valuation',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, InventoryValuationReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/pending-documents',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, PendingDocumentsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/inventory-turnover',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, InventoryTurnoverReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/bank-accounts-turnover',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, BankAccountsTurnoverReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/cash-petty-turnover',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, CashPettyTurnoverReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/distribution-dashboard',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, DistributionReportsDashboardPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/daily-sales',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, DailySalesReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/daily-purchases',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, DailyPurchasesReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/monthly-sales',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, MonthlySalesReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/top-customers',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, TopCustomersReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/top-suppliers',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, TopSuppliersReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/materials-consumption',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, MaterialsConsumptionReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/production',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, ProductionReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/trial-balance',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, TrialBalanceReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/general-ledger',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, GeneralLedgerReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/journal-ledger',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, JournalLedgerReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/pnl-period',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, PnlPeriodReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/pnl-cumulative',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, PnlCumulativeReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/accounts-review',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, AccountReviewReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/activity-logs',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, ActivityLogsPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/basalam/overview',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, BasalamReportsOverviewPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/basalam/synced-invoices',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, BasalamSyncedInvoicesReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/basalam/dead-letter',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, BasalamDeadLetterReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/basalam/product-conflicts',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, BasalamProductConflictsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/woocommerce/overview',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, WooCommerceReportsOverviewPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/woocommerce/recent-orders',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, WooCommerceRecentOrdersReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/woocommerce/catalog',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, WooCommerceCatalogReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'reports/woocommerce/bridge-health',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, WooCommerceBridgeHealthReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'settings',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                // گارد دسترسی: فقط کاربرانی که دسترسی join دارند
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, SettingsPage(
                    businessId: businessId,
                    localeController: controller,
                    calendarController: _calendarController!,
                    themeController: themeController,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'settings/backup',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage());
                }
                return hesabixNoTransitionPage(state, BusinessBackupPage(businessId: businessId));
              },
            ),
            GoRoute(
              path: 'settings/ftp-backup',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage());
                }
                final isOwner = _authStore!.currentBusiness?.id == businessId &&
                    _authStore!.currentBusiness?.isOwner == true;
                final hasFtp = _authStore!.hasBusinessPermission('settings', 'manage_ftp');
                if (!isOwner && !hasFtp) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage());
                }
                return hesabixNoTransitionPage(state, BusinessFtpBackupSettingsPage(businessId: businessId));
              },
            ),
            GoRoute(
              path: 'settings/restore',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage());
                }
                return hesabixNoTransitionPage(state, BusinessRestorePage(businessId: businessId));
              },
            ),
            GoRoute(
              path: 'settings/delete',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                // فقط مالک می‌تواند حذف کند
                if (_authStore!.currentBusiness?.isOwner != true) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage());
                }
                return hesabixNoTransitionPage(state, DeleteBusinessPage(businessId: businessId));
              },
            ),
            GoRoute(
              path: 'settings/fiscal-year-rollback',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final isOwner = _authStore!.currentBusiness?.id == businessId &&
                    _authStore!.currentBusiness?.isOwner == true;
                final canRollback = isOwner || _authStore!.hasBusinessPermission('fiscal_years', 'rollback');
                if (!canRollback) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage());
                }
                return hesabixNoTransitionPage(state, FiscalYearRollbackPage(businessId: businessId));
              },
            ),
            GoRoute(
              path: 'settings/business',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, BusinessInfoSettingsPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: 'settings/currencies',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'business')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, BusinessCurrenciesSettingsPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: 'settings/fx-revaluation',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'business')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, FxRevaluationSettingsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'settings/quick-sales',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'business')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, QuickSalesSettingsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'quick-sales',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('invoices', 'add')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, QuickSalesPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'settings/credit',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, CreditSettingsPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: 'settings/crm',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.canReadSection('crm')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, BusinessCrmSettingsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: 'settings/basalam',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage());
                }
                final canBasalam =
                    _authStore!.hasBusinessPermission('basalam', 'view') ||
                    _authStore!.currentBusiness?.isOwner == true;
                if (!canBasalam) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage());
                }
                return hesabixNoTransitionPage(
                  state,
                  BasalamSettingsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'settings/woocommerce',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage());
                }
                final canWoo = _authStore!.hasBusinessPermission('woocommerce', 'view') ||
                    _authStore!.currentBusiness?.isOwner == true;
                if (!canWoo) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage());
                }
                return hesabixNoTransitionPage(
                  state,
                  WoocommerceSettingsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'settings/customer-club',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                final isOwner = _authStore!.currentBusiness?.id == businessId &&
                    _authStore!.currentBusiness?.isOwner == true;
                final canAccess = isOwner ||
                    _authStore!.hasBusinessPermission('customer_club', 'view') ||
                    _authStore!.hasBusinessPermission('customer_club', 'manage');
                if (!canAccess) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, CustomerClubSettingsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'settings/document-numbering',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, DocumentNumberingSettingsPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: 'settings/tax',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, TaxSettingsPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: 'settings/fiscal-year',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('fiscal_years', 'edit')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, FiscalYearSettingsPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: 'settings/print',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, BusinessPrintSettingsPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: 'settings/installments',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, InstallmentPlansPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: 'document-monetization',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, DocumentMonetizationBusinessPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: 'product-attributes',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, ProductAttributesPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'products/bulk-prices-sheet',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('products', 'view')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, ProductBulkPricesSheetPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'products',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, ProductsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'price-lists',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, PriceListsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'price-lists/:price_list_id/items',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final priceListId = int.parse(state.pathParameters['price_list_id']!);
                return hesabixNoTransitionPage(state, PriceListItemsPage(
                    businessId: businessId,
                    priceListId: priceListId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'persons',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, PersonsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'projects',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, ProjectsPage(
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
              path: 'receipts-payments',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, ReceiptsPaymentsListPage(
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
              path: 'installments-report',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, InstallmentsReportPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: 'expense-income',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, ExpenseIncomeListPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: 'transfers',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, TransfersPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: 'warehouses/:warehouse_id/locations',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final warehouseId = int.parse(state.pathParameters['warehouse_id']!);
                return hesabixNoTransitionPage(state, WarehouseLocationsPage(
                    businessId: businessId,
                    warehouseId: warehouseId,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'warehouses',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, WarehousesPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'warehouse-docs',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, WarehouseDocsPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'warehouse-docs/:doc_id',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final docId = int.parse(state.pathParameters['doc_id']!);
                return hesabixNoTransitionPage(state, WarehouseDocumentDetailsPage(
                    businessId: businessId,
                    documentId: docId,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'stock-count',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final calendarController = ApiClient.getCalendarController();
                return hesabixNoTransitionPage(state, StockCountPage(
                    businessId: businessId,
                    calendarController: calendarController,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'documents',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, DocumentsPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: 'storage-files',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, StorageFilesPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'storage-files/file-manager',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, StorageFileManagerPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'report-templates',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, ReportTemplatesPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'plugin-marketplace',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                // گارد دسترسی مشاهده بازار
                if (!_authStore!.hasBusinessPermission('marketplace', 'view')) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, PluginMarketplacePage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'plugin-marketplace/invoices',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final allowed = _authStore!.hasBusinessPermission('marketplace', 'invoices') ||
                    _authStore!.hasBusinessPermission('marketplace', 'view');
                if (!allowed) {
                  return hesabixNoTransitionPage(state, PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return hesabixNoTransitionPage(state, MarketplaceInvoicesPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'checks',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, ChecksPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'checks/new',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, CheckFormPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'checks/:check_id/edit',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final checkId = int.tryParse(state.pathParameters['check_id'] ?? '0');
                return hesabixNoTransitionPage(state, CheckFormPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    checkId: checkId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: 'checks/reconciliation',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return hesabixNoTransitionPage(state, CheckReconciliationPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),

                        ],
                      ),
                    ],
                  ),
              ],
            ),
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
          child: UserActivityHeartbeat(
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
          ),
        );
      },
    );
  }
}
