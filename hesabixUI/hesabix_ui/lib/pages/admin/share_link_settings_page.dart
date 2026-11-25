import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../services/system_settings_service.dart';
import '../../utils/error_extractor.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

class ShareLinkSettingsPage extends StatefulWidget {
  const ShareLinkSettingsPage({super.key});

  @override
  State<ShareLinkSettingsPage> createState() => _ShareLinkSettingsPageState();
}

class _ShareLinkSettingsPageState extends State<ShareLinkSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _feePercentController = TextEditingController();
  late final SystemSettingsService _service;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = SystemSettingsService(ApiClient());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getShareLinkSettings();
      _urlController.text = (data['public_app_url'] ?? '').toString();
      final fee = data['invoice_gateway_fee_percent'];
      if (fee != null) {
        _feePercentController.text = fee.toString();
      } else {
        _feePercentController.text = '0';
      }
    } catch (e) {
      if (mounted) {
        _error = ErrorExtractor.forContext(e, context);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final feeText = _feePercentController.text.trim();
      double? feeVal;
      if (feeText.isEmpty) {
        feeVal = 0;
      } else {
        feeVal = double.tryParse(feeText.replaceAll(',', '.'));
        if (feeVal == null) {
          throw Exception(adminTx(context, 'درصد کارمزد نامعتبر است', 'Invalid fee percent'));
        }
      }
      await _service.updateShareLinkSettings(
        _urlController.text.trim(),
        invoiceGatewayFeePercent: feeVal,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminTx(context, 'ذخیره شد', 'Saved')), backgroundColor: SemanticColorResolver.positive(context)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${adminTx(context, 'ذخیره نشد', 'Could not save')}: ${ErrorExtractor.forContext(e, context)}',
            ),
            backgroundColor: SemanticColorResolver.negative(context),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _feePercentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AdminCompactScaffold(
      title: adminTx(context, 'پیوندهای اشتراک', 'Share links'),
      subtitle: adminTx(context, 'محدودیت و عمر لینک‌های اشتراک فایل', 'Limits and lifetime of file share links'),
      actions: [
        IconButton(
          tooltip: adminTx(context, 'ذخیره', 'Save'),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined, size: 20),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error)),
                      const SizedBox(height: 12),
                      FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(adminTx(context, 'تلاش مجدد', 'Retry'))),
                    ],
                  ),
                )
              : Padding(
                  padding: context.settingsHub.pagePadding,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          adminTx(context, 'آدرس پایه اپ عمومی', 'Public app base URL'),
                          style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          adminTx(
                            context,
                            'دامنه را وارد کنید. /public خودکار اضافه می‌شود و برای کارت حساب، اشتراک فایل و بازگشت از درگاه استفاده می‌شود.',
                            'Enter the domain. /public is added automatically and used for account cards, file shares, and gateway returns.',
                          ),
                          style: context.settingsHub.cardSubtitleStyle(theme.textTheme, color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            labelText: adminTx(context, 'آدرس پایه', 'Base URL'),
                            prefixIcon: const Icon(Icons.link),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.isEmpty) {
                              return adminTx(context, 'آدرس الزامی است', 'URL is required');
                            }
                            final lower = text.toLowerCase();
                            if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
                              return adminTx(context, 'آدرس باید با http:// یا https:// شروع شود', 'The URL must start with http:// or https://');
                            }
                            if (lower.endsWith('/public')) {
                              return adminTx(context, '/public لازم نیست', '/public is added automatically');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        Text(
                          adminTx(context, 'پرداخت از لینک فاکتور', 'Invoice-link payment'),
                          style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          adminTx(context, 'درصد کارمزد درگاه هنگام پرداخت از لینک عمومی. صفر یعنی بدون خط کارمزد جدا.', 'Gateway fee percent when a customer pays from the public invoice link. Zero means no separate fee line.'),
                          style: context.settingsHub.cardSubtitleStyle(theme.textTheme, color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _feePercentController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: adminTx(context, 'درصد کارمزد (۰ تا ۱۰۰)', 'Fee percent (0–100)'),
                            prefixIcon: const Icon(Icons.percent),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.isEmpty) return null;
                            final v = double.tryParse(text.replaceAll(',', '.'));
                            if (v == null) return adminTx(context, 'عدد معتبر وارد کنید', 'Enter a valid number');
                            if (v < 0 || v > 100) return adminTx(context, 'مقدار باید بین ۰ و ۱۰۰ باشد', 'Value must be between 0 and 100');
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save, size: 18),
                          label: Text(_saving ? adminTx(context, 'در حال ذخیره', 'Saving') : adminTx(context, 'ذخیره', 'Save')),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

