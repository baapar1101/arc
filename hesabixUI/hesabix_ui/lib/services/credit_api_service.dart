import '../core/api_client.dart';
import '../models/credit_models.dart';

class CreditApiService {
  static final ApiClient _api = ApiClient();

  static String _basePath(int businessId) => '/api/v1/businesses/$businessId/credit';

  // Credit settings
  static Future<CreditSettings> getCreditSettings(int businessId) async {
    final resp = await _api.get('${_basePath(businessId)}/settings');
    if (resp.data['success'] == true) {
      return CreditSettings.fromJson(resp.data['data']);
    }
    throw Exception(resp.data['message'] ?? 'خطا در دریافت تنظیمات اعتبار');
  }

  static Future<CreditSettings> updateCreditSettings(int businessId, CreditSettings settings) async {
    final resp = await _api.put('${_basePath(businessId)}/settings', data: settings.toJson());
    if (resp.data['success'] == true) {
      return CreditSettings.fromJson(resp.data['data']);
    }
    throw Exception(resp.data['message'] ?? 'خطا در ذخیره تنظیمات اعتبار');
    }

  // Installment plans
  static Future<List<InstallmentPlan>> listInstallmentPlans(int businessId, {bool? onlyActive}) async {
    final query = (onlyActive == null) ? '' : '?only_active=${onlyActive ? 'true' : 'false'}';
    final resp = await _api.get('${_basePath(businessId)}/installment-plans$query');
    if (resp.data['success'] == true) {
      final List items = resp.data['data']['items'] ?? [];
      return items.map((e) => InstallmentPlan.fromJson(e)).toList();
    }
    throw Exception(resp.data['message'] ?? 'خطا در دریافت پلن‌های اقساط');
  }

  static Future<InstallmentPlan> createInstallmentPlan(int businessId, InstallmentPlan plan) async {
    final resp = await _api.post('${_basePath(businessId)}/installment-plans', data: plan.toJson());
    if (resp.data['success'] == true) {
      return InstallmentPlan.fromJson(resp.data['data']);
    }
    throw Exception(resp.data['message'] ?? 'خطا در ایجاد پلن اقساط');
  }

  static Future<InstallmentPlan> updateInstallmentPlan(int businessId, int planId, Map<String, dynamic> updates) async {
    final resp = await _api.put('${_basePath(businessId)}/installment-plans/$planId', data: updates);
    if (resp.data['success'] == true) {
      return InstallmentPlan.fromJson(resp.data['data']);
    }
    throw Exception(resp.data['message'] ?? 'خطا در ویرایش پلن اقساط');
  }

  static Future<void> deleteInstallmentPlan(int businessId, int planId) async {
    final resp = await _api.delete('${_basePath(businessId)}/installment-plans/$planId');
    if (resp.data['success'] != true) {
      throw Exception(resp.data['message'] ?? 'خطا در حذف پلن اقساط');
    }
  }

  // Person credit
  static Future<Map<String, dynamic>> getPersonCredit(int businessId, int personId) async {
    final resp = await _api.get('${_basePath(businessId)}/persons/$personId');
    if (resp.data['success'] == true) {
      return Map<String, dynamic>.from(resp.data['data']);
    }
    throw Exception(resp.data['message'] ?? 'خطا در دریافت اعتبار شخص');
  }

  static Future<Map<String, dynamic>> updatePersonCredit(
    int businessId,
    int personId, {
    double? creditLimit,
    bool? creditCheckEnabled, // null means inherit
  }) async {
    final payload = <String, dynamic>{};
    if (creditLimit != null) payload['credit_limit'] = creditLimit;
    // allow explicit null for inherit
    payload['credit_check_enabled'] = creditCheckEnabled;
    final resp = await _api.put('${_basePath(businessId)}/persons/$personId', data: payload);
    if (resp.data['success'] == true) {
      return Map<String, dynamic>.from(resp.data['data']);
    }
    throw Exception(resp.data['message'] ?? 'خطا در ذخیره اعتبار شخص');
  }
}


