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
    String? engine,
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
        if (engine != null) 'engine': engine,
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

  Future<List<Map<String, dynamic>>> statusEvents({
    required int businessId,
    required int templateId,
    int limit = 50,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/report-templates/$templateId/business/$businessId/status-events',
      query: {'limit': limit},
    );
    final items = (res.data?['items'] as List?) ?? const [];
    return items.cast<Map<String, dynamic>>();
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

  Future<Map<String, dynamic>> transitionStatus({
    required int businessId,
    required int templateId,
    required String toStatus,
    String? reason,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/report-templates/$templateId/business/$businessId/transition',
      data: {
        'to_status': toStatus,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
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
    String? contentHtml,
    String? contentCss,
    String? headerHtml,
    String? footerHtml,
    String? engine,
    Map<String, dynamic>? design,
    Map<String, dynamic>? assets,
    Map<String, dynamic>? context,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/report-templates/business/$businessId/preview',
      data: {
        if (contentHtml != null) 'content_html': contentHtml,
        if (contentCss != null) 'content_css': contentCss,
        if (headerHtml != null) 'header_html': headerHtml,
        if (footerHtml != null) 'footer_html': footerHtml,
        if (engine != null) 'engine': engine,
        if (design != null) 'design': design,
        if (assets != null) 'assets': assets,
        'context': context ?? const <String, dynamic>{},
      },
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> schema({
    required int businessId,
    required String moduleKey,
    String? subtype,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/report-templates/business/$businessId/schema',
      query: {
        'module_key': moduleKey,
        if (subtype != null && subtype.isNotEmpty) 'subtype': subtype,
      },
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> scopeCatalog({
    required int businessId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/report-templates/business/$businessId/scope-catalog',
    );
    final items = (res.data?['items'] as List?) ?? const [];
    return items.cast<Map<String, dynamic>>();
  }

  Future<List<int>> previewPdf({
    required int businessId,
    String? contentHtml,
    String? contentCss,
    String? headerHtml,
    String? footerHtml,
    String? engine,
    Map<String, dynamic>? design,
    Map<String, dynamic>? assets,
    Map<String, dynamic>? context,
    String? paperSize,
    String? orientation,
    Map<String, dynamic>? margins,
  }) async {
    final res = await _api.downloadPdf(
      '/report-templates/business/$businessId/preview-pdf',
      query: null,
      data: {
        if (contentHtml != null) 'content_html': contentHtml,
        if (contentCss != null) 'content_css': contentCss,
        if (headerHtml != null) 'header_html': headerHtml,
        if (footerHtml != null) 'footer_html': footerHtml,
        if (engine != null) 'engine': engine,
        if (design != null) 'design': design,
        if (assets != null) 'assets': assets,
        'context': context ?? const <String, dynamic>{},
        if (paperSize != null) 'paper_size': paperSize,
        if (orientation != null) 'orientation': orientation,
        if (margins != null) 'margins': margins,
      },
    );
    return res;
  }

  Future<Map<String, dynamic>> validateBuilderDesign({
    required int businessId,
    required String moduleKey,
    String? subtype,
    required Map<String, dynamic> design,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/report-templates/business/$businessId/validate-builder-design',
      data: {
        'module_key': moduleKey,
        if (subtype != null) 'subtype': subtype,
        'design': design,
      },
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> statusEventsReport({
    required int businessId,
    String? status,
    int? actorUserId,
    String? fromDate,
    String? toDate,
    int offset = 0,
    String sortBy = 'created_at',
    String sortOrder = 'desc',
    int limit = 100,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/report-templates/business/$businessId/status-events',
      query: {
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        if (actorUserId != null) 'actor_user_id': actorUserId,
        if (fromDate != null && fromDate.trim().isNotEmpty) 'from_date': fromDate.trim(),
        if (toDate != null && toDate.trim().isNotEmpty) 'to_date': toDate.trim(),
        'offset': offset,
        'sort_by': sortBy,
        'sort_order': sortOrder,
        'limit': limit,
      },
    );
    return res.data ?? const <String, dynamic>{};
  }
}


