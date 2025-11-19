import 'package:dio/dio.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/expense_income_document.dart';

import 'document_policy_guard.dart';

/// سرویس CRUD اسناد هزینه/درآمد
class ExpenseIncomeService {
  final ApiClient _apiClient;
  late final DocumentPolicyGuard _policyGuard = DocumentPolicyGuard(_apiClient);

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
      final amount = _sumItemAmounts(itemLines);

      await _policyGuard.ensureAllowed(
        businessId: businessId,
        documentType: documentType,
        documentDate: documentDate,
        amount: amount,
      );

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
              // برای سازگاری با بک‌اند create و update هر دو کلید ارسال شود
              data['bank_account_id'] = line.bankAccountId;
              data['bank_account_name'] = line.bankAccountName;
              data['bank_id'] = line.bankAccountId; // سازگاری با create
              data['bank_name'] = line.bankAccountName;
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

      final data = response.data['data'] as Map<String, dynamic>;
      return _mapApiToExpenseIncomeDocument(data);
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

      final data = response.data['data'] as Map<String, dynamic>;
      return _mapApiToExpenseIncomeDocument(data);
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

  /// نگاشت پاسخ API (ساختار ساده) به مدل فرنتمون
  ExpenseIncomeDocument _mapApiToExpenseIncomeDocument(Map<String, dynamic> json) {
    final String documentType = (json['document_type'] as String?) ?? '';
    final bool isIncome = documentType == 'income';
    final DateTime documentDate = DateTime.parse(json['document_date'] as String);
    final int currencyId = (json['currency_id'] as num).toInt();
    final String code = json['code'] as String? ?? '';
    final int id = (json['id'] as num).toInt();
    final String? description = json['description'] as String?;

    // آیتم‌ها (amount از debit/credit استخراج می‌شود)
    final List<ItemLine> itemLines = ((json['items'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final double debit = (item['debit'] as num?)?.toDouble() ?? 0.0;
          final double credit = (item['credit'] as num?)?.toDouble() ?? 0.0;
          final double amount = isIncome ? credit : debit;
          return ItemLine(
            id: (item['id'] as num).toInt(),
            accountId: (item['account_id'] as num).toInt(),
            accountCode: (item['account_code'] as String?) ?? '',
            accountName: (item['account_name'] as String?) ?? '',
            amount: amount,
            description: item['description'] as String?,
          );
        })
        .toList();

    // طرف‌حساب‌ها
    final List<CounterpartyLine> counterpartyLines = ((json['counterparties'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .map((line) {
          final Map<String, dynamic> extra = (line['extra_info'] as Map?)?.cast<String, dynamic>() ?? const {};
          final String txType = (line['transaction_type'] as String?) ??
              (extra['transaction_type'] as String?) ??
              // fallback ساده
              (line['person_id'] != null ? 'person' : (line['account_id'] != null ? 'account' : 'bank'));
          final String txTypeName = _txTypeName(txType);
          final double debit = (line['debit'] as num?)?.toDouble() ?? 0.0;
          final double credit = (line['credit'] as num?)?.toDouble() ?? 0.0;
          final double amount = isIncome ? debit : credit;
          final String? transactionDateStr = (line['transaction_date'] as String?) ?? (extra['transaction_date'] as String?);
          final DateTime txDate = transactionDateStr != null
              ? DateTime.parse(transactionDateStr)
              : documentDate;
          return CounterpartyLine(
            id: (line['id'] as num).toInt(),
            transactionType: txType,
            transactionTypeName: txTypeName,
            amount: amount,
            transactionDate: txDate,
            description: line['description'] as String?,
            commission: (extra['commission'] as num?)?.toDouble(),
            bankAccountId: line['bank_account_id'] as int? ?? (extra['bank_account_id'] as int?),
            bankAccountName: line['bank_account_name'] as String? ?? (extra['bank_account_name'] as String?),
            cashRegisterId: line['cash_register_id'] as int? ?? (extra['cash_register_id'] as int?),
            cashRegisterName: line['cash_register_name'] as String? ?? (extra['cash_register_name'] as String?),
            pettyCashId: line['petty_cash_id'] as int? ?? (extra['petty_cash_id'] as int?),
            pettyCashName: line['petty_cash_name'] as String? ?? (extra['petty_cash_name'] as String?),
            checkId: line['check_id'] as int? ?? (extra['check_id'] as int?),
            checkNumber: line['check_number'] as String? ?? (extra['check_number'] as String?),
            personId: line['person_id'] as int? ?? (extra['person_id'] as int?),
            personName: line['person_name'] as String? ?? (extra['person_name'] as String?),
            accountId: line['account_id'] as int?,
            accountName: line['account_name'] as String?,
          );
        })
        .toList();

    final double totalAmount = itemLines.fold(0.0, (sum, it) => sum + (it.amount));

    return ExpenseIncomeDocument(
      id: id,
      code: code,
      documentType: documentType,
      documentTypeName: documentType == 'income' ? 'درآمد' : 'هزینه',
      documentDate: documentDate,
      currencyId: currencyId,
      currencyCode: null,
      totalAmount: totalAmount,
      description: description,
      itemLines: itemLines,
      counterpartyLines: counterpartyLines,
      itemLinesCount: itemLines.length,
      counterpartyLinesCount: counterpartyLines.length,
      createdByName: null,
      // بک‌اند create فعلاً registered_at برنمی‌گرداند؛ نزدیک‌ترین چیز زمان کنونی است
      registeredAt: DateTime.now(),
      extraInfo: null,
    );
  }

  String _txTypeName(String type) {
    switch (type) {
      case 'bank':
        return 'بانک';
      case 'cash_register':
        return 'صندوق';
      case 'petty_cash':
        return 'تنخواهگردان';
      case 'check':
        return 'چک';
      case 'check_expense':
        return 'خرج چک';
      case 'person':
        return 'شخص';
      case 'account':
        return 'حساب';
      default:
        return type;
    }
  }
}

num _sumItemAmounts(List<ItemLineData> lines) {
  num sum = 0;
  for (final line in lines) {
    sum += line.amount;
  }
  return sum.abs();
}