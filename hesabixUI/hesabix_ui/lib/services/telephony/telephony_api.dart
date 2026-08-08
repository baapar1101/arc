import '../../core/api_client.dart';

/// کلاینت REST افزونه اتصال آستریکس/ایزابل.
class TelephonyApi {
  TelephonyApi({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Map<String, dynamic> _data(dynamic body) {
    if (body is Map<String, dynamic>) {
      final data = body['data'];
      if (data is Map<String, dynamic>) return Map<String, dynamic>.from(data);
      if (data != null) return <String, dynamic>{'value': data};
      return Map<String, dynamic>.from(body);
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getMyContext(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/telephony/business/$businessId/me/context');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> getDashboard(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/telephony/business/$businessId/dashboard');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> getSettings(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/telephony/business/$businessId/settings');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> updateSettings(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/settings',
      data: payload,
    );
    return _data(res.data);
  }

  Future<List<Map<String, dynamic>>> listPbx(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/telephony/business/$businessId/pbx');
    final data = _data(res.data);
    final items = data['items'];
    if (items is List) {
      return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> createPbx(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/pbx',
      data: payload,
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> rotateToken(int businessId, int pbxId) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/pbx/$pbxId/rotate-token',
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> patchPbx(int businessId, int pbxId, Map<String, dynamic> payload) async {
    final res = await _api.patch<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/pbx/$pbxId',
      data: payload,
    );
    return _data(res.data);
  }

  Future<List<Map<String, dynamic>>> listExtensions(int businessId, {int? pbxId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/extensions',
      query: {if (pbxId != null) 'pbx_id': '$pbxId'},
    );
    final data = _data(res.data);
    final items = data['items'];
    if (items is List) {
      return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> upsertExtension(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/extensions',
      data: payload,
    );
    return _data(res.data);
  }

  Future<List<Map<String, dynamic>>> listUserExtensions(int businessId, {int? userId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/user-extensions',
      query: {if (userId != null) 'user_id': '$userId'},
    );
    final data = _data(res.data);
    final items = data['items'];
    if (items is List) {
      return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> upsertUserExtension(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/user-extensions',
      data: payload,
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> listCalls(
    int businessId, {
    String? direction,
    String? status,
    String? q,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/calls',
      query: {
        if (direction != null) 'direction': direction,
        if (status != null) 'status': status,
        if (q != null && q.isNotEmpty) 'q': q,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> getCall(int businessId, int callId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/telephony/business/$businessId/calls/$callId');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> patchCall(int businessId, int callId, Map<String, dynamic> payload) async {
    final res = await _api.patch<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/calls/$callId',
      data: payload,
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> screenPopContext(int businessId, int callId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/calls/$callId/screen-pop-context',
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> clickToCall(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/click-to-call',
      data: payload,
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> createPersonFromCall(
    int businessId,
    int callId, {
    Map<String, dynamic>? payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/calls/$callId/create-person',
      data: payload ?? const {},
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> createLeadFromCall(
    int businessId,
    int callId, {
    Map<String, dynamic>? payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/calls/$callId/create-lead',
      data: payload ?? const {},
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> lookupNumber(int businessId, String number) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/lookup-number',
      query: {'number': number},
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> reportSummary(int businessId, {String? dateFrom, String? dateTo}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/reports/summary',
      query: {
        if (dateFrom != null) 'date_from': dateFrom,
        if (dateTo != null) 'date_to': dateTo,
      },
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> reportOperators(int businessId, {String? dateFrom, String? dateTo}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/reports/operators',
      query: {
        if (dateFrom != null) 'date_from': dateFrom,
        if (dateTo != null) 'date_to': dateTo,
      },
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> liveSnapshot(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/telephony/business/$businessId/live/snapshot');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> controlCall(
    int businessId,
    int callId, {
    required String action,
    String? target,
    Map<String, dynamic>? extra,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/calls/$callId/control',
      data: {
        'action': action,
        if (target != null) 'target': target,
        ...?extra,
      },
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> recordingInfo(int businessId, int callId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/calls/$callId/recording',
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> opsMetrics(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/telephony/business/$businessId/ops/metrics');
    return _data(res.data);
  }

  Future<List<Map<String, dynamic>>> deadLetters(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/telephony/business/$businessId/ops/dead-letters');
    final data = _data(res.data);
    final items = data['items'];
    if (items is List) {
      return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<void> resolveDeadLetter(int businessId, int dlqId) async {
    await _api.post<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/ops/dead-letters/$dlqId/resolve',
    );
  }

  // ── Softphone Relay ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> softphoneHealth(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/telephony/business/$businessId/softphone/health');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> softphoneDevicesConfig(int businessId) async {
    final res =
        await _api.get<Map<String, dynamic>>('/api/v1/telephony/business/$businessId/softphone/devices-config');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> createSoftphoneSession(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/softphone/sessions',
      data: payload,
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> softphoneHeartbeat(int businessId, String sessionId) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/softphone/sessions/$sessionId/heartbeat',
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> endSoftphoneSession(int businessId, String sessionId) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/softphone/sessions/$sessionId',
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> softphoneOutboundCall(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/softphone/calls',
      data: payload,
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> softphoneAnswerCall(
    int businessId,
    int callId,
    Map<String, dynamic> payload,
  ) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/softphone/calls/$callId/answer',
      data: payload,
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> softphoneDtmf(
    int businessId,
    int callId,
    Map<String, dynamic> payload,
  ) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/telephony/business/$businessId/softphone/calls/$callId/dtmf',
      data: payload,
    );
    return _data(res.data);
  }
}
