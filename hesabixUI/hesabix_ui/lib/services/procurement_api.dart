import 'package:dio/dio.dart';

import '../core/api_client.dart';

class ProcurementApi {
  final ApiClient _api;

  ProcurementApi({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> dashboard(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/dashboard');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> listRequisitions(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/requisitions');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> createRequisition(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/requisitions', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> updateRequisition(int businessId, int id, Map<String, dynamic> payload) async {
    final res = await _api.put<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/requisitions/$id', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> submitRequisition(int businessId, int id, {List<int> approverIds = const []}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/procurement/business/$businessId/requisitions/$id/submit',
      data: {'approver_user_ids': approverIds},
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> listOrders(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/orders');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> createOrder(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/orders', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> updateOrder(int businessId, int id, Map<String, dynamic> payload) async {
    final res = await _api.put<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/orders/$id', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> submitOrder(int businessId, int id, {List<int> approverIds = const []}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/procurement/business/$businessId/orders/$id/submit',
      data: {'approver_user_ids': approverIds},
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> receive(int businessId, int orderId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/orders/$orderId/receipts', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> invoice(int businessId, int orderId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/orders/$orderId/invoice', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> decide(int businessId, String entityType, int entityId, String action, {String? note}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/procurement/business/$businessId/decisions/$entityType/$entityId',
      data: {'action': action, if (note != null) 'note': note},
    );
    return _data(res.data);
  }

  Future<Map<String, dynamic>> listSourcing(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/sourcing');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> createSourcing(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/sourcing', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> getSourcing(int businessId, int eventId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/sourcing/$eventId');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> invite(int businessId, int eventId, List<int> personIds) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/sourcing/$eventId/invites', data: {'person_ids': personIds});
    return _data(res.data);
  }

  Future<Map<String, dynamic>> compare(int businessId, int eventId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/sourcing/$eventId/comparison');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> addSourcingLines(int businessId, int eventId, List<Map<String, dynamic>> lines) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/sourcing/$eventId/lines', data: {'lines': lines});
    return _data(res.data);
  }

  Future<Map<String, dynamic>> cancelSourcing(int businessId, int eventId, {String? reason}) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/sourcing/$eventId/cancel', data: {'reason': reason});
    return _data(res.data);
  }

  Future<Map<String, dynamic>> award(int businessId, int eventId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/sourcing/$eventId/award', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> openTechnical(int businessId, int eventId) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/sourcing/$eventId/open-technical', data: const {});
    return _data(res.data);
  }

  Future<Map<String, dynamic>> openFinancial(int businessId, int eventId) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/sourcing/$eventId/open-financial', data: const {});
    return _data(res.data);
  }

  Future<Map<String, dynamic>> minutes(int businessId, int eventId, String minutes) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/sourcing/$eventId/minutes', data: {'minutes': minutes});
    return _data(res.data);
  }

  Future<Map<String, dynamic>> listSuppliers(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/suppliers');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> saveSupplier(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/suppliers', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> listBudgets(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/budgets');
    return _data(res.data);
  }

  Future<List<Map<String, dynamic>>> listPendingBudgetMovements(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/budget-movements');
    final items = _data(res.data)['items'];
    if (items is! List) return [];
    return items.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>> createBudget(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/budgets', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> listContracts(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/contracts');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> createContract(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/contracts', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> activateContract(int businessId, int id) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/contracts/$id/activate', data: const {});
    return _data(res.data);
  }

  Future<Map<String, dynamic>> listReorder(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/reorder');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> refreshReorder(int businessId) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/reorder/refresh', data: const {});
    return _data(res.data);
  }

  Future<Map<String, dynamic>> convertReorder(int businessId, int id) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/reorder/$id/convert', data: const {});
    return _data(res.data);
  }

  Future<Map<String, dynamic>> orderFromRequisition(int businessId, int id, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/requisitions/$id/order', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> sendOrder(int businessId, int id) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/orders/$id/send', data: const {});
    return _data(res.data);
  }

  Future<Map<String, dynamic>> cancelOrder(int businessId, int id) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/orders/$id/cancel', data: const {});
    return _data(res.data);
  }

  Future<Map<String, dynamic>> closeOrder(int businessId, int id) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/orders/$id/close', data: const {});
    return _data(res.data);
  }

  Future<Map<String, dynamic>> returnOrder(int businessId, int orderId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/orders/$orderId/returns', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> prepay(int businessId, int orderId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/orders/$orderId/prepayments', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> increaseBudget(int businessId, int budgetId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/budgets/$budgetId/increases', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> transferBudget(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/budget-transfers', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> resubmitBudgetMovement(int businessId, int movementId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/budget-movements/$movementId/resubmit', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> releaseContract(int businessId, int contractId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/contracts/$contractId/release', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> addGuarantee(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/guarantees', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> getSettings(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/settings');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> updateSettings(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.put<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/settings', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> createCostCenter(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/cost-centers', data: payload);
    return _data(res.data);
  }

  Future<List<Map<String, dynamic>>> listCostCenters(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/cost-centers');
    final data = _data(res.data);
    final raw = data['items'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>> createDelegation(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/delegations', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> listSupplierDocuments(int businessId, int profileId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/suppliers/$profileId/documents');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> addSupplierDocument(int businessId, int profileId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/suppliers/$profileId/documents', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> scoreSupplier(int businessId, int personId, {String? periodKey}) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/scores/$personId', data: {if (periodKey != null) 'period_key': periodKey});
    return _data(res.data);
  }

  Future<Map<String, dynamic>> technicalScores(int businessId, int eventId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/sourcing/$eventId/technical-scores', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> submitBid(int businessId, int inviteId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/sourcing/invites/$inviteId/bids', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> productSources(int businessId, int productId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/products/$productId/sources');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> revokeShare(int businessId, int linkId) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/share-links/$linkId/revoke');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> share(int businessId, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/procurement/business/$businessId/share-links', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> publicView(String token) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/public/procurement/$token');
    return _data(res.data);
  }

  Future<Map<String, dynamic>> publicBid(String token, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/public/procurement/$token/bid', data: payload);
    return _data(res.data);
  }

  Future<Map<String, dynamic>> publicAck(String token) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/public/procurement/$token/acknowledge', data: const {});
    return _data(res.data);
  }

  Future<Map<String, dynamic>> publicInvoice(String token, Map<String, dynamic> payload) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/public/procurement/$token/invoice', data: payload);
    return _data(res.data);
  }

  Map<String, dynamic> _data(Map<String, dynamic>? body) {
    if (body == null) return {};
    final data = body['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }
}

String procurementErrorText(Object error) {
  final nested = _procurementError(error);
  if (nested != null && nested['message'] != null) return nested['message'].toString();
  if (error is DioException) return error.message ?? error.toString();
  return error.toString();
}

String? procurementErrorCode(Object error) {
  final nested = _procurementError(error);
  final code = nested?['code'];
  return code == null ? null : code.toString();
}

Map? _procurementError(Object error) {
  if (error is! DioException) return null;
  final data = error.response?.data;
  if (data is! Map) return null;
  final nested = data['error'];
  if (nested is Map) return nested;
  final detail = data['detail'];
  if (detail is Map && detail['error'] is Map) return detail['error'] as Map;
  return null;
}
