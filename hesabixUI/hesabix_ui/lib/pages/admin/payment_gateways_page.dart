import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../config/app_config.dart';
import '../../services/payment_gateway_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'package:uuid/uuid.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

class PaymentGatewaysPage extends StatefulWidget {
  const PaymentGatewaysPage({super.key});

  @override
  State<PaymentGatewaysPage> createState() => _PaymentGatewaysPageState();
}

class _PaymentGatewaysPageState extends State<PaymentGatewaysPage> {
  late final PaymentGatewayService _service;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  int? _editingId;

  // Create form
  final _formKey = GlobalKey<FormState>();
  String _provider = 'zarinpal';
  String _displayName = '';
  bool _isActive = true;
  bool _isSandbox = true;
  final _merchantIdCtrl = TextEditingController();
  final _terminalIdCtrl = TextEditingController();
  final _apiCtrl = TextEditingController(); // برای BitPay
  final _callbackUrlCtrl = TextEditingController();
  final _successRedirectCtrl = TextEditingController();
  final _failureRedirectCtrl = TextEditingController();
  bool _useSuggestedCallback = true;
  final _uuid = const Uuid();

  void _maybeGenerateSandboxMerchantId() {
    if (_provider == 'zarinpal' && _isSandbox) {
      final current = _merchantIdCtrl.text.trim();
      // اگر خالی است یا UUID معتبر نیست، یک UUID تولید کن
      final isUuid = RegExp(r'^[0-9a-fA-F\-]{32,36}$').hasMatch(current);
      if (current.isEmpty || !isUuid) {
        _merchantIdCtrl.text = _uuid.v4();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _service = PaymentGatewayService(ApiClient());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _service.listAdmin();
      setState(() => _items = res);
    } catch (e) {
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      setState(() => _loading = false);
    }
  }

  void _prefillForEdit(Map<String, dynamic> it) {
    print('📝 [PREFILL] Starting prefill for gateway id: ${it['id']}');
    _editingId = int.tryParse('${it['id']}');
    _provider = (it['provider'] ?? 'zarinpal').toString();
    _displayName = (it['display_name'] ?? '').toString();
    _isActive = it['is_active'] == true;
    _isSandbox = it['is_sandbox'] == true;
    print('📝 [PREFILL] Provider: $_provider, DisplayName: $_displayName');
    print('📝 [PREFILL] isActive: $_isActive, isSandbox: $_isSandbox');
    _merchantIdCtrl.clear();
    _terminalIdCtrl.clear();
    _apiCtrl.clear();
    _callbackUrlCtrl.clear();
    _successRedirectCtrl.clear();
    _failureRedirectCtrl.clear();
    final cfg = (it['config'] is Map<String, dynamic>) ? it['config'] as Map<String, dynamic> : <String, dynamic>{};
    if (cfg['merchant_id'] != null) _merchantIdCtrl.text = '${cfg['merchant_id']}';
    if (_provider == 'parsian') {
      final pin = cfg['pin'] ?? cfg['login_account'] ?? cfg['merchant_id'] ?? cfg['terminal_id'];
      if (pin != null && '$pin'.trim().isNotEmpty) {
        _terminalIdCtrl.text = '$pin';
      }
    }
    if (_provider == 'bitpay' && cfg['api'] != null) _apiCtrl.text = '${cfg['api']}';
    if (cfg['callback_url'] != null) _callbackUrlCtrl.text = '${cfg['callback_url']}';
    if (cfg['success_redirect'] != null) _successRedirectCtrl.text = '${cfg['success_redirect']}';
    if (cfg['failure_redirect'] != null) _failureRedirectCtrl.text = '${cfg['failure_redirect']}';
    print('✅ [PREFILL] Prefill completed');
  }

  Map<String, dynamic> _buildConfig() {
    final cfg = <String, dynamic>{};
    if (_provider == 'zarinpal') {
      cfg['merchant_id'] = _merchantIdCtrl.text.trim();
      cfg['callback_url'] = _callbackUrlCtrl.text.trim();
    } else if (_provider == 'parsian') {
      final pin = _terminalIdCtrl.text.trim();
      cfg['pin'] = pin;
      cfg['login_account'] = pin;
      cfg['terminal_id'] = pin;
      cfg['merchant_id'] = pin;
      cfg['callback_url'] = _callbackUrlCtrl.text.trim();
    } else if (_provider == 'bitpay') {
      cfg['merchant_id'] = _merchantIdCtrl.text.trim();
      cfg['api'] = _apiCtrl.text.trim();
      cfg['callback_url'] = _callbackUrlCtrl.text.trim();
    }
    if (_successRedirectCtrl.text.trim().isNotEmpty) {
      cfg['success_redirect'] = _successRedirectCtrl.text.trim();
    }
    if (_failureRedirectCtrl.text.trim().isNotEmpty) {
      cfg['failure_redirect'] = _failureRedirectCtrl.text.trim();
    }
    return cfg;
  }

  Future<void> _submitCreate(BuildContext dialogCtx) async {
    print('💾 [CREATE] Starting create submission');
    print('💾 [CREATE] Provider: $_provider, DisplayName: $_displayName');
    print('💾 [CREATE] isActive: $_isActive, isSandbox: $_isSandbox');
    if (!(_formKey.currentState?.validate() ?? false)) {
      print('❌ [CREATE] Form validation failed');
      return;
    }
    if (!context.mounted) return;
    final ctx = context;
    try {
      final config = _buildConfig();
      print('💾 [CREATE] Config: $config');
      await _service.createAdmin(
        provider: _provider,
        displayName: _displayName,
        isActive: _isActive,
        isSandbox: _isSandbox,
        config: config,
      );
      print('✅ [CREATE] Gateway created successfully');
      if (!ctx.mounted) return;
      Navigator.of(dialogCtx).pop();
      final t = AppLocalizations.of(ctx);
      SnackBarHelper.showSuccess(ctx, message: t.save);
      await _load();
    } catch (e) {
      print('❌ [CREATE] Error creating gateway: $e');
      if (!ctx.mounted) return;
      final t = AppLocalizations.of(ctx);
      SnackBarHelper.showError(
        ctx,
        message: '${t.error}: ${ErrorExtractor.forContext(e, ctx)}',
      );
    }
  }

  Future<void> _submitUpdate(BuildContext dialogCtx) async {
    print('💾 [UPDATE] Starting update submission for gateway id: $_editingId');
    print('💾 [UPDATE] Provider: $_provider, DisplayName: $_displayName');
    print('💾 [UPDATE] isActive: $_isActive, isSandbox: $_isSandbox');
    if (!(_formKey.currentState?.validate() ?? false)) {
      print('❌ [UPDATE] Form validation failed');
      return;
    }
    if (_editingId == null) {
      print('❌ [UPDATE] No editing ID found');
      return;
    }
    if (!context.mounted) return;
    final ctx = context;
    try {
      final config = _buildConfig();
      print('💾 [UPDATE] Config: $config');
      await _service.updateAdmin(
        gatewayId: _editingId!,
        provider: _provider,
        displayName: _displayName,
        isActive: _isActive,
        isSandbox: _isSandbox,
        config: config,
      );
      print('✅ [UPDATE] Gateway updated successfully');
      if (!ctx.mounted) return;
      Navigator.of(dialogCtx).pop();
      final t = AppLocalizations.of(ctx);
      SnackBarHelper.showSuccess(ctx, message: t.updated);
      await _load();
    } catch (e) {
      print('❌ [UPDATE] Error updating gateway: $e');
      if (!ctx.mounted) return;
      final t = AppLocalizations.of(ctx);
      SnackBarHelper.showError(
        ctx,
        message: '${t.error}: ${ErrorExtractor.forContext(e, ctx)}',
      );
    }
  }

  void _openCreateDialog() {
    print('➕ [CREATE DIALOG] Opening create dialog');
    _provider = 'zarinpal';
    _displayName = '';
    _isActive = true;
    _isSandbox = true;
    print('➕ [CREATE DIALOG] Initial state - isActive: $_isActive, isSandbox: $_isSandbox');
    _merchantIdCtrl.clear();
    _terminalIdCtrl.clear();
    _apiCtrl.clear();
    _callbackUrlCtrl.clear();
    _successRedirectCtrl.clear();
    _failureRedirectCtrl.clear();
    _useSuggestedCallback = true;
    _applySuggestedCallback();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.payment_outlined, color: Theme.of(context).colorScheme.primary),
            ),
            SizedBox(width: 12),
            Text(adminTx(context, 'ایجاد درگاه پرداخت', 'New payment gateway')),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // بخش انتخاب Provider
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.apps, size: 20, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(adminTx(context, 'انتخاب درگاه', 'Choose a gateway'), style: context.settingsHub.cardTitleStyle(Theme.of(context).textTheme, color: Theme.of(context).colorScheme.onSurface)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _provider,
                            decoration: InputDecoration(
                              labelText: adminTx(context, 'درگاه پرداخت', 'Payment gateway'),
                              prefixIcon: const Icon(Icons.account_balance),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'zarinpal',
                                child: Row(
                                  children: [
                                    Icon(Icons.payment, size: 20, color: SemanticColorResolver.info(context)),
                                    SizedBox(width: 8),
                                    Text(adminTx(context, 'زرین‌پال', 'Zarinpal')),
                                  ],
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'parsian',
                                child: Row(
                                  children: [
                                    Icon(Icons.payment, size: 20, color: SemanticColorResolver.positive(context)),
                                    SizedBox(width: 8),
                                    Text(adminTx(context, 'پارسیان', 'Parsian')),
                                  ],
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'bitpay',
                                child: Row(
                                  children: [
                                    Icon(Icons.payment, size: 20, color: SemanticColorResolver.warning(context)),
                                    const SizedBox(width: 8),
                                    Text(adminTx(context, 'بیت‌پی', 'BitPay')),
                                  ],
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              print('🔄 [CREATE] Changing provider from $_provider to $v');
                              setState(() {
                                _provider = v ?? 'zarinpal';
                                _applySuggestedCallback();
                                _maybeGenerateSandboxMerchantId();
                              });
                              print('✅ [CREATE] Provider changed to $_provider');
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // بخش تنظیمات عمومی
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.settings, size: 20, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(adminTx(context, 'تنظیمات عمومی', 'General'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: adminTx(context, 'نام نمایشی', 'Display name'),
                              hintText: adminTx(context, 'مثال: درگاه پرداخت اصلی', 'Example: main payment gateway'),
                              prefixIcon: const Icon(Icons.label),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                            ),
                            onChanged: (v) => _displayName = v.trim(),
                            validator: (v) => (v == null || v.trim().isEmpty) ? AppLocalizations.of(context).requiredField : null,
                          ),
                          const SizedBox(height: 12),
                          StatefulBuilder(
                            builder: (BuildContext context, StateSetter setDialogState) {
                              return Column(
                                children: [
                                  SwitchListTile(
                                    title: Text(AppLocalizations.of(context).active),
                                    subtitle: Text(adminTx(context, 'درگاه برای پرداخت در دسترس باشد', 'The gateway is available for payments')),
                                    secondary: const Icon(Icons.check_circle_outline),
                                    value: _isActive,
                                    onChanged: (v) {
                                      print('🔄 [CREATE] Changing isActive from $_isActive to $v');
                                      setDialogState(() {
                                        setState(() {
                                          _isActive = v;
                                        });
                                      });
                                      print('✅ [CREATE] isActive changed to $_isActive');
                                    },
                                  ),
                                  SwitchListTile(
                                    title: Text(adminTx(context, 'حالت تست', 'Sandbox')),
                                    subtitle: Text(adminTx(context, 'پرداخت واقعی انجام نمی‌شود', 'No real payment is taken')),
                                    secondary: const Icon(Icons.science_outlined),
                                    value: _isSandbox,
                                    onChanged: (v) {
                                      print('🔄 [CREATE] Changing isSandbox from $_isSandbox to $v');
                                      setDialogState(() {
                                        setState(() {
                                          _isSandbox = v;
                                          _applySuggestedCallback();
                                          _maybeGenerateSandboxMerchantId();
                                        });
                                      });
                                      print('✅ [CREATE] isSandbox changed to $_isSandbox');
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // بخش تنظیمات درگاه
                  if (_provider == 'zarinpal' || _provider == 'parsian' || _provider == 'bitpay') ...[
                    Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.vpn_key, size: 20, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  _provider == 'zarinpal'
                                      ? adminTx(context, 'تنظیمات زرین‌پال', 'Zarinpal settings')
                                      : _provider == 'parsian'
                                          ? adminTx(context, 'تنظیمات پارسیان', 'Parsian settings')
                                          : adminTx(context, 'تنظیمات بیت‌پی', 'BitPay settings'),
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_provider == 'zarinpal')
                              TextFormField(
                                controller: _merchantIdCtrl,
                                decoration: InputDecoration(
                                  labelText: 'Merchant ID',
                                  hintText: adminTx(context, 'کد پذیرنده از پنل زرین‌پال', 'Merchant code from the Zarinpal panel'),
                                  prefixIcon: const Icon(Icons.badge),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                  helperText: _isSandbox ? adminTx(context, 'در حالت تست یک UUID معتبر بگذارید', 'Use a valid UUID in sandbox') : adminTx(context, 'کد ۳۶ نویسه‌ای پذیرنده از پنل زرین‌پال', 'The 36-character merchant code from the Zarinpal panel'),
                                  helperMaxLines: 2,
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return AppLocalizations.of(context).requiredField;
                                  }
                                  // در حالت sandbox، باید UUID باشد
                                  if (_isSandbox) {
                                    final isUuid = RegExp(r'^[0-9a-fA-F\-]{32,36}$').hasMatch(v.trim());
                                    if (!isUuid) {
                                      return adminTx(context, 'در حالت تست باید یک UUID معتبر وارد کنید', 'Sandbox mode requires a valid UUID');
                                    }
                                  }
                                  return null;
                                },
                              ),
                            if (_provider == 'parsian') ...[
                              TextFormField(
                                controller: _terminalIdCtrl,
                                decoration: InputDecoration(
                                  labelText: adminTx(context, 'شناسه پذیرنده', 'Merchant PIN'),
                                  hintText: adminTx(context, 'رمز پذیرنده از پارسیان', 'Merchant password from Parsian'),
                                  prefixIcon: const Icon(Icons.vpn_key),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                  helperText: adminTx(context, 'همان LoginAccount وب‌سرویس پارسیان است', 'This is the Parsian web service LoginAccount'),
                                  helperMaxLines: 3,
                                ),
                                validator: (v) => (v == null || v.trim().isEmpty) ? AppLocalizations.of(context).requiredField : null,
                              ),
                            ],
                            if (_provider == 'bitpay') ...[
                              TextFormField(
                                controller: _merchantIdCtrl,
                                decoration: InputDecoration(
                                  labelText: 'Merchant ID',
                                  hintText: adminTx(context, 'کد پذیرنده از پنل بیت‌پی', 'Merchant code from the BitPay panel'),
                                  prefixIcon: const Icon(Icons.badge),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                  helperText: adminTx(context, 'شناسه پذیرنده از پنل بیت‌پی', 'Merchant ID from the BitPay panel'),
                                ),
                                validator: (v) => (v == null || v.isEmpty) ? AppLocalizations.of(context).requiredField : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _apiCtrl,
                                decoration: InputDecoration(
                                  labelText: 'API Key',
                                  hintText: adminTx(context, 'کلید API از پنل بیت‌پی، ۵۲ نویسه', 'API key from the BitPay panel, 52 characters'),
                                  prefixIcon: const Icon(Icons.key),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                  helperText: adminTx(context, 'کلید ۵۲ نویسه‌ای. برای تست می‌توانید کلید نمونهٔ پنل را بگذارید.', '52-character key. For testing you can use the sample key from the panel.'),
                                  helperMaxLines: 2,
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return AppLocalizations.of(context).requiredField;
                                  }
                                  if (v.trim().length != 52) {
                                    return adminTx(context, 'کلید API باید دقیقاً ۵۲ نویسه باشد', 'The API key must be exactly 52 characters');
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // بخش Callback و Redirect
                    Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.link, size: 20, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(adminTx(context, 'آدرس‌های بازگشت', 'Return addresses'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(adminTx(context, 'آدرس بازگشت پیشنهادی', 'Suggested callback address')),
                              subtitle: Text(adminTx(context, 'از تنظیمات سیستم پر می‌شود', 'Filled from system settings')),
                              secondary: const Icon(Icons.auto_awesome),
                              value: _useSuggestedCallback,
                              onChanged: (v) {
                                setState(() {
                                  _useSuggestedCallback = v ?? true;
                                  _applySuggestedCallback();
                                });
                              },
                            ),
                            SizedBox(height: 12),
                            TextFormField(
                              controller: _callbackUrlCtrl,
                              decoration: InputDecoration(
                                labelText: 'Callback URL',
                                hintText: adminTx(context, 'آدرس بازگشت پس از پرداخت', 'Return address after payment'),
                                prefixIcon: Icon(Icons.call_received),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                              validator: (v) => (v == null || v.isEmpty) ? AppLocalizations.of(context).requiredField : null,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: SemanticColorResolver.info(context).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: SemanticColorResolver.info(context).withValues(alpha: 0.35)!),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 20, color: SemanticColorResolver.info(context)),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      adminTx(context, 'tx_id خودکار به callback اضافه می‌شود. اگر آدرس بازگشت تنظیم شده باشد، کاربر بعد از پرداخت به آنجا می‌رود.', 'tx_id is added to the callback. If a return address is set, the user is sent there after payment.'),
                                      style: TextStyle(fontSize: 12, color: SemanticColorResolver.info(context)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 12),
                            TextFormField(
                              controller: _successRedirectCtrl,
                              decoration: InputDecoration(
                                labelText: adminTx(context, 'آدرس پس از پرداخت موفق', 'Address after a successful payment'),
                                hintText: adminTx(context, 'مثال: https://app.com/success', 'Example: https://app.com/success'),
                                prefixIcon: Icon(Icons.check_circle, color: SemanticColorResolver.positive(context)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                            ),
                            SizedBox(height: 12),
                            TextFormField(
                              controller: _failureRedirectCtrl,
                              decoration: InputDecoration(
                                labelText: adminTx(context, 'آدرس پس از پرداخت ناموفق', 'Address after a failed payment'),
                                hintText: adminTx(context, 'مثال: https://app.com/failed', 'Example: https://app.com/failed'),
                                prefixIcon: Icon(Icons.error, color: SemanticColorResolver.negative(context)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            label: Text(AppLocalizations.of(context).cancel),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          FilledButton.icon(
            onPressed: () => _submitCreate(ctx),
            icon: const Icon(Icons.check),
            label: Text(AppLocalizations.of(context).save),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _applySuggestedCallback() {
    if (!_useSuggestedCallback) return;
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    String path = '/api/v1/wallet/payments/callback/zarinpal';
    if (_provider == 'parsian') {
      path = '/api/v1/wallet/payments/callback/parsian';
    } else if (_provider == 'bitpay') {
      path = '/api/v1/wallet/payments/callback/bitpay';
    }
    _callbackUrlCtrl.text = '$base$path';
  }

  Future<void> _delete(int id) async {
    if (!context.mounted) return;
    final ctx = context;
    try {
      await _service.deleteAdmin(id);
      await _load();
      if (!ctx.mounted) return;
      final t = AppLocalizations.of(ctx);
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t.deletedSuccessfully)));
    } catch (e) {
      if (!ctx.mounted) return;
      final t = AppLocalizations.of(ctx);
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('${t.error}: ${ErrorExtractor.forContext(e, ctx)}'),
        ),
      );
    }
  }

  Future<void> _openEditDialog(Map<String, dynamic> item) async {
    print('🔧 [EDIT DIALOG] Opening edit dialog for gateway: ${item['id']}');
    final id = int.tryParse('${item['id']}');
    Map<String, dynamic> detail = item;
    if (id != null && id > 0) {
      try {
        detail = await _service.getAdmin(id);
      } catch (e) {
        print('❌ [EDIT DIALOG] Failed to load gateway details: $e');
        if (!mounted) return;
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _prefillForEdit(detail);
    });
    print('🔧 [EDIT DIALOG] State after prefill - isActive: $_isActive, isSandbox: $_isSandbox');
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.edit_outlined, color: Theme.of(context).colorScheme.primary),
            ),
            SizedBox(width: 12),
            Text(adminTx(context, 'ویرایش درگاه پرداخت', 'Edit payment gateway')),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // بخش انتخاب Provider
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.apps, size: 20, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(adminTx(context, 'درگاه پرداخت', 'Payment gateway'), style: context.settingsHub.cardTitleStyle(Theme.of(context).textTheme, color: Theme.of(context).colorScheme.onSurface)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _provider,
                            decoration: InputDecoration(
                              labelText: adminTx(context, 'نوع درگاه', 'Gateway type'),
                              prefixIcon: const Icon(Icons.account_balance),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'zarinpal',
                                child: Row(
                                  children: [
                                    Icon(Icons.payment, size: 20, color: SemanticColorResolver.info(context)),
                                    SizedBox(width: 8),
                                    Text(adminTx(context, 'زرین‌پال', 'Zarinpal')),
                                  ],
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'parsian',
                                child: Row(
                                  children: [
                                    Icon(Icons.payment, size: 20, color: SemanticColorResolver.positive(context)),
                                    SizedBox(width: 8),
                                    Text(adminTx(context, 'پارسیان', 'Parsian')),
                                  ],
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'bitpay',
                                child: Row(
                                  children: [
                                    Icon(Icons.payment, size: 20, color: SemanticColorResolver.warning(context)),
                                    const SizedBox(width: 8),
                                    Text(adminTx(context, 'بیت‌پی', 'BitPay')),
                                  ],
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              print('🔄 [EDIT] Changing provider from $_provider to $v');
                              setState(() {
                                _provider = v ?? 'zarinpal';
                                // پاک کردن فیلدهای قبلی هنگام تغییر provider
                                _merchantIdCtrl.clear();
                                _terminalIdCtrl.clear();
                                _apiCtrl.clear();
                                _applySuggestedCallback();
                                _maybeGenerateSandboxMerchantId();
                              });
                              print('✅ [EDIT] Provider changed to $_provider');
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // بخش تنظیمات عمومی
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.settings, size: 20, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(adminTx(context, 'تنظیمات عمومی', 'General'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            initialValue: _displayName,
                            decoration: InputDecoration(
                              labelText: adminTx(context, 'نام نمایشی', 'Display name'),
                              hintText: adminTx(context, 'مثال: درگاه پرداخت اصلی', 'Example: main payment gateway'),
                              prefixIcon: const Icon(Icons.label),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                            ),
                            onChanged: (v) => _displayName = v.trim(),
                            validator: (v) => (v == null || v.trim().isEmpty) ? AppLocalizations.of(context).requiredField : null,
                          ),
                          const SizedBox(height: 12),
                          StatefulBuilder(
                            builder: (BuildContext context, StateSetter setDialogState) {
                              return Column(
                                children: [
                                  SwitchListTile(
                                    title: Text(AppLocalizations.of(context).active),
                                    subtitle: Text(adminTx(context, 'درگاه برای پرداخت در دسترس باشد', 'The gateway is available for payments')),
                                    secondary: const Icon(Icons.check_circle_outline),
                                    value: _isActive,
                                    onChanged: (v) {
                                      print('🔄 [EDIT] Changing isActive from $_isActive to $v');
                                      setDialogState(() {
                                        setState(() {
                                          _isActive = v;
                                        });
                                      });
                                      print('✅ [EDIT] isActive changed to $_isActive');
                                    },
                                  ),
                                  SwitchListTile(
                                    title: Text(adminTx(context, 'حالت تست', 'Sandbox')),
                                    subtitle: Text(adminTx(context, 'پرداخت واقعی انجام نمی‌شود', 'No real payment is taken')),
                                    secondary: const Icon(Icons.science_outlined),
                                    value: _isSandbox,
                                    onChanged: (v) {
                                      print('🔄 [EDIT] Changing isSandbox from $_isSandbox to $v');
                                      setDialogState(() {
                                        setState(() {
                                          _isSandbox = v;
                                        });
                                      });
                                      print('✅ [EDIT] isSandbox changed to $_isSandbox');
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // بخش تنظیمات درگاه
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.vpn_key, size: 20, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                _provider == 'zarinpal'
                                    ? adminTx(context, 'تنظیمات زرین‌پال', 'Zarinpal settings')
                                    : _provider == 'parsian'
                                        ? adminTx(context, 'تنظیمات پارسیان', 'Parsian settings')
                                        : adminTx(context, 'تنظیمات بیت‌پی', 'BitPay settings'),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_provider == 'zarinpal')
                            TextFormField(
                              controller: _merchantIdCtrl,
                              decoration: InputDecoration(
                                labelText: 'Merchant ID',
                                hintText: adminTx(context, 'کد پذیرنده از پنل زرین‌پال', 'Merchant code from the Zarinpal panel'),
                                prefixIcon: const Icon(Icons.badge),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                helperText: _isSandbox ? adminTx(context, 'در حالت تست یک UUID معتبر بگذارید', 'Use a valid UUID in sandbox') : adminTx(context, 'کد ۳۶ نویسه‌ای پذیرنده از پنل زرین‌پال', 'The 36-character merchant code from the Zarinpal panel'),
                                helperMaxLines: 2,
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return AppLocalizations.of(context).requiredField;
                                }
                                // در حالت sandbox، باید UUID باشد
                                if (_isSandbox) {
                                  final isUuid = RegExp(r'^[0-9a-fA-F\-]{32,36}$').hasMatch(v.trim());
                                  if (!isUuid) {
                                    return adminTx(context, 'در حالت تست باید یک UUID معتبر وارد کنید', 'Sandbox mode requires a valid UUID');
                                  }
                                }
                                return null;
                              },
                            ),
                          if (_provider == 'parsian') ...[
                            TextFormField(
                              controller: _terminalIdCtrl,
                              decoration: InputDecoration(
                                labelText: adminTx(context, 'شناسه پذیرنده', 'Merchant PIN'),
                                hintText: adminTx(context, 'رمز پذیرنده از پارسیان', 'Merchant password from Parsian'),
                                prefixIcon: const Icon(Icons.vpn_key),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                helperText: adminTx(context, 'همان LoginAccount وب‌سرویس پارسیان است', 'This is the Parsian web service LoginAccount'),
                                helperMaxLines: 3,
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? AppLocalizations.of(context).requiredField : null,
                            ),
                          ],
                          if (_provider == 'bitpay') ...[
                            TextFormField(
                              controller: _merchantIdCtrl,
                              decoration: InputDecoration(
                                labelText: 'Merchant ID',
                                hintText: adminTx(context, 'کد پذیرنده از پنل بیت‌پی', 'Merchant code from the BitPay panel'),
                                prefixIcon: const Icon(Icons.badge),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                helperText: adminTx(context, 'شناسه پذیرنده از پنل بیت‌پی', 'Merchant ID from the BitPay panel'),
                              ),
                              validator: (v) => (v == null || v.isEmpty) ? AppLocalizations.of(context).requiredField : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _apiCtrl,
                              decoration: InputDecoration(
                                labelText: 'API Key',
                                hintText: adminTx(context, 'کلید API از پنل بیت‌پی، ۵۲ نویسه', 'API key from the BitPay panel, 52 characters'),
                                prefixIcon: const Icon(Icons.key),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                helperText: adminTx(context, 'کلید ۵۲ نویسه‌ای از پنل بیت‌پی', '52-character key from the BitPay panel'),
                                helperMaxLines: 2,
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return AppLocalizations.of(context).requiredField;
                                }
                                if (v.trim().length != 52) {
                                  return adminTx(context, 'کلید API باید دقیقاً ۵۲ نویسه باشد', 'The API key must be exactly 52 characters');
                                }
                                return null;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // بخش Callback و Redirect
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.link, size: 20, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(adminTx(context, 'آدرس‌های بازگشت', 'Return addresses'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(adminTx(context, 'آدرس بازگشت پیشنهادی', 'Suggested callback address')),
                            subtitle: Text(adminTx(context, 'از تنظیمات سیستم پر می‌شود', 'Filled from system settings')),
                            secondary: const Icon(Icons.auto_awesome),
                            value: _useSuggestedCallback,
                            onChanged: (v) {
                              setState(() {
                                _useSuggestedCallback = v ?? true;
                                _applySuggestedCallback();
                              });
                            },
                          ),
                          SizedBox(height: 12),
                          TextFormField(
                            controller: _callbackUrlCtrl,
                            decoration: InputDecoration(
                              labelText: 'Callback URL',
                              hintText: adminTx(context, 'آدرس بازگشت پس از پرداخت', 'Return address after payment'),
                              prefixIcon: Icon(Icons.call_received),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                            ),
                            validator: (v) => (v == null || v.isEmpty) ? AppLocalizations.of(context).requiredField : null,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: SemanticColorResolver.info(context).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: SemanticColorResolver.info(context).withValues(alpha: 0.35)!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, size: 20, color: SemanticColorResolver.info(context)),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    adminTx(context, 'tx_id خودکار به callback اضافه می‌شود. اگر آدرس بازگشت تنظیم شده باشد، کاربر بعد از پرداخت به آنجا می‌رود.', 'tx_id is added to the callback. If a return address is set, the user is sent there after payment.'),
                                    style: TextStyle(fontSize: 12, color: SemanticColorResolver.info(context)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 12),
                          TextFormField(
                            controller: _successRedirectCtrl,
                            decoration: InputDecoration(
                              labelText: adminTx(context, 'آدرس پس از پرداخت موفق', 'Address after a successful payment'),
                              hintText: adminTx(context, 'مثال: https://app.com/success', 'Example: https://app.com/success'),
                              prefixIcon: Icon(Icons.check_circle, color: SemanticColorResolver.positive(context)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                            ),
                          ),
                          SizedBox(height: 12),
                          TextFormField(
                            controller: _failureRedirectCtrl,
                            decoration: InputDecoration(
                              labelText: adminTx(context, 'آدرس پس از پرداخت ناموفق', 'Address after a failed payment'),
                              hintText: adminTx(context, 'مثال: https://app.com/failed', 'Example: https://app.com/failed'),
                              prefixIcon: Icon(Icons.error, color: SemanticColorResolver.negative(context)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            label: Text(AppLocalizations.of(context).cancel),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          FilledButton.icon(
            onPressed: () => _submitUpdate(ctx),
            icon: const Icon(Icons.check),
            label: Text(AppLocalizations.of(context).update),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final hub = context.settingsHub;
    return AdminCompactScaffold(
      title: adminTx(context, 'درگاه‌های پرداخت', 'Payment gateways'),
      actions: [
        IconButton(
          onPressed: _load,
          tooltip: adminTx(context, 'بازخوانی', 'Refresh'),
          icon: const Icon(Icons.refresh, size: 20),
        ),
        IconButton(onPressed: _openCreateDialog, tooltip: t.add, icon: const Icon(Icons.add, size: 20)),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(
                          padding: hub.pagePadding,
                          children: [
                            Center(child: Text(t.noDataFound)),
                          ],
                        )
                      : ListView.separated(
                          padding: hub.pagePadding,
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final it = _items[i];
                            final provider = it['provider']?.toString() ?? '';
                            final isActive = it['is_active'] == true;
                            final isSandbox = it['is_sandbox'] == true;
                            
                            Color providerColor = SemanticColorResolver.info(context);
                            IconData providerIcon = Icons.payment;
                            String providerLabel = provider;
                            
                            if (provider == 'zarinpal') {
                              providerColor = SemanticColorResolver.info(context)!;
                              providerLabel = adminTx(context, 'زرین‌پال', 'Zarinpal');
                            } else if (provider == 'parsian') {
                              providerColor = SemanticColorResolver.positive(context)!;
                              providerLabel = adminTx(context, 'پارسیان', 'Parsian');
                            } else if (provider == 'bitpay') {
                              providerColor = SemanticColorResolver.warning(context)!;
                              providerLabel = adminTx(context, 'بیت‌پی', 'BitPay');
                            }
                            
                            return Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: providerColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(providerIcon, color: providerColor, size: 24),
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${it['display_name']}',
                                                style: hub.cardTitleStyle(
                                                  Theme.of(context).textTheme,
                                                  color: Theme.of(context).colorScheme.onSurface,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                providerLabel,
                                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: providerColor),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Wrap(
                                          spacing: 8,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: isActive ? SemanticColorResolver.positive(context).withValues(alpha: 0.12) : SemanticColorResolver.negative(context).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: isActive ? SemanticColorResolver.positive(context).withValues(alpha: 0.35)! : SemanticColorResolver.negative(context).withValues(alpha: 0.35)!,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    isActive ? Icons.check_circle : Icons.cancel,
                                                    size: 16,
                                                    color: isActive ? SemanticColorResolver.positive(context) : SemanticColorResolver.negative(context),
                                                  ),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    isActive ? t.active : adminTx(context, 'غیرفعال', 'Inactive'),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: isActive ? SemanticColorResolver.positive(context) : SemanticColorResolver.negative(context),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (isSandbox)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber[50],
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(color: Colors.amber[200]!),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.science, size: 16, color: Colors.amber[700]),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      adminTx(context, 'تست', 'Test'),
                                                      style: TextStyle(fontSize: 12, color: Colors.amber[700]),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 24),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: () => _openEditDialog(it),
                                          icon: Icon(Icons.edit_outlined, size: 18),
                                          label: Text(t.edit),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          onPressed: () => _delete(int.tryParse('${it['id']}') ?? 0),
                                          icon: const Icon(Icons.delete_outline, size: 18),
                                          label: Text(t.delete),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: SemanticColorResolver.negative(context),
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}


