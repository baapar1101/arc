import '../core/api_client.dart';
import 'package:dio/dio.dart';

import 'document_policy_guard.dart';

class TransferService {
  final ApiClient _apiClient;
  late final DocumentPolicyGuard _policyGuard = DocumentPolicyGuard(_apiClient);

  TransferService(this._apiClient);

  Future<Map<String, dynamic>> create({
    required int businessId,
    required DateTime documentDate,
    required int currencyId,
    required Map<String, dynamic> source,
    required Map<String, dynamic> destination,
    required double amount,
    double? commission,
    String? description,
    Map<String, dynamic>? extraInfo,
  }) async {
    await _policyGuard.ensureAllowed(
      businessId: businessId,
      documentType: 'transfer',
      documentDate: documentDate,
      amount: amount.abs(),
    );

    // تبدیل نوع حساب از "bank" به "bank_account" برای سازگاری با API
    String sourceType = source['type'] as String? ?? '';
    if (sourceType == 'bank') {
      sourceType = 'bank_account';
    }
    
    String destinationType = destination['type'] as String? ?? '';
    if (destinationType == 'bank') {
      destinationType = 'bank_account';
    }

    // total_amount همان amount است (بدون commission)
    final body = <String, dynamic>{
      'document_date': documentDate.toIso8601String(),
      'currency_id': currencyId,
      'source_type': sourceType,
      'source_id': source['id'],
      'destination_type': destinationType,
      'destination_id': destination['id'],
      'total_amount': amount,
      if (commission != null && commission > 0) 'commission': commission,
      if (description != null && description.isNotEmpty) 'description': description,
      if (extraInfo != null) 'extra_info': extraInfo,
    };
    final res = await _apiClient.post('/businesses/$businessId/transfers/create', data: body);
    return (res.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> list({
    required int businessId,
    int skip = 0,
    int take = 20,
    String? search,
    DateTime? fromDate,
    DateTime? toDate,
    String? sortBy,
    bool sortDesc = true,
  }) async {
    final body = <String, dynamic>{
      'skip': skip,
      'take': take,
      'sort_desc': sortDesc,
      if (sortBy != null) 'sort_by': sortBy,
      if (search != null && search.isNotEmpty) 'search': search,
      if (fromDate != null) 'from_date': fromDate.toUtc().toIso8601String(),
      if (toDate != null) 'to_date': toDate.toUtc().toIso8601String(),
    };
    final res = await _apiClient.post('/businesses/$businessId/transfers', data: body);
    return (res.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  }

  Future<List<int>> exportExcel({
    required int businessId,
    int skip = 0,
    int take = 1000,
    String? search,
    DateTime? fromDate,
    DateTime? toDate,
    String? sortBy,
    bool sortDesc = true,
  }) async {
    final body = <String, dynamic>{
      'skip': skip,
      'take': take,
      'sort_desc': sortDesc,
      if (sortBy != null) 'sort_by': sortBy,
      if (search != null && search.isNotEmpty) 'search': search,
      if (fromDate != null) 'from_date': fromDate.toUtc().toIso8601String(),
      if (toDate != null) 'to_date': toDate.toUtc().toIso8601String(),
    };
    final res = await _apiClient.post<List<int>>(
      '/businesses/$businessId/transfers/export/excel',
      data: body,
      responseType: ResponseType.bytes,
    );
    return res.data ?? <int>[];
  }

  Future<List<int>> exportPdf({
    required int businessId,
    int skip = 0,
    int take = 1000,
    String? search,
    DateTime? fromDate,
    DateTime? toDate,
    String? sortBy,
    bool sortDesc = true,
  }) async {
    final body = <String, dynamic>{
      'skip': skip,
      'take': take,
      'sort_desc': sortDesc,
      if (sortBy != null) 'sort_by': sortBy,
      if (search != null && search.isNotEmpty) 'search': search,
      if (fromDate != null) 'from_date': fromDate.toUtc().toIso8601String(),
      if (toDate != null) 'to_date': toDate.toUtc().toIso8601String(),
    };
    final res = await _apiClient.post<List<int>>(
      '/businesses/$businessId/transfers/export/pdf',
      data: body,
      responseType: ResponseType.bytes,
    );
    return res.data ?? <int>[];
  }

  Future<Map<String, dynamic>> getById(int documentId) async {
    final res = await _apiClient.get('/transfers/$documentId');
    return (res.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> update({
    required int documentId,
    required DateTime documentDate,
    required int currencyId,
    required Map<String, dynamic> source,
    required Map<String, dynamic> destination,
    required double amount,
    double? commission,
    String? description,
    Map<String, dynamic>? extraInfo,
  }) async {
    // تبدیل نوع حساب از "bank" به "bank_account" برای سازگاری با API
    String sourceType = source['type'] as String? ?? '';
    if (sourceType == 'bank') {
      sourceType = 'bank_account';
    }
    
    String destinationType = destination['type'] as String? ?? '';
    if (destinationType == 'bank') {
      destinationType = 'bank_account';
    }

    final body = <String, dynamic>{
      'document_date': documentDate.toIso8601String(),
      'currency_id': currencyId,
      'source_type': sourceType,
      'source_id': source['id'],
      'destination_type': destinationType,
      'destination_id': destination['id'],
      'total_amount': amount,
      if (commission != null && commission > 0) 'commission': commission,
      if (description != null && description.isNotEmpty) 'description': description,
      if (extraInfo != null) 'extra_info': extraInfo,
    };
    final res = await _apiClient.put('/transfers/$documentId', data: body);
    return (res.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  }

  Future<void> deleteById(int documentId) async {
    await _apiClient.delete('/transfers/$documentId');
  }
}


