/// پروفایل چاپگر رولی/سیستم برای افزونه برچسب بارکد.
class LabelPrinterProfile {
  final String id;
  final String name;
  /// pdf_spooler | zpl | escpos
  final String mode;
  /// system_default | tcp | usb | ble
  final String connection;
  final String? host;
  final int? port;
  final double labelWidthMm;
  final double labelHeightMm;
  final int dpi;
  final bool enabled;

  const LabelPrinterProfile({
    required this.id,
    required this.name,
    this.mode = 'pdf_spooler',
    this.connection = 'system_default',
    this.host,
    this.port,
    this.labelWidthMm = 50,
    this.labelHeightMm = 30,
    this.dpi = 203,
    this.enabled = true,
  });

  factory LabelPrinterProfile.fromJson(Map<String, dynamic> json) {
    return LabelPrinterProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      mode: (json['mode']?.toString() ?? 'pdf_spooler').toLowerCase(),
      connection: (json['connection']?.toString() ?? 'system_default').toLowerCase(),
      host: json['host']?.toString(),
      port: json['port'] is num ? (json['port'] as num).toInt() : int.tryParse('${json['port'] ?? ''}'),
      labelWidthMm: (json['label_width_mm'] as num?)?.toDouble() ?? 50,
      labelHeightMm: (json['label_height_mm'] as num?)?.toDouble() ?? 30,
      dpi: (json['dpi'] as num?)?.toInt() ?? 203,
      enabled: json['enabled'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mode': mode,
        'connection': connection,
        'host': host,
        'port': port,
        'label_width_mm': labelWidthMm,
        'label_height_mm': labelHeightMm,
        'dpi': dpi,
        'enabled': enabled,
      };

  LabelPrinterProfile copyWith({
    String? id,
    String? name,
    String? mode,
    String? connection,
    String? host,
    int? port,
    double? labelWidthMm,
    double? labelHeightMm,
    int? dpi,
    bool? enabled,
    bool clearHost = false,
    bool clearPort = false,
  }) {
    return LabelPrinterProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      mode: mode ?? this.mode,
      connection: connection ?? this.connection,
      host: clearHost ? null : (host ?? this.host),
      port: clearPort ? null : (port ?? this.port),
      labelWidthMm: labelWidthMm ?? this.labelWidthMm,
      labelHeightMm: labelHeightMm ?? this.labelHeightMm,
      dpi: dpi ?? this.dpi,
      enabled: enabled ?? this.enabled,
    );
  }

  bool get isPdfSpooler => mode == 'pdf_spooler';
  bool get isZpl => mode == 'zpl';
}

class LabelPrinterSettings {
  final List<LabelPrinterProfile> profiles;
  final String? activeProfileId;

  const LabelPrinterSettings({
    this.profiles = const [],
    this.activeProfileId,
  });

  factory LabelPrinterSettings.fromJson(Map<String, dynamic> json) {
    final items = (json['printer_profiles'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => LabelPrinterProfile.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return LabelPrinterSettings(
      profiles: items,
      activeProfileId: json['active_profile_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'printer_profiles': profiles.map((e) => e.toJson()).toList(),
        'active_profile_id': activeProfileId,
      };

  LabelPrinterProfile? get activeProfile {
    if (activeProfileId == null) return null;
    for (final p in profiles) {
      if (p.id == activeProfileId) return p;
    }
    return null;
  }

  List<LabelPrinterProfile> get enabledProfiles =>
      profiles.where((p) => p.enabled).toList();
}
