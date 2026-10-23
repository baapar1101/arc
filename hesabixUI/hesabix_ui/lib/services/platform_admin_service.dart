import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../core/api_client.dart';

class PlatformAdminService {
  final ApiClient api;
  PlatformAdminService(this.api);
  static const base = '/api/v1/admin/platform';
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final res = await api.get<Map<String, dynamic>>(
      '$base/$path',
      query: query,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? {});
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> data,
  ) async {
    final res = await api.put<Map<String, dynamic>>('$base/$path', data: data);
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? {});
  }

  Future<Map<String, dynamic>> adjust(int id, Map<String, dynamic> data) async {
    final res = await api.post<Map<String, dynamic>>(
      '$base/wallets/$id/adjustments',
      data: data,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? {});
  }

  Future<Map<String, dynamic>> logo(
    Uint8List bytes,
    String name,
    String reason,
  ) async {
    final res = await api.post<Map<String, dynamic>>(
      '$base/logo',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: name),
        'reason': reason,
      }),
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? {});
  }
}
