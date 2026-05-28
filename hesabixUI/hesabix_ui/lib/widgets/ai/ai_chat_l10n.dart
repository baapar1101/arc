import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';

/// برچسب ابزار AI از کلید l10n (هماهنگ با بک‌اند).
String aiToolLabel(AppLocalizations l10n, String toolName, {String? toolKey}) {
  final key = toolKey ?? _toolNameToKey(toolName);
  switch (key) {
    case 'aiToolGetBusinessInfo':
      return l10n.aiToolGetBusinessInfo;
    case 'aiToolSearchInvoices':
      return l10n.aiToolSearchInvoices;
    case 'aiToolGetInvoiceDetails':
      return l10n.aiToolGetInvoiceDetails;
    case 'aiToolGetInvoicesCount':
      return l10n.aiToolGetInvoicesCount;
    case 'aiToolCreateInvoice':
      return l10n.aiToolCreateInvoice;
    case 'aiToolSearchProducts':
      return l10n.aiToolSearchProducts;
    case 'aiToolGetProductInfo':
      return l10n.aiToolGetProductInfo;
    case 'aiToolGetInventoryStatus':
      return l10n.aiToolGetInventoryStatus;
    case 'aiToolGetProductKardex':
      return l10n.aiToolGetProductKardex;
    case 'aiToolGetCustomerInfo':
      return l10n.aiToolGetCustomerInfo;
    case 'aiToolSearchPersons':
      return l10n.aiToolSearchPersons;
    case 'aiToolGetPersonBalance':
      return l10n.aiToolGetPersonBalance;
    case 'aiToolCreatePerson':
      return l10n.aiToolCreatePerson;
    case 'aiToolUpdatePerson':
      return l10n.aiToolUpdatePerson;
    case 'aiToolGetFinancialSummary':
      return l10n.aiToolGetFinancialSummary;
    case 'aiToolGetDebtorsReport':
      return l10n.aiToolGetDebtorsReport;
    case 'aiToolGetCreditorsReport':
      return l10n.aiToolGetCreditorsReport;
    case 'aiToolSearchReceiptsPayments':
      return l10n.aiToolSearchReceiptsPayments;
    case 'aiToolCreateReceiptPayment':
      return l10n.aiToolCreateReceiptPayment;
    case 'aiToolGetSalesReport':
      return l10n.aiToolGetSalesReport;
    case 'aiToolGetPurchaseReport':
      return l10n.aiToolGetPurchaseReport;
    case 'aiToolGetInventoryValuation':
      return l10n.aiToolGetInventoryValuation;
    case 'aiToolGetCashFlow':
      return l10n.aiToolGetCashFlow;
    case 'aiToolSearchLeads':
      return l10n.aiToolSearchLeads;
    case 'aiToolGetLeadDetails':
      return l10n.aiToolGetLeadDetails;
    case 'aiToolSearchDeals':
      return l10n.aiToolSearchDeals;
    case 'aiToolGetDealDetails':
      return l10n.aiToolGetDealDetails;
    case 'aiToolSearchActivities':
      return l10n.aiToolSearchActivities;
    case 'aiToolGetCrmSummary':
      return l10n.aiToolGetCrmSummary;
    case 'aiToolGetPipelineReport':
      return l10n.aiToolGetPipelineReport;
    case 'aiToolGetLeadFunnelReport':
      return l10n.aiToolGetLeadFunnelReport;
    case 'aiToolInvokeConnector':
      return l10n.aiToolInvokeConnector;
    case 'aiToolQueryBusinessData':
      return l10n.aiToolQueryBusinessData;
    case 'aiToolSearchWarehouseDocuments':
      return l10n.aiToolSearchWarehouseDocuments;
    case 'aiToolGetWarehouseDocumentDetails':
      return l10n.aiToolGetWarehouseDocumentDetails;
    case 'aiToolListWarehouses':
      return l10n.aiToolListWarehouses;
    case 'aiToolGetWarehouseStockSummary':
      return l10n.aiToolGetWarehouseStockSummary;
    case 'aiToolSearchChecks':
      return l10n.aiToolSearchChecks;
    case 'aiToolGetCheckDetails':
      return l10n.aiToolGetCheckDetails;
    case 'aiToolSearchTransfers':
      return l10n.aiToolSearchTransfers;
    case 'aiToolSearchExpenseIncome':
      return l10n.aiToolSearchExpenseIncome;
    case 'aiToolSearchDocuments':
      return l10n.aiToolSearchDocuments;
    case 'aiToolGetDocumentDetails':
      return l10n.aiToolGetDocumentDetails;
    case 'aiToolListBankAccounts':
      return l10n.aiToolListBankAccounts;
    case 'aiToolListCashRegisters':
      return l10n.aiToolListCashRegisters;
    case 'aiToolListFiscalYears':
      return l10n.aiToolListFiscalYears;
    case 'aiToolGetCurrentFiscalYear':
      return l10n.aiToolGetCurrentFiscalYear;
    case 'aiToolGetBusinessDashboard':
      return l10n.aiToolGetBusinessDashboard;
    case 'aiToolGetPersonTransactions':
      return l10n.aiToolGetPersonTransactions;
    case 'aiToolSearchProjects':
      return l10n.aiToolSearchProjects;
    case 'aiToolGetProjectSummary':
      return l10n.aiToolGetProjectSummary;
    case 'aiToolListBoms':
      return l10n.aiToolListBoms;
    case 'aiToolGetBomDetails':
      return l10n.aiToolGetBomDetails;
    case 'aiToolSearchProductionDocuments':
      return l10n.aiToolSearchProductionDocuments;
    case 'aiToolSearchRepairOrders':
      return l10n.aiToolSearchRepairOrders;
    case 'aiToolGetRepairOrderDetails':
      return l10n.aiToolGetRepairOrderDetails;
    case 'aiToolGetTaxSettings':
      return l10n.aiToolGetTaxSettings;
    case 'aiToolSearchTaxWorkspace':
      return l10n.aiToolSearchTaxWorkspace;
    case 'aiToolGetTaxDataQuality':
      return l10n.aiToolGetTaxDataQuality;
    case 'aiToolListWorkflows':
      return l10n.aiToolListWorkflows;
    case 'aiToolListWorkflowExecutions':
      return l10n.aiToolListWorkflowExecutions;
    case 'aiToolListDistributionRoutes':
      return l10n.aiToolListDistributionRoutes;
    case 'aiToolSearchWarrantyCodes':
      return l10n.aiToolSearchWarrantyCodes;
    case 'aiToolListPettyCash':
      return l10n.aiToolListPettyCash;
    case 'aiToolGetCustomerClubSettings':
      return l10n.aiToolGetCustomerClubSettings;
    case 'aiToolListCustomerClubTiers':
      return l10n.aiToolListCustomerClubTiers;
    case 'aiToolListCustomerClubLedger':
      return l10n.aiToolListCustomerClubLedger;
    case 'aiToolGetCustomerClubRfmSummary':
      return l10n.aiToolGetCustomerClubRfmSummary;
    case 'aiToolSearchCustomerClubRfmPersons':
      return l10n.aiToolSearchCustomerClubRfmPersons;
    case 'aiToolGetQuickSalesSettings':
      return l10n.aiToolGetQuickSalesSettings;
    case 'aiToolListPriceLists':
      return l10n.aiToolListPriceLists;
    case 'aiToolSearchActivityLogs':
      return l10n.aiToolSearchActivityLogs;
    case 'aiToolGetOpeningBalance':
      return l10n.aiToolGetOpeningBalance;
    case 'aiToolGetBusinessCreditSettings':
      return l10n.aiToolGetBusinessCreditSettings;
    case 'aiToolListCreditInstallmentPlans':
      return l10n.aiToolListCreditInstallmentPlans;
    case 'aiToolGetPersonCredit':
      return l10n.aiToolGetPersonCredit;
    case 'aiToolListWooCommerceOrders':
      return l10n.aiToolListWooCommerceOrders;
    case 'aiToolListWooCommerceProducts':
      return l10n.aiToolListWooCommerceProducts;
    case 'aiToolListBasalamSyncedInvoices':
      return l10n.aiToolListBasalamSyncedInvoices;
    case 'aiToolListBasalamProductConflicts':
      return l10n.aiToolListBasalamProductConflicts;
    default:
      return _toolLabelFallbackFa[toolName] ?? l10n.aiToolGeneric;
  }
}

