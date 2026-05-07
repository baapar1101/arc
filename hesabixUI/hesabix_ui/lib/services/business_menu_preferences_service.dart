import '../core/api_client.dart';

class BusinessMenuPreferencesDto {
  final List<String> rootOrder;
  final List<String> hiddenKeys;
  final Map<String, List<String>> childrenOrder;

  const BusinessMenuPreferencesDto({
    required this.rootOrder,
    required this.hiddenKeys,
    required this.childrenOrder,
  });

  factory BusinessMenuPreferencesDto.empty() {
    return const BusinessMenuPreferencesDto(
      rootOrder: <String>[],
      hiddenKeys: <String>[],
      childrenOrder: <String, List<String>>{},
    );
  }

  factory BusinessMenuPreferencesDto.fromJson(Map<String, dynamic> json) {
    List<String> castList(dynamic raw) {
      if (raw is! List) return const <String>[];
      return raw.map((e) => e.toString()).toList();
    }

    final childrenRaw = json['children_order'];
    final children = <String, List<String>>{};
    if (childrenRaw is Map) {
      for (final entry in childrenRaw.entries) {
        children[entry.key.toString()] = castList(entry.value);
      }
    }

    return BusinessMenuPreferencesDto(
      rootOrder: castList(json['root_order']),
      hiddenKeys: castList(json['hidden_keys']),
      childrenOrder: children,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'root_order': rootOrder,
      'hidden_keys': hiddenKeys,
      'children_order': childrenOrder,
    };
  }
}

class BusinessMenuPreferencesService {
  final ApiClient _api;

  BusinessMenuPreferencesService(this._api);

  Future<BusinessMenuPreferencesDto> getPreferences(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/business/$businessId/menu-preferences');
    final data = Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
    return BusinessMenuPreferencesDto.fromJson(data);
  }

  Future<BusinessMenuPreferencesDto> putPreferences(
    int businessId,
    BusinessMenuPreferencesDto dto,
  ) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/business/$businessId/menu-preferences',
      data: dto.toJson(),
    );
    final data = Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
    return BusinessMenuPreferencesDto.fromJson(data);
  }
}
