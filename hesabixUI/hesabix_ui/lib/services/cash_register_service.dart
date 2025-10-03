import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/cash_register.dart';

class CashRegisterService {
  final ApiClient _client;
  CashRegisterService({ApiClient? client}) : _client = client ?? ApiClient();

  Future<Map<String, dynamic>> list({required int businessId, required Map<String, dynamic> queryInfo}) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/v1/cash-registers/businesses/$businessId/cash-registers',
      data: queryInfo,
    );
    return (res.data ?? <String, dynamic>{});
  }

  Future<CashRegister> create({required int businessId, required Map<String, dynamic> payload}) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/v1/cash-registers/businesses/$businessId/cash-registers/create',
      data: payload,
    );
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return CashRegister.fromJson(data);
  }

  Future<CashRegister> getById(int id) async {
    final res = await _client.get<Map<String, dynamic>>('/api/v1/cash-registers/cash-registers/$id');
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return CashRegister.fromJson(data);
  }

  Future<CashRegister> update({required int id, required Map<String, dynamic> payload}) async {
    final res = await _client.put<Map<String, dynamic>>('/api/v1/cash-registers/cash-registers/$id', data: payload);
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return CashRegister.fromJson(data);
  }

  Future<void> delete(int id) async {
    await _client.delete<Map<String, dynamic>>('/api/v1/cash-registers/cash-registers/$id');
  }

  Future<Response<List<int>>> exportExcel({required int businessId, required Map<String, dynamic> body}) async {
    return _client.post<List<int>>(
      '/api/v1/cash-registers/businesses/$businessId/cash-registers/export/excel',
      data: body,
      responseType: ResponseType.bytes,
    );
  }

  Future<Response<List<int>>> exportPdf({required int businessId, required Map<String, dynamic> body}) async {
    return _client.post<List<int>>(
      '/api/v1/cash-registers/businesses/$businessId/cash-registers/export/pdf',
      data: body,
      responseType: ResponseType.bytes,
    );
  }
}