String _toolNameToKey(String name) {
  const map = {
    'get_business_info': 'aiToolGetBusinessInfo',
    'search_invoices': 'aiToolSearchInvoices',
    'get_invoice_details': 'aiToolGetInvoiceDetails',
    'get_invoices_count': 'aiToolGetInvoicesCount',
    'create_invoice': 'aiToolCreateInvoice',
    'search_products': 'aiToolSearchProducts',
    'get_product_info': 'aiToolGetProductInfo',
    'get_inventory_status': 'aiToolGetInventoryStatus',
    'get_product_kardex': 'aiToolGetProductKardex',
    'get_customer_info': 'aiToolGetCustomerInfo',
    'search_persons': 'aiToolSearchPersons',
    'get_person_balance': 'aiToolGetPersonBalance',
    'create_person': 'aiToolCreatePerson',
    'update_person': 'aiToolUpdatePerson',
    'get_financial_summary': 'aiToolGetFinancialSummary',
    'get_debtors_report': 'aiToolGetDebtorsReport',
    'get_creditors_report': 'aiToolGetCreditorsReport',
    'search_receipts_payments': 'aiToolSearchReceiptsPayments',
    'create_receipt_payment': 'aiToolCreateReceiptPayment',
    'get_sales_report': 'aiToolGetSalesReport',
    'get_purchase_report': 'aiToolGetPurchaseReport',
    'get_inventory_valuation': 'aiToolGetInventoryValuation',
    'get_cash_flow': 'aiToolGetCashFlow',
    'search_leads': 'aiToolSearchLeads',
    'get_lead_details': 'aiToolGetLeadDetails',
    'search_deals': 'aiToolSearchDeals',
    'get_deal_details': 'aiToolGetDealDetails',
    'search_activities': 'aiToolSearchActivities',
    'get_crm_summary': 'aiToolGetCrmSummary',
    'get_pipeline_report': 'aiToolGetPipelineReport',
    'get_lead_funnel_report': 'aiToolGetLeadFunnelReport',
    'invoke_business_connector': 'aiToolInvokeConnector',
    'query_business_data': 'aiToolQueryBusinessData',
    'search_warehouse_documents': 'aiToolSearchWarehouseDocuments',
    'get_warehouse_document_details': 'aiToolGetWarehouseDocumentDetails',
    'list_warehouses': 'aiToolListWarehouses',
    'get_warehouse_stock_summary': 'aiToolGetWarehouseStockSummary',
    'search_checks': 'aiToolSearchChecks',
    'get_check_details': 'aiToolGetCheckDetails',
    'search_transfers': 'aiToolSearchTransfers',
    'search_expense_income': 'aiToolSearchExpenseIncome',
    'search_documents': 'aiToolSearchDocuments',
    'get_document_details': 'aiToolGetDocumentDetails',
    'list_bank_accounts': 'aiToolListBankAccounts',
    'list_cash_registers': 'aiToolListCashRegisters',
    'list_fiscal_years': 'aiToolListFiscalYears',
    'get_current_fiscal_year': 'aiToolGetCurrentFiscalYear',
    'get_business_dashboard': 'aiToolGetBusinessDashboard',
    'get_person_transactions': 'aiToolGetPersonTransactions',
    'search_projects': 'aiToolSearchProjects',
    'get_project_summary': 'aiToolGetProjectSummary',
    'list_boms': 'aiToolListBoms',
    'get_bom_details': 'aiToolGetBomDetails',
    'search_production_documents': 'aiToolSearchProductionDocuments',
    'search_repair_orders': 'aiToolSearchRepairOrders',
    'get_repair_order_details': 'aiToolGetRepairOrderDetails',
    'get_tax_settings': 'aiToolGetTaxSettings',
    'search_tax_workspace': 'aiToolSearchTaxWorkspace',
    'get_tax_data_quality': 'aiToolGetTaxDataQuality',
    'list_workflows': 'aiToolListWorkflows',
    'list_workflow_executions': 'aiToolListWorkflowExecutions',
    'list_distribution_routes': 'aiToolListDistributionRoutes',
    'search_warranty_codes': 'aiToolSearchWarrantyCodes',
    'list_petty_cash': 'aiToolListPettyCash',
    'get_customer_club_settings': 'aiToolGetCustomerClubSettings',
    'list_customer_club_tiers': 'aiToolListCustomerClubTiers',
    'list_customer_club_ledger': 'aiToolListCustomerClubLedger',
    'get_customer_club_rfm_summary': 'aiToolGetCustomerClubRfmSummary',
    'search_customer_club_rfm_persons': 'aiToolSearchCustomerClubRfmPersons',
    'get_quick_sales_settings': 'aiToolGetQuickSalesSettings',
    'list_price_lists': 'aiToolListPriceLists',
    'search_activity_logs': 'aiToolSearchActivityLogs',
    'get_opening_balance': 'aiToolGetOpeningBalance',
    'get_business_credit_settings': 'aiToolGetBusinessCreditSettings',
    'list_credit_installment_plans': 'aiToolListCreditInstallmentPlans',
    'get_person_credit': 'aiToolGetPersonCredit',
    'list_woocommerce_orders': 'aiToolListWooCommerceOrders',
    'list_woocommerce_products': 'aiToolListWooCommerceProducts',
    'list_basalam_synced_invoices': 'aiToolListBasalamSyncedInvoices',
    'list_basalam_product_conflicts': 'aiToolListBasalamProductConflicts',
    'batch_query_business_data': 'aiToolBatchQueryBusinessData',
    'get_report': 'aiToolGetReport',
    'search_categories': 'aiToolSearchCategories',
    'list_person_groups': 'aiToolListPersonGroups',
    'list_currencies': 'aiToolListCurrencies',
    'delete_person': 'aiToolDeletePerson',
    'create_product': 'aiToolCreateProduct',
    'update_product': 'aiToolUpdateProduct',
    'create_check': 'aiToolCreateCheck',
    'create_transfer': 'aiToolCreateTransfer',
    'create_expense_income': 'aiToolCreateExpenseIncome',
    'update_invoice': 'aiToolUpdateInvoice',
    'delete_invoice': 'aiToolDeleteInvoice',
    'create_lead': 'aiToolCreateLead',
    'execute_workflow': 'aiToolExecuteWorkflow',
    'list_workflow_trigger_catalog': 'aiToolGeneric',
    'list_workflow_action_catalog': 'aiToolGeneric',
    'list_workflow_builtin_nodes': 'aiToolGeneric',
    'get_workflow_component_schema': 'aiToolGeneric',
    'get_workflow_design_rules': 'aiToolGeneric',
    'validate_workflow_draft': 'aiToolGeneric',
    'get_workflow': 'aiToolGeneric',
    'create_workflow': 'aiToolGeneric',
    'update_workflow': 'aiToolGeneric',
    'delete_workflow': 'aiToolGeneric',
    'test_workflow': 'aiToolGeneric',
    'get_workflow_execution_debug': 'aiToolGeneric',
    'poll_workflow_execution': 'aiToolGeneric',
    'export_business_data': 'aiToolExportBusinessData',
    'list_queryable_fields': 'aiToolListQueryableFields',
    'list_available_reports': 'aiToolListAvailableReports',
    'list_report_templates': 'aiToolListReportTemplates',
    'get_report_template': 'aiToolGetReportTemplate',
    'get_report_template_scope_catalog': 'aiToolGetReportTemplateScopeCatalog',
    'set_default_report_template': 'aiToolSetDefaultReportTemplate',
    'publish_report_template': 'aiToolPublishReportTemplate',
    'list_marketplace_plugins': 'aiToolListMarketplacePlugins',
    'list_business_plugins': 'aiToolListBusinessPlugins',
    'get_basalam_overview': 'aiToolGetBasalamOverview',
    'list_basalam_dead_letter': 'aiToolListBasalamDeadLetter',
    'adjust_customer_club_points': 'aiToolAdjustCustomerClubPoints',
    'recalculate_customer_club_rfm': 'aiToolRecalculateCustomerClubRfm',
    'update_customer_club_settings': 'aiToolUpdateCustomerClubSettings',
    'get_user_memory': 'aiToolGeneric',
    'update_user_memory': 'aiToolGeneric',
  };
  return map[name] ?? 'aiToolGeneric';
}

