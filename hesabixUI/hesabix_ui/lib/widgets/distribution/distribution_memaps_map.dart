import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/distribution_map_tiles.dart';
import '../../core/memaps_config.dart';
import '../../l10n/app_localizations.dart';
import 'distribution_map_marker.dart';

/// نقشهٔ تعاملی با تایل OSM یا می‌مپس و مارکرها.
class DistributionMemapsMap extends StatefulWidget {
  final List<DistributionMapMarker> markers;
  final double height;
  final LatLng? selectedPoint;
  final bool pickMode;
  final ValueChanged<LatLng>? onPick;
  final ValueChanged<DistributionMapMarker>? onMarkerTap;
  final DistributionMapTileConfig tileConfig;
  final List<LatLng> polyline;
  final Color? polylineColor;
  final int fitNonce;

  const DistributionMemapsMap({
    super.key,
    required this.markers,
    this.height = 280,
    this.selectedPoint,
    this.pickMode = false,
    this.onPick,
    this.onMarkerTap,
    this.tileConfig = const DistributionMapTileConfig(),
    this.polyline = const [],
    this.polylineColor,
    this.fitNonce = 0,
  });

  @override
  State<DistributionMemapsMap> createState() => _DistributionMemapsMapState();
}

class _DistributionMemapsMapState extends State<DistributionMemapsMap> {
  final MapController _controller = MapController();
  int _lastFitNonce = -1;

  @override
  void didUpdateWidget(covariant DistributionMemapsMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fitNonce != oldWidget.fitNonce ||
        widget.selectedPoint != oldWidget.selectedPoint) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitIfNeeded(force: true));
    }
  }

  List<LatLng> get _fitPoints {
    return <LatLng>[
      ...widget.markers.map((m) => LatLng(m.lat, m.lng)),
      ...widget.polyline,
      if (widget.selectedPoint != null) widget.selectedPoint!,
    ];
  }

  void _fitIfNeeded({bool force = false}) {
    if (!mounted) return;
    if (!force && _lastFitNonce == widget.fitNonce) return;
    final points = _fitPoints;
    if (points.isEmpty) return;
    _lastFitNonce = widget.fitNonce;
    if (points.length == 1) {
      _controller.move(points.first, 15);
      return;
    }
    final bounds = LatLngBounds.fromPoints(points);
    _controller.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
    );
  }

  Widget _markerChild(DistributionMapMarker m, ColorScheme cs) {
    final color = m.color ?? cs.primary;
    if (m.kind == DistributionMapMarkerKind.visitor) {
      return _VisitorPin(
        label: m.label,
        color: color,
        selected: m.selected,
        icon: m.icon ?? Icons.directions_walk,
      );
    }
    if (m.kind == DistributionMapMarkerKind.customer) {
      return Tooltip(
        message: [m.label, m.subtitle].where((s) => s != null && s.toString().trim().isNotEmpty).join(' · '),
        child: Icon(m.icon ?? Icons.storefront, color: color, size: m.selected ? 34 : 28),
      );
    }
    return Tooltip(
      message: m.label,
      child: Icon(m.icon ?? Icons.place, color: color, size: 32),
    );
  }

  Size _markerSize(DistributionMapMarker m) {
    if (m.kind == DistributionMapMarkerKind.visitor) {
      return m.selected ? const Size(108, 78) : const Size(96, 70);
    }
    if (m.kind == DistributionMapMarkerKind.customer) {
      return const Size(40, 40);
    }
    return const Size(36, 36);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    final tiles = widget.tileConfig;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final allMarkers = <Marker>[];

    for (final m in widget.markers) {
      final size = _markerSize(m);
      allMarkers.add(
        Marker(
          point: LatLng(m.lat, m.lng),
          width: size.width,
          height: size.height,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onMarkerTap == null ? null : () => widget.onMarkerTap!(m),
            child: _markerChild(m, cs),
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
            : widget.polyline.isNotEmpty
                ? widget.polyline.first
                : const LatLng(MemapsConfig.defaultLat, MemapsConfig.defaultLng));

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: initial,
                initialZoom: MemapsConfig.defaultZoom,
                onTap: widget.pickMode && widget.onPick != null
                    ? (_, point) => widget.onPick!(point)
                    : null,
                onMapReady: () => _fitIfNeeded(force: true),
              ),
              children: [
                TileLayer(
                  key: ValueKey(
                    '${tiles.source}:${tiles.memapsApiKey}:$dark:${tiles.isMemaps}',
                  ),
                  urlTemplate: tiles.urlTemplate(dark: dark),
                  additionalOptions: tiles.additionalOptions,
                  retinaMode: tiles.isMemaps && !dark && RetinaMode.isHighDensity(context),
                  maxZoom: tiles.maxZoom.toDouble(),
                  userAgentPackageName: 'ir.hesabix.ui',
                ),
                if (widget.polyline.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: widget.polyline,
                        strokeWidth: 4.5,
                        color: widget.polylineColor ?? cs.primary.withValues(alpha: 0.88),
                        borderStrokeWidth: 1.5,
                        borderColor: cs.surface.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                MarkerLayer(markers: allMarkers),
              ],
            ),
            if (tiles.needsMemapsKey)
              Positioned(
                left: 8,
                right: 8,
                top: 8,
                child: Material(
                  color: cs.errorContainer.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      t.distributionMemapsApiKeyMissing,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onErrorContainer),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Text(
                tiles.attribution,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.72),
                      shadows: const [Shadow(color: Colors.white70, blurRadius: 6)],
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisitorPin extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final IconData icon;

  const _VisitorPin({
    required this.label,
    required this.color,
    required this.selected,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? color : cs.outlineVariant),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: selected ? 36 : 30,
          height: selected ? 36 : 30,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: cs.surface, width: selected ? 3 : 2),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8, spreadRadius: selected ? 2 : 0),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: selected ? 20 : 16),
        ),
      ],
    );
  }
}
