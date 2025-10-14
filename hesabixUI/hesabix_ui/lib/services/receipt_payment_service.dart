import '../core/api_client.dart';

/// سرویس دریافت و پرداخت
class ReceiptPaymentService {
  final ApiClient _apiClient;

  ReceiptPaymentService(this._apiClient);

  /// ایجاد سند دریافت یا پرداخت
  /// 
  /// [businessId] شناسه کسب‌وکار
  /// [documentType] نوع سند: "receipt" یا "payment"
  /// [documentDate] تاریخ سند
  /// [currencyId] شناسه ارز
  /// [personLines] لیست تراکنش‌های اشخاص
  /// [accountLines] لیست تراکنش‌های حساب‌ها
  /// [extraInfo] اطلاعات اضافی (اختیاری)
  Future<Map<String, dynamic>> createReceiptPayment({
    required int businessId,
    required String documentType,
    required DateTime documentDate,
    required int currencyId,
    required List<Map<String, dynamic>> personLines,
    required List<Map<String, dynamic>> accountLines,
    Map<String, dynamic>? extraInfo,
  }) async {
    final response = await _apiClient.post(
      '/businesses/$businessId/receipts-payments/create',
      data: {
        'document_type': documentType,
        'document_date': documentDate.toIso8601String(),
        'currency_id': currencyId,
        'person_lines': personLines,
        'account_lines': accountLines,
        if (extraInfo != null) 'extra_info': extraInfo,
      },
    );

    return response.data['data'] as Map<String, dynamic>;
  }

  /// دریافت لیست اسناد دریافت و پرداخت
  /// 
  /// [businessId] شناسه کسب‌وکار
  /// [documentType] فیلتر بر اساس نوع سند (اختیاری)
  /// [fromDate] فیلتر تاریخ از (اختیاری)
  /// [toDate] فیلتر تاریخ تا (اختیاری)
  /// [skip] تعداد رکورد برای رد کردن
  /// [take] تعداد رکورد برای دریافت
  /// [search] عبارت جستجو (اختیاری)
  Future<Map<String, dynamic>> listReceiptsPayments({
    required int businessId,
    String? documentType,
    DateTime? fromDate,
    DateTime? toDate,
    int skip = 0,
    int take = 20,
    String? search,
    String? sortBy,
    bool sortDesc = true,
  }) async {
    final body = {
      'skip': skip,
      'take': take,
      'sort_desc': sortDesc,
      if (sortBy != null) 'sort_by': sortBy,
      if (search != null && search.isNotEmpty) 'search': search,
      if (documentType != null) 'document_type': documentType,
      if (fromDate != null) 'from_date': fromDate.toIso8601String(),
      if (toDate != null) 'to_date': toDate.toIso8601String(),
    };

    final response = await _apiClient.post(
      '/businesses/$businessId/receipts-payments',
      data: body,
    );

    return response.data['data'] as Map<String, dynamic>;
  }

  /// دریافت جزئیات یک سند دریافت/پرداخت
  /// 
  /// [documentId] شناسه سند
  Future<Map<String, dynamic>> getReceiptPayment(int documentId) async {
    final response = await _apiClient.get(
      '/receipts-payments/$documentId',
    );

    return response.data['data'] as Map<String, dynamic>;
  }

  /// حذف سند دریافت/پرداخت
  /// 
  /// [documentId] شناسه سند
  Future<void> deleteReceiptPayment(int documentId) async {
    await _apiClient.delete(
      '/receipts-payments/$documentId',
    );
  }

  /// ایجاد سند دریافت
  /// 
  /// این متد یک wrapper ساده برای createReceiptPayment است
  Future<Map<String, dynamic>> createReceipt({
    required int businessId,
    required DateTime documentDate,
    required int currencyId,
    required List<Map<String, dynamic>> personLines,
    required List<Map<String, dynamic>> accountLines,
    Map<String, dynamic>? extraInfo,
  }) {
    return createReceiptPayment(
      businessId: businessId,
      documentType: 'receipt',
      documentDate: documentDate,
      currencyId: currencyId,
      personLines: personLines,
      accountLines: accountLines,
      extraInfo: extraInfo,
    );
  }

  /// ایجاد سند پرداخت
  /// 
  /// این متد یک wrapper ساده برای createReceiptPayment است
  Future<Map<String, dynamic>> createPayment({
    required int businessId,
    required DateTime documentDate,
    required int currencyId,
    required List<Map<String, dynamic>> personLines,
    required List<Map<String, dynamic>> accountLines,
    Map<String, dynamic>? extraInfo,
  }) {
    return createReceiptPayment(
      businessId: businessId,
      documentType: 'payment',
      documentDate: documentDate,
      currencyId: currencyId,
      personLines: personLines,
      accountLines: accountLines,
      extraInfo: extraInfo,
    );
  }

  /// دریافت لیست فقط دریافت‌ها
  Future<Map<String, dynamic>> listReceipts({
    required int businessId,
    DateTime? fromDate,
    DateTime? toDate,
    int skip = 0,
    int take = 20,
    String? search,
  }) {
    return listReceiptsPayments(
      businessId: businessId,
      documentType: 'receipt',
      fromDate: fromDate,
      toDate: toDate,
      skip: skip,
      take: take,
      search: search,
    );
  }

  /// دریافت لیست فقط پرداخت‌ها
  Future<Map<String, dynamic>> listPayments({
    required int businessId,
    DateTime? fromDate,
    DateTime? toDate,
    int skip = 0,
    int take = 20,
    String? search,
  }) {
    return listReceiptsPayments(
      businessId: businessId,
      documentType: 'payment',
      fromDate: fromDate,
      toDate: toDate,
      skip: skip,
      take: take,
      search: search,
    );
  }
}

