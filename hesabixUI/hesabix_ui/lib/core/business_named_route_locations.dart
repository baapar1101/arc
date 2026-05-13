import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'business_nav.dart';
import 'business_route_paths.dart';

/// الگوی مسیر نسبی (بدون business id و بدون tab) برای نام مسیرهای go_router قبلی.
abstract final class BusinessNamedRoutes {
  static const Map<String, String> _suffixByName = {
    'business_dashboard': 'dashboard',
    'business_users_permissions': 'users-permissions',
    'business_opening_balance': 'opening-balance',
    'business_year_end_closing': 'year-end-closing',
    'business_currency_revaluation': 'currency-revaluation',
    'business_chart_of_accounts': 'chart-of-accounts',
    'business_accounts': 'accounts',
    'business_petty_cash': 'petty-cash',
    'business_cash_box': 'cash-box',
    'business_wallet': 'wallet',
    'business_ai_subscription': 'ai/subscription',
    'business_ai_usage': 'ai/usage',
    'business_zohal_inquiries': 'zohal/inquiries',
    'business_new_workflow': 'workflows/new',
    'business_edit_workflow': 'workflows/:workflow_id/edit',
    'business_warranty': 'warranty',
    'business_warranty_settings': 'warranty/settings',
    'business_repair_shop': 'repair-shop',
    'business_repair_shop_new': 'repair-shop/new',
    'business_repair_shop_detail': 'repair-shop/:order_id',
    'business_repair_shop_technicians': 'repair-shop-technicians',
    'business_repair_shop_settings': 'repair-shop-settings',
    'business_customer_club': 'customer-club',
    'business_distribution': 'distribution',
    'business_notification_templates': 'notification-templates',
    'business_notification_template_new': 'notification-templates/new',
    'business_notification_template_edit': 'notification-templates/:template_id/edit',
    'business_workflows': 'workflows',
    'business_workflow_marketplace': 'workflows/marketplace',
    'business_crm_dashboard': 'crm',
    'business_crm_dashboard_page': 'crm/dashboard',
    'business_crm_process_definitions': 'crm/process-definitions',
    'business_crm_leads': 'crm/leads',
    'business_crm_deals': 'crm/deals',
    'business_crm_activities': 'crm/activities',
    'business_crm_reports': 'crm/reports',
    'business_crm_notes_calendar': 'crm/notes-calendar',
    'business_crm_web_chat': 'crm/web-chat',
    'business_invoice': 'invoice',
    'business_tax_workspace': 'tax-workspace',
    'business_new_invoice': 'invoice/new',
    'business_edit_invoice': 'invoice/:invoice_id/edit',
    'business_reports': 'reports',
    'business_reports_kardex': 'reports/kardex',
    'business_reports_debtors': 'reports/debtors',
    'business_reports_creditors': 'reports/creditors',
    'business_reports_people_transactions': 'reports/people-transactions',
    'business_reports_item_movements': 'reports/item-movements',
    'business_reports_sales_by_product': 'reports/sales-by-product',
    'business_reports_inventory_kardex': 'reports/inventory-kardex',
    'business_reports_inventory_stock': 'reports/inventory-stock',
    'business_reports_stock_count': 'reports/stock-count',
    'business_reports_warehouse_documents_summary': 'reports/warehouse-documents-summary',
    'business_reports_slow_moving_items': 'reports/slow-moving-items',
    'business_reports_critical_stock': 'reports/critical-stock',
    'business_reports_inter_warehouse_transfers': 'reports/inter-warehouse-transfers',
    'business_reports_adjustment_documents': 'reports/adjustment-documents',
    'business_reports_warehouse_performance': 'reports/warehouse-performance',
    'business_reports_product_movement_history': 'reports/product-movement-history',
    'business_reports_inventory_valuation': 'reports/inventory-valuation',
    'business_reports_pending_documents': 'reports/pending-documents',
    'business_reports_inventory_turnover': 'reports/inventory-turnover',
    'business_reports_bank_accounts_turnover': 'reports/bank-accounts-turnover',
    'business_reports_cash_petty_turnover': 'reports/cash-petty-turnover',
    'business_reports_distribution_dashboard': 'reports/distribution-dashboard',
    'business_reports_daily_sales': 'reports/daily-sales',
    'business_reports_daily_purchases': 'reports/daily-purchases',
    'business_reports_monthly_sales': 'reports/monthly-sales',
    'business_reports_top_customers': 'reports/top-customers',
    'business_reports_top_suppliers': 'reports/top-suppliers',
    'business_reports_materials_consumption': 'reports/materials-consumption',
    'business_reports_production': 'reports/production',
    'business_reports_trial_balance': 'reports/trial-balance',
    'business_reports_general_ledger': 'reports/general-ledger',
    'business_reports_journal_ledger': 'reports/journal-ledger',
    'business_reports_pnl_period': 'reports/pnl-period',
    'business_reports_pnl_cumulative': 'reports/pnl-cumulative',
    'business_reports_accounts_review': 'reports/accounts-review',
    'business_reports_activity_logs': 'reports/activity-logs',
    'business_reports_basalam_overview': 'reports/basalam/overview',
    'business_reports_basalam_synced_invoices': 'reports/basalam/synced-invoices',
    'business_reports_basalam_dead_letter': 'reports/basalam/dead-letter',
    'business_reports_basalam_product_conflicts': 'reports/basalam/product-conflicts',
    'business_reports_woocommerce_overview': 'reports/woocommerce/overview',
    'business_reports_woocommerce_recent_orders': 'reports/woocommerce/recent-orders',
    'business_reports_woocommerce_catalog': 'reports/woocommerce/catalog',
    'business_reports_woocommerce_bridge_health': 'reports/woocommerce/bridge-health',
    'business_basalam': 'basalam',
    'business_woocommerce': 'woocommerce',
    'business_settings': 'settings',
    'business_settings_backup': 'settings/backup',
    'business_settings_ftp_backup': 'settings/ftp-backup',
    'business_settings_restore': 'settings/restore',
    'business_settings_delete': 'settings/delete',
    'business_settings_fiscal_year_rollback': 'settings/fiscal-year-rollback',
    'business_settings_business': 'settings/business',
    'business_settings_currencies': 'settings/currencies',
    'business_settings_fx_revaluation': 'settings/fx-revaluation',
    'business_settings_quick_sales': 'settings/quick-sales',
    'business_quick_sales': 'quick-sales',
    'business_settings_credit': 'settings/credit',
    'business_settings_crm': 'settings/crm',
    'business_settings_customer_club': 'settings/customer-club',
    'business_settings_document_numbering': 'settings/document-numbering',
    'business_settings_tax': 'settings/tax',
    'business_settings_fiscal_year': 'settings/fiscal-year',
    'business_settings_print': 'settings/print',
    'business_settings_installments': 'settings/installments',
    'business_document_monetization': 'document-monetization',
    'business_product_attributes': 'product-attributes',
    'business_product_bulk_prices_sheet': 'products/bulk-prices-sheet',
    'business_products': 'products',
    'business_price_lists': 'price-lists',
    'business_price_list_items': 'price-lists/:price_list_id/items',
    'business_persons': 'persons',
    'business_projects': 'projects',
    'business_receipts_payments': 'receipts-payments',
    'business_installments_report': 'installments-report',
    'business_expense_income': 'expense-income',
    'business_transfers': 'transfers',
    'business_warehouse_locations': 'warehouses/:warehouse_id/locations',
    'business_warehouses': 'warehouses',
    'business_warehouse_docs': 'warehouse-docs',
    'business_warehouse_doc_details': 'warehouse-docs/:doc_id',
    'business_stock_count': 'stock-count',
    'business_documents': 'documents',
    'business_storage_files': 'storage-files',
    'business_storage_file_manager': 'storage-files/file-manager',
    'business_report_templates': 'report-templates',
    'business_plugin_marketplace': 'plugin-marketplace',
    'business_plugin_marketplace_invoices': 'plugin-marketplace/invoices',
    'business_checks': 'checks',
    'business_new_check': 'checks/new',
    'business_edit_check': 'checks/:check_id/edit',
    'business_checks_reconciliation': 'checks/reconciliation'
  };

