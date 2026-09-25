import 'package:hesabix_ui/models/account_model.dart';

/// پارامترهای مشترک برای ناوبری از گزارش‌های مالی به دفتر کل.
class FinancialReportLedgerContext {
  final int? fiscalYearId;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int? currencyId;
  final int? projectId;

  const FinancialReportLedgerContext({
    this.fiscalYearId,
    this.dateFrom,
    this.dateTo,
    this.currencyId,
    this.projectId,
  });
}

/// ساخت مسیر دفتر کل با فیلتر حساب و بازهٔ گزارش مبدأ.
String buildGeneralLedgerRoute({
  required int businessId,
  required Map<String, dynamic> accountRow,
  FinancialReportLedgerContext? context,
}) {
  final accountId = accountRow['account_id'];
  if (accountId == null) {
    return '/business/$businessId/reports/general-ledger';
  }

  final params = <String, String>{
    'account_id': accountId.toString(),
    if (accountRow['account_code'] != null) 'account_code': accountRow['account_code'].toString(),
    if (accountRow['account_name'] != null) 'account_name': accountRow['account_name'].toString(),
    if (accountRow['account_type'] != null) 'account_type': accountRow['account_type'].toString(),
  };

  if (context != null) {
    if (context.fiscalYearId != null) {
      params['fiscal_year_id'] = context.fiscalYearId.toString();
    }
    if (context.dateFrom != null) {
      params['date_from'] = context.dateFrom!.toIso8601String().split('T').first;
    }
    if (context.dateTo != null) {
      params['date_to'] = context.dateTo!.toIso8601String().split('T').first;
    }
    if (context.currencyId != null) {
      params['currency_id'] = context.currencyId.toString();
    }
    if (context.projectId != null) {
      params['project_id'] = context.projectId.toString();
    }
  }

  final query = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
  return '/business/$businessId/reports/general-ledger?$query';
}

Account? accountFromQueryParams(Map<String, String> query) {
  final id = int.tryParse(query['account_id'] ?? '');
  if (id == null) return null;
  return Account(
    id: id,
    code: query['account_code'] ?? '',
    name: query['account_name'] ?? '',
    accountType: query['account_type'] ?? 'accounting_document',
  );
}

FinancialReportLedgerContext? ledgerContextFromQueryParams(Map<String, String> query) {
  final fiscalYearId = int.tryParse(query['fiscal_year_id'] ?? '');
  final currencyId = int.tryParse(query['currency_id'] ?? '');
  final projectId = int.tryParse(query['project_id'] ?? '');
  final dateFrom = DateTime.tryParse(query['date_from'] ?? '');
  final dateTo = DateTime.tryParse(query['date_to'] ?? '');

  if (fiscalYearId == null &&
      currencyId == null &&
      projectId == null &&
      dateFrom == null &&
      dateTo == null) {
    return null;
  }

  return FinancialReportLedgerContext(
    fiscalYearId: fiscalYearId,
    currencyId: currencyId,
    projectId: projectId,
    dateFrom: dateFrom,
    dateTo: dateTo,
  );
}

/// پارامترهای فیلتر از query string (برای مقداردهی اولیهٔ دفتر کل).
({int? fiscalYearId, int? currencyId, int? projectId, DateTime? dateFrom, DateTime? dateTo})
    reportFiltersFromQueryParams(Map<String, String> query) {
  return (
    fiscalYearId: int.tryParse(query['fiscal_year_id'] ?? ''),
    currencyId: int.tryParse(query['currency_id'] ?? ''),
    projectId: int.tryParse(query['project_id'] ?? ''),
    dateFrom: DateTime.tryParse(query['date_from'] ?? ''),
    dateTo: DateTime.tryParse(query['date_to'] ?? ''),
  );
}
