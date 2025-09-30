import 'package:dio/dio.dart';
import '../core/api_client.dart';

class UnitService {
  final ApiClient _apiClient;
  UnitService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<List<Map<String, dynamic>>> getUnits({required int businessId}) async {
    try {
      final res = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/units/business/$businessId',
      );
      final data = res.data?['data'];
      final items = (data is Map<String, dynamic>) ? data['items'] : null;
      if (items is List) {
        return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
      }
      return const <Map<String, dynamic>>[];
    } on DioException {
      // Endpoint may not exist yet; return empty to allow UI fallback
      return const <Map<String, dynamic>>[];
    }
  }
}