const _toolLabelFallbackFa = <String, String>{
  'batch_query_business_data': 'پرس‌وجوی دسته‌ای',
  'get_report': 'گزارش یکپارچه',
  'search_categories': 'جستجوی دسته‌بندی',
  'list_person_groups': 'گروه‌های اشخاص',
  'list_currencies': 'لیست ارزها',
  'delete_person': 'حذف شخص',
  'create_product': 'ایجاد کالا',
  'update_product': 'ویرایش کالا',
  'create_check': 'ثبت چک',
  'create_transfer': 'ثبت انتقال',
  'create_expense_income': 'ثبت هزینه/درآمد',
  'update_invoice': 'ویرایش فاکتور',
  'delete_invoice': 'حذف فاکتور',
  'create_lead': 'ایجاد سرنخ CRM',
    'execute_workflow': 'اجرای workflow',
    'list_workflow_trigger_catalog': 'کاتالوگ تریگرهای اتوماسیون',
    'list_workflow_action_catalog': 'کاتالوگ اکشن‌های اتوماسیون',
    'list_workflow_builtin_nodes': 'نودهای شرط و حلقه',
    'get_workflow_component_schema': 'schema جزء workflow',
    'get_workflow_design_rules': 'قوانین طراحی workflow',
    'validate_workflow_draft': 'اعتبارسنجی workflow',
    'get_workflow': 'دریافت workflow',
    'create_workflow': 'ایجاد اتوماسیون',
    'update_workflow': 'ویرایش اتوماسیون',
    'delete_workflow': 'حذف اتوماسیون',
    'test_workflow': 'تست اتوماسیون',
    'get_workflow_execution_debug': 'دیباگ اجرای workflow',
    'poll_workflow_execution': 'پیگیری اجرای workflow',
  'export_business_data': 'خروجی داده',
  'list_queryable_fields': 'فیلدهای قابل جستجو',
  'list_available_reports': 'فهرست گزارش‌های مجاز',
  'list_report_templates': 'لیست قالب گزارش',
  'get_report_template': 'جزئیات قالب گزارش',
  'get_report_template_scope_catalog': 'کاتالوگ scope قالب',
  'set_default_report_template': 'قالب پیش‌فرض',
  'publish_report_template': 'انتشار قالب گزارش',
  'list_marketplace_plugins': 'کاتالوگ افزونه‌ها',
  'list_business_plugins': 'افزونه‌های کسب‌وکار',
  'get_basalam_overview': 'خلاصه باسلام',
  'list_basalam_dead_letter': 'خطاهای باسلام',
  'adjust_customer_club_points': 'تنظیم امتیاز باشگاه',
  'recalculate_customer_club_rfm': 'محاسبه مجدد RFM',
  'update_customer_club_settings': 'تنظیمات باشگاه مشتری',
  'get_user_memory': 'خواندن حافظه دستیار',
  'update_user_memory': 'به‌روزرسانی حافظه دستیار',
};

