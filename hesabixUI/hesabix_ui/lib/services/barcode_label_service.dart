import '../core/api_client.dart';
import '../models/barcode_label/label_design_v1.dart';
import '../models/barcode_label/label_printer_profile.dart';

class BarcodeLabelService {
  final ApiClient _api;
  BarcodeLabelService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  String _base(int businessId) => '/api/v1/barcode-labels/business/$businessId';

  Future<List<LabelTemplateSummary>> listTemplates({
    required int businessId,
    String status = 'all',
    String? q,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '${_base(businessId)}/templates',
      query: {
        'status': status,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      },
    );
    final data = res.data?['data'];
    final items = (data is Map ? data['items'] : null) as List? ?? const [];
    return items
        .whereType<Map>()
        .map((e) => LabelTemplateSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<LabelTemplateDetail> getTemplate({
    required int businessId,
    required int templateId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '${_base(businessId)}/templates/$templateId',
    );
    return LabelTemplateDetail.fromJson(
      Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {}),
    );
  }

  Future<LabelTemplateDetail?> getDefaultTemplate({required int businessId}) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        '${_base(businessId)}/templates/default',
      );
      return LabelTemplateDetail.fromJson(
        Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {}),
      );
    } catch (_) {
      return null;
    }
  }

  Future<LabelTemplateDetail> createTemplate({
    required int businessId,
    required String name,
    String? description,
    Map<String, dynamic>? designJson,
    Map<String, dynamic>? sheetJson,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '${_base(businessId)}/templates',
      data: {
        'name': name,
        if (description != null) 'description': description,
        if (designJson != null) 'design_json': designJson,
        if (sheetJson != null) 'sheet_json': sheetJson,
      },
    );
    return LabelTemplateDetail.fromJson(
      Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {}),
    );
  }

  Future<LabelTemplateDetail> updateTemplate({
    required int businessId,
    required int templateId,
    String? name,
    String? description,
    Map<String, dynamic>? designJson,
    Map<String, dynamic>? sheetJson,
    String? changelog,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (description != null) payload['description'] = description;
    if (designJson != null) payload['design_json'] = designJson;
    if (sheetJson != null) payload['sheet_json'] = sheetJson;
    if (changelog != null) payload['changelog'] = changelog;
    final res = await _api.put<Map<String, dynamic>>(
      '${_base(businessId)}/templates/$templateId',
      data: payload,
    );
    return LabelTemplateDetail.fromJson(
      Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {}),
    );
  }

  Future<LabelTemplateDetail> publishTemplate({
    required int businessId,
    required int templateId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '${_base(businessId)}/templates/$templateId/publish',
    );
    return LabelTemplateDetail.fromJson(
      Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {}),
    );
  }

  Future<LabelTemplateDetail> archiveTemplate({
    required int businessId,
    required int templateId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '${_base(businessId)}/templates/$templateId/archive',
    );
    return LabelTemplateDetail.fromJson(
      Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {}),
    );
  }

  Future<LabelTemplateDetail> duplicateTemplate({
    required int businessId,
    required int templateId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '${_base(businessId)}/templates/$templateId/duplicate',
    );
    return LabelTemplateDetail.fromJson(
      Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {}),
    );
  }

  Future<LabelTemplateDetail> setDefault({
    required int businessId,
    required int templateId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '${_base(businessId)}/templates/set-default',
      data: {'template_id': templateId},
    );
    return LabelTemplateDetail.fromJson(
      Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {}),
    );
  }

  Future<List<LabelPreset>> listPresets({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '${_base(businessId)}/presets',
    );
    final data = res.data?['data'];
    final items = (data is Map ? data['items'] : null) as List? ?? const [];
    return items
        .whereType<Map>()
        .map((e) => LabelPreset.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<LabelTemplateDetail> createFromPreset({
    required int businessId,
    required String presetCode,
    String? name,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '${_base(businessId)}/templates/from-preset',
      data: {
        'preset_code': presetCode,
        if (name != null) 'name': name,
      },
    );
    return LabelTemplateDetail.fromJson(
      Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {}),
    );
  }

  Future<Map<String, dynamic>> sampleContext({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '${_base(businessId)}/sample-context',
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<LabelPrinterSettings> getPrinterSettings({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '${_base(businessId)}/printer-settings',
    );
    return LabelPrinterSettings.fromJson(
      Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {}),
    );
  }

  Future<LabelPrinterSettings> savePrinterSettings({
    required int businessId,
    required LabelPrinterSettings settings,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '${_base(businessId)}/printer-settings',
      data: settings.toJson(),
    );
    return LabelPrinterSettings.fromJson(
      Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {}),
    );
  }
}
