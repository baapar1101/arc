import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/bank_account_model.dart';

class BankAccountService {
  final ApiClient _client;
  BankAccountService({ApiClient? client}) : _client = client ?? ApiClient();

  Future<Map<String, dynamic>> list({required int businessId, required Map<String, dynamic> queryInfo}) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/v1/bank-accounts/businesses/$businessId/bank-accounts',
      data: queryInfo,
    );
    return (res.data ?? <String, dynamic>{});
  }

  Future<BankAccount> create({required int businessId, required Map<String, dynamic> payload}) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/v1/bank-accounts/businesses/$businessId/bank-accounts/create',
      data: payload,
    );
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return BankAccount.fromJson(data);
  }

  Future<BankAccount> getById(int id) async {
    final res = await _client.get<Map<String, dynamic>>('/api/v1/bank-accounts/bank-accounts/$id');
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return BankAccount.fromJson(data);
  }

  Future<BankAccount> update({required int id, required Map<String, dynamic> payload}) async {
    final res = await _client.put<Map<String, dynamic>>('/api/v1/bank-accounts/bank-accounts/$id', data: payload);
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return BankAccount.fromJson(data);
  }

  Future<void> delete(int id) async {
    await _client.delete<Map<String, dynamic>>('/api/v1/bank-accounts/bank-accounts/$id');
  }

  Future<Response<List<int>>> exportExcel({required int businessId, required Map<String, dynamic> body}) async {
    return _client.post<List<int>>(
      '/api/v1/bank-accounts/businesses/$businessId/bank-accounts/export/excel',
      data: body,
      responseType: ResponseType.bytes,
    );
  }

  Future<Response<List<int>>> exportPdf({required int businessId, required Map<String, dynamic> body}) async {
    return _client.post<List<int>>(
      '/api/v1/bank-accounts/businesses/$businessId/bank-accounts/export/pdf',
      data: body,
      responseType: ResponseType.bytes,
    );
  }
}