  static String fillTemplate(String template, Map<String, String> params) {
    var out = template;
    params.forEach((key, value) {
      if (key == 'business_id') return;
      out = out.replaceAll(':' + key, Uri.encodeComponent(value));
    });
    return out;
  }

  static Uri uri({
    required int businessId,
    required int tabSlot,
    required String routeName,
    Map<String, String> pathParameters = const {},
    Map<String, dynamic>? queryParameters,
  }) {
    final tpl = _suffixByName[routeName];
    if (tpl == null) {
      throw ArgumentError.value(routeName, 'routeName', 'Unknown business route name');
    }
    final filled = fillTemplate(tpl, pathParameters);
    final path = BusinessRoutePaths.uri(businessId, tabSlot, filled);
    final q = queryParameters == null
        ? null
        : Map<String, String>.fromEntries(
            queryParameters.entries.map((e) => MapEntry(e.key.toString(), e.value?.toString() ?? '')),
          );
    return Uri(path: path, queryParameters: q);
  }

  static void goNamed(
    BuildContext context, {
    required int businessId,
    required String routeName,
    Map<String, String> pathParameters = const {},
    Map<String, dynamic>? queryParameters,
    Object? extra,
  }) {
    final slot = context.businessTabSlot(businessId);
    final u = uri(
      businessId: businessId,
      tabSlot: slot,
      routeName: routeName,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
    );
    GoRouter.of(context).go(u.toString(), extra: extra);
  }

  static Future<T?> pushNamed<T extends Object?>(
    BuildContext context, {
    required int businessId,
    required String routeName,
    Map<String, String> pathParameters = const {},
    Map<String, dynamic>? queryParameters,
    Object? extra,
  }) {
    final slot = context.businessTabSlot(businessId);
    final u = uri(
      businessId: businessId,
      tabSlot: slot,
      routeName: routeName,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
    );
    return GoRouter.of(context).push<T>(u.toString(), extra: extra);
  }
}
