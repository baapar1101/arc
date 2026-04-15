import '../core/api_client.dart';

class CrmService {
  final ApiClient _apiClient;

  CrmService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// داده‌ی خروجی API را استخراج می‌کند. می‌تواند List یا Map باشد.
  dynamic _extractData(dynamic response) {
    if (response == null) return <String, dynamic>{};
    final body = response is Map<String, dynamic> ? response : null;
    if (body != null && body['data'] != null) return body['data'];
    return body ?? <String, dynamic>{};
  }

  List<dynamic> _extractList(dynamic response) {
    final data = _extractData(response);
    if (data['data'] is List) return data['data'] as List<dynamic>;
    if (data is List) return data;
    return [];
  }

  /// پیگیری‌های امروز (سرنخ و فرصت با یادآور در امروز تا N روز آینده)
  Future<Map<String, dynamic>> getFollowUpsToday({
    required int businessId,
    int daysAhead = 7,
  }) async {
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/follow-ups-today',
      query: {'days_ahead': daysAhead},
    );
    return _extractData(res.data) is Map
        ? Map<String, dynamic>.from(_extractData(res.data) as Map)
        : <String, dynamic>{'leads': [], 'deals': []};
  }

  /// تاریخچه تغییرات سرنخ
  Future<List<dynamic>> getLeadHistory({
    required int businessId,
    required int leadId,
    int limit = 50,
  }) async {
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/leads/$leadId/history',
      query: {'limit': limit},
    );
    final data = _extractData(res.data);
    return data is List ? data : [];
  }

  /// تاریخچه تغییرات فرصت فروش
  Future<List<dynamic>> getDealHistory({
    required int businessId,
    required int dealId,
    int limit = 50,
  }) async {
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/deals/$dealId/history',
      query: {'limit': limit},
    );
    final data = _extractData(res.data);
    return data is List ? data : [];
  }

  /// خلاصه CRM
  Future<Map<String, dynamic>> getSummary({required int businessId}) async {
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/summary',
    );
    return _extractData(res.data);
  }

  /// گزارش پایپلاین فروش
  Future<List<dynamic>> getPipelineReport({
    required int businessId,
    int? processDefinitionId,
    String? fromDate,
    String? toDate,
  }) async {
    final query = <String, dynamic>{};
    if (processDefinitionId != null) query['process_definition_id'] = processDefinitionId;
    if (fromDate != null && fromDate.isNotEmpty) query['from_date'] = fromDate;
    if (toDate != null && toDate.isNotEmpty) query['to_date'] = toDate;
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/reports/pipeline',
      query: query.isEmpty ? null : query,
    );
    final data = _extractData(res.data);
    return data is List ? data : [];
  }

  /// گزارش قیف سرنخ
  Future<List<dynamic>> getLeadFunnelReport({
    required int businessId,
    int? processDefinitionId,
    String? fromDate,
    String? toDate,
  }) async {
    final query = <String, dynamic>{};
    if (processDefinitionId != null) query['process_definition_id'] = processDefinitionId;
    if (fromDate != null && fromDate.isNotEmpty) query['from_date'] = fromDate;
    if (toDate != null && toDate.isNotEmpty) query['to_date'] = toDate;
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/reports/lead-funnel',
      query: query.isEmpty ? null : query,
    );
    final data = _extractData(res.data);
    return data is List ? data : [];
  }

  /// پیش‌بینی درآمد (مبلغ موزون با احتمال)
  Future<Map<String, dynamic>> getWeightedForecast({
    required int businessId,
    int? processDefinitionId,
  }) async {
    final query = processDefinitionId != null ? {'process_definition_id': processDefinitionId} : null;
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/reports/weighted-forecast',
      query: query,
    );
    final data = _extractData(res.data);
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// گزارش منبع سرنخ
  Future<List<dynamic>> getLeadSourcesReport({required int businessId}) async {
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/reports/lead-sources',
    );
    final data = _extractData(res.data);
    return data is List ? data : [];
  }

  /// گزارش عملکرد کارمندان
  /// خروجی: Map با کلیدهای data (List) و restricted_to_self (bool)
  Future<Map<String, dynamic>> getEmployeePerformanceReport({required int businessId}) async {
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/reports/employee-performance',
    );
    final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
    final data = body != null && body['data'] != null ? body['data'] : <dynamic>[];
    final list = data is List ? data : [];
    final restricted = body?['restricted_to_self'] == true;
    return {'data': list, 'restricted_to_self': restricted};
  }

  /// روند فروش در زمان
  Future<List<dynamic>> getSalesTrendReport({
    required int businessId,
    String period = 'month',
    int months = 6,
  }) async {
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/reports/sales-trend',
      query: {'period': period, 'months': months},
    );
    final data = _extractData(res.data);
    return data is List ? data : [];
  }

  /// لیست فرایندهای CRM (خروجی: لیست یا map بسته به پاسخ API)
  Future<dynamic> listProcessDefinitions({
    required int businessId,
    String? processType,
    bool? isActive,
  }) async {
    final queryParams = <String, dynamic>{};
    if (processType != null && processType.isNotEmpty) queryParams['process_type'] = processType;
    if (isActive != null) queryParams['is_active'] = isActive;
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/process-definitions',
      query: queryParams.isNotEmpty ? queryParams : null,
    );
    return _extractData(res.data);
  }

  /// ایجاد فرایند
  Future<Map<String, dynamic>> createProcessDefinition({
    required int businessId,
    required String processType,
    required String code,
    required String name,
    String? description,
    bool isDefault = false,
    bool isActive = true,
    List<Map<String, dynamic>>? stages,
  }) async {
    final body = <String, dynamic>{
      'process_type': processType,
      'code': code,
      'name': name,
      'is_default': isDefault,
      'is_active': isActive,
    };
    if (description != null) body['description'] = description;
    if (stages != null && stages.isNotEmpty) body['stages'] = stages;
    final res = await _apiClient.post<dynamic>(
      '/api/v1/crm/businesses/$businessId/process-definitions',
      data: body,
    );
    return _extractData(res.data);
  }

  /// جزئیات فرایند
  Future<Map<String, dynamic>> getProcessDefinition({
    required int businessId,
    required int definitionId,
  }) async {
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/process-definitions/$definitionId',
    );
    return _extractData(res.data);
  }

  /// ویرایش فرایند
  Future<Map<String, dynamic>> updateProcessDefinition({
    required int businessId,
    required int definitionId,
    String? name,
    String? description,
    bool? isDefault,
    bool? isActive,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (isDefault != null) body['is_default'] = isDefault;
    if (isActive != null) body['is_active'] = isActive;
    final res = await _apiClient.put<dynamic>(
      '/api/v1/crm/businesses/$businessId/process-definitions/$definitionId',
      data: body,
    );
    return _extractData(res.data);
  }

  /// حذف فرایند
  Future<void> deleteProcessDefinition({
    required int businessId,
    required int definitionId,
  }) async {
    await _apiClient.delete(
      '/api/v1/crm/businesses/$businessId/process-definitions/$definitionId',
    );
  }

  /// لیست مراحل یک فرایند
  Future<Map<String, dynamic>> listStages({
    required int businessId,
    required int definitionId,
  }) async {
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/process-definitions/$definitionId/stages',
    );
    return _extractData(res.data);
  }

  /// افزودن مرحله
  Future<Map<String, dynamic>> createStage({
    required int businessId,
    required int definitionId,
    required String stageCode,
    required String name,
    int orderIndex = 0,
    String? color,
    bool isWin = false,
    bool isLost = false,
    List<String>? allowTransitionTo,
  }) async {
    final body = <String, dynamic>{
      'stage_code': stageCode,
      'name': name,
      'order_index': orderIndex,
      'is_win': isWin,
      'is_lost': isLost,
    };
    if (color != null) body['color'] = color;
    if (allowTransitionTo != null) body['allow_transition_to'] = allowTransitionTo;
    final res = await _apiClient.post<dynamic>(
      '/api/v1/crm/businesses/$businessId/process-definitions/$definitionId/stages',
      data: body,
    );
    return _extractData(res.data);
  }

  /// ویرایش مرحله
  Future<Map<String, dynamic>> updateStage({
    required int businessId,
    required int definitionId,
    required int stageId,
    String? stageCode,
    String? name,
    int? orderIndex,
    String? color,
    bool? isWin,
    bool? isLost,
    List<String>? allowTransitionTo,
  }) async {
    final body = <String, dynamic>{};
    if (stageCode != null) body['stage_code'] = stageCode;
    if (name != null) body['name'] = name;
    if (orderIndex != null) body['order_index'] = orderIndex;
    if (color != null) body['color'] = color;
    if (isWin != null) body['is_win'] = isWin;
    if (isLost != null) body['is_lost'] = isLost;
    if (allowTransitionTo != null) body['allow_transition_to'] = allowTransitionTo;
    final res = await _apiClient.put<dynamic>(
      '/api/v1/crm/businesses/$businessId/process-definitions/$definitionId/stages/$stageId',
      data: body,
    );
    return _extractData(res.data);
  }

  /// حذف مرحله
  Future<void> deleteStage({
    required int businessId,
    required int definitionId,
    required int stageId,
  }) async {
    await _apiClient.delete(
      '/api/v1/crm/businesses/$businessId/process-definitions/$definitionId/stages/$stageId',
    );
  }

  // --- دستیار AI در CRM ---

  /// خلاصه و پیشنهاد AI برای سرنخ
  Future<Map<String, dynamic>> aiSummarizeLead({
    required int businessId,
    required int leadId,
  }) async {
    final res = await _apiClient.post<dynamic>(
      '/api/v1/ai/crm/businesses/$businessId/summarize-lead',
      data: {'lead_id': leadId},
    );
    return _extractData(res.data);
  }

  /// خلاصه و پیشنهاد AI برای فرصت فروش
  Future<Map<String, dynamic>> aiSummarizeDeal({
    required int businessId,
    required int dealId,
  }) async {
    final res = await _apiClient.post<dynamic>(
      '/api/v1/ai/crm/businesses/$businessId/summarize-deal',
      data: {'deal_id': dealId},
    );
    return _extractData(res.data);
  }

  /// پیشنهاد متن فعالیت
  Future<Map<String, dynamic>> aiSuggestActivityText({
    required int businessId,
    required int personId,
    String activityType = 'note',
    int? dealId,
  }) async {
    final data = <String, dynamic>{'person_id': personId, 'activity_type': activityType};
    if (dealId != null) data['deal_id'] = dealId;
    final res = await _apiClient.post<dynamic>(
      '/api/v1/ai/crm/businesses/$businessId/suggest-activity-text',
      data: data,
    );
    return _extractData(res.data);
  }

  /// پیشنهاد احتمال موفقیت فرصت فروش
  Future<Map<String, dynamic>> aiSuggestDealProbability({
    required int businessId,
    required int dealId,
  }) async {
    final res = await _apiClient.post<dynamic>(
      '/api/v1/ai/crm/businesses/$businessId/suggest-deal-probability',
      data: {'deal_id': dealId},
    );
    return _extractData(res.data);
  }

  /// لیست سرنخ‌ها
  Future<Map<String, dynamic>> listLeads({
    required int businessId,
    int? processDefinitionId,
    int? stageId,
    int? assignedToUserId,
    String? search,
    String? fromDate,
    String? toDate,
    bool? openOnly,
    int page = 1,
    int limit = 50,
  }) async {
    final queryParams = <String, dynamic>{'page': page, 'limit': limit};
    if (processDefinitionId != null) queryParams['process_definition_id'] = processDefinitionId;
    if (stageId != null) queryParams['stage_id'] = stageId;
    if (assignedToUserId != null) queryParams['assigned_to_user_id'] = assignedToUserId;
    if (search != null && search.trim().isNotEmpty) queryParams['search'] = search.trim();
    if (fromDate != null && fromDate.isNotEmpty) queryParams['from_date'] = fromDate;
    if (toDate != null && toDate.isNotEmpty) queryParams['to_date'] = toDate;
    if (openOnly != null) queryParams['open_only'] = openOnly;
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/leads',
      query: queryParams,
    );
    return _extractData(res.data);
  }

  /// ایجاد سرنخ
  Future<Map<String, dynamic>> createLead({
    required int businessId,
    required int processDefinitionId,
    required int stageId,
    required String name,
    String? code,
    String? sourceCode,
    String? companyName,
    String? mobile,
    String? email,
    String? description,
    int? assignedToUserId,
    DateTime? nextFollowUpAt,
  }) async {
    final body = <String, dynamic>{
      'process_definition_id': processDefinitionId,
      'stage_id': stageId,
      'name': name,
    };
    if (code != null && code.trim().isNotEmpty) body['code'] = code.trim();
    if (sourceCode != null) body['source_code'] = sourceCode;
    if (companyName != null) body['company_name'] = companyName;
    if (mobile != null) body['mobile'] = mobile;
    if (email != null) body['email'] = email;
    if (description != null) body['description'] = description;
    if (assignedToUserId != null) body['assigned_to_user_id'] = assignedToUserId;
    if (nextFollowUpAt != null) body['next_follow_up_at'] = nextFollowUpAt.toIso8601String();
    final res = await _apiClient.post<dynamic>(
      '/api/v1/crm/businesses/$businessId/leads',
      data: body,
    );
    return _extractData(res.data);
  }

  /// لیست فرصت‌های فروش
  Future<Map<String, dynamic>> listDeals({
    required int businessId,
    int? processDefinitionId,
    int? stageId,
    int? personId,
    int? assignedToUserId,
    String? search,
    String? fromDate,
    String? toDate,
    bool? openOnly,
    int page = 1,
    int limit = 50,
  }) async {
    final queryParams = <String, dynamic>{'page': page, 'limit': limit};
    if (processDefinitionId != null) queryParams['process_definition_id'] = processDefinitionId;
    if (stageId != null) queryParams['stage_id'] = stageId;
    if (personId != null) queryParams['person_id'] = personId;
    if (assignedToUserId != null) queryParams['assigned_to_user_id'] = assignedToUserId;
    if (search != null && search.trim().isNotEmpty) queryParams['search'] = search.trim();
    if (fromDate != null && fromDate.isNotEmpty) queryParams['from_date'] = fromDate;
    if (toDate != null && toDate.isNotEmpty) queryParams['to_date'] = toDate;
    if (openOnly != null) queryParams['open_only'] = openOnly;
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/deals',
      query: queryParams,
    );
    return _extractData(res.data);
  }

  /// لیست فعالیت‌ها (برای یک شخص)
  Future<Map<String, dynamic>> listActivities({
    required int businessId,
    int? personId,
    int? leadId,
    int? dealId,
    String? activityType,
    int page = 1,
    int limit = 50,
  }) async {
    final queryParams = <String, dynamic>{'page': page, 'limit': limit};
    if (personId != null) queryParams['person_id'] = personId;
    if (leadId != null) queryParams['lead_id'] = leadId;
    if (dealId != null) queryParams['deal_id'] = dealId;
    if (activityType != null) queryParams['activity_type'] = activityType;
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/activities',
      query: queryParams,
    );
    return _extractData(res.data);
  }

  /// ویرایش فعالیت
  Future<Map<String, dynamic>> updateActivity({
    required int businessId,
    required int activityId,
    String? code,
    String? activityType,
    String? subject,
    String? description,
    DateTime? activityDate,
    int? dealId,
  }) async {
    final body = <String, dynamic>{};
    if (code != null && code.trim().isNotEmpty) body['code'] = code.trim();
    if (activityType != null) body['activity_type'] = activityType;
    if (subject != null) body['subject'] = subject;
    if (description != null) body['description'] = description;
    if (activityDate != null) body['activity_date'] = activityDate.toIso8601String();
    if (dealId != null) body['deal_id'] = dealId;
    final res = await _apiClient.put<dynamic>(
      '/api/v1/crm/businesses/$businessId/activities/$activityId',
      data: body,
    );
    return _extractData(res.data);
  }

  /// حذف فعالیت
  Future<void> deleteActivity({
    required int businessId,
    required int activityId,
  }) async {
    await _apiClient.delete(
      '/api/v1/crm/businesses/$businessId/activities/$activityId',
    );
  }

  /// ثبت فعالیت
  Future<Map<String, dynamic>> createActivity({
    required int businessId,
    int? personId,
    int? leadId,
    required String activityType,
    String? code,
    String? subject,
    String? description,
    required DateTime activityDate,
    int? dealId,
  }) async {
    final body = <String, dynamic>{
      'activity_type': activityType,
      'activity_date': activityDate.toIso8601String(),
    };
    if (personId != null) body['person_id'] = personId;
    if (leadId != null) body['lead_id'] = leadId;
    if (code != null && code.trim().isNotEmpty) body['code'] = code.trim();
    if (subject != null) body['subject'] = subject;
    if (description != null) body['description'] = description;
    if (dealId != null) body['deal_id'] = dealId;
    final res = await _apiClient.post<dynamic>(
      '/api/v1/crm/businesses/$businessId/activities',
      data: body,
    );
    return _extractData(res.data);
  }

  /// حذف فرصت فروش
  Future<void> deleteDeal({
    required int businessId,
    required int dealId,
  }) async {
    await _apiClient.delete(
      '/api/v1/crm/businesses/$businessId/deals/$dealId',
    );
  }

  /// لیست اسناد مرتبط با یک شخص (برای انتخاب در بستن معامله)
  Future<List<Map<String, dynamic>>> listDocumentsForPerson({
    required int businessId,
    required int personId,
    int limit = 100,
  }) async {
    try {
      final res = await _apiClient.post<dynamic>(
        '/api/v1/kardex/businesses/$businessId/lines',
        data: {
          'person_ids': [personId],
          'result_scope': 'lines_matching',
          'take': limit,
          'skip': 0,
        },
      );
      final body = res.data;
      if (body == null || body['success'] != true) return [];
      final data = body['data'];
      if (data == null || data['items'] is! List) return [];
      final items = data['items'] as List;
      final seen = <int>{};
      final docs = <Map<String, dynamic>>[];
      for (final item in items) {
        final m = item is Map ? item as Map<String, dynamic> : null;
        if (m == null) continue;
        final docId = (m['document_id'] as num?)?.toInt();
        if (docId == null || seen.contains(docId)) continue;
        seen.add(docId);
        docs.add({
          'id': docId,
          'document_code': m['document_code']?.toString(),
          'document_date': m['document_date']?.toString(),
          'document_type': m['document_type']?.toString(),
          'document_type_name': m['document_type_name']?.toString(),
        });
      }
      return docs;
    } catch (_) {
      return [];
    }
  }

  /// به‌روزرسانی فرصت فروش
  Future<Map<String, dynamic>> updateDeal({
    required int businessId,
    required int dealId,
    int? stageId,
    String? code,
    String? title,
    num? amount,
    int? currencyId,
    int? probabilityPercent,
    DateTime? expectedCloseDate,
    DateTime? nextFollowUpAt,
    int? assignedToUserId,
    String? description,
    int? documentId,
    DateTime? closedAt,
  }) async {
    final body = <String, dynamic>{};
    if (stageId != null) body['stage_id'] = stageId;
    if (code != null && code.trim().isNotEmpty) body['code'] = code.trim();
    if (title != null) body['title'] = title;
    if (amount != null) body['amount'] = amount;
    if (currencyId != null) body['currency_id'] = currencyId;
    if (probabilityPercent != null) body['probability_percent'] = probabilityPercent;
    if (expectedCloseDate != null) body['expected_close_date'] = expectedCloseDate.toIso8601String().split('T')[0];
    if (nextFollowUpAt != null) body['next_follow_up_at'] = nextFollowUpAt.toIso8601String();
    if (assignedToUserId != null) body['assigned_to_user_id'] = assignedToUserId;
    if (description != null) body['description'] = description;
    if (documentId != null) body['document_id'] = documentId;
    if (closedAt != null) body['closed_at'] = closedAt.toIso8601String();
    final res = await _apiClient.put<dynamic>(
      '/api/v1/crm/businesses/$businessId/deals/$dealId',
      data: body,
    );
    return _extractData(res.data);
  }

  /// ایجاد فرصت فروش
  Future<Map<String, dynamic>> createDeal({
    required int businessId,
    required int personId,
    required int processDefinitionId,
    required int stageId,
    required String title,
    required num amount,
    String? code,
    int? currencyId,
    int? probabilityPercent,
    DateTime? expectedCloseDate,
    DateTime? nextFollowUpAt,
    int? assignedToUserId,
    String? description,
  }) async {
    final body = <String, dynamic>{
      'person_id': personId,
      'process_definition_id': processDefinitionId,
      'stage_id': stageId,
      'title': title,
      'amount': amount,
    };
    if (code != null && code.trim().isNotEmpty) body['code'] = code.trim();
    if (currencyId != null) body['currency_id'] = currencyId;
    if (probabilityPercent != null) body['probability_percent'] = probabilityPercent;
    if (expectedCloseDate != null) body['expected_close_date'] = expectedCloseDate.toIso8601String().split('T')[0];
    if (nextFollowUpAt != null) body['next_follow_up_at'] = nextFollowUpAt.toIso8601String();
    if (assignedToUserId != null) body['assigned_to_user_id'] = assignedToUserId;
    if (description != null) body['description'] = description;
    final res = await _apiClient.post<dynamic>(
      '/api/v1/crm/businesses/$businessId/deals',
      data: body,
    );
    return _extractData(res.data);
  }

  /// حذف سرنخ
  Future<void> deleteLead({
    required int businessId,
    required int leadId,
  }) async {
    await _apiClient.delete(
      '/api/v1/crm/businesses/$businessId/leads/$leadId',
    );
  }

  /// تبدیل سرنخ به مشتری (با امکان ایجاد همزمان فرصت فروش)
  Future<Map<String, dynamic>> convertLeadToCustomer({
    required int businessId,
    required int leadId,
    Map<String, dynamic>? createDeal,
  }) async {
    final body = createDeal != null && createDeal.isNotEmpty ? {'create_deal': createDeal} : null;
    final res = await _apiClient.post<dynamic>(
      '/api/v1/crm/businesses/$businessId/leads/$leadId/convert',
      data: body,
    );
    final data = _extractData(res.data);
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// به‌روزرسانی سرنخ
  Future<Map<String, dynamic>> updateLead({
    required int businessId,
    required int leadId,
    int? stageId,
    String? code,
    String? name,
    String? sourceCode,
    String? companyName,
    String? mobile,
    String? email,
    String? description,
    int? assignedToUserId,
    DateTime? nextFollowUpAt,
  }) async {
    final body = <String, dynamic>{};
    if (stageId != null) body['stage_id'] = stageId;
    if (code != null && code.trim().isNotEmpty) body['code'] = code.trim();
    if (name != null) body['name'] = name;
    if (sourceCode != null) body['source_code'] = sourceCode;
    if (companyName != null) body['company_name'] = companyName;
    if (mobile != null) body['mobile'] = mobile;
    if (email != null) body['email'] = email;
    if (description != null) body['description'] = description;
    if (assignedToUserId != null) body['assigned_to_user_id'] = assignedToUserId;
    if (nextFollowUpAt != null) body['next_follow_up_at'] = nextFollowUpAt.toIso8601String();
    final res = await _apiClient.put<dynamic>(
      '/api/v1/crm/businesses/$businessId/leads/$leadId',
      data: body,
    );
    return _extractData(res.data);
  }

  /// انواع یادداشت CRM (چندزبانه در سرور)
  Future<List<dynamic>> listCrmNoteTypes({required int businessId}) async {
    final res = await _apiClient.get<dynamic>('/api/v1/crm/businesses/$businessId/note-types');
    final data = _extractData(res.data);
    if (data is Map && data['items'] is List) return data['items'] as List<dynamic>;
    return [];
  }

  /// ایجاد نوع یادداشت سفارشی (code + title_i18n + scheduling_mode + allow_comments)
  Future<Map<String, dynamic>> createCrmNoteType({
    required int businessId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _apiClient.post<dynamic>(
      '/api/v1/crm/businesses/$businessId/note-types',
      data: body,
    );
    final data = _extractData(res.data);
    return data is Map<String, dynamic> ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// یادداشت‌های بازه تقویم (from/to میلادی YYYY-MM-DD)
  Future<List<dynamic>> listCrmNotes({
    required int businessId,
    required String fromDate,
    required String toDate,
  }) async {
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/notes',
      query: {'from_date': fromDate, 'to_date': toDate},
    );
    final data = _extractData(res.data);
    if (data is Map && data['items'] is List) return data['items'] as List<dynamic>;
    return [];
  }

  Future<Map<String, dynamic>> getCrmNote({required int businessId, required int noteId}) async {
    final res = await _apiClient.get<dynamic>('/api/v1/crm/businesses/$businessId/notes/$noteId');
    final data = _extractData(res.data);
    return data is Map<String, dynamic> ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> createCrmNote({
    required int businessId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _apiClient.post<dynamic>(
      '/api/v1/crm/businesses/$businessId/notes',
      data: body,
    );
    final data = _extractData(res.data);
    return data is Map<String, dynamic> ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> updateCrmNote({
    required int businessId,
    required int noteId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _apiClient.patch<dynamic>(
      '/api/v1/crm/businesses/$businessId/notes/$noteId',
      data: body,
    );
    final data = _extractData(res.data);
    return data is Map<String, dynamic> ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<void> deleteCrmNote({required int businessId, required int noteId}) async {
    await _apiClient.delete<void>('/api/v1/crm/businesses/$businessId/notes/$noteId');
  }

  Future<List<dynamic>> listCrmNoteComments({required int businessId, required int noteId}) async {
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/notes/$noteId/comments',
    );
    final data = _extractData(res.data);
    if (data is Map && data['items'] is List) return data['items'] as List<dynamic>;
    return [];
  }

  Future<void> addCrmNoteComment({
    required int businessId,
    required int noteId,
    required String body,
  }) async {
    await _apiClient.post<void>(
      '/api/v1/crm/businesses/$businessId/notes/$noteId/comments',
      data: {'body': body},
    );
  }

  Future<void> deleteCrmNoteComment({
    required int businessId,
    required int noteId,
    required int commentId,
  }) async {
    await _apiClient.delete<void>(
      '/api/v1/crm/businesses/$businessId/notes/$noteId/comments/$commentId',
    );
  }

  Future<List<dynamic>> listCrmNoteAudit({required int businessId, required int noteId}) async {
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/notes/$noteId/audit',
    );
    final data = _extractData(res.data);
    if (data is Map && data['items'] is List) return data['items'] as List<dynamic>;
    return [];
  }
}