/// متن وضعیت استریم AI از phase/step.
String aiStreamStatusLabel(
  AppLocalizations l10n, {
  required String phase,
  String? step,
  String? toolKey,
  String? toolName,
  int? iteration,
  int? maxIterations,
}) {
  if (phase == 'agent_progress' &&
      iteration != null &&
      maxIterations != null) {
    return l10n.aiStatusAgentProgress(iteration, maxIterations);
  }
  switch (phase) {
    case 'sending':
      return l10n.aiStatusSending;
    case 'connecting':
      return l10n.aiStatusConnecting;
    case 'thinking':
      return l10n.aiStatusThinking;
    case 'planning_tools':
      return l10n.aiStatusPlanningTools;
    case 'writing':
      return l10n.aiStatusWriting;
    case 'saving':
      return l10n.aiStatusSaving;
    case 'agent_progress':
      if (step != null && step.contains('/')) {
        final parts = step.split('/');
        final it = int.tryParse(parts.first);
        final mx = int.tryParse(parts.length > 1 ? parts[1] : '');
        if (it != null && mx != null) {
          return l10n.aiStatusAgentProgress(it, mx);
        }
      }
      return l10n.aiStatusThinking;
    case 'running_tool':
      final label = aiToolLabel(
        l10n,
        toolName ?? '',
        toolKey: toolKey,
      );
      return l10n.aiStatusRunningTool(label);
    case 'preparing_context':
      switch (step) {
        case 'loading_prompt':
          return l10n.aiStatusLoadingPrompt;
        case 'loading_insights':
          return l10n.aiStatusLoadingInsights;
        case 'loading_memory':
          return l10n.aiStatusLoadingMemory;
        case 'loading_attachments':
          return l10n.aiStatusLoadingAttachments;
        case 'loading_knowledge':
          return l10n.aiStatusLoadingKnowledge;
        case 'loading_connectors':
          return l10n.aiStatusLoadingConnectors;
        default:
          return l10n.aiStatusPreparingContext;
      }
    default:
      return l10n.aiStatusThinking;
  }
}

