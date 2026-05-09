import 'dart:convert';

import 'package:dio/dio.dart' as dio;
import 'package:flutter/widgets.dart' show BuildContext, Locale;

import '../core/api_client.dart';
import '../l10n/app_localizations.dart';
import '../services/errors/api_error.dart';
import '../services/document_policy_guard.dart';

/// استخراج پیام خطای قابل‌نمایش برای کاربر (زبان از [AppLocalizations] یا آخرین locale برنامه).
class ErrorExtractor {
  static AppLocalizations _resolve(AppLocalizations? t) {
    if (t != null) return t;
    final loc = ApiClient.currentLocale;
    if (loc != null) {
      return lookupAppLocalizations(loc);
    }
    return lookupAppLocalizations(const Locale('en'));
  }

  /// پیام خطا برای نمایش به کاربر؛ ترجیحاً [t] را از `AppLocalizations.of(context)` بدهید.
  static String userMessage(Object e, [AppLocalizations? t]) {
    return _userMessage(e, _resolve(t));
  }

  /// راحت‌تر وقتی [BuildContext] در دسترس است (زبان از همان context).
  static String forContext(Object e, BuildContext context) {
    return userMessage(e, AppLocalizations.of(context));
  }

  /// همان [userMessage]؛ امضای دومین آرگومان اختیاری برای سازگاری با فراخوانی‌های `extractErrorMessage(e, t)`.
  static String extractErrorMessage(Object e, [AppLocalizations? t]) {
    return userMessage(e, t);
  }

  /// پیام خطا برای کدهای API شناخته‌شده (اولویت با ترجمهٔ کلاینت).
  static String? _messageForKnownApiErrorCode(String? code, AppLocalizations t) {
    if (code == null || code.isEmpty) return null;
    switch (code) {
      case 'BUSINESS_USERS_BUSINESS_NOT_FOUND':
        return t.apiErrorBusinessUsersBusinessNotFound;
      case 'BUSINESS_USERS_USER_NOT_FOUND':
        return t.apiErrorBusinessUsersUserNotFound;
      case 'BUSINESS_USERS_INVITE_ACCOUNT_MISSING':
        return t.apiErrorBusinessUsersInviteAccountMissing;
      case 'BUSINESS_USERS_ALREADY_MEMBER':
        return t.apiErrorBusinessUsersAlreadyMember;
      case 'BUSINESS_USERS_CANNOT_REMOVE_OWNER':
        return t.apiErrorBusinessUsersCannotRemoveOwner;
      case 'BUSINESS_USERS_REMOVE_MEMBER_NOT_FOUND':
        return t.apiErrorBusinessUsersRemoveMemberNotFound;
      case 'BUSINESS_USERS_OWNER_CANNOT_LEAVE':
        return t.apiErrorBusinessUsersOwnerCannotLeave;
      case 'BUSINESS_USERS_NOT_A_MEMBER_LEAVE':
        return t.apiErrorBusinessUsersNotAMemberLeave;
      case 'BUSINESS_USERS_LEAVE_FAILED':
        return t.apiErrorBusinessUsersLeaveFailed;

      case 'NO_FISCAL_YEAR':
        return t.apiErrorNoFiscalYearForDate;
      case 'FISCAL_YEAR_LOCKED':
        return t.apiErrorFiscalYearLockedForPosting;
      case 'DOCUMENT_CODE_RACE':
        return t.apiErrorDocumentCodeRace;

      case 'LOAN_FACILITY_NOT_FOUND':
        return t.apiErrorLoanFacilityNotFound;
      case 'LOAN_INSTALLMENT_NOT_FOUND':
        return t.apiErrorLoanInstallmentNotFound;
      case 'LOAN_PAYMENT_NOT_FOUND':
        return t.apiErrorLoanPaymentNotFound;
      case 'LOAN_FACILITY_MISSING_AFTER_COMMIT':
        return t.apiErrorLoanFacilityMissingAfterCommit;
      case 'PAYMENT_ACCOUNTING_FAILED':
        return t.apiErrorLoanPaymentAccountingFailed;
      case 'LOAN_CHART_ACCOUNT_NOT_FOUND':
        return t.apiErrorLoanChartAccountNotFound;
      case 'LOAN_ACCOUNTING_LINES_UNBALANCED':
        return t.apiErrorLoanAccountingLinesUnbalanced;
      case 'LOAN_BANK_REQUIRED_FOR_PAYMENT_DOCUMENT':
        return t.apiErrorLoanBankRequiredForPaymentDocument;

      case 'FACILITY_FINANCIAL_LOCKED':
        return t.apiErrorLoanFacilityFinancialLocked;
      case 'FACILITY_NOT_DRAFT':
        return t.apiErrorLoanFacilityNotDraft;
      case 'HAS_PAYMENTS':
        return t.apiErrorLoanFacilityHasPayments;

      case 'INVALID_CURRENCY':
        return t.apiErrorLoanInvalidCurrency;
      case 'INVALID_PRINCIPAL':
        return t.apiErrorLoanInvalidPrincipal;
      case 'CONTRACT_DATE_REQUIRED':
      case 'INVALID_CONTRACT_DATE':
        return t.apiErrorLoanContractDateRequired;

      case 'INVALID_RATE':
        return t.apiErrorLoanInvalidRate;
      case 'INVALID_FIRST_INSTALLMENT_DATE':
        return t.apiErrorLoanInvalidFirstInstallmentDate;

      case 'INVALID_SCHEDULE_METHOD':
        return t.apiErrorLoanInvalidScheduleMethod;
      case 'INVALID_INSTALLMENT_COUNT':
        return t.apiErrorLoanInvalidInstallmentCount;
      case 'FIRST_DUE_REQUIRED':
        return t.apiErrorLoanFirstDueRequired;
      case 'BAD_SCHEDULE_PAYLOAD':
        return t.apiErrorLoanBadSchedulePayload;

      case 'BANK_REQUIRED_FOR_ACCOUNTING':
        return t.apiErrorLoanBankRequiredAccounting;
      case 'BANK_CURRENCY_MISMATCH':
        return t.apiErrorLoanBankCurrencyMismatch;
      case 'FACILITY_DRAFT':
        return t.apiErrorLoanFacilityDraft;

      case 'INVALID_AMOUNT':
        return t.apiErrorLoanInvalidAmount;
      case 'PAYMENT_EXCEEDS_BALANCE':
        return t.apiErrorLoanPaymentExceedsBalance;
      case 'ALLOCATION_ERROR':
        return t.apiErrorLoanAllocationError;
      case 'INVALID_PAYMENT_DATE':
        return t.apiErrorLoanInvalidPaymentDate;
      case 'SCHEDULE_ERROR':
        return t.apiErrorLoanScheduleError;
      case 'INVALID_BANK_ACCOUNT':
        return t.apiErrorLoanInvalidBankAccount;

      case 'TITLE_REQUIRED':
        return t.loanFacilityValidationTitleRequired;

      default:
        return null;
    }
  }

