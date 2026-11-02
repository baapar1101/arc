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
