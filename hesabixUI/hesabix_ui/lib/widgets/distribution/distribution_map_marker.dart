import 'package:flutter/material.dart';

/// مارکر روی نقشهٔ پخش مویرگی.
class DistributionMapMarker {
  final double lat;
  final double lng;
  final String label;
  final String? subtitle;
  final Color? color;

  const DistributionMapMarker({
    required this.lat,
    required this.lng,
    required this.label,
    this.subtitle,
    this.color,
  });

  static DistributionMapMarker? tryFromPayload(Map<String, dynamic> m) {
    final lat = m['latitude'] ?? m['customer_latitude'] ?? m['visit_latitude'] ?? m['lat'];
    final lng = m['longitude'] ?? m['customer_longitude'] ?? m['visit_longitude'] ?? m['lng'];
    if (lat == null || lng == null) return null;
    final la = double.tryParse('$lat');
    final ln = double.tryParse('$lng');
    if (la == null || ln == null) return null;
    return DistributionMapMarker(
      lat: la,
      lng: ln,
      label: m['person_name']?.toString() ?? m['label']?.toString() ?? '',
      subtitle: m['status']?.toString(),
    );
  }
}
