import 'package:dio/dio.dart';

import '../core/api_client.dart';

int? oaId(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

/// سرویس API اتوماسیون اداری سمت‌محور (`/api/v1/office-automation/...`).
class OfficeAutomationService {
  final ApiClient _api;

  OfficeAutomationService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Options _opts(int? positionId) => Options(
        headers: {
          if (positionId != null) 'X-OA-Position-Id': '$positionId',
        },
      );

  Map<String, dynamic> _posQuery(int? positionId, [Map<String, dynamic>? extra]) => {
        if (positionId != null) 'as_position_id': positionId,
        ...?extra,
      };

  Future<Map<String, dynamic>> getSettings({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/settings',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> updateSettings({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/settings',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> getPersonalDesk({
    required int businessId,
    required int positionId,
    int horizonDays = 7,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/desk',
      query: _posQuery(positionId, {'horizon_days': horizonDays}),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> publishLinearProcess({
    required int businessId,
    required String name,
    required int assigneePositionId,
    String? code,
    int? slaHours,
    String? formLabel,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/processes/linear',
      data: {
        'name': name,
        'assignee_position_id': assigneePositionId,
        if (code != null && code.isNotEmpty) 'code': code,
        if (slaHours != null && slaHours > 0) 'sla_hours': slaHours,
        if (formLabel != null && formLabel.isNotEmpty) 'form_label': formLabel,
      },
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listProcessDefinitions({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/processes',
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> saveProcessDraft({
    required int businessId,
    required String code,
    required String name,
    required Map<String, dynamic> graph,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/processes',
      data: {'code': code, 'name': name, 'graph': graph},
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> publishProcess({
    required int businessId,
    required int definitionId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/processes/$definitionId/publish',
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listProcessVersions({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/process-versions',
    );
    final data = _extractData(res.data);
    final items = data['items'];
    if (items is List) return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    return const [];
  }

  Future<Map<String, dynamic>> startProcess({
    required int businessId,
    required int versionId,
    required int positionId,
    Map<String, dynamic>? variables,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/process-versions/$versionId/start',
      data: {'variables': variables ?? const {}},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listProcessTasks({
    required int businessId,
    required int positionId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/process-tasks',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    final data = _extractData(res.data);
    final items = data['items'];
    if (items is List) return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    return const [];
  }

  Future<Map<String, dynamic>> completeProcessTask({
    required int businessId,
    required int taskId,
    required int positionId,
    required Map<String, dynamic> form,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/process-tasks/$taskId/complete',
      data: {'form': form},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> registerDocument({
    required int businessId,
    required int positionId,
    required String title,
    required String fileStorageId,
    String confidentiality = 'normal',
    int? letterId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/documents',
      data: {
        'title': title,
        'file_storage_id': fileStorageId,
        'confidentiality': confidentiality,
        if (letterId != null) 'letter_id': letterId,
      },
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> addDocumentVersion({
    required int businessId,
    required int documentId,
    required int positionId,
    required String fileStorageId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/documents/$documentId/versions',
      data: {'file_storage_id': fileStorageId},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> searchDocuments({
    required int businessId,
    required int positionId,
    String? q,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/documents',
      query: _posQuery(positionId, {if (q != null && q.isNotEmpty) 'q': q}),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> getDocument({
    required int businessId,
    required int documentId,
    required int positionId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/documents/$documentId',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> decideDocumentSuggestion({
    required int businessId,
    required int suggestionId,
    required int positionId,
    required bool accept,
  }) async {
    final action = accept ? 'accept' : 'reject';
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/document-suggestions/$suggestionId/$action',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listBranches({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/office-automation/business/$businessId/branches');
    final data = _extractData(res.data);
    return List<Map<String, dynamic>>.from(data['items'] as List? ?? const []);
  }

  Future<void> createSignatureProvider({
    required int businessId,
    required String code,
    required String name,
    String? endpointUrl,
    String? accessToken,
  }) async {
    await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/signature-providers',
      data: {
        'code': code,
        'name': name,
        if (endpointUrl != null && endpointUrl.isNotEmpty) 'endpoint_url': endpointUrl,
        if (accessToken != null && accessToken.isNotEmpty) 'access_token': accessToken,
      },
    );
  }

  Future<void> createBranch({required int businessId, required String code, required String name}) async {
    await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/branches',
      data: {'code': code, 'name': name},
    );
  }

  Future<List<Map<String, dynamic>>> listRetentionPolicies({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/office-automation/business/$businessId/retention-policies');
    final data = _extractData(res.data);
    return List<Map<String, dynamic>>.from(data['items'] as List? ?? const []);
  }

  Future<void> saveRetentionPolicy({
    required int businessId,
    required String confidentiality,
    required int retainDays,
  }) async {
    await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/retention-policies',
      data: {'confidentiality': confidentiality, 'retain_days': retainDays},
    );
  }

  Future<List<Map<String, dynamic>>> listSignatureProviders({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/office-automation/business/$businessId/signature-providers');
    final data = _extractData(res.data);
    return List<Map<String, dynamic>>.from(data['items'] as List? ?? const []);
  }

  Future<List<Map<String, dynamic>>> listQualifiedRequests({
    required int businessId,
    required int letterId,
    required int positionId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/qualified-signatures',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    final data = _extractData(res.data);
    return List<Map<String, dynamic>>.from(data['items'] as List? ?? const []);
  }

  Future<void> requestQualifiedSignature({
    required int businessId,
    required int letterId,
    required int positionId,
    required int providerId,
  }) async {
    await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/qualified-signature',
      query: _posQuery(positionId),
      options: _opts(positionId),
      data: {'provider_id': providerId, 'as_position_id': positionId},
    );
  }

  Future<void> recordQualifiedResult({
    required int businessId,
    required int requestId,
    required String externalRef,
    required String outcome,
  }) async {
    await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/qualified-signatures/$requestId/result',
      data: {'external_ref': externalRef, 'outcome': outcome},
    );
  }

  Future<void> exchangeLetter({
    required int businessId,
    required int letterId,
    required int positionId,
    required int targetBusinessId,
    required int targetPositionId,
  }) async {
    await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/exchange',
      query: _posQuery(positionId),
      options: _opts(positionId),
      data: {
        'as_position_id': positionId,
        'target_business_id': targetBusinessId,
        'target_position_id': targetPositionId,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listRetentionReviews({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/office-automation/business/$businessId/retention-reviews');
    final data = _extractData(res.data);
    return List<Map<String, dynamic>>.from(data['items'] as List? ?? const []);
  }

  Future<List<Map<String, dynamic>>> listRetentionDocuments({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/office-automation/business/$businessId/retention-reviews');
    final data = _extractData(res.data);
    return List<Map<String, dynamic>>.from(data['documents'] as List? ?? const []);
  }

  Future<void> holdLetterRetention({required int businessId, required int letterId}) async {
    await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/retention-hold',
    );
  }

  Future<void> holdDocumentRetention({required int businessId, required int documentId}) async {
    await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/documents/$documentId/retention-hold',
    );
  }

  Future<List<Map<String, dynamic>>> listMcpConfirmations({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/mcp-confirmations',
    );
    final data = _extractData(res.data);
    return List<Map<String, dynamic>>.from(data['items'] as List? ?? const []);
  }

  Future<void> decideMcpConfirmation({
    required int businessId,
    required int confirmationId,
    required bool accept,
  }) async {
    final action = accept ? 'approve' : 'reject';
    await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/mcp-confirmations/$confirmationId/$action',
    );
  }

  Future<Map<String, dynamic>> getDashboard({
    required int businessId,
    int? positionId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/dashboard',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listOrgUnits({
    required int businessId,
    bool includeInactive = false,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/org-units',
      query: {'include_inactive': '$includeInactive'},
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> createOrgUnit({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/org-units',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> updateOrgUnit({
    required int businessId,
    required int unitId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/org-units/$unitId',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listPositions({
    required int businessId,
    bool includeInactive = false,
    String? q,
    int? limit,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/positions',
      query: {
        'include_inactive': '$includeInactive',
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (limit != null) 'limit': limit,
      },
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> createPosition({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/positions',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> updatePosition({
    required int businessId,
    required int positionId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/positions/$positionId',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listMyPositions({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/my-positions',
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<List<Map<String, dynamic>>> listHolders({
    required int businessId,
    int? positionId,
    int? userId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/holders',
      query: {
        if (positionId != null) 'position_id': positionId,
        if (userId != null) 'user_id': userId,
      },
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> assignHolder({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/holders',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> endHolder({
    required int businessId,
    required int holderId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/holders/$holderId/end',
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listDelegations({
    required int businessId,
    int? positionId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/delegations',
      query: {if (positionId != null) 'position_id': positionId},
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> createDelegation({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/delegations',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> endDelegation({
    required int businessId,
    required int delegationId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/delegations/$delegationId/end',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> listCartable({
    required int businessId,
    required int positionId,
    String folder = 'inbox',
    String? q,
    String? dateFrom,
    String? dateTo,
    int limit = 50,
    int skip = 0,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/cartable',
      query: _posQuery(positionId, {
        'folder': folder,
        if (q != null && q.isNotEmpty) 'q': q,
        if (dateFrom != null) 'date_from': dateFrom,
        if (dateTo != null) 'date_to': dateTo,
        'limit': limit,
        'skip': skip,
      }),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> listCartableBoard({
    required int businessId,
    required int positionId,
    String? q,
    int limit = 40,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/cartable/board',
      query: _posQuery(positionId, {
        if (q != null && q.isNotEmpty) 'q': q,
        'limit': limit,
      }),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listSavedFilters({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/cartable/filters',
    );
    final data = _extractData(res.data);
    final items = data['items'];
    if (items is List) {
      return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> saveSavedFilter({
    required int businessId,
    required String name,
    required String folder,
    String? q,
    String? dateFrom,
    String? dateTo,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/cartable/filters',
      data: {
        'name': name,
        'folder': folder,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
      },
    );
    return _extractData(res.data);
  }

  Future<void> deleteSavedFilter({required int businessId, required int filterId}) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/cartable/filters/$filterId',
    );
  }

  Future<Map<String, dynamic>> createDraft({
    required int businessId,
    required int positionId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters',
      data: payload,
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> getLetter({
    required int businessId,
    required int letterId,
    int? positionId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listCommercialLinks({
    required int businessId,
    required int letterId,
    required int positionId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/commercial-links',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    final data = _extractData(res.data);
    return List<Map<String, dynamic>>.from(data['items'] as List? ?? const []);
  }

  Future<void> linkCommercial({
    required int businessId,
    required int letterId,
    required int positionId,
    required String targetKind,
    required int targetId,
  }) async {
    await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/commercial-links',
      data: {'target_kind': targetKind, 'target_id': targetId},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
  }

  Future<Map<String, dynamic>> getLetterPrint({
    required int businessId,
    required int letterId,
    int? positionId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/print',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> updateDraft({
    required int businessId,
    required int letterId,
    required int positionId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId',
      data: payload,
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> deleteDraft({
    required int businessId,
    required int letterId,
    required int positionId,
  }) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> registerLetter({
    required int businessId,
    required int letterId,
    required int positionId,
    Map<String, dynamic>? payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/register',
      data: payload ?? const {},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> referLetter({
    required int businessId,
    required int letterId,
    required int positionId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/refer',
      data: payload,
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> completeReferral({
    required int businessId,
    required int referralId,
    required int positionId,
    String? note,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/referrals/$referralId/complete',
      data: {'note': note},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> returnReferral({
    required int businessId,
    required int referralId,
    required int positionId,
    String? note,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/referrals/$referralId/return',
      data: {'note': note},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> addParaph({
    required int businessId,
    required int letterId,
    required int positionId,
    required String text,
    int? referralId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/paraphs',
      data: {'text': text, if (referralId != null) 'referral_id': referralId},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> uploadAttachment({
    required int businessId,
    required int letterId,
    required int positionId,
    required List<int> bytes,
    required String filename,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/attachments/upload',
      data: form,
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> removeAttachment({
    required int businessId,
    required int attachmentId,
    required int positionId,
  }) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/attachments/$attachmentId',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> archiveLetter({
    required int businessId,
    required int letterId,
    required int positionId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/archive',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> setFollowUp({
    required int businessId,
    required int letterId,
    required int positionId,
    String? followUpAt,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/follow-up',
      data: {'follow_up_at': followUpAt},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> replyToLetter({
    required int businessId,
    required int letterId,
    required int positionId,
    String? subject,
    String? body,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/reply',
      data: {
        if (subject != null && subject.trim().isNotEmpty) 'subject': subject.trim(),
        if (body != null) 'body': body,
      },
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> linkLetters({
    required int businessId,
    required int letterId,
    required int positionId,
    required int relatedLetterId,
    String linkKind = 'related',
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/links',
      data: {'related_letter_id': relatedLetterId, 'link_kind': linkKind},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listFormats({
    required int businessId,
    bool includeInactive = false,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/formats',
      query: {'include_inactive': '$includeInactive'},
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> createFormat({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/formats',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> updateFormat({
    required int businessId,
    required int formatId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/formats/$formatId',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> deleteFormat({
    required int businessId,
    required int formatId,
  }) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/formats/$formatId',
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listTemplates({
    required int businessId,
    bool includeInactive = false,
    String? letterKind,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/templates',
      query: {
        'include_inactive': '$includeInactive',
        if (letterKind != null && letterKind.isNotEmpty) 'letter_kind': letterKind,
      },
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> createTemplate({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/templates',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> updateTemplate({
    required int businessId,
    required int templateId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/templates/$templateId',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> deleteTemplate({
    required int businessId,
    required int templateId,
  }) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/templates/$templateId',
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> searchLetters({
    required int businessId,
    String? q,
    int limit = 20,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/search',
      query: {
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        'limit': limit,
      },
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<List<Map<String, dynamic>>> listSecretariats({
    required int businessId,
    bool includeInactive = false,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/secretariats',
      query: {'include_inactive': '$includeInactive'},
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> createSecretariat({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/secretariats',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> updateSecretariat({
    required int businessId,
    required int secretariatId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/secretariats/$secretariatId',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listExternalOrgs({
    required int businessId,
    String? q,
    bool includeInactive = false,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/external-orgs',
      query: {
        'include_inactive': '$includeInactive',
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      },
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> createExternalOrg({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/external-orgs',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> updateExternalOrg({
    required int businessId,
    required int orgId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/external-orgs/$orgId',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listSignatures({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/signatures',
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> upsertSignature({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/signatures',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listSignPaths({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/sign-paths',
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> saveSignPath({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/sign-paths',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> startSignPath({
    required int businessId,
    required int letterId,
    required int positionId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/sign-path',
      data: payload,
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> signLetter({
    required int businessId,
    required int letterId,
    required int positionId,
    Map<String, dynamic>? payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/sign',
      data: payload ?? const {},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> rejectSign({
    required int businessId,
    required int letterId,
    required int positionId,
    String? note,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/sign/reject',
      data: {'note': note},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> dispatchLetter({
    required int businessId,
    required int letterId,
    required int positionId,
    required int toPositionId,
    String? instruction,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/dispatch',
      data: {'to_position_id': toPositionId, 'instruction': instruction},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> acknowledgeDispatch({
    required int businessId,
    required int dispatchId,
    required int positionId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/dispatches/$dispatchId/acknowledge',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listLetterVersions({
    required int businessId,
    required int letterId,
    int? positionId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/versions',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> exportEce({
    required int businessId,
    required int letterId,
    required int positionId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/ece/export',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> sendEce({
    required int businessId,
    required int letterId,
    required int positionId,
    String? toEmail,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/ece/send',
      data: {'to_email': toEmail},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> importEce({
    required int businessId,
    required int positionId,
    required String xml,
    String? fromEmail,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/ece/import',
      data: {'xml': xml, 'from_email': fromEmail},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listEce({required int businessId, String? direction}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/ece',
      query: {if (direction != null) 'direction': direction},
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<List<Map<String, dynamic>>> listCartableRules({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/cartable-rules',
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> saveCartableRule({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/cartable-rules',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<void> deleteCartableRule({required int businessId, required int ruleId}) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/cartable-rules/$ruleId',
    );
  }

  Future<List<Map<String, dynamic>>> listArchiveFolders({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/archive-folders',
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> saveArchiveFolder({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/archive-folders',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> archiveToFolder({
    required int businessId,
    required int letterId,
    required int positionId,
    required int folderId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/archive-to-folder',
      data: {'folder_id': folderId},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> cancelReferral({
    required int businessId,
    required int referralId,
    required int positionId,
    String? note,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/referrals/$referralId/cancel',
      data: {'note': note},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> unarchiveLetter({
    required int businessId,
    required int letterId,
    required int positionId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/unarchive',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> delayReport({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/reports/delay',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> volumeReport({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/reports/volume',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> performanceReport({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/reports/performance',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> importEmail({
    required int businessId,
    required int positionId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/mailbox/import',
      data: payload,
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> sendLetterEmail({
    required int businessId,
    required int letterId,
    required int positionId,
    required String toEmail,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/email',
      data: {'to_email': toEmail},
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> ocrLetter({
    required int businessId,
    required int letterId,
    required int positionId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/ocr',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> summarizeLetter({
    required int businessId,
    required int letterId,
    required int positionId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/office-automation/business/$businessId/letters/$letterId/ai-summary',
      query: _posQuery(positionId),
      options: _opts(positionId),
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> publicTrack({required String token}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/office-automation/public/track/${Uri.encodeComponent(token)}',
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listBusinessUsers({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/business/$businessId/users');
    final body = res.data ?? const {};
    final nested = body['data'];
    if (nested is Map && nested['users'] is List) {
      return _asMapList(nested['users']);
    }
    return _asMapList(body['users']);
  }

  Map<String, dynamic> _extractData(Map<String, dynamic>? body) {
    if (body is Map<String, dynamic>) {
      final data = body['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return Map<String, dynamic>.from(body);
    }
    return const {};
  }

  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
