import '../core/api_client.dart';

class AdminUsersService {
  final ApiClient _api;
  AdminUsersService(this._api);

  /// دریافت App Permissions کاربر
  Future<Map<String, dynamic>> getUserAppPermissions(int userId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/users/$userId/app-permissions'
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// به‌روزرسانی App Permissions کاربر
  Future<Map<String, dynamic>> updateUserAppPermissions(
    int userId,
    Map<String, bool> permissions
  ) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/users/$userId/app-permissions',
      data: {'permissions': permissions}
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// لیست اپراتورهای پشتیبانی
  Future<List<Map<String, dynamic>>> listSupportOperators() async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/users/operators'
    );
    final data = res.data?['data'] as Map? ?? {};
    final items = data['items'] as List? ?? [];
    return items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  /// اضافه کردن اپراتور
  Future<void> addSupportOperator(int userId) async {
    await _api.post(
      '/api/v1/admin/users/operators/$userId',
    );
  }

  /// حذف اپراتور
  Future<void> removeSupportOperator(int userId) async {
    await _api.delete(
      '/api/v1/admin/users/operators/$userId',
    );
  }
}