/// عنوان گام trace از کلید l10n.
String aiTraceStepTitle(AppLocalizations l10n, AIAgentTraceStep step) {
  final params = step.titleParams ?? {};
  switch (step.titleKey) {
    case 'aiTracePlanningAction':
      return l10n.aiTracePlanningAction;
    case 'aiTracePlanningNext':
      return l10n.aiTracePlanningNext;
    case 'aiTraceRetrying':
      return l10n.aiTraceRetrying(
        params['attempt'] as String? ?? '1',
        params['max'] as String? ?? '3',
      );
    case 'aiTraceNeedMoreExploration':
      return l10n.aiTraceNeedMoreExploration;
    case 'aiTraceRunningTool':
      final name = params['toolName'] as String? ??
          aiToolLabel(l10n, step.tool ?? '', toolKey: step.toolKey);
      return l10n.aiTraceRunningTool(name);
    case 'aiTraceObservation':
      final name = params['toolName'] as String? ??
          aiToolLabel(l10n, step.tool ?? '', toolKey: step.toolKey);
      return l10n.aiTraceObservation(name);
    case 'aiTraceComposingAnswer':
      return l10n.aiTraceComposingAnswer;
    case 'aiTraceExploring':
      return l10n.aiTraceExploring;
    case 'aiTraceExploringDone':
      return l10n.aiTraceExploringDone;
    case 'aiTraceExploringTarget':
      return l10n.aiTraceExploringTarget(
        params['target'] as String? ?? step.exploreTarget ?? '…',
      );
    case 'aiTraceExploredTarget':
      return l10n.aiTraceExploredTarget(
        params['target'] as String? ?? step.exploreTarget ?? '…',
      );
    case 'aiTraceExplored':
      return l10n.aiTraceExplored(
        params['title'] as String? ?? '…',
        params['count'] as String? ?? '${step.resultCount ?? 0}',
      );
    case 'aiTraceThought':
      return l10n.aiTraceThought(
        params['count'] as String? ?? '${step.findingsCount ?? 0}',
      );
    case 'aiStatusThinking':
      return l10n.aiStatusThinking;
    case 'aiStatusLoadingPrompt':
      return l10n.aiStatusLoadingPrompt;
    case 'aiStatusLoadingInsights':
      return l10n.aiStatusLoadingInsights;
    case 'aiStatusLoadingMemory':
      return l10n.aiStatusLoadingMemory;
    case 'aiStatusLoadingAttachments':
      return l10n.aiStatusLoadingAttachments;
    case 'aiStatusLoadingKnowledge':
      return l10n.aiStatusLoadingKnowledge;
    case 'aiStatusLoadingConnectors':
      return l10n.aiStatusLoadingConnectors;
    case 'aiStatusPreparingContext':
      return l10n.aiStatusPreparingContext;
    default:
      if (step.kind == 'narrative') {
        return l10n.aiStatusThinking;
      }
      if (step.kind == 'plan') {
        return l10n.aiTracePlanningAction;
      }
      if (step.kind == 'explore') {
        return step.exploreTarget != null
            ? l10n.aiTraceExploringTarget(step.exploreTarget!)
            : l10n.aiTraceExploring;
      }
      if (step.kind == 'explored') {
        return l10n.aiTraceExplored('…', '${step.resultCount ?? 0}');
      }
      if (step.kind == 'thought') {
        return l10n.aiTraceThought('${step.findingsCount ?? 0}');
      }
      if (step.tool != null) {
        return aiToolLabel(l10n, step.tool!, toolKey: step.toolKey);
      }
      return l10n.aiStatusThinking;
  }
}
