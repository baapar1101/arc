import 'dart:convert';

import '../core/api_client.dart';

class DocumentMonetizationService {
  final ApiClient _api;
  DocumentMonetizationService(this._api);

  Future<List<Map<String, dynamic>>> listSubscriptionPlans({bool? onlyActive}) async {
    final query = <String, dynamic>{};
    if (onlyActive != null) {
      query['only_active'] = onlyActive;
    }
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/document-monetization/subscription-plans',
      query: query,
    );
    final data = res.data?['data'];
    if (data is List) {
      return data.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> createSubscriptionPlan(Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/document-monetization/subscription-plans',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map);
  }

  Future<Map<String, dynamic>> updateSubscriptionPlan(int planId, Map<String, dynamic> payload) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/document-monetization/subscription-plans/$planId',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map);
  }

  Future<Map<String, dynamic>> deleteSubscriptionPlan(int planId) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/api/v1/admin/document-monetization/subscription-plans/$planId',
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map);
  }

  Future<List<Map<String, dynamic>>> listBusinessPoliciesAdmin(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/document-monetization/business/$businessId/policies',
    );
    return _extractList(res.data);
  }

  Future<Map<String, dynamic>> validateDocumentSubmission(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/business/$businessId/document-monetization/validate',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map);
  }

  List<Map<String, dynamic>> _extractList(dynamic root) {
    if (root is List) {
      return root.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (root is Map) {
      for (final key in ['data', 'items', 'policies']) {
        if (root.containsKey(key)) {
          final result = _extractList(root[key]);
          if (result.isNotEmpty) {
            return result;
          }
        }
      }
    }
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> saveBusinessPolicyAdmin(int businessId, Map<String, dynamic> payload) async {
    final bool hasId = payload['id'] != null;
    final path = hasId
        ? '/api/v1/admin/document-monetization/business/$businessId/policies/${payload['id']}'
        : '/api/v1/admin/document-monetization/business/$businessId/policies';
    final method = hasId ? _api.put<Map<String, dynamic>> : _api.post<Map<String, dynamic>>;
    final res = await method(
      path,
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map);
  }

  Future<void> deleteBusinessPolicyAdmin(int businessId, int policyId) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/admin/document-monetization/business/$businessId/policies/$policyId',
    );
  }

  Future<List<Map<String, dynamic>>> getDefaultPolicies() async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/document-monetization/default-policies',
    );
    final data = res.data?['data'];
    if (data is Map && data['policies'] is List) {
      return (data['policies'] as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> setDefaultPolicies(List<Map<String, dynamic>> policies) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/document-monetization/default-policies',
      data: {'policies': policies},
    );
    final data = res.data?['data'];
    if (data is Map && data['policies'] is List) {
      return (data['policies'] as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> assignSubscriptionToBusiness(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/document-monetization/business/$businessId/subscriptions',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map);
  }

  Future<Map<String, dynamic>> listBusinessPlans(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/document-monetization/plans',
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map);
  }

  Future<Map<String, dynamic>> activateBusinessSubscription(
    int businessId, {
    required int planId,
    bool autoRenew = false,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/business/$businessId/document-monetization/subscriptions',
      data: {
        'plan_id': planId,
        'auto_renew': autoRenew,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map);
  }

  Future<Map<String, dynamic>> getBusinessOverview(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/document-monetization/overview',
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map);
  }

  Future<Map<String, dynamic>> listBusinessCharges(
    int businessId, {
    String? status,
    String? chargeType,
    int limit = 50,
    int skip = 0,
  }) async {
    final query = <String, dynamic>{
      'limit': limit,
      'skip': skip,
    };
    if (status != null && status.isNotEmpty) {
      query['status'] = status;
    }
    if (chargeType != null && chargeType.isNotEmpty) {
      query['charge_type'] = chargeType;
    }
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/document-monetization/charges',
      query: query,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map);
  }

  Future<Map<String, dynamic>> payBusinessCharge(int businessId, int chargeId) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/business/$businessId/document-monetization/charges/$chargeId/pay',
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map);
  }

  Future<Map<String, dynamic>> processDocumentManually(int businessId, int documentId) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/business/$businessId/document-monetization/documents/$documentId/process',
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map);
  }

  Future<Map<String, dynamic>> finalizeVolume(int businessId) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/business/$businessId/document-monetization/finalize-volume',
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map);
  }

  String prettyJson(Map<String, dynamic> data) {
    return const JsonEncoder.withIndent('  ').convert(data);
  }
}

