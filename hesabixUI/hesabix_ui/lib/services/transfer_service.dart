import '../core/api_client.dart';
import 'package:dio/dio.dart';

class TransferService {
  final ApiClient _apiClient;
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
    final body = <String, dynamic>{
      'document_date': documentDate.toIso8601String(),
      'currency_id': currencyId,
      'source': source,
      'destination': destination,
      'amount': amount,
      if (commission != null) 'commission': commission,
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
    final body = <String, dynamic>{
      'document_date': documentDate.toIso8601String(),
      'currency_id': currencyId,
      'source': source,
      'destination': destination,
      'amount': amount,
      if (commission != null) 'commission': commission,
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


