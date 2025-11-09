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
    switch ((t ?? '').toLowerCase()) {
      case 'top_up':
        return 'افزایش اعتبار';
      case 'customer_payment':
        return 'پرداخت مشتری';
      case 'payout_request':
        return 'درخواست تسویه';
      case 'payout_settlement':
        return 'تسویه';
      case 'refund':
        return 'استرداد';
      case 'fee':
        return 'کارمزد';
      default:
        return t ?? 'نامشخص';
    }
  }

  String _statusLabel(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'pending':
        return 'در انتظار';
      case 'approved':
        return 'تایید شده';
      case 'processing':
        return 'در حال پردازش';
      case 'succeeded':
        return 'موفق';
      case 'failed':
        return 'ناموفق';
      case 'canceled':
        return 'لغو شده';
      default:
        return s ?? 'نامشخص';
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
          title: Text('درخواست تسویه'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BankAccountComboboxWidget(
                  businessId: widget.businessId,
                  selectedAccountId: bankId?.toString(),
                  onChanged: (opt) => bankId = int.tryParse(opt?.id ?? ''),
                  hintText: 'انتخاب حساب بانکی',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(labelText: 'مبلغ'),
                  keyboardType: TextInputType.number,
                  validator: (v) => (v == null || v.isEmpty) ? 'الزامی' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)'),
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('درخواست تسویه ثبت شد')));
        }
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
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
          title: const Text('افزایش اعتبار'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(labelText: 'مبلغ'),
                  keyboardType: TextInputType.number,
                  validator: (v) => (v == null || v.isEmpty) ? 'الزامی' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)'),
                ),
                const SizedBox(height: 8),
                if (gateways.isNotEmpty)
                  DropdownButtonFormField<int>(
                    value: gatewayId,
                    decoration: const InputDecoration(labelText: 'درگاه پرداخت'),
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
        _showLoadingDialog('در حال ثبت درخواست و آماده‌سازی درگاه...');
        final data = await _service.topUp(
          businessId: widget.businessId,
          amount: amount,
          description: descCtrl.text,
          gatewayId: gatewayId,
        );
        if (mounted) Navigator.of(context).pop(); // close loading
        final paymentUrl = (data['payment_url'] ?? '').toString();
        if (paymentUrl.isNotEmpty) {
          _showLoadingDialog('در حال انتقال به درگاه پرداخت...');
          await _openPaymentUrlWithFallback(paymentUrl);
          if (mounted) Navigator.of(context).pop(); // close loading
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('درخواست افزایش اعتبار ثبت شد، اما لینک پرداخت دریافت نشد. لطفاً بعداً دوباره تلاش کنید یا تنظیمات درگاه را بررسی کنید.')));
          }
        }
        await _load();
      } catch (e) {
        if (mounted) {
          // ensure loading dialog is closed if open
          Navigator.of(context, rootNavigator: true).maybePop();
        }
        String friendly = 'خطا در ثبت درخواست افزایش اعتبار';
        if (e is DioException) {
          final status = e.response?.statusCode;
          final body = e.response?.data;
          final serverMsg = (body is Map && body['message'] is String) ? (body['message'] as String) : null;
          final errorCode = (body is Map && body['error_code'] is String) ? (body['error_code'] as String) : null;
          if (errorCode == 'GATEWAY_INIT_FAILED') {
            friendly = 'خطا در اتصال به درگاه. لطفاً تنظیمات درگاه را بررسی کنید یا بعداً تلاش کنید.';
          } else if (errorCode == 'INVALID_CONFIG') {
            friendly = 'پیکربندی درگاه ناقص است. لطفاً مرچنت آی‌دی و آدرس بازگشت را بررسی کنید.';
          } else if (errorCode == 'GATEWAY_DISABLED') {
            friendly = 'این درگاه غیرفعال است.';
          } else if (errorCode == 'GATEWAY_NOT_FOUND') {
            friendly = 'درگاه پرداخت یافت نشد.';
          } else if (status != null && status >= 500) {
            friendly = 'خطای سرور هنگام اتصال به درگاه. لطفاً بعداً تلاش کنید.';
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
        title: const Text('انتقال به درگاه پرداخت'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('برای ادامه پرداخت، لینک زیر را باز کنید:'),
            const SizedBox(height: 8),
            SelectableText(url),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لینک کپی شد')));
              }
            },
            child: const Text('کپی لینک'),
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
                child: const Text('باز کردن'),
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
              child: const Text('باز کردن'),
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
                              Text('کیف‌پول کسب‌وکار', style: theme.textTheme.titleLarge),
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
                                        Text('مانده قابل برداشت', style: theme.textTheme.labelLarge),
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
                                        Text('مانده در انتظار تایید', style: theme.textTheme.labelLarge),
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
                                label: const Text('درخواست تسویه'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: _openTopUpDialog,
                                icon: const Icon(Icons.add),
                                label: const Text('افزایش اعتبار'),
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
                                    Text('گزارش ۳۰ روز اخیر', style: theme.textTheme.titleMedium),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      children: [
                                        Chip(label: Text('ورودی ناخالص: ${formatWithThousands((_metrics?['totals']?['gross_in'] ?? 0) is num ? (_metrics?['totals']?['gross_in'] ?? 0) : double.tryParse('${_metrics?['totals']?['gross_in']}') ?? 0)}')),
                                        Chip(label: Text('کارمزد ورودی: ${formatWithThousands((_metrics?['totals']?['fees_in'] ?? 0) is num ? (_metrics?['totals']?['fees_in'] ?? 0) : double.tryParse('${_metrics?['totals']?['fees_in']}') ?? 0)}')),
                                        Chip(label: Text('ورودی خالص: ${formatWithThousands((_metrics?['totals']?['net_in'] ?? 0) is num ? (_metrics?['totals']?['net_in'] ?? 0) : double.tryParse('${_metrics?['totals']?['net_in']}') ?? 0)}')),
                                        Chip(label: Text('خروجی ناخالص: ${formatWithThousands((_metrics?['totals']?['gross_out'] ?? 0) is num ? (_metrics?['totals']?['gross_out'] ?? 0) : double.tryParse('${_metrics?['totals']?['gross_out']}') ?? 0)}')),
                                        Chip(label: Text('کارمزد خروجی: ${formatWithThousands((_metrics?['totals']?['fees_out'] ?? 0) is num ? (_metrics?['totals']?['fees_out'] ?? 0) : double.tryParse('${_metrics?['totals']?['fees_out']}') ?? 0)}')),
                                        Chip(label: Text('خروجی خالص: ${formatWithThousands((_metrics?['totals']?['net_out'] ?? 0) is num ? (_metrics?['totals']?['net_out'] ?? 0) : double.tryParse('${_metrics?['totals']?['net_out']}') ?? 0)}')),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          // دکمه‌های خروجی CSV در پایین جدول موجود هستند؛ این بخش حذف شد تا فیلتر تاریخ از طریق جدول انجام شود
                          const SizedBox(height: 16),
                          Text('تراکنش‌های اخیر', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: tableHeight,
                            child: DataTableWidget<Map<String, dynamic>>(
                              config: DataTableConfig<Map<String, dynamic>>(
                                endpoint: '/businesses/${widget.businessId}/wallet/transactions/table',
                                title: 'تراکنش‌ها',
                                showTableIcon: true,
                                showSearch: false,
                                showActiveFilters: false,
                                showPagination: true,
                                defaultPageSize: 20,
                                pageSizeOptions: const [10, 20, 50, 100],
                                enableColumnSettings: true,
                                columns: [
                              DateColumn('created_at', 'تاریخ', filterType: ColumnFilterType.dateRange, formatter: (it) {
                                    final v = (it['created_at'] ?? '').toString();
                                    return v.split('T').first;
                                  }),
                                  TextColumn('type', 'نوع', formatter: (it) => _typeLabel((it['type'] ?? '').toString())),
                                  TextColumn('status', 'وضعیت', formatter: (it) => _statusLabel((it['status'] ?? '').toString())),
                                  TextColumn('description', 'توضیحات', searchable: false, overflow: true, maxLines: 1),
                                  NumberColumn('amount', 'مبلغ', formatter: (it) {
                                    final amount = it['amount'];
                                    final n = (amount is num) ? amount.toDouble() : double.tryParse('$amount') ?? 0;
                                    return formatWithThousands(n);
                                  }),
                                  NumberColumn('fee_amount', 'کارمزد', formatter: (it) {
                                    final fee = it['fee_amount'];
                                    final n = (fee is num) ? fee.toDouble() : double.tryParse('$fee') ?? 0;
                                    return formatWithThousands(n);
                                  }),
                                  TextColumn('document_id', 'سند', formatter: (it) {
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
