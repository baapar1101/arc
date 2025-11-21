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
      // Error handled silently, returning empty result
      return <String, dynamic>{'items': <dynamic>[]};
    }
  }

  /// دریافت لیست حساب‌ها برای یک کسب و کار
  Future<Map<String, dynamic>> getAccounts({required int businessId}) async {
    try {
      final res = await _client.get<Map<String, dynamic>>(
        '/api/v1/accounts/business/$businessId',
      );
      
      final responseData = res.data?['data'] as Map<String, dynamic>?;
      return responseData ?? <String, dynamic>{'items': <dynamic>[]};
    } catch (e) {
      // Error handled silently, returning empty result
      return <String, dynamic>{'items': <dynamic>[]};
    }
  }

  /// دریافت یک حساب خاص با ID
  Future<Map<String, dynamic>> getAccount({
    required int businessId,
    required int accountId,
  }) async {
    try {
      final res = await _client.get<Map<String, dynamic>>(
        '/api/v1/accounts/business/$businessId/account/$accountId',
      );
      
      final responseData = res.data?['data'] as Map<String, dynamic>?;
      if (responseData == null) {
        throw Exception('حساب یافت نشد');
      }
      return responseData;
    } catch (e) {
      rethrow;
    }
  }

  /// جستجوی حساب‌ها
  Future<Map<String, dynamic>> searchAccounts({
    required int businessId,
    String? searchQuery,
    int limit = 50,
    int skip = 0,
    String? sortBy,
    bool sortDesc = false,
  }) async {
    try {
      final requestData = <String, dynamic>{
        'take': limit,
        'skip': skip,
        'sort_by': sortBy ?? 'code',
        'sort_desc': sortDesc,
      };

      if (searchQuery != null && searchQuery.isNotEmpty) {
        requestData['search'] = searchQuery;
      }

      final res = await _client.post<Map<String, dynamic>>(
        '/api/v1/accounts/business/$businessId',
        data: requestData,
      );
      
      final responseData = res.data?['data'] as Map<String, dynamic>?;
      return responseData ?? <String, dynamic>{
        'items': <dynamic>[],
        'total': 0,
        'skip': skip,
        'take': limit,
      };
    } catch (e) {
      rethrow;
    }
  }
}

