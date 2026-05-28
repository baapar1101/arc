import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/memaps_config.dart';
import 'distribution_map_marker.dart';

/// نقشهٔ تعاملی با تایل می‌مپس و مارکرها.
class DistributionMemapsMap extends StatefulWidget {
  final List<DistributionMapMarker> markers;
  final double height;
  final LatLng? selectedPoint;
  final bool pickMode;
  final ValueChanged<LatLng>? onPick;

  const DistributionMemapsMap({
    super.key,
    required this.markers,
    this.height = 280,
    this.selectedPoint,
    this.pickMode = false,
    this.onPick,
  });

  @override
  State<DistributionMemapsMap> createState() => _DistributionMemapsMapState();
}

class _DistributionMemapsMapState extends State<DistributionMemapsMap> {
  final MapController _controller = MapController();
  bool _fitted = false;

  @override
  void didUpdateWidget(covariant DistributionMemapsMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markers.length != widget.markers.length ||
        oldWidget.selectedPoint != widget.selectedPoint) {
      _fitted = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitIfNeeded());
    }
  }

  void _fitIfNeeded() {
    if (_fitted || !mounted) return;
    final points = <LatLng>[
      ...widget.markers.map((m) => LatLng(m.lat, m.lng)),
      if (widget.selectedPoint != null) widget.selectedPoint!,
    ];
    if (points.isEmpty) return;
    _fitted = true;
    if (points.length == 1) {
      _controller.move(points.first, 15);
      return;
    }
    final bounds = LatLngBounds.fromPoints(points);
    _controller.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allMarkers = <Marker>[];

    for (final m in widget.markers) {
      allMarkers.add(
        Marker(
          point: LatLng(m.lat, m.lng),
          width: 36,
          height: 36,
          child: Tooltip(
            message: m.label,
            child: Icon(Icons.place, color: m.color ?? cs.primary, size: 32),
          ),
        ),
      );
    }
    if (widget.selectedPoint != null) {
      allMarkers.add(
        Marker(
          point: widget.selectedPoint!,
          width: 44,
          height: 44,
          child: Icon(Icons.edit_location_alt, color: cs.tertiary, size: 36),
        ),
      );
    }

    final initial = widget.selectedPoint ??
        (widget.markers.isNotEmpty
            ? LatLng(widget.markers.first.lat, widget.markers.first.lng)
            : const LatLng(MemapsConfig.defaultLat, MemapsConfig.defaultLng));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: widget.height,
            child: FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: initial,
                initialZoom: MemapsConfig.defaultZoom,
                onTap: widget.pickMode && widget.onPick != null
                    ? (_, point) => widget.onPick!(point)
                    : null,
                onMapReady: _fitIfNeeded,
              ),
              children: [
                TileLayer(
                  urlTemplate: MemapsConfig.tileUrlTemplate,
                  retinaMode: RetinaMode.isHighDensity(context),
                  userAgentPackageName: 'ir.hesabix.ui',
                ),
                MarkerLayer(markers: allMarkers),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          MemapsConfig.attribution,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.outline),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
