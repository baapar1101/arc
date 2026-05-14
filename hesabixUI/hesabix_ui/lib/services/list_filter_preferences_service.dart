import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// شناسهٔ پایدار صفحه برای کلید ذخیرهٔ فیلترهای لیست (همراه با [businessId]).
abstract class ListFilterPageIds {
  static const String invoices = 'invoices';
  static const String receiptsPayments = 'receipts_payments';
  static const String expenseIncome = 'expense_income';
  static const String persons = 'persons';
  static const String products = 'products';

  /// فیلترهای داخل [DataTableWidget] (جستجو، فیلتر ستون، …) — جدا از فیلترهای سربرگ صفحه.
  static const String warehouseDocsTable = 'warehouse_docs_table';
  static const String bankAccountsTable = 'bank_accounts_table';
  static const String cashRegistersTable = 'cash_registers_table';
  static const String pettyCashTable = 'petty_cash_table';
  static const String warehousesTable = 'warehouses_table';

  static const String checksTable = 'checks_table';
  static const String projectsTable = 'projects_table';
  static const String documentsTable = 'documents_table';
  static const String transfersTable = 'transfers_table';
  static const String activityLogsTable = 'activity_logs_table';
  static const String stockCountReportTable = 'stock_count_report_table';
  /// فیلترهای داخل جدول فاکتورها؛ جدا از prefs سربرگ [invoices].
  static const String invoicesListTable = 'invoices_list_table';
  /// جدا از prefs سربرگ [receiptsPayments].
  static const String receiptsPaymentsTable = 'receipts_payments_table';
  /// جدا از prefs سربرگ [expenseIncome].
  static const String expenseIncomeTable = 'expense_income_table';
  static const String warrantyCodesTable = 'warranty_codes_table';
  static const String productAttributesTable = 'product_attributes_table';
  static const String taxWorkspaceTable = 'tax_workspace_table';
  static const String currencyRevaluationRatesTable = 'currency_revaluation_rates_table';
  static const String interWarehouseTransfersReportTable =
      'inter_warehouse_transfers_report_table';

  static const String kardexLinesTable = 'kardex_lines_table';
  static const String walletTransactionsTable = 'wallet_transactions_table';
  static const String documentMonetizationChargesTable =
      'document_monetization_charges_table';
  static const String checkReconciliationSelectTable =
      'check_reconciliation_select_table';
  static const String checkReconciliationHistoryTable =
      'check_reconciliation_history_table';

  static const String trialBalanceReportTable = 'trial_balance_report_table';
  static const String journalLedgerReportTable = 'journal_ledger_report_table';
  static const String generalLedgerReportTable = 'general_ledger_report_table';
  static const String pendingDocumentsReportTable =
      'pending_documents_report_table';
  static const String warehouseDocumentsSummaryReportTable =
      'warehouse_documents_summary_report_table';
  static const String warehousePerformanceReportTable =
      'warehouse_performance_report_table';
  static const String inventoryKardexReportTable =
      'inventory_kardex_report_table';
  static const String inventoryTurnoverReportTable =
      'inventory_turnover_report_table';
  static const String inventoryValuationReportTable =
      'inventory_valuation_report_table';
  static const String inventoryStockReportTable =
      'inventory_stock_report_table';
  static const String itemMovementsReportTable =
      'item_movements_report_table';
  static const String slowMovingItemsReportTable =
      'slow_moving_items_report_table';
  static const String criticalStockReportTable =
      'critical_stock_report_table';
  static const String salesByProductReportTable =
      'sales_by_product_report_table';
  static const String materialsConsumptionReportTable =
      'materials_consumption_report_table';
  static const String productionReportTable = 'production_report_table';
  static const String dailyPurchasesReportTable =
      'daily_purchases_report_table';
  static const String dailySalesReportTable = 'daily_sales_report_table';
  static const String monthlySalesReportTable = 'monthly_sales_report_table';
  static const String topCustomersReportTable = 'top_customers_report_table';
  static const String topSuppliersReportTable = 'top_suppliers_report_table';
  static const String bankAccountsTurnoverReportTable =
      'bank_accounts_turnover_report_table';
  static const String cashPettyTurnoverReportTable =
      'cash_petty_turnover_report_table';
  static const String debtorsReportTable = 'debtors_report_table';
  static const String creditorsReportTable = 'creditors_report_table';
  static const String peopleTransactionsReportTable =
      'people_transactions_report_table';
  static const String productMovementHistoryReportTable =
      'product_movement_history_report_table';
  static const String adjustmentDocumentsReportTable =
      'adjustment_documents_report_table';

  static const String basalamSyncedInvoicesReportTable =
      'basalam_synced_invoices_report_table';
  static const String basalamDeadLetterReportTable =
      'basalam_dead_letter_report_table';
  static const String basalamProductConflictsReportTable =
      'basalam_product_conflicts_report_table';
}

/// ذخیرهٔ JSON فیلترهای «بیرون جدول» در حافظهٔ محلی کاربر.
///
/// نسخهٔ اسکیما در payload است تا بعد از تغییر ساختار، دادهٔ قدیمی نادیده گرفته شود.
class ListFilterPreferencesService {
  ListFilterPreferencesService._();

  static const int _schemaVersion = 1;
  static const String _legacyInvoiceDocTypePrefix = 'invoices_list_document_type_';

  static String _storageKey(String pageId, int businessId) =>
      'list_filter_prefs_v${_schemaVersion}_${pageId}_$businessId';

  static Future<Map<String, dynamic>?> load(String pageId, int businessId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey(pageId, businessId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final v = decoded['v'];
      if (v is! int || v != _schemaVersion) return null;
      final d = decoded['d'];
      if (d is! Map) return null;
      return Map<String, dynamic>.from(d);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String pageId, int businessId, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(<String, dynamic>{
        'v': _schemaVersion,
        'd': data,
      });
      await prefs.setString(_storageKey(pageId, businessId), payload);
    } catch (_) {}
  }

  static Future<void> clear(String pageId, int businessId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey(pageId, businessId));
    } catch (_) {}
  }

  /// بارگذاری فیلتر فاکتورها؛ در نبود رکورد جدید، از کلید قدیمی فقط نوع سند مهاجرت می‌کند.
  static Future<Map<String, dynamic>?> loadInvoicesMergedLegacy(int businessId) async {
    final modern = await load(ListFilterPageIds.invoices, businessId);
    if (modern != null) return modern;
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString('$_legacyInvoiceDocTypePrefix$businessId');
      if (legacy != null && legacy.isNotEmpty) {
        return <String, dynamic>{'document_type': legacy};
      }
    } catch (_) {}
    return null;
  }

  /// حذف ذخیرهٔ فاکتورها + کلید قدیمی نوع سند.
  static Future<void> clearInvoicesWithLegacy(int businessId) async {
    await clear(ListFilterPageIds.invoices, businessId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_legacyInvoiceDocTypePrefix$businessId');
    } catch (_) {}
  }
}
