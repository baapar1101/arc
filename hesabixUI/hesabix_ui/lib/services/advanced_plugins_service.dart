import '../core/api_client.dart';

class AdvancedPluginsService {
  final ApiClient _api = ApiClient();
  final int businessId;
  AdvancedPluginsService(this.businessId);
  String get base => '/api/v1/advanced-plugins/business/$businessId';
  Map<String, dynamic> data(dynamic body) =>
      Map<String, dynamic>.from(body?['data'] as Map? ?? {});
  Future<Map<String, dynamic>> overview() async =>
      data((await _api.get<Map<String, dynamic>>(base)).data);
  Future<Map<String, dynamic>> records(
    String code, {
    String? kind,
    String q = '',
    int skip = 0,
    bool archived = false,
  }) async => data(
    (await _api.get<Map<String, dynamic>>(
      '$base/$code/records',
      query: {
        'take': 50,
        'skip': skip,
        'q': q,
        'include_archived': archived,
        'kind': ?kind,
      },
    )).data,
  );
  Future<Map<String, dynamic>> detail(String code, int id) async => data(
    (await _api.get<Map<String, dynamic>>('$base/$code/records/$id')).data,
  );
  Future<Map<String, dynamic>> saveRecord(
    String code,
    String kind,
    Map<String, dynamic> values, {
    int? id,
  }) async => data(
    id == null
        ? (await _api.post<Map<String, dynamic>>(
            '$base/$code/records/$kind',
            data: values,
          )).data
        : (await _api.put<Map<String, dynamic>>(
            '$base/$code/records/$id',
            data: values,
          )).data,
  );
  Future<Map<String, dynamic>> saveSettings(
    String code,
    Map<String, dynamic> values,
  ) async => data(
    (await _api.put<Map<String, dynamic>>(
      '$base/$code/settings',
      data: values,
    )).data,
  );
  Future<Map<String, dynamic>> operation(
    String code,
    String action,
    Map<String, dynamic> values,
  ) async => data(
    (await _api.post<Map<String, dynamic>>(
      '$base/$code/operations/$action',
      data: values,
    )).data,
  );
  Future<List<Map<String, dynamic>>> references(
    String code,
    String type,
    String q,
  ) async {
    final out = data(
      (await _api.get<Map<String, dynamic>>(
        '$base/$code/references/$type',
        query: {'q': q},
      )).data,
    );
    return (out['items'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> audit(String code) async {
    final out = data(
      (await _api.get<Map<String, dynamic>>('$base/$code/audit')).data,
    );
    return (out['items'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> finance(String code) async =>
      data((await _api.get<Map<String, dynamic>>('$base/$code/finance')).data);
  Future<Map<String, dynamic>> financeConfig(
    String code,
    Map<String, dynamic> values,
  ) async => data(
    (await _api.put<Map<String, dynamic>>(
      '$base/$code/finance/config',
      data: values,
    )).data,
  );
  Future<Map<String, dynamic>> financeAction(
    String code,
    String path,
    Map<String, dynamic> values,
  ) async => data(
    (await _api.post<Map<String, dynamic>>(
      '$base/$code/finance/$path',
      data: values,
    )).data,
  );
}
