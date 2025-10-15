import '../core/api_client.dart';

class AccountService {
  final ApiClient _client;
  AccountService({ApiClient? client}) : _client = client ?? ApiClient();

  /// دریافت درخت حساب‌ها برای یک کسب و کار
  Future<Map<String, dynamic>> getAccountsTree({required int businessId}) async {
    try {
      final res = await _client.get<Map<String, dynamic>>(
        '/api/v1/accounts/business/$businessId/tree',
      );
      
      // API پاسخ را در فیلد 'data' برمی‌گرداند
      final responseData = res.data?['data'] as Map<String, dynamic>?;
      return responseData ?? <String, dynamic>{'items': <dynamic>[]};
    } catch (e) {
      print('خطا در دریافت درخت حساب‌ها: $e');
      return <String, dynamic>{'items': <dynamic>[]};
    }
  }
}
