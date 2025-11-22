import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/wallet_service.dart';
import '../../services/payment_gateway_service.dart';
import '../../core/api_client.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/snackbar_helper.dart';

/// دیالوگ افزایش اعتبار کیف پول
/// 
/// این ویجت یک دیالوگ کامل برای افزایش اعتبار کیف پول ارائه می‌دهد
/// که شامل فیلدهای مبلغ، توضیحات و انتخاب درگاه پرداخت است.
class WalletTopUpDialog extends StatefulWidget {
  final int businessId;
  final String? currencyLabel;
  final VoidCallback? onSuccess;
  final void Function(String error)? onError;

  const WalletTopUpDialog({
    super.key,
    required this.businessId,
    this.currencyLabel,
    this.onSuccess,
    this.onError,
  });

  /// نمایش دیالوگ افزایش اعتبار کیف پول
  static Future<void> show({
    required BuildContext context,
    required int businessId,
    String? currencyLabel,
    VoidCallback? onSuccess,
    void Function(String error)? onError,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => WalletTopUpDialog(
        businessId: businessId,
        currencyLabel: currencyLabel,
        onSuccess: onSuccess,
        onError: onError,
      ),
    );
  }

  @override
  State<WalletTopUpDialog> createState() => _WalletTopUpDialogState();
}

class _WalletTopUpDialogState extends State<WalletTopUpDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _walletService = WalletService(ApiClient());
  final _pgService = PaymentGatewayService(ApiClient());
  
  bool _loading = false;
  bool _loadingGateways = true;
  List<Map<String, dynamic>> _gateways = const <Map<String, dynamic>>[];
  int? _gatewayId;
  String _currencyLabel = 'تومان';

  @override
  void initState() {
    super.initState();
    _currencyLabel = widget.currencyLabel ?? 'تومان';
    _loadData();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loadingGateways = true);
    try {
      // بارگذاری درگاه‌های پرداخت
      _gateways = await _pgService.listBusinessGateways(widget.businessId);
      if (_gateways.isNotEmpty) {
        _gatewayId = int.tryParse('${_gateways.first['id']}');
      }
      
      // اگر currencyLabel داده نشده، از wallet overview دریافت می‌کنیم
      if (widget.currencyLabel == null) {
        try {
          final overview = await _walletService.getOverview(businessId: widget.businessId);
          final currencyCode = overview['base_currency_code'] ?? 'IRR';
          _currencyLabel = currencyCode == 'IRR' ? 'تومان' : currencyCode;
        } catch (_) {
          // اگر خطا رخ داد، از پیش‌فرض استفاده می‌کنیم
        }
      }
    } catch (_) {
      // خطا در بارگذاری درگاه‌ها
    } finally {
      if (mounted) {
        setState(() => _loadingGateways = false);
      }
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_gateways.isNotEmpty && _gatewayId == null) return;

    setState(() => _loading = true);
    try {
      final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;
      final data = await _walletService.topUp(
        businessId: widget.businessId,
        amount: amount,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        gatewayId: _gatewayId,
      );

      if (!mounted) return;

      final paymentUrl = (data['payment_url'] ?? '').toString();
      if (paymentUrl.isNotEmpty) {
        try {
          await launchUrl(Uri.parse(paymentUrl), mode: LaunchMode.externalApplication);
        } catch (_) {
          // اگر باز نشد، فقط لینک را نمایش می‌دهیم
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('لینک پرداخت: $paymentUrl')),
            );
          }
        }
      } else {
        if (mounted) {
          final t = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.walletTopUpNoPaymentLink)),
          );
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess?.call();
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString();
        widget.onError?.call(errorMsg);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در افزایش اعتبار: $errorMsg'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header با گرادیان
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary,
                    colorScheme.primary.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.walletTopUpTitle,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'افزودن اعتبار به کیف پول کسب و کار',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: t.dialogClose,
                  ),
                ],
              ),
            ),
            // محتوای فرم
            Form(
              key: _formKey,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _loadingGateways
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // فیلد مبلغ
                          TextFormField(
                            controller: _amountCtrl,
                            enabled: !_loading,
                            decoration: InputDecoration(
                              labelText: '${t.moneyAmount} ($_currencyLabel)',
                              hintText: 'مبلغ مورد نظر را وارد کنید',
                              prefixIcon: const Icon(Icons.currency_exchange),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              EnglishDigitsFormatter(),
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                            ],
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'وارد کردن مبلغ الزامی است';
                              }
                              final amount = double.tryParse(v.replaceAll(',', ''));
                              if (amount == null || amount <= 0) {
                                return 'مبلغ معتبر وارد کنید';
                              }
                              return null;
                            },
                            autofocus: true,
                          ),
                          const SizedBox(height: 20),
                          // فیلد توضیحات
                          TextFormField(
                            controller: _descCtrl,
                            enabled: !_loading,
                            decoration: InputDecoration(
                              labelText: t.descriptionOptional,
                              hintText: 'توضیحات مربوط به این تراکنش',
                              prefixIcon: const Icon(Icons.description_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            ),
                            maxLines: 3,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 20),
                          // انتخاب درگاه پرداخت
                          if (_gateways.isNotEmpty)
                            IgnorePointer(
                              ignoring: _loading,
                              child: Opacity(
                                opacity: _loading ? 0.6 : 1.0,
                                child: DropdownButtonFormField<int>(
                                  value: _gatewayId,
                              decoration: InputDecoration(
                                labelText: t.walletPaymentGateway,
                                hintText: 'درگاه پرداخت را انتخاب کنید',
                                prefixIcon: const Icon(Icons.payment),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              ),
                              items: _gateways
                                  .map((g) => DropdownMenuItem<int>(
                                        value: int.tryParse('${g['id']}'),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.credit_card,
                                              size: 20,
                                              color: colorScheme.primary,
                                            ),
                                            const SizedBox(width: 12),
                                            Text('${g['display_name']} (${g['provider']})'),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (v) => setState(() => _gatewayId = v),
                              validator: (v) => (_gateways.isNotEmpty && v == null) ? 'انتخاب درگاه الزامی است' : null,
                                ),
                              ),
                            ),
                          if (_gateways.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.orange[700], size: 24),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'هیچ درگاه پرداختی تنظیم نشده است. لطفاً از بخش تنظیمات، درگاه پرداخت اضافه کنید.',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.orange[900],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 24),
                          // دکمه‌های عملیات
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _loading ? null : () => Navigator.of(context).pop(),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(t.cancel),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: FilledButton.icon(
                                  onPressed: _loading ? null : _handleSubmit,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: _loading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.payment),
                                  label: Text(_loading ? t.walletTopUpInitializing : t.confirm),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

