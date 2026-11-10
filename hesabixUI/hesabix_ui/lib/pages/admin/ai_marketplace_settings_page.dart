import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../services/system_settings_service.dart';
import '../../utils/error_extractor.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

/// تنظیمات مارکت‌پلیس مهارت‌های AI (سهم ناشر و …)
class AIMarketplaceSettingsPage extends StatefulWidget {
  final bool embedded;
  const AIMarketplaceSettingsPage({super.key, this.embedded = false});

  @override
  State<AIMarketplaceSettingsPage> createState() => _AIMarketplaceSettingsPageState();
}

class _AIMarketplaceSettingsPageState extends State<AIMarketplaceSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _sharePercentCtrl = TextEditingController();
  late final SystemSettingsService _service;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  double _defaultShare = 70;

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
      final data = await _service.getMarketplaceSettings();
      _defaultShare = (data['default_publisher_share_percent'] as num?)?.toDouble() ?? 70;
      final share = data['publisher_share_percent'];
      _sharePercentCtrl.text = share?.toString() ?? _defaultShare.toString();
    } catch (e) {
      if (mounted) {
        _error = ErrorExtractor.forContext(e, context);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final share = double.parse(_sharePercentCtrl.text.trim().replaceAll(',', '.'));
      await _service.updateMarketplaceSettings(publisherSharePercent: share);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminTx(context, 'ذخیره شد', 'Saved')), backgroundColor: SemanticColorResolver.positive(context)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorExtractor.forContext(e, context)),
            backgroundColor: SemanticColorResolver.negative(context),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _sharePercentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = double.tryParse(_sharePercentCtrl.text.replaceAll(',', '.')) ?? _defaultShare;
    final platformShare = (100 - share).clamp(0, 100);

    return Scaffold(
      appBar: aiHubAppBar(
        embedded: widget.embedded,
        title: Text(adminTx(context, 'بازارچه مهارت‌ها', 'Skills marketplace')),
        actions: [
          IconButton(
            tooltip: adminTx(context, 'ذخیره', 'Save'),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined, size: 20),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error)),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: Text(adminTx(context, 'تلاش مجدد', 'Retry')),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: context.settingsHub.pagePadding,
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      children: [
                        Text(
                          adminTx(context, 'سهم درآمد ناشر مهارت', 'Skill publisher revenue share'),
                          style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          adminTx(
                            context,
                            'هنگام خرید مهارت پولی، این درصد به کیف پول ناشر واریز می‌شود. باقی‌مانده سهم پلتفرم است. پیش‌فرض: $_defaultShare٪.',
                            'On a paid skill purchase, this percent goes to the publisher wallet. The rest is the platform share. Default: $_defaultShare%.',
                          ),
                          style: context.settingsHub.cardSubtitleStyle(theme.textTheme, color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _sharePercentCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: adminTx(context, 'درصد سهم ناشر (۰ تا ۱۰۰)', 'Publisher share percent (0 to 100)'),
                            prefixIcon: const Icon(Icons.percent),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.isEmpty) return adminTx(context, 'الزامی', 'Required');
                            final v = double.tryParse(text.replaceAll(',', '.'));
                            if (v == null) return adminTx(context, 'عدد معتبر وارد کنید', 'Enter a valid number');
                            if (v < 0 || v > 100) return adminTx(context, 'مقدار باید بین ۰ و ۱۰۰ باشد', 'Value must be between 0 and 100');
                            return null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  adminTx(context, 'پیش‌نمایش تقسیم برای فروش ۱۰۰٬۰۰۰', 'Split preview for a 100,000 sale'),
                                  style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                                ),
                                const SizedBox(height: 6),
                                Text('${adminTx(context, 'ناشر', 'Publisher')}: ${(100000 * share / 100).toStringAsFixed(0)}'),
                                Text('${adminTx(context, 'پلتفرم', 'Platform')}: ${(100000 * platformShare / 100).toStringAsFixed(0)}'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save, size: 18),
                          label: Text(_saving ? adminTx(context, 'در حال ذخیره…', 'Saving…') : adminTx(context, 'ذخیره', 'Save')),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
