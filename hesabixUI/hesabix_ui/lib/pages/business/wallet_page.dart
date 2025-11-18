import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../widgets/permission/access_denied_page.dart';
// import '../../core/api_client.dart'; // duplicate removed
import '../../services/wallet_service.dart';
import '../../widgets/invoice/bank_account_combobox_widget.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../services/payment_gateway_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:url_launcher/link.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import '../../core/calendar_controller.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import '../../core/date_utils.dart' show HesabixDateUtils;

class WalletPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const WalletPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  late final WalletService _service;
  bool _loading = true;
  Map<String, dynamic>? _overview;
  String? _error;
  Map<String, dynamic>? _metrics;
  DateTime? _fromDate;
  DateTime? _toDate;
  CalendarController? _calendarCtrl;

  String _typeLabel(String? t) {
    final l = AppLocalizations.of(context);
    switch ((t ?? '').toLowerCase()) {
      case 'top_up':
        return l.walletTypeTopUp;
      case 'customer_payment':
        return l.walletTypeCustomerPayment;
      case 'payout_request':
        return l.walletTypePayoutRequest;
      case 'payout_settlement':
        return l.walletTypePayoutSettlement;
      case 'refund':
        return l.walletTypeRefund;
      case 'fee':
        return l.walletTypeFee;
      case 'storage_subscription':
        return 'خرید اشتراک ذخیره‌سازی';
      case 'storage_over_usage':
        return 'پرداخت استفاده بیش از حد ذخیره‌سازی';
      case 'storage_renewal':
        return 'تمدید اشتراک ذخیره‌سازی';
      case 'storage_payment':
        return 'پرداخت ذخیره‌سازی';
      case 'gift_credit':
        return 'اعتبار هدیه';
      default:
        return l.unknown;
    }
  }

  String _statusLabel(String? s) {
    final l = AppLocalizations.of(context);
    switch ((s ?? '').toLowerCase()) {
      case 'pending':
        return l.pending;
      case 'approved':
        return l.statusApproved;
      case 'processing':
        return l.statusProcessing;
      case 'succeeded':
        return l.statusSucceeded;
      case 'failed':
        return l.statusFailed;
      case 'canceled':
        return l.statusCanceled;
      default:
        return l.unknown;
    }
  }

  // آیکون نوع تراکنش دیگر استفاده نمی‌شود (نمایش در جدول)

  @override
  void initState() {
    super.initState();
    _service = WalletService(ApiClient());
    // بارگذاری کنترلر تقویم برای پشتیبانی از جلالی/میلادی در فیلترهای جدول
    CalendarController.load().then((c) {
      if (mounted) setState(() => _calendarCtrl = c);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _service.getOverview(businessId: widget.businessId);
      final now = DateTime.now();
      _toDate = now;
      _fromDate = now.subtract(const Duration(days: 30));
      final m = await _service.getMetrics(businessId: widget.businessId, fromDate: _fromDate, toDate: _toDate);
      setState(() {
        _overview = res;
        _metrics = m;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _openPayoutDialog() async {
    final t = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    int? bankId;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.walletPayoutRequestTitle),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BankAccountComboboxWidget(
                  businessId: widget.businessId,
                  selectedAccountId: bankId?.toString(),
                  onChanged: (opt) => bankId = int.tryParse(opt?.id ?? ''),
                  hintText: t.walletSelectBankAccountHint,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amountCtrl,
                  decoration: InputDecoration(labelText: t.moneyAmount),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    EnglishDigitsFormatter(),
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  validator: (v) => (v == null || v.isEmpty) ? t.required : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: descCtrl,
                  decoration: InputDecoration(labelText: t.descriptionOptional),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() == true && bankId != null) {
                  Navigator.pop(ctx, true);
                }
              },
              child: Text(t.confirm),
            ),
          ],
        );
      },
    );
    if (result == true && bankId != null) {
      try {
        final amount = double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
        await _service.requestPayout(
          businessId: widget.businessId,
          bankAccountId: bankId!,
          amount: amount,
          description: descCtrl.text,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.walletPayoutRequested)));
        }
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t.error}: $e')));
        }
      }
    }
  }

  Future<void> _openTopUpDialog() async {
    final t = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final pgService = PaymentGatewayService(ApiClient());
    List<Map<String, dynamic>> gateways = const <Map<String, dynamic>>[];
    int? gatewayId;
    try {
      gateways = await pgService.listBusinessGateways(widget.businessId);
      if (gateways.isNotEmpty) {
        gatewayId = int.tryParse('${gateways.first['id']}');
      }
    } catch (_) {}
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.walletTopUpTitle),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: amountCtrl,
                  decoration: InputDecoration(labelText: t.moneyAmount),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    EnglishDigitsFormatter(),
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  validator: (v) => (v == null || v.isEmpty) ? t.required : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: descCtrl,
                  decoration: InputDecoration(labelText: t.descriptionOptional),
                ),
                const SizedBox(height: 8),
                if (gateways.isNotEmpty)
                  DropdownButtonFormField<int>(
                    value: gatewayId,
                    decoration: InputDecoration(labelText: t.walletPaymentGateway),
                    items: gateways
                        .map((g) => DropdownMenuItem<int>(
                              value: int.tryParse('${g['id']}'),
                              child: Text('${g['display_name']} (${g['provider']})'),
                            ))
                        .toList(),
                    onChanged: (v) => gatewayId = v,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() == true && (gateways.isEmpty || gatewayId != null)) {
                  Navigator.pop(ctx, true);
                }
              },
              child: Text(t.confirm),
            ),
          ],
        );
      },
    );
    if (result == true) {
      try {
        final amount = double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
        _showLoadingDialog(t.walletTopUpInitializing);
        final data = await _service.topUp(
          businessId: widget.businessId,
          amount: amount,
          description: descCtrl.text,
          gatewayId: gatewayId,
        );
        if (mounted) Navigator.of(context).pop(); // close loading
        final paymentUrl = (data['payment_url'] ?? '').toString();
        if (paymentUrl.isNotEmpty) {
          _showLoadingDialog(t.walletRedirectingToGateway);
          await _openPaymentUrlWithFallback(paymentUrl);
          if (mounted) Navigator.of(context).pop(); // close loading
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.walletTopUpNoPaymentLink)));
          }
        }
        await _load();
      } catch (e) {
        if (mounted) {
          // ensure loading dialog is closed if open
          Navigator.of(context, rootNavigator: true).maybePop();
        }
        String friendly = t.walletGatewayServerError;
        if (e is DioException) {
          final status = e.response?.statusCode;
          final body = e.response?.data;
          final serverMsg = (body is Map && body['message'] is String) ? (body['message'] as String) : null;
          final errorCode = (body is Map && body['error_code'] is String) ? (body['error_code'] as String) : null;
          if (errorCode == 'GATEWAY_INIT_FAILED') {
            friendly = t.walletGatewayInitFailed;
          } else if (errorCode == 'INVALID_CONFIG') {
            friendly = t.walletInvalidGatewayConfig;
          } else if (errorCode == 'GATEWAY_DISABLED') {
            friendly = t.walletGatewayDisabled;
          } else if (errorCode == 'GATEWAY_NOT_FOUND') {
            friendly = t.walletGatewayNotFound;
          } else if (status != null && status >= 500) {
            friendly = t.walletGatewayServerError;
          } else if (serverMsg != null && serverMsg.isNotEmpty) {
            friendly = serverMsg;
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly)));
        }
      }
    }
  }

  Future<void> _openPaymentUrlWithFallback(String url) async {
    // وب: تلاش برای باز کردن مستقیم؛ در صورت عدم موفقیت، دیالوگ جایگزین
    if (kIsWeb) {
      try {
        final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        if (!launched) {
          await _showOpenLinkDialog(url);
        }
      } catch (_) {
        await _showOpenLinkDialog(url);
      }
      return;
    }
    // دسکتاپ/موبایل: باز کردن در مرورگر پیش‌فرض باFallback
    try {
      final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!launched) {
        await _showOpenLinkDialog(url);
      }
    } catch (_) {
      await _showOpenLinkDialog(url);
    }
  }

  void _showLoadingDialog(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showOpenLinkDialog(String url) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).walletOpenGatewayDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context).walletOpenGatewayDialogInstructions),
            const SizedBox(height: 8),
            SelectableText(url),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).copied)));
              }
            },
            child: Text(AppLocalizations.of(context).copyLink),
          ),
          if (kIsWeb)
            Link(
              uri: Uri.parse(url),
              target: LinkTarget.blank,
              builder: (context, followLink) => FilledButton(
                onPressed: () {
                  followLink?.call();
                  Navigator.of(ctx).pop();
                },
                child: Text(AppLocalizations.of(context).open),
              ),
            )
          else
            FilledButton(
              onPressed: () async {
                try {
                  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                } finally {
                  if (mounted) Navigator.of(ctx).pop();
                }
              },
              child: Text(AppLocalizations.of(context).open),
            ),
        ],
      ),
    );
  }

  // فیلتر بازه تاریخ اکنون توسط DataTableWidget و Dialog داخلی آن انجام می‌شود

  // بارگذاری بیشتر جایگزین با جدول سراسری شده است

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (!widget.authStore.canReadSection('wallet')) {
      return AccessDeniedPage(message: t.accessDenied);
    }

    final theme = Theme.of(context);
    final overview = _overview;
    final currency = overview?['base_currency_code'] ?? 'IRR';

    return Scaffold(
      appBar: AppBar(title: Text(t.wallet)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final double tableHeight = (constraints.maxHeight - 360).clamp(280.0, constraints.maxHeight);
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.wallet, size: 32, color: theme.colorScheme.primary),
                              const SizedBox(width: 12),
                              Text(t.walletBusinessTitle, style: theme.textTheme.titleLarge),
                              const Spacer(),
                              Chip(label: Text(currency)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(t.walletAvailableBalance, style: theme.textTheme.labelLarge),
                                        const SizedBox(height: 8),
                                        Text('${formatWithThousands((overview?['available_balance'] ?? 0) is num ? (overview?['available_balance'] ?? 0) : double.tryParse('${overview?['available_balance']}') ?? 0)}', style: theme.textTheme.headlineSmall),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(t.walletPendingBalance, style: theme.textTheme.labelLarge),
                                        const SizedBox(height: 8),
                                        Text('${formatWithThousands((overview?['pending_balance'] ?? 0) is num ? (overview?['pending_balance'] ?? 0) : double.tryParse('${overview?['pending_balance']}') ?? 0)}', style: theme.textTheme.headlineSmall),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Spacer(),
                              FilledButton.icon(
                                onPressed: _openPayoutDialog,
                                icon: const Icon(Icons.account_balance),
                                label: Text(t.walletRequestPayout),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: _openTopUpDialog,
                                icon: const Icon(Icons.add),
                                label: Text(t.walletTopUp),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_metrics != null)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.walletLast30Days, style: theme.textTheme.titleMedium),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      children: [
                                        Chip(label: Text('${t.walletGrossIn}: ${formatWithThousands((_metrics?['totals']?['gross_in'] ?? 0) is num ? (_metrics?['totals']?['gross_in'] ?? 0) : double.tryParse('${_metrics?['totals']?['gross_in']}') ?? 0)}')),
                                        Chip(label: Text('${t.walletFeesIn}: ${formatWithThousands((_metrics?['totals']?['fees_in'] ?? 0) is num ? (_metrics?['totals']?['fees_in'] ?? 0) : double.tryParse('${_metrics?['totals']?['fees_in']}') ?? 0)}')),
                                        Chip(label: Text('${t.walletNetIn}: ${formatWithThousands((_metrics?['totals']?['net_in'] ?? 0) is num ? (_metrics?['totals']?['net_in'] ?? 0) : double.tryParse('${_metrics?['totals']?['net_in']}') ?? 0)}')),
                                        Chip(label: Text('${t.walletGrossOut}: ${formatWithThousands((_metrics?['totals']?['gross_out'] ?? 0) is num ? (_metrics?['totals']?['gross_out'] ?? 0) : double.tryParse('${_metrics?['totals']?['gross_out']}') ?? 0)}')),
                                        Chip(label: Text('${t.walletFeesOut}: ${formatWithThousands((_metrics?['totals']?['fees_out'] ?? 0) is num ? (_metrics?['totals']?['fees_out'] ?? 0) : double.tryParse('${_metrics?['totals']?['fees_out']}') ?? 0)}')),
                                        Chip(label: Text('${t.walletNetOut}: ${formatWithThousands((_metrics?['totals']?['net_out'] ?? 0) is num ? (_metrics?['totals']?['net_out'] ?? 0) : double.tryParse('${_metrics?['totals']?['net_out']}') ?? 0)}')),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          // دکمه‌های خروجی CSV در پایین جدول موجود هستند؛ این بخش حذف شد تا فیلتر تاریخ از طریق جدول انجام شود
                          const SizedBox(height: 16),
                          Text(t.walletRecentTransactions, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: tableHeight,
                            child: DataTableWidget<Map<String, dynamic>>(
                              config: DataTableConfig<Map<String, dynamic>>(
                                endpoint: '/businesses/${widget.businessId}/wallet/transactions/table',
                                title: t.walletTransactions,
                                showTableIcon: true,
                                showSearch: false,
                                showActiveFilters: false,
                                showPagination: true,
                                defaultPageSize: 20,
                                pageSizeOptions: const [10, 20, 50, 100],
                                enableColumnSettings: true,
                                columns: [
                              DateColumn('created_at', t.createdAt, filterType: ColumnFilterType.dateRange, formatter: (it) {
                                    final v = it['created_at'];
                                    if (v == null) return '';
                                    
                                    DateTime? date;
                                    if (v is DateTime) {
                                      date = v;
                                    } else if (v is String) {
                                      try {
                                        // حذف T و بخش زمان اگر وجود دارد
                                        final cleanDate = v.split('T').first;
                                        date = DateTime.parse(cleanDate);
                                      } catch (e) {
                                        return v.toString();
                                      }
                                    } else if (v is Map<String, dynamic>) {
                                      // اگر تاریخ فرمت‌شده از سرور آمد
                                      if (v.containsKey('formatted')) {
                                        // اگر تاریخ از قبل فرمت شده است، مستقیم بازگردان
                                        return v['formatted'].toString();
                                      } else if (v.containsKey('date_only')) {
                                        try {
                                          date = DateTime.parse(v['date_only'].toString());
                                        } catch (e) {
                                          return v['date_only'].toString();
                                        }
                                      } else {
                                        return v.toString();
                                      }
                                    } else {
                                      return v.toString();
                                    }
                                    
                                    // استفاده از تقویم کاربر برای فرمت کردن
                                    final isJalali = _calendarCtrl?.isJalali ?? false;
                                    return HesabixDateUtils.formatForDisplay(date, isJalali);
                                  }),
                                  TextColumn('type', t.type, formatter: (it) => _typeLabel((it['type'] ?? '').toString())),
                                  TextColumn('status', t.status, formatter: (it) => _statusLabel((it['status'] ?? '').toString())),
                                  TextColumn('description', t.description, searchable: false, overflow: true, maxLines: 1),
                                  NumberColumn('amount', t.moneyAmount, formatter: (it) {
                                    final amount = it['amount'];
                                    final n = (amount is num) ? amount.toDouble() : double.tryParse('$amount') ?? 0;
                                    return formatWithThousands(n);
                                  }),
                                  NumberColumn('fee_amount', t.feeAmount, formatter: (it) {
                                    final fee = it['fee_amount'];
                                    final n = (fee is num) ? fee.toDouble() : double.tryParse('$fee') ?? 0;
                                    return formatWithThousands(n);
                                  }),
                                  TextColumn('document_id', t.document, formatter: (it) {
                                    final d = it['document_id'];
                                    return (d == null || '$d' == 'null') ? '-' : '$d';
                                  }),
                                ],
                                onRowTap: (row) async {
                                  final docId = row['document_id'];
                                  if (docId == null) return;
                                  if (!mounted) return;
                                  await context.pushNamed(
                                    'business_documents',
                                    pathParameters: {'business_id': widget.businessId.toString()},
                                    extra: {'focus_document_id': docId},
                                  );
                                },
                                showExportButtons: true,
                                excelEndpoint: '/businesses/${widget.businessId}/wallet/transactions/export'
                                    '${_fromDate != null ? '?from_date=${_fromDate!.toIso8601String()}' : ''}'
                                    '${_toDate != null ? (_fromDate != null ? '&' : '?') + 'to_date=${_toDate!.toIso8601String()}' : ''}',
                              ),
                              fromJson: (json) => Map<String, dynamic>.from(json),
                              calendarController: _calendarCtrl,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
