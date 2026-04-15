import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../services/system_settings_service.dart';
import '../../utils/snackbar_helper.dart';

class ShareLinkSettingsPage extends StatefulWidget {
  const ShareLinkSettingsPage({super.key});

  @override
  State<ShareLinkSettingsPage> createState() => _ShareLinkSettingsPageState();
}

class _ShareLinkSettingsPageState extends State<ShareLinkSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
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
    } catch (e) {
      _error = '$e';
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
      await _service.updateShareLinkSettings(_urlController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('آدرس با موفقیت ذخیره شد'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در ذخیره: $e'), backgroundColor: Colors.red),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('تنظیمات لینک‌های اشتراک'),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'آدرس پایه اپلیکیشن عمومی',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'دامنه یا آدرس اصلی را وارد کنید (مثلاً https://app.hesabix.com). بخش /public به‌صورت خودکار اضافه می‌شود. '
                          'همین مقدار برای لینک کارت حساب (شخص) و لینک اشتراک فایل از فضای ذخیره‌سازی استفاده می‌شود.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _urlController,
                          decoration: const InputDecoration(
                            labelText: 'آدرس پایه (بدون /public)',
                            prefixIcon: Icon(Icons.link),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.isEmpty) {
                              return 'آدرس الزامی است';
                            }
                            final lower = text.toLowerCase();
                            if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
                              return 'آدرس باید با http:// یا https:// شروع شود';
                            }
                            if (lower.endsWith('/public')) {
                              return 'نیازی به درج /public نیست؛ سیستم خودکار اضافه می‌کند';
                            }
                            return null;
                          },
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

