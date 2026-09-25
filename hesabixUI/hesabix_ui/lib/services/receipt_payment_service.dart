import '../core/api_client.dart';
import '../models/receipt_payment_document.dart';
import 'document_policy_guard.dart';
import '../core/date_utils.dart' show MarkStreetDateUtils;

/// سرویس دریافت و پرداخت
class ReceiptPaymentService {
  final ApiClient _apiClient;
  late final DocumentPolicyGuard _policyGuard = DocumentPolicyGuard(_apiClient);

  ReceiptPaymentService(this._apiClient);

  /// ایجاد سند دریافت یا پرداخت
  /// 
  /// [businessId] شناسه کسب‌وکار
  /// [documentType] نوع سند: "receipt" یا "payment"
  /// [documentDate] تاریخ سند
  /// [currencyId] شناسه ارز
  /// [personLines] لیست تراکنش‌های اشخاص
  /// [accountLines] لیست تراکنش‌های حساب‌ها
  /// [description] توضیحات کلی سند (اختیاری)
  /// [projectId] شناسه پروژه (اختیاری)
  /// [extraInfo] اطلاعات اضافی (اختیاری)
  Future<Map<String, dynamic>> createReceiptPayment({
    required int businessId,
    required String documentType,
    required DateTime documentDate,
    required int currencyId,
    required List<Map<String, dynamic>> personLines,
    required List<Map<String, dynamic>> accountLines,
    String? description,
    int? projectId,
    Map<String, dynamic>? extraInfo,
  }) async {
    final amount = _sumLineAmounts(personLines);

    await _policyGuard.ensureAllowed(
      businessId: businessId,
      documentType: documentType,
      documentDate: documentDate,
      amount: amount,
    );

    final response = await _apiClient.post(
      '/businesses/$businessId/receipts-payments/create',
      data: {
        'document_type': documentType,
        'document_date': documentDate.toIso8601String(),
        'currency_id': currencyId,
        if (description != null && description.isNotEmpty) 'description': description,
        'person_lines': personLines,
        'account_lines': accountLines,
        if (projectId != null) 'project_id': projectId,
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
      // ارسال تاریخ به صورت YYYY-MM-DD (بدون زمان) برای جلوگیری از جابجایی روز به‌خاطر UTC
      if (fromDate != null) 'from_date': MarkStreetDateUtils.formatForApiDate(fromDate),
      if (toDate != null) 'to_date': MarkStreetDateUtils.formatForApiDate(toDate),
    };

    print('🚨🚨🚨 [ReceiptPaymentService] ارسال درخواست POST به /businesses/$businessId/receipts-payments');
    print('🚨🚨🚨 [ReceiptPaymentService] body: $body');
    print('🚨🚨🚨 [ReceiptPaymentService] Stack trace:');
    print(StackTrace.current);

    final response = await _apiClient.post(
      '/businesses/$businessId/receipts-payments',
      data: body,
    );

    print('✅✅✅ [ReceiptPaymentService] پاسخ دریافت شد - تعداد آیتم‌ها: ${(response.data['data']?['items'] as List<dynamic>?)?.length ?? 0}');

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

  /// دریافت جزئیات یک سند دریافت/پرداخت (wrapper برای getReceiptPayment)
  /// 
  /// [documentId] شناسه سند
  Future<ReceiptPaymentDocument?> getById(int documentId) async {
    try {
      final data = await getReceiptPayment(documentId);
      return ReceiptPaymentDocument.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  /// حذف سند دریافت/پرداخت
  /// 
  /// [documentId] شناسه سند
  Future<void> deleteReceiptPayment(int documentId) async {
    await _apiClient.delete(
      '/receipts-payments/$documentId',
    );
  }

  /// ویرایش سند دریافت/پرداخت
  Future<Map<String, dynamic>> updateReceiptPayment({
    required int documentId,
    required DateTime documentDate,
    required int currencyId,
    required List<Map<String, dynamic>> personLines,
    required List<Map<String, dynamic>> accountLines,
    String? description,
    int? projectId,
    Map<String, dynamic>? extraInfo,
  }) async {
    final response = await _apiClient.put(
      '/receipts-payments/$documentId',
      data: {
        'document_date': documentDate.toIso8601String(),
        'currency_id': currencyId,
        if (description != null && description.isNotEmpty) 'description': description,
        'person_lines': personLines,
        'account_lines': accountLines,
        if (projectId != null) 'project_id': projectId,
        if (extraInfo != null) 'extra_info': extraInfo,
      },
    );
    return response.data['data'] as Map<String, dynamic>;
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
    String? description,
    Map<String, dynamic>? extraInfo,
  }) {
    return createReceiptPayment(
      businessId: businessId,
      documentType: 'receipt',
      documentDate: documentDate,
      currencyId: currencyId,
      personLines: personLines,
      accountLines: accountLines,
      description: description,
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
    String? description,
    Map<String, dynamic>? extraInfo,
  }) {
    return createReceiptPayment(
      businessId: businessId,
      documentType: 'payment',
      documentDate: documentDate,
      currencyId: currencyId,
      personLines: personLines,
      accountLines: accountLines,
      description: description,
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

  /// اسناد دریافت/پرداخت مرتبط با فاکتور (لینک مستقیم + person_line.invoice_id)
  Future<List<ReceiptPaymentDocument>> listPaymentDocumentsForInvoice({
    required int businessId,
    required int invoiceId,
    Map<String, dynamic>? invoiceLinks,
  }) async {
    final processedDocIds = <int>{};
    final documents = <ReceiptPaymentDocument>[];

    Future<void> tryAddDoc(int docId) async {
      if (processedDocIds.contains(docId)) return;
      try {
        final doc = await getById(docId);
        if (doc == null) return;
        processedDocIds.add(docId);
        documents.add(doc);
      } catch (_) {}
    }

    final rawIds = invoiceLinks?['receipt_payment_document_ids'];
    if (rawIds is List) {
      for (final id in rawIds) {
        final docId = id is int ? id : int.tryParse(id.toString());
        if (docId != null) {
          await tryAddDoc(docId);
        }
      }
    }

    try {
      final receiptPaymentList = await listReceiptsPayments(
        businessId: businessId,
        skip: 0,
        take: 1000,
      );
      final items = (receiptPaymentList['items'] as List<dynamic>?) ?? [];
      for (final item in items) {
        final docId = (item['id'] as num?)?.toInt();
        if (docId == null || processedDocIds.contains(docId)) continue;

        final personLines = item['person_lines'] as List<dynamic>?;
        if (personLines == null) continue;

        var hasInvoiceLink = false;
        for (final pl in personLines) {
          final extraInfo = pl['extra_info'] as Map<String, dynamic>?;
          if (extraInfo == null) continue;
          final linkedInvoiceId = extraInfo['invoice_id'];
          if (linkedInvoiceId is int && linkedInvoiceId == invoiceId) {
            hasInvoiceLink = true;
            break;
          }
          if (linkedInvoiceId is num && linkedInvoiceId.toInt() == invoiceId) {
            hasInvoiceLink = true;
            break;
          }
        }
        if (!hasInvoiceLink) continue;
        await tryAddDoc(docId);
      }
    } catch (_) {}

    return documents;
  }
}

num _sumLineAmounts(List<Map<String, dynamic>> lines) {
  num sum = 0;
  for (final line in lines) {
    final value = line['amount'];
    if (value is num) {
      sum += value.abs();
    } else if (value is String) {
      sum += num.tryParse(value) ?? 0;
    }
  }
  return sum.abs();
}

