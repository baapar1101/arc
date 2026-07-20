import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/api_client.dart';

/// کلاینت API گزارش‌های سفارشی HScript.
class HScriptReportService {
  HScriptReportService(this._api);

  final ApiClient _api;

  String _base(int businessId) => '/businesses/$businessId/hscript';

  Map<String, dynamic> _data(Response<dynamic> res) {
    final body = res.data;
    if (body is Map<String, dynamic>) {
      final data = body['data'];
      if (data is Map<String, dynamic>) return data;
      return body;
    }
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getPlanStatus({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>('${_base(businessId)}/plan');
    return _data(res);
  }

  Future<Map<String, dynamic>> validate({
    required int businessId,
    required String sourceCode,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '${_base(businessId)}/validate',
      data: {'source_code': sourceCode},
    );
    return _data(res);
  }

  Future<Map<String, dynamic>> runAdhoc({
    required int businessId,
    required String sourceCode,
    Map<String, dynamic>? params,
    bool persist = false,
    bool asyncMode = false,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '${_base(businessId)}/run',
      data: {
        'source_code': sourceCode,
        if (params != null) 'params': params,
        'preview': true,
        'persist': persist,
        'async_mode': asyncMode,
      },
    );
    return _data(res);
  }

  Future<Map<String, dynamic>> assistContext({
    required int businessId,
    required String query,
    String? sourceCode,
    int limit = 5,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '${_base(businessId)}/assist/context',
      data: {
        'query': query,
        if (sourceCode != null) 'source_code': sourceCode,
        'limit': limit,
      },
    );
    return _data(res);
  }

  Future<List<Map<String, dynamic>>> listReports({
    required int businessId,
    String? status,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '${_base(businessId)}/reports',
      query: {
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    final data = _data(res);
    final items = data['items'];
    if (items is List) {
      return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> getReport({
    required int businessId,
    required int reportId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '${_base(businessId)}/reports/$reportId',
    );
    return _data(res);
  }

  Future<Map<String, dynamic>> createReport({
    required int businessId,
    required String title,
    required String sourceCode,
    String? slug,
    String? description,
    Map<String, dynamic>? defaultParams,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '${_base(businessId)}/reports',
      data: {
        'title': title,
        'source_code': sourceCode,
        if (slug != null) 'slug': slug,
        if (description != null) 'description': description,
        if (defaultParams != null) 'default_params': defaultParams,
      },
    );
    return _data(res);
  }

  Future<Map<String, dynamic>> updateReport({
    required int businessId,
    required int reportId,
    String? title,
    String? sourceCode,
    String? description,
    Map<String, dynamic>? defaultParams,
    String? changelog,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '${_base(businessId)}/reports/$reportId',
      data: {
        if (title != null) 'title': title,
        if (sourceCode != null) 'source_code': sourceCode,
        if (description != null) 'description': description,
        if (defaultParams != null) 'default_params': defaultParams,
        if (changelog != null) 'changelog': changelog,
      },
    );
    return _data(res);
  }

  Future<Map<String, dynamic>> publishReport({
    required int businessId,
    required int reportId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '${_base(businessId)}/reports/$reportId/publish',
    );
    return _data(res);
  }

  Future<Map<String, dynamic>> archiveReport({
    required int businessId,
    required int reportId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '${_base(businessId)}/reports/$reportId/archive',
    );
    return _data(res);
  }

  Future<void> deleteReport({
    required int businessId,
    required int reportId,
  }) async {
    await _api.delete<Map<String, dynamic>>(
      '${_base(businessId)}/reports/$reportId',
    );
  }

  Future<Map<String, dynamic>> runSaved({
    required int businessId,
    required int reportId,
    Map<String, dynamic>? params,
    bool preview = false,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '${_base(businessId)}/reports/$reportId/run',
      data: {
        if (params != null) 'params': params,
        'preview': preview,
        'persist': true,
      },
    );
    return _data(res);
  }

  Future<Uint8List> exportPdfAdhoc({
    required int businessId,
    String? sourceCode,
    Map<String, dynamic>? spec,
    Map<String, dynamic>? params,
  }) async {
    final res = await _api.post<List<int>>(
      '${_base(businessId)}/pdf',
      data: {
        if (sourceCode != null) 'source_code': sourceCode,
        if (spec != null) 'spec': spec,
        if (params != null) 'params': params,
      },
      responseType: ResponseType.bytes,
      options: Options(headers: {'Accept': 'application/pdf'}),
    );
    final raw = res.data;
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    throw StateError('پاسخ PDF نامعتبر است');
  }

  Future<Uint8List> exportPdfSaved({
    required int businessId,
    required int reportId,
    Map<String, dynamic>? spec,
    Map<String, dynamic>? params,
  }) async {
    final res = await _api.post<List<int>>(
      '${_base(businessId)}/reports/$reportId/pdf',
      data: {
        if (spec != null) 'spec': spec,
        if (params != null) 'params': params,
      },
      responseType: ResponseType.bytes,
      options: Options(headers: {'Accept': 'application/pdf'}),
    );
    final raw = res.data;
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    throw StateError('پاسخ PDF نامعتبر است');
  }

  Future<Uint8List> exportExcelAdhoc({
    required int businessId,
    String? sourceCode,
    Map<String, dynamic>? spec,
    Map<String, dynamic>? params,
  }) async {
    final res = await _api.post<List<int>>(
      '${_base(businessId)}/excel',
      data: {
        if (sourceCode != null) 'source_code': sourceCode,
        if (spec != null) 'spec': spec,
        if (params != null) 'params': params,
      },
      responseType: ResponseType.bytes,
      options: Options(
        headers: {
          'Accept': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        },
      ),
    );
    final raw = res.data;
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    throw StateError('پاسخ Excel نامعتبر است');
  }
}
