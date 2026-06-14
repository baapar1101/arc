import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../services/system_settings_service.dart';
import '../../utils/error_extractor.dart';

/// تنظیمات مارکت‌پلیس مهارت‌های AI (سهم ناشر و …)
class AIMarketplaceSettingsPage extends StatefulWidget {
  const AIMarketplaceSettingsPage({super.key});

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
          const SnackBar(content: Text('تنظیمات ذخیره شد'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا: ${ErrorExtractor.forContext(e, context)}'),
            backgroundColor: Colors.red,
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
      appBar: AppBar(
        title: const Text('تنظیمات مارکت‌پلیس AI'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('ذخیره', style: TextStyle(color: Colors.white)),
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
                      FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('تلاش مجدد')),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      children: [
                        const Text(
                          'سهم درآمد ناشر مهارت',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'هنگام خرید مهارت پولی، این درصد به کیف پول ناشر واریز می‌شود. '
                          'باقی‌مانده سهم پلتفرم است. پیش‌فرض سیستم: $_defaultShare٪.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _sharePercentCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
                          decoration: const InputDecoration(
                            labelText: 'درصد سهم ناشر (۰ تا ۱۰۰)',
                            prefixIcon: Icon(Icons.percent),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.isEmpty) return 'الزامی';
                            final v = double.tryParse(text.replaceAll(',', '.'));
                            if (v == null) return 'عدد معتبر وارد کنید';
                            if (v < 0 || v > 100) return 'مقدار باید بین ۰ و ۱۰۰ باشد';
                            return null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('پیش‌نمایش تقسیم (مثال فروش ۱۰۰٬۰۰۰)', style: theme.textTheme.titleSmall),
                                const SizedBox(height: 8),
                                Text('ناشر: ${(100000 * share / 100).toStringAsFixed(0)}'),
                                Text('پلتفرم: ${(100000 * platformShare / 100).toStringAsFixed(0)}'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save),
                          label: Text(_saving ? 'در حال ذخیره...' : 'ذخیره'),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
