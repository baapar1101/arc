import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../config/app_config.dart';
import '../../services/payment_gateway_service.dart';
import 'package:uuid/uuid.dart';

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
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _prefillForEdit(Map<String, dynamic> it) {
    _editingId = int.tryParse('${it['id']}');
    _provider = (it['provider'] ?? 'zarinpal').toString();
    _displayName = (it['display_name'] ?? '').toString();
    _isActive = it['is_active'] == true;
    _isSandbox = it['is_sandbox'] == true;
    _merchantIdCtrl.clear();
    _terminalIdCtrl.clear();
    _callbackUrlCtrl.clear();
    _successRedirectCtrl.clear();
    _failureRedirectCtrl.clear();
    final cfg = (it['config'] is Map<String, dynamic>) ? it['config'] as Map<String, dynamic> : <String, dynamic>{};
    if (_provider == 'zarinpal' && cfg['merchant_id'] != null) _merchantIdCtrl.text = '${cfg['merchant_id']}';
    if (_provider == 'parsian' && cfg['terminal_id'] != null) _terminalIdCtrl.text = '${cfg['terminal_id']}';
    if (cfg['callback_url'] != null) _callbackUrlCtrl.text = '${cfg['callback_url']}';
    if (cfg['success_redirect'] != null) _successRedirectCtrl.text = '${cfg['success_redirect']}';
    if (cfg['failure_redirect'] != null) _failureRedirectCtrl.text = '${cfg['failure_redirect']}';
  }

  Map<String, dynamic> _buildConfig() {
    final cfg = <String, dynamic>{};
    if (_provider == 'zarinpal') {
      cfg['merchant_id'] = _merchantIdCtrl.text.trim();
      cfg['callback_url'] = _callbackUrlCtrl.text.trim();
    } else if (_provider == 'parsian') {
      cfg['terminal_id'] = _terminalIdCtrl.text.trim();
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
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!context.mounted) return;
    final ctx = context;
    try {
      await _service.createAdmin(
        provider: _provider,
        displayName: _displayName,
        isActive: _isActive,
        isSandbox: _isSandbox,
        config: _buildConfig(),
      );
      if (!ctx.mounted) return;
      Navigator.of(dialogCtx).pop();
      final t = AppLocalizations.of(ctx);
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t.save)));
      await _load();
    } catch (e) {
      if (!ctx.mounted) return;
      final t = AppLocalizations.of(ctx);
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${t.error}: $e')));
    }
  }

  Future<void> _submitUpdate(BuildContext dialogCtx) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_editingId == null) return;
    if (!context.mounted) return;
    final ctx = context;
    try {
      await _service.updateAdmin(
        gatewayId: _editingId!,
        provider: _provider,
        displayName: _displayName,
        isActive: _isActive,
        isSandbox: _isSandbox,
        config: _buildConfig(),
      );
      if (!ctx.mounted) return;
      Navigator.of(dialogCtx).pop();
      final t = AppLocalizations.of(ctx);
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t.updated)));
      await _load();
    } catch (e) {
      if (!ctx.mounted) return;
      final t = AppLocalizations.of(ctx);
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${t.error}: $e')));
    }
  }

  void _openCreateDialog() {
    _provider = 'zarinpal';
    _displayName = '';
    _isActive = true;
    _isSandbox = true;
    _merchantIdCtrl.clear();
    _terminalIdCtrl.clear();
    _callbackUrlCtrl.clear();
    _successRedirectCtrl.clear();
    _failureRedirectCtrl.clear();
    _useSuggestedCallback = true;
    _applySuggestedCallback();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [const Icon(Icons.payment_outlined), const SizedBox(width: 8), const Text('ایجاد درگاه پرداخت')]),
        content: SizedBox(
          width: 500,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _provider,
                    decoration: const InputDecoration(labelText: 'Provider'),
                    items: const [
                      DropdownMenuItem(value: 'zarinpal', child: Text('Zarinpal')),
                      DropdownMenuItem(value: 'parsian', child: Text('Parsian')),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _provider = v ?? 'zarinpal';
                        _applySuggestedCallback();
                        _maybeGenerateSandboxMerchantId();
                      });
                    },
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'نام نمایشی'),
                    onChanged: (v) => _displayName = v.trim(),
                    validator: (v) => (v == null || v.trim().isEmpty) ? AppLocalizations.of(context).requiredField : null,
                  ),
                  SwitchListTile(
                    title: Text(AppLocalizations.of(context).active),
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                  SwitchListTile(
                    title: const Text('Sandbox'),
                    value: _isSandbox,
                    onChanged: (v) {
                      setState(() {
                        _isSandbox = v;
                        _applySuggestedCallback();
                        _maybeGenerateSandboxMerchantId();
                      });
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('استفاده از کال‌بک پیشنهادی'),
                          value: _useSuggestedCallback,
                          onChanged: (v) {
                            setState(() {
                              _useSuggestedCallback = v ?? true;
                              _applySuggestedCallback();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_provider == 'zarinpal' || _provider == 'parsian') ...[
                    if (_provider == 'zarinpal')
                      TextFormField(
                        controller: _merchantIdCtrl,
                        decoration: const InputDecoration(labelText: 'merchant_id'),
                        validator: (v) => (v == null || v.isEmpty) ? AppLocalizations.of(context).requiredField : null,
                      ),
                    if (_provider == 'parsian')
                      TextFormField(
                        controller: _terminalIdCtrl,
                        decoration: const InputDecoration(labelText: 'terminal_id'),
                        validator: (v) => (v == null || v.isEmpty) ? AppLocalizations.of(context).requiredField : null,
                      ),
                    TextFormField(
                      controller: _callbackUrlCtrl,
                      decoration: const InputDecoration(labelText: 'callback_url'),
                      validator: (v) => (v == null || v.isEmpty) ? AppLocalizations.of(context).requiredField : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'نکته: پارامتر tx_id به‌صورت خودکار به callback اضافه می‌شود. پس از بازگشت، در صورت تنظیم success/failure redirect، کاربر به آدرس‌های مربوطه هدایت می‌شود.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _successRedirectCtrl,
                      decoration: const InputDecoration(labelText: 'success_redirect (اختیاری)'),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _failureRedirectCtrl,
                      decoration: const InputDecoration(labelText: 'failure_redirect (اختیاری)'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(AppLocalizations.of(context).cancel)),
          FilledButton.icon(onPressed: () => _submitCreate(ctx), icon: const Icon(Icons.save), label: Text(AppLocalizations.of(context).save)),
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
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${t.error}: $e')));
    }
  }

  void _openEditDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [const Icon(Icons.edit_outlined), const SizedBox(width: 8), const Text('ویرایش درگاه پرداخت')]),
        content: SizedBox(
          width: 500,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _provider,
                    decoration: const InputDecoration(labelText: 'Provider'),
                    items: const [
                      DropdownMenuItem(value: 'zarinpal', child: Text('Zarinpal')),
                      DropdownMenuItem(value: 'parsian', child: Text('Parsian')),
                    ],
                    onChanged: (v) => setState(() => _provider = v ?? 'zarinpal'),
                  ),
                  TextFormField(
                    initialValue: _displayName,
                    decoration: const InputDecoration(labelText: 'نام نمایشی'),
                    onChanged: (v) => _displayName = v.trim(),
                    validator: (v) => (v == null || v.trim().isEmpty) ? AppLocalizations.of(context).requiredField : null,
                  ),
                  SwitchListTile(
                    title: Text(AppLocalizations.of(context).active),
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                  SwitchListTile(
                    title: const Text('Sandbox'),
                    value: _isSandbox,
                    onChanged: (v) => setState(() => _isSandbox = v),
                  ),
                  if (_provider == 'zarinpal')
                    TextFormField(
                      controller: _merchantIdCtrl,
                      decoration: const InputDecoration(labelText: 'merchant_id'),
                      validator: (v) => (v == null || v.isEmpty) ? AppLocalizations.of(context).requiredField : null,
                    ),
                  if (_provider == 'parsian')
                    TextFormField(
                      controller: _terminalIdCtrl,
                      decoration: const InputDecoration(labelText: 'terminal_id'),
                      validator: (v) => (v == null || v.isEmpty) ? AppLocalizations.of(context).requiredField : null,
                    ),
                  TextFormField(
                    controller: _callbackUrlCtrl,
                    decoration: const InputDecoration(labelText: 'callback_url'),
                    validator: (v) => (v == null || v.isEmpty) ? AppLocalizations.of(context).requiredField : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _successRedirectCtrl,
                    decoration: const InputDecoration(labelText: 'success_redirect (اختیاری)'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _failureRedirectCtrl,
                    decoration: const InputDecoration(labelText: 'failure_redirect (اختیاری)'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(AppLocalizations.of(context).cancel)),
          FilledButton.icon(onPressed: () => _submitUpdate(ctx), icon: const Icon(Icons.save), label: Text(AppLocalizations.of(context).update)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('درگاه‌های پرداخت'),
        actions: [
          IconButton(onPressed: _openCreateDialog, tooltip: t.add, icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            Center(child: Text(t.noDataFound)),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (ctx, i) {
                            final it = _items[i];
                            return Card(
                              elevation: 1,
                              child: ListTile(
                                title: Text('${it['display_name']} (${it['provider']})'),
                                subtitle: Text('sandbox: ${it['is_sandbox']} • ${t.active}: ${it['is_active']}'),
                                trailing: Wrap(
                                  spacing: 8,
                                  children: [
                                    IconButton(
                                      tooltip: t.edit,
                                      onPressed: () {
                                        _prefillForEdit(it);
                                        _openEditDialog(it);
                                      },
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: t.delete,
                                      onPressed: () => _delete(int.tryParse('${it['id']}') ?? 0),
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
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


