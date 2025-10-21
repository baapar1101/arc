import 'package:hesabix_ui/core/api_client.dart';

class ExpenseIncomeService {
  final ApiClient api;
  ExpenseIncomeService(this.api);

  Future<Map<String, dynamic>> create({
    required int businessId,
    required String documentType, // 'expense' | 'income'
    required DateTime documentDate,
    required int currencyId,
    String? description,
    List<Map<String, dynamic>> itemLines = const [],
    List<Map<String, dynamic>> counterpartyLines = const [],
  }) async {
    final body = <String, dynamic>{
      'document_type': documentType,
      'document_date': documentDate.toIso8601String(),
      'currency_id': currencyId,
      if (description != null && description.isNotEmpty) 'description': description,
      'item_lines': itemLines,
      'counterparty_lines': counterpartyLines,
    };
    final res = await api.post<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/expense-income/create',
      data: body,
    );
    return res.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> list({
    required int businessId,
    String? documentType, // 'expense' | 'income'
    DateTime? fromDate,
    DateTime? toDate,
    int skip = 0,
    int take = 20,
    String? search,
    String? sortBy,
    bool sortDesc = true,
  }) async {
    final body = <String, dynamic>{
      'skip': skip,
      'take': take,
      'sort_desc': sortDesc,
      if (sortBy != null) 'sort_by': sortBy,
      if (search != null && search.isNotEmpty) 'search': search,
      if (documentType != null) 'document_type': documentType,
      if (fromDate != null) 'from_date': fromDate.toUtc().toIso8601String(),
      if (toDate != null) 'to_date': toDate.toUtc().toIso8601String(),
    };
    final res = await api.post<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/expense-income',
      data: body,
    );
    return res.data ?? <String, dynamic>{};
  }
}


