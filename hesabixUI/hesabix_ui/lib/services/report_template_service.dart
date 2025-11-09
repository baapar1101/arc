import '../core/api_client.dart';

class ReportTemplateService {
  final ApiClient _api;
  ReportTemplateService(this._api);

  Future<List<Map<String, dynamic>>> listTemplates({
    required int businessId,
    String? moduleKey,
    String? subtype,
    String? status,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/report-templates/business/$businessId',
      query: {
        if (moduleKey != null && moduleKey.isNotEmpty) 'module_key': moduleKey,
        if (subtype != null && subtype.isNotEmpty) 'subtype': subtype,
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    final items = (res.data?['items'] as List?) ?? const [];
    return items.cast<Map<String, dynamic>>();
  }

  Future<int> createTemplate({
    required int businessId,
    required String moduleKey,
    String? subtype,
    required String name,
    String? description,
    required String contentHtml,
    String? contentCss,
    String? headerHtml,
    String? footerHtml,
    String? paperSize,
    String? orientation,
    Map<String, dynamic>? margins,
    Map<String, dynamic>? assets,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/report-templates/business/$businessId',
      data: {
        'module_key': moduleKey,
        if (subtype != null) 'subtype': subtype,
        'name': name,
        if (description != null) 'description': description,
        'content_html': contentHtml,
        if (contentCss != null) 'content_css': contentCss,
        if (headerHtml != null) 'header_html': headerHtml,
        if (footerHtml != null) 'footer_html': footerHtml,
        if (paperSize != null) 'paper_size': paperSize,
        if (orientation != null) 'orientation': orientation,
        if (margins != null) 'margins': margins,
        if (assets != null) 'assets': assets,
      },
    );
    return (res.data?['id'] as num).toInt();
  }

  Future<Map<String, dynamic>> updateTemplate({
    required int businessId,
    required int templateId,
    Map<String, dynamic>? changes,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/report-templates/$templateId/business/$businessId',
      data: changes ?? const <String, dynamic>{},
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getTemplate({
    required int businessId,
    required int templateId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/report-templates/$templateId/business/$businessId',
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<void> deleteTemplate({
    required int businessId,
    required int templateId,
  }) async {
    await _api.delete<Map<String, dynamic>>(
      '/report-templates/$templateId/business/$businessId',
    );
  }

  Future<Map<String, dynamic>> publish({
    required int businessId,
    required int templateId,
    required bool published,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/report-templates/$templateId/business/$businessId/publish',
      data: {'published': published},
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> setDefault({
    required int businessId,
    required String moduleKey,
    String? subtype,
    required int templateId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/report-templates/business/$businessId/set-default',
      data: {
        'module_key': moduleKey,
        if (subtype != null) 'subtype': subtype,
        'template_id': templateId,
      },
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> preview({
    required int businessId,
    required String contentHtml,
    String? contentCss,
    Map<String, dynamic>? context,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/report-templates/business/$businessId/preview',
      data: {
        'content_html': contentHtml,
        if (contentCss != null) 'content_css': contentCss,
        'context': context ?? const <String, dynamic>{},
      },
    );
    return res.data ?? const <String, dynamic>{};
  }
}


