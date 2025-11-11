import 'package:dio/dio.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/expense_income_document.dart';

/// سرویس CRUD اسناد هزینه/درآمد
class ExpenseIncomeService {
  final ApiClient _apiClient;

  ExpenseIncomeService(this._apiClient);

  /// ایجاد سند هزینه/درآمد جدید
  Future<ExpenseIncomeDocument> create({
    required int businessId,
    required String documentType,
    required DateTime documentDate,
    required int currencyId,
    required List<ItemLineData> itemLines,
    required List<CounterpartyLineData> counterpartyLines,
    String? description,
    Map<String, dynamic>? extraInfo,
  }) async {
    try {
      // تبدیل itemLines به فرمت API
      final itemLinesData = itemLines.map((line) => {
        'account_id': line.accountId,
        'amount': line.amount,
        if (line.description != null && line.description!.isNotEmpty)
          'description': line.description,
      }).toList();

      // تبدیل counterpartyLines به فرمت API
      final counterpartyLinesData = counterpartyLines.map((line) {
        final data = {
          'transaction_type': line.transactionType.value,
          'amount': line.amount,
          'transaction_date': line.transactionDate.toIso8601String(),
          if (line.description != null && line.description!.isNotEmpty)
            'description': line.description,
          if (line.commission != null && line.commission! > 0)
            'commission': line.commission,
        };

        // اضافه کردن فیلدهای خاص بر اساس نوع تراکنش
        switch (line.transactionType) {
          case TransactionType.bank:
            if (line.bankAccountId != null) {
              data['bank_account_id'] = line.bankAccountId;
              data['bank_account_name'] = line.bankAccountName;
            }
            break;
          case TransactionType.cashRegister:
            if (line.cashRegisterId != null) {
              data['cash_register_id'] = line.cashRegisterId;
              data['cash_register_name'] = line.cashRegisterName;
            }
            break;
          case TransactionType.pettyCash:
            if (line.pettyCashId != null) {
              data['petty_cash_id'] = line.pettyCashId;
              data['petty_cash_name'] = line.pettyCashName;
            }
            break;
          case TransactionType.check:
          case TransactionType.checkExpense:
            if (line.checkId != null) {
              data['check_id'] = line.checkId;
              data['check_number'] = line.checkNumber;
            }
            break;
          case TransactionType.person:
            if (line.personId != null) {
              data['person_id'] = line.personId;
              data['person_name'] = line.personName;
            }
            break;
          case TransactionType.account:
            if (line.accountId != null) {
              data['account_id'] = line.accountId;
              data['account_name'] = line.accountName;
            }
            break;
        }

        return data;
      }).toList();

      final requestData = {
        'document_type': documentType,
        'document_date': documentDate.toIso8601String(),
        'currency_id': currencyId,
        if (description != null && description.isNotEmpty) 'description': description,
        'item_lines': itemLinesData,
        'counterparty_lines': counterpartyLinesData,
        if (extraInfo != null) 'extra_info': extraInfo,
      };

      final response = await _apiClient.post(
        '/businesses/$businessId/expense-income/create',
        data: requestData,
      );

      final data = response.data['data'];
      return ExpenseIncomeDocument.fromJson(data);
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// ویرایش سند هزینه/درآمد
  Future<ExpenseIncomeDocument> update({
    required int documentId,
    required DateTime documentDate,
    required int currencyId,
    required List<ItemLineData> itemLines,
    required List<CounterpartyLineData> counterpartyLines,
    String? description,
    Map<String, dynamic>? extraInfo,
  }) async {
    try {
      // تبدیل itemLines به فرمت API
      final itemLinesData = itemLines.map((line) => {
        'account_id': line.accountId,
        'amount': line.amount,
        if (line.description != null && line.description!.isNotEmpty)
          'description': line.description,
      }).toList();

      // تبدیل counterpartyLines به فرمت API
      final counterpartyLinesData = counterpartyLines.map((line) {
        final data = {
          'transaction_type': line.transactionType.value,
          'amount': line.amount,
          'transaction_date': line.transactionDate.toIso8601String(),
          if (line.description != null && line.description!.isNotEmpty)
            'description': line.description,
          if (line.commission != null && line.commission! > 0)
            'commission': line.commission,
        };

        // اضافه کردن فیلدهای خاص بر اساس نوع تراکنش
        switch (line.transactionType) {
          case TransactionType.bank:
            if (line.bankAccountId != null) {
              data['bank_account_id'] = line.bankAccountId;
              data['bank_account_name'] = line.bankAccountName;
            }
            break;
          case TransactionType.cashRegister:
            if (line.cashRegisterId != null) {
              data['cash_register_id'] = line.cashRegisterId;
              data['cash_register_name'] = line.cashRegisterName;
            }
            break;
          case TransactionType.pettyCash:
            if (line.pettyCashId != null) {
              data['petty_cash_id'] = line.pettyCashId;
              data['petty_cash_name'] = line.pettyCashName;
            }
            break;
          case TransactionType.check:
          case TransactionType.checkExpense:
            if (line.checkId != null) {
              data['check_id'] = line.checkId;
              data['check_number'] = line.checkNumber;
            }
            break;
          case TransactionType.person:
            if (line.personId != null) {
              data['person_id'] = line.personId;
              data['person_name'] = line.personName;
            }
            break;
          case TransactionType.account:
            if (line.accountId != null) {
              data['account_id'] = line.accountId;
              data['account_name'] = line.accountName;
            }
            break;
        }

        return data;
      }).toList();

      final requestData = {
        'document_date': documentDate.toIso8601String(),
        'currency_id': currencyId,
        if (description != null && description.isNotEmpty) 'description': description,
        'item_lines': itemLinesData,
        'counterparty_lines': counterpartyLinesData,
        if (extraInfo != null) 'extra_info': extraInfo,
      };

      final response = await _apiClient.put(
        '/expense-income/$documentId',
        data: requestData,
      );

      final data = response.data['data'];
      return ExpenseIncomeDocument.fromJson(data);
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// دریافت فایل PDF یک سند
  Future<List<int>> generatePdf(
    int documentId, {
    String paperSize = 'A4',
    String orientation = 'portrait',
    String disposition = 'attachment',
  }) async {
    try {
      return await _apiClient.downloadPdf(
        '/expense-income/$documentId/pdf',
        query: {
          'paper_size': paperSize,
          'orientation': orientation,
          'disposition': disposition,
        },
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  Exception _handleError(dynamic error) {
    if (error is DioException) {
      final response = error.response;
      if (response != null) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          final message = data['message'] ?? data['detail'] ?? error.message;
          return Exception(message);
        }
      }
      return Exception(error.message ?? 'خطا در ارتباط با سرور');
    }
    return Exception(error.toString());
  }
}