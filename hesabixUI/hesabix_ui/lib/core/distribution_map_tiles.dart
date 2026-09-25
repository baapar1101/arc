/// منبع تایل نقشه در پخش مویرگی: OSM جهانی رایگان یا می‌مپس (کلید API).
class DistributionMapTileConfig {
  static const String sourceOsm = 'osm';
  static const String sourceMemaps = 'memaps';

  final String source;
  final String memapsApiKey;

  const DistributionMapTileConfig({
    this.source = sourceOsm,
    this.memapsApiKey = '',
  });

  factory DistributionMapTileConfig.fromSettings(Map<String, dynamic>? settings) {
    final raw = (settings?['map_tile_source'] ?? sourceOsm).toString().trim().toLowerCase();
    return DistributionMapTileConfig(
      source: raw == sourceMemaps ? sourceMemaps : sourceOsm,
      memapsApiKey: (settings?['memaps_api_key'] ?? '').toString().trim(),
    );
  }

  bool get isMemaps => source == sourceMemaps;

  bool get needsMemapsKey => isMemaps && memapsApiKey.isEmpty;

  int get maxZoom => isMemaps ? 18 : 19;

  String urlTemplate({required bool dark}) {
    if (!isMemaps) {
      return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
    final path = dark ? 'dark' : 'hot';
    final r = dark ? '' : '{r}';
    final keyQ = memapsApiKey.isEmpty ? '' : '?key={memapsKey}';
    return 'https://memaps.ir/$path/{z}/{x}/{y}$r.png$keyQ';
  }

  Map<String, String> get additionalOptions {
    if (!isMemaps || memapsApiKey.isEmpty) return const {};
    return {'memapsKey': Uri.encodeQueryComponent(memapsApiKey)};
  }

  String get attribution => isMemaps
      ? '© OpenStreetMap · © می‌مپس'
      : '© OpenStreetMap contributors';
}
