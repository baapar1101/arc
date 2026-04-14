import 'package:dio/dio.dart';
import '../core/api_client.dart';

class TaxService {
  final ApiClient _apiClient;
  TaxService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<List<Map<String, dynamic>>> getTaxTypes({int? businessId}) async {
    try {
      final res = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/tax-types/',
      );
      final data = res.data?['data'];
      if (data is List) {
        return data
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      if (data is Map<String, dynamic> && data['items'] is List) {
        final items = data['items'] as List;
        return items
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return const <Map<String, dynamic>>[];
    } on DioException {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> getTaxUnits({int? businessId}) async {
    try {
      final res = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/tax-units/',
      );
      final data = res.data?['data'];
      if (data is List) {
        return data
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      if (data is Map<String, dynamic> && data['items'] is List) {
        final items = data['items'] as List;
        return items
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return const <Map<String, dynamic>>[];
    } on DioException {
      return const <Map<String, dynamic>>[];
    }
  }
}


