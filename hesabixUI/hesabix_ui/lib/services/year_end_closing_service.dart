import '../core/api_client.dart';

class YearEndClosingService {
  final ApiClient _apiClient;

  YearEndClosingService(this._apiClient);

  /// دریافت پیش‌نمایش بستن سال مالی
  Future<Map<String, dynamic>> preview({
    required int businessId,
    required int fiscalYearId,
  }) async {
    final resp = await _apiClient.get(
      '/api/v1/business/$businessId/fiscal-years/$fiscalYearId/closing/preview',
    );
    if (resp.statusCode == 200) {
      return (resp.data?['data'] as Map<String, dynamic>?) ?? {};
    }
    throw Exception('خطا در دریافت پیش‌نمایش بستن سال مالی: ${resp.statusMessage}');
  }

  /// بستن سال مالی
  Future<Map<String, dynamic>> close({
    required int businessId,
    required int fiscalYearId,
    required String newFiscalYearTitle,
    bool autoCreateOpeningBalance = true,
    // مالیات
    double? taxPercentage,
    double? taxAmount,
    // تقسیم سود
    double? profitDistributionPercentage,
    double? profitDistributionAmount,
    int? shareholderProfitAccountId,
    // سود انباشته سنواتی
    double? retainedEarningsFromPreviousYears,
    // تنظیمات
    bool autoIssuePersonBalanceDocument = false,
    // تنظیمات سال مالی جدید
    DateTime? newFiscalYearStartDate,
    DateTime? newFiscalYearEndDate,
    String inventoryValuationMethod = 'FIFO',
    // تقسیم سود بین سهامداران
    List<Map<String, dynamic>>? shareholderDistributions,
  }) async {
    final data = <String, dynamic>{
      'new_fiscal_year_title': newFiscalYearTitle,
      'auto_create_opening_balance': autoCreateOpeningBalance,
    };
    
    // مالیات
    if (taxPercentage != null) {
      data['tax_percentage'] = taxPercentage;
    }
    if (taxAmount != null) {
      data['tax_amount'] = taxAmount;
    }
    
    // تقسیم سود
    if (profitDistributionPercentage != null) {
      data['profit_distribution_percentage'] = profitDistributionPercentage;
    }
    if (profitDistributionAmount != null) {
      data['profit_distribution_amount'] = profitDistributionAmount;
    }
    if (shareholderProfitAccountId != null) {
      data['shareholder_profit_account_id'] = shareholderProfitAccountId;
    }
    
    // سود انباشته سنواتی
    if (retainedEarningsFromPreviousYears != null) {
      data['retained_earnings_from_previous_years'] = retainedEarningsFromPreviousYears;
    }
    
    // تنظیمات
    data['auto_issue_person_balance_document'] = autoIssuePersonBalanceDocument;
    
    // تنظیمات سال مالی جدید
    if (newFiscalYearStartDate != null) {
      data['new_fiscal_year_start_date'] = newFiscalYearStartDate.toIso8601String().split('T')[0];
    }
    if (newFiscalYearEndDate != null) {
      data['new_fiscal_year_end_date'] = newFiscalYearEndDate.toIso8601String().split('T')[0];
    }
    data['inventory_valuation_method'] = inventoryValuationMethod;
    
    // تقسیم سود بین سهامداران
    if (shareholderDistributions != null && shareholderDistributions.isNotEmpty) {
      data['shareholder_distributions'] = shareholderDistributions.map((dist) => {
        'person_id': dist['person_id'],
        'profit_amount': dist['profit_amount'],
      }).toList();
    }
    
    final resp = await _apiClient.post(
      '/api/v1/business/$businessId/fiscal-years/$fiscalYearId/close',
      data: data,
    );
    if (resp.statusCode == 200) {
      return (resp.data?['data'] as Map<String, dynamic>?) ?? {};
    }
    throw Exception('خطا در بستن سال مالی: ${resp.statusMessage}');
  }
}

