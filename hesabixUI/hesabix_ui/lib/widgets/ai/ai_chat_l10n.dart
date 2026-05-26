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
    default:
      return l10n.aiToolGeneric;
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
  };
  return map[name] ?? 'aiToolGeneric';
}

/// متن وضعیت استریم AI از phase/step.
String aiStreamStatusLabel(
  AppLocalizations l10n, {
  required String phase,
  String? step,
  String? toolKey,
  String? toolName,
}) {
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
      if (step.tool != null) {
        return aiToolLabel(l10n, step.tool!, toolKey: step.toolKey);
      }
      return l10n.aiStatusThinking;
  }
}