  static String? _extractFromResponseData(dynamic data, AppLocalizations t) {
    Map<String, dynamic>? dataMap;
    if (data is Map) {
      dataMap = Map<String, dynamic>.from(data);
    } else if (data is List<int> || data is Iterable<int>) {
      try {
        final decoded = utf8.decode(data is List<int> ? data : data.toList());
        dataMap = jsonDecode(decoded) as Map<String, dynamic>?;
      } catch (_) {
        return null;
      }
    }
    if (dataMap == null) return null;
    final error = dataMap['error'];
    if (error is Map) {
      final code = error['code'];
      final codeStr = code is String ? code : null;
      final fromCode = _messageForKnownApiErrorCode(codeStr, t);
      if (fromCode != null) return fromCode;
    }
    if (error is Map && error['code'] == 'STORAGE_LIMIT_EXCEEDED') {
      return error['message'] as String? ?? 'حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند';
    }
    if (error is Map && error['message'] is String) {
      final message = error['message'] as String;
      if (message.isNotEmpty) return message;
    }
    if (dataMap['message'] is String) {
      final message = dataMap['message'] as String;
      if (message.isNotEmpty) return message;
    }
    return null;
  }

  static bool _isLowLevelNetworkNoise(String s) {
    final l = s.toLowerCase();
    if (l.contains('failed to fetch')) return true;
    if (l.contains('xmlhttprequest')) return true;
    if (l.contains('socketexception')) return true;
    if (l.contains('clientexception')) return true;
    if (l.contains('connection errored') || l.contains('connection error')) {
      return l.contains('dio') || l.contains('onerror') || l.contains('callback') || l.contains('network layer');
    }
    if (l.contains('err_internet_disconnected') || l.contains('err_network_changed')) return true;
    return false;
  }

