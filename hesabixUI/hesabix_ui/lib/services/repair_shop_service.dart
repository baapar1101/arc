import '../models/repair_order_model.dart';
import '../models/repair_technician_model.dart';
import '../models/repair_settings_model.dart';
import '../core/api_client.dart';

/// سرویس API برای افزونه مدیریت تعمیرگاه
class RepairShopService {
  final ApiClient _api;

  RepairShopService(this._api);

  // ========== Plugin Status ==========

  /// دریافت وضعیت افزونه
  Future<Map<String, dynamic>> getPluginStatus({
    required int businessId,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/plugin-status',
    );
    return response.data?['data'] as Map<String, dynamic>;
  }

  // ========== Settings ==========

  /// دریافت تنظیمات تعمیرگاه
  Future<RepairShopSettings> getSettings({
    required int businessId,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/settings',
    );
    final data = response.data?['data'] as Map<String, dynamic>;
    return RepairShopSettings.fromJson(data);
  }

  /// به‌روزرسانی تنظیمات
  Future<RepairShopSettings> updateSettings({
    required int businessId,
    required Map<String, dynamic> settings,
  }) async {
    final response = await _api.put<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/settings',
      data: settings,
    );
    final data = response.data?['data'] as Map<String, dynamic>;
    return RepairShopSettings.fromJson(data);
  }

  // ========== Technicians ==========

  /// لیست تعمیرکاران
  Future<List<RepairTechnician>> listTechnicians({
    required int businessId,
    bool onlyActive = true,
    int offset = 0,
    int limit = 100,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/technicians',
      query: {
        'only_active': onlyActive,
        'offset': offset,
        'limit': limit,
      },
    );

    final data = response.data?['data'] as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>;

    return items
        .map((item) => RepairTechnician.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// دریافت یک تعمیرکار
  Future<RepairTechnician> getTechnician({
    required int businessId,
    required int technicianId,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/technicians/$technicianId',
    );
    final data = response.data?['data'] as Map<String, dynamic>;
    return RepairTechnician.fromJson(data);
  }

  /// ایجاد تعمیرکار
  Future<RepairTechnician> createTechnician({
    required int businessId,
    required Map<String, dynamic> technicianData,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/technicians',
      data: technicianData,
    );
    final data = response.data?['data'] as Map<String, dynamic>;
    return RepairTechnician.fromJson(data);
  }

  /// به‌روزرسانی تعمیرکار
  Future<RepairTechnician> updateTechnician({
    required int businessId,
    required int technicianId,
    required Map<String, dynamic> technicianData,
  }) async {
    final response = await _api.put<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/technicians/$technicianId',
      data: technicianData,
    );
    final data = response.data?['data'] as Map<String, dynamic>;
    return RepairTechnician.fromJson(data);
  }

  /// حذف تعمیرکار
  Future<Map<String, dynamic>> deleteTechnician({
    required int businessId,
    required int technicianId,
  }) async {
    final response = await _api.delete<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/technicians/$technicianId',
    );
    return response.data?['data'] as Map<String, dynamic>;
  }

  // ========== Repair Orders ==========

  /// لیست سفارشات تعمیر
  Future<Map<String, dynamic>> listOrders({
    required int businessId,
    String? status,
    int? customerPersonId,
    int? assignedTechnicianId,
    int? warrantyCodeId,
    String? search,
    int offset = 0,
    int limit = 50,
  }) async {
    final queryParams = <String, dynamic>{
      'offset': offset,
      'limit': limit,
    };

    if (status != null) queryParams['status'] = status;
    if (customerPersonId != null) queryParams['customer_person_id'] = customerPersonId;
    if (assignedTechnicianId != null) queryParams['assigned_technician_id'] = assignedTechnicianId;
    if (warrantyCodeId != null) queryParams['warranty_code_id'] = warrantyCodeId;
    if (search != null && search.isNotEmpty) queryParams['search'] = search;

    final response = await _api.get<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/orders',
      query: queryParams,
    );

    final data = response.data?['data'] as Map<String, dynamic>;

    final items = (data['items'] as List<dynamic>)
        .map((item) => RepairOrderListItem.fromJson(item as Map<String, dynamic>))
        .toList();

    return {
      'items': items,
      'total': data['total'] as int,
      'offset': data['offset'] as int,
      'limit': data['limit'] as int,
    };
  }

  /// دریافت یک سفارش تعمیر
  Future<RepairOrder> getOrder({
    required int businessId,
    required int orderId,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/orders/$orderId',
    );
    final data = response.data?['data'] as Map<String, dynamic>;
    return RepairOrder.fromJson(data);
  }

  /// ایجاد سفارش تعمیر جدید
  Future<RepairOrder> createOrder({
    required int businessId,
    required Map<String, dynamic> orderData,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/orders',
      data: orderData,
    );
    final data = response.data?['data'] as Map<String, dynamic>;
    return RepairOrder.fromJson(data);
  }

  /// به‌روزرسانی سفارش تعمیر
  Future<RepairOrder> updateOrder({
    required int businessId,
    required int orderId,
    required Map<String, dynamic> orderData,
  }) async {
    final response = await _api.put<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/orders/$orderId',
      data: orderData,
    );
    final data = response.data?['data'] as Map<String, dynamic>;
    return RepairOrder.fromJson(data);
  }

  /// حذف (لغو) سفارش تعمیر
  Future<Map<String, dynamic>> deleteOrder({
    required int businessId,
    required int orderId,
  }) async {
    final response = await _api.delete<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/orders/$orderId',
    );
    return response.data?['data'] as Map<String, dynamic>;
  }

  // ========== Operations ==========

  /// اختصاص تعمیرکار به سفارش
  Future<RepairOrder> assignTechnician({
    required int businessId,
    required int orderId,
    required int technicianId,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/orders/$orderId/assign-technician',
      data: {'technician_id': technicianId},
    );
    final data = response.data?['data'] as Map<String, dynamic>;
    return RepairOrder.fromJson(data);
  }

  /// تغییر وضعیت سفارش
  Future<RepairOrder> updateStatus({
    required int businessId,
    required int orderId,
    required String status,
    String? notes,
    bool sendNotification = true,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/orders/$orderId/update-status',
      data: {
        'status': status,
        'notes': notes,
        'send_notification': sendNotification,
      },
    );
    final data = response.data?['data'] as Map<String, dynamic>;
    return RepairOrder.fromJson(data);
  }

  /// افزودن قطعات به سفارش
  Future<RepairOrder> addParts({
    required int businessId,
    required int orderId,
    required List<Map<String, dynamic>> parts,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/orders/$orderId/add-parts',
      data: {'parts': parts},
    );
    final data = response.data?['data'] as Map<String, dynamic>;
    return RepairOrder.fromJson(data);
  }

  /// محاسبه هزینه‌های تعمیر
  Future<Map<String, dynamic>> calculateCosts({
    required int businessId,
    required int orderId,
    required double laborCost,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/orders/$orderId/calculate-costs',
      data: {'labor_cost': laborCost},
    );
    return response.data?['data'] as Map<String, dynamic>;
  }

  /// اتمام تعمیر
  Future<RepairOrder> completeRepair({
    required int businessId,
    required int orderId,
    required bool isFixed,
    String? notes,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/orders/$orderId/complete',
      data: {
        'is_fixed': isFixed,
        'notes': notes,
      },
    );
    final data = response.data?['data'] as Map<String, dynamic>;
    return RepairOrder.fromJson(data);
  }

  /// تحویل کالا به مشتری
  Future<RepairOrder> deliverRepair({
    required int businessId,
    required int orderId,
    String? notes,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/orders/$orderId/deliver',
      data: {'notes': notes},
    );
    final data = response.data?['data'] as Map<String, dynamic>;
    return RepairOrder.fromJson(data);
  }

  // ========== Accounting ==========

  /// صدور فاکتور تعمیر
  Future<Map<String, dynamic>> createInvoice({
    required int businessId,
    required int orderId,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/orders/$orderId/create-invoice',
    );
    return response.data?['data'] as Map<String, dynamic>;
  }

  /// دریافت خلاصه حسابداری
  Future<Map<String, dynamic>> getAccountingSummary({
    required int businessId,
    required int orderId,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/orders/$orderId/accounting-summary',
    );
    return response.data?['data'] as Map<String, dynamic>;
  }

  // ========== Reports ==========

  /// تاریخچه تعمیرات براساس کد گارانتی
  Future<List<Map<String, dynamic>>> getWarrantyRepairHistory({
    required int businessId,
    required int warrantyCodeId,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/api/v1/repair-shop/businesses/$businessId/warranty/$warrantyCodeId/history',
    );
    final data = response.data?['data'] as Map<String, dynamic>;
    return (data['items'] as List<dynamic>)
        .map((item) => item as Map<String, dynamic>)
        .toList();
  }
}
