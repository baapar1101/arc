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
  List<Map<String, dynamic>> _transactions = const <Map<String, dynamic>>[];
  Map<String, dynamic>? _metrics;
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _service = WalletService(ApiClient());
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
      final tx = await _service.listTransactions(businessId: widget.businessId, limit: 20, fromDate: _fromDate, toDate: _toDate);
      final m = await _service.getMetrics(businessId: widget.businessId, fromDate: _fromDate, toDate: _toDate);
      setState(() {
        _overview = res;
        _transactions = tx;
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
        final data = await _service.topUp(
          businessId: widget.businessId,
          amount: amount,
          description: descCtrl.text,
          gatewayId: gatewayId,
        );
        final paymentUrl = (data['payment_url'] ?? '').toString();
        if (paymentUrl.isNotEmpty) {
          final uri = Uri.parse(paymentUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('درخواست افزایش اعتبار ثبت شد')));
          }
        }
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
        }
      }
    }
  }

  Future<void> _pickFromDate() async {
    final initial = _fromDate ?? DateTime.now().subtract(const Duration(days: 30));
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: initial,
    );
    if (picked != null) {
      setState(() => _fromDate = picked);
      await _reloadRange();
    }
  }

  Future<void> _pickToDate() async {
    final initial = _toDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: initial,
    );
    if (picked != null) {
      setState(() => _toDate = picked);
      await _reloadRange();
    }
  }

  Future<void> _reloadRange() async {
    setState(() => _loading = true);
    try {
      final tx = await _service.listTransactions(
        businessId: widget.businessId,
        limit: 20,
        fromDate: _fromDate,
        toDate: _toDate,
      );
      final m = await _service.getMetrics(
        businessId: widget.businessId,
        fromDate: _fromDate,
        toDate: _toDate,
      );
      if (mounted) {
        setState(() {
          _transactions = tx;
          _metrics = m;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
              : Padding(
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
                                    Text('${overview?['available_balance'] ?? 0}', style: theme.textTheme.headlineSmall),
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
                                    Text('${overview?['pending_balance'] ?? 0}', style: theme.textTheme.headlineSmall),
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
                          OutlinedButton.icon(
                            onPressed: _pickFromDate,
                            icon: const Icon(Icons.date_range),
                            label: Text(_fromDate != null ? _fromDate!.toIso8601String().split('T').first : 'از تاریخ'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _pickToDate,
                            icon: const Icon(Icons.event),
                            label: Text(_toDate != null ? _toDate!.toIso8601String().split('T').first : 'تا تاریخ'),
                          ),
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
                                    Chip(label: Text('ورودی ناخالص: ${_metrics?['totals']?['gross_in'] ?? 0}')),
                                    Chip(label: Text('کارمزد ورودی: ${_metrics?['totals']?['fees_in'] ?? 0}')),
                                    Chip(label: Text('ورودی خالص: ${_metrics?['totals']?['net_in'] ?? 0}')),
                                    Chip(label: Text('خروجی ناخالص: ${_metrics?['totals']?['gross_out'] ?? 0}')),
                                    Chip(label: Text('کارمزد خروجی: ${_metrics?['totals']?['fees_out'] ?? 0}')),
                                    Chip(label: Text('خروجی خالص: ${_metrics?['totals']?['net_out'] ?? 0}')),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final api = ApiClient();
                              final path = '/businesses/${widget.businessId}/wallet/transactions/export'
                                  '${_fromDate != null ? '?from_date=${_fromDate!.toIso8601String()}' : ''}'
                                  '${_toDate != null ? (_fromDate != null ? '&' : '?') + 'to_date=${_toDate!.toIso8601String()}' : ''}';
                              try {
                                await api.downloadExcel(path); // bytes download and save handled
                                // Save as CSV file
                                // ignore: avoid_web_libraries_in_flutter
                                // ignore: unused_import
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در دانلود CSV تراکنش‌ها: $e')));
                              }
                            },
                            icon: const Icon(Icons.download),
                            label: const Text('دانلود CSV تراکنش‌ها'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final api = ApiClient();
                              final path = '/businesses/${widget.businessId}/wallet/metrics/export'
                                  '${_fromDate != null ? '?from_date=${_fromDate!.toIso8601String()}' : ''}'
                                  '${_toDate != null ? (_fromDate != null ? '&' : '?') + 'to_date=${_toDate!.toIso8601String()}' : ''}';
                              try {
                                await api.downloadExcel(path);
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در دانلود CSV خلاصه: $e')));
                              }
                            },
                            icon: const Icon(Icons.table_view),
                            label: const Text('دانلود CSV خلاصه'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('تراکنش‌های اخیر', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Card(
                          child: ListView.separated(
                            itemCount: _transactions.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final m = _transactions[i];
                              final amount = m['amount'] ?? 0;
                              return ListTile(
                                leading: Icon(
                                  m['type'] == 'payout_request' ? Icons.account_balance : Icons.swap_horiz,
                                  color: theme.colorScheme.primary,
                                ),
                                title: Text('${m['type']} - ${m['status']}'),
                                subtitle: Text('${m['description'] ?? ''}'),
                                trailing: Text('${formatWithThousands((amount is num) ? amount : double.tryParse('$amount') ?? 0)}'),
                                onTap: () async {
                                  final docId = m['document_id'];
                                  if (!mounted) return;
                                  await context.pushNamed(
                                    'business_documents',
                                    pathParameters: {'business_id': widget.businessId.toString()},
                                    extra: {'focus_document_id': docId},
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