  /// قطع/تایم‌اوت اتصال یا خطای سطح سوکت (بفراتر از صرف [DioException.message]).
  static bool _isNetworkConnectivityFailure(dio.DioException e) {
    final type = e.type;
    if (type == dio.DioExceptionType.connectionTimeout ||
        type == dio.DioExceptionType.receiveTimeout ||
        type == dio.DioExceptionType.sendTimeout ||
        type == dio.DioExceptionType.connectionError ||
        type == dio.DioExceptionType.badCertificate) {
      return true;
    }
    if (type == dio.DioExceptionType.badResponse || type == dio.DioExceptionType.cancel) {
      return false;
    }
    if (type == dio.DioExceptionType.unknown) {
      final m = (e.message ?? '').toLowerCase();
      final errStr = (e.error?.toString() ?? '').toLowerCase();
      if (m.contains('dioexception') &&
          (m.contains('connection timeout') ||
              m.contains('connection error') ||
              m.contains('receive timeout') ||
              m.contains('send timeout') ||
              m.contains('aborted') ||
              m.contains('took longer') ||
              m.contains('larger than') ||
              m.contains('requestoptions'))) {
        return true;
      }
      if (m.contains('socketexception') || errStr.contains('socketexception')) {
        return true;
      }
      if (m.contains('failed host lookup') ||
          m.contains('network is unreachable') ||
          m.contains('errno = 7') ||
          m.contains('errno = 101') ||
          m.contains('no address associated with hostname')) {
        return true;
      }
    }
    return false;
  }

  static String _dioExceptionMessage(dio.DioException e, AppLocalizations t) {
    final inner = e.error;
    if (inner is ApiErrorDetails) {
      final fromCode = _messageForKnownApiErrorCode(inner.code, t);
      if (fromCode != null) return fromCode;
      final m = inner.message;
      if (m != null && m.isNotEmpty) return m;
    }

    final response = e.response;
    if (response != null && response.data != null) {
      final msg = _extractFromResponseData(response.data, t);
      if (msg != null && msg.isNotEmpty) return msg;
    }

    if (_isNetworkConnectivityFailure(e)) {
      return t.errorInternetUnavailablePleaseRetry;
    }

    switch (e.type) {
      case dio.DioExceptionType.connectionTimeout:
        return t.errorConnectionTimeout;
      case dio.DioExceptionType.sendTimeout:
        return t.errorSendTimeout;
      case dio.DioExceptionType.receiveTimeout:
        return t.errorReceiveTimeout;
      case dio.DioExceptionType.connectionError:
        return t.errorConnectionError;
      case dio.DioExceptionType.badCertificate:
        return t.errorConnectionError;
      case dio.DioExceptionType.cancel:
        return t.errorUnknown;
      case dio.DioExceptionType.badResponse:
      case dio.DioExceptionType.unknown:
        break;
    }

    if (e.message != null && e.message!.isNotEmpty) {
      if (_isLowLevelNetworkNoise(e.message!)) {
        return t.errorConnectionError;
      }
      var message = e.message!;
      if (message.contains('400:')) {
        message = message.split('400:').last.trim();
        if (message.startsWith('{')) {
          return t.errorFileUploadFailed;
        }
        return message;
      }
      if (_isLowLevelNetworkNoise(message) || (message.length > 200 && message.contains('DioException'))) {
        return t.errorConnectionError;
      }
      return message;
    }

    if (e.type == dio.DioExceptionType.connectionError) {
      return t.errorConnectionError;
    }
    return t.errorUnknownServer;
  }

  static String _userMessage(Object e, AppLocalizations t) {
    if (e is dio.DioException) {
      return _dioExceptionMessage(e, t);
    }
    if (e is DocumentPolicyException) {
      final msg = e.message.trim();
      if (msg.isNotEmpty) return msg;
      final code = e.code?.trim();
      if (code != null && code.isNotEmpty) return code;
      return t.errorDataSaveFailed;
    }

    final errorMessage = e.toString();
    if (errorMessage == 'Exception') {
      return t.errorDataSaveFailed;
    }
    if (_isLowLevelNetworkNoise(errorMessage)) {
      return t.errorConnectionError;
    }
    if (errorMessage.contains('خطا')) {
      return errorMessage;
    }
    return t.errorDataSaveFailed;
  }
}
