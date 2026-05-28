import 'package:dio/dio.dart';

import '../core/memaps_config.dart';

/// نتیجهٔ جستجوی مکان از API می‌مپس.
class MemapsPlaceResult {
  final String name;
  final double lat;
  final double lng;
  final String? city;
  final String? category;
  final double? distanceMeters;

  const MemapsPlaceResult({
    required this.name,
    required this.lat,
    required this.lng,
    this.city,
    this.category,
    this.distanceMeters,
  });

  factory MemapsPlaceResult.fromJson(Map<String, dynamic> json) {
    return MemapsPlaceResult(
      name: '${json['name'] ?? ''}',
      lat: double.parse('${json['lat']}'),
      lng: double.parse('${json['lng']}'),
      city: json['city']?.toString(),
      category: json['category']?.toString(),
      distanceMeters: json['distance'] == null ? null : double.tryParse('${json['distance']}'),
    );
  }
}

/// جستجوی مکان — بدون API Key (می‌مپس).
class MemapsPlacesService {
  MemapsPlacesService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                headers: const {'Accept': 'application/json'},
              ),
            );

  final Dio _dio;

  Future<List<MemapsPlaceResult>> searchPlaces({
    required String query,
    double? nearLat,
    double? nearLng,
    String? type,
    int limit = 10,
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];
    final res = await _dio.get<Map<String, dynamic>>(
      MemapsConfig.searchPlacesUrl,
      queryParameters: <String, dynamic>{
        'q': q,
        if (nearLat != null) 'lat': nearLat,
        if (nearLng != null) 'lng': nearLng,
        if (type != null && type.isNotEmpty) 'type': type,
        'limit': limit,
      },
    );
    final data = res.data;
    if (data == null || data['success'] != true) return [];
    final results = data['results'];
    if (results is! List) return [];
    return results
        .whereType<Map>()
        .map((e) => MemapsPlaceResult.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
