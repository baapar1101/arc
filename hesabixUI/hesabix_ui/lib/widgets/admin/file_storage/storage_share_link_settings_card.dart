import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../services/system_settings_service.dart';
import '../../../utils/snackbar_helper.dart';

/// همان کلید `share_link_public_app_url` در تنظیمات سیستم؛ برای لینک اشتراک فایل و کارت حساب.
class StorageShareLinkSettingsCard extends StatefulWidget {
  const StorageShareLinkSettingsCard({super.key});

  @override
  State<StorageShareLinkSettingsCard> createState() => _StorageShareLinkSettingsCardState();
}

class _StorageShareLinkSettingsCardState extends State<StorageShareLinkSettingsCard> {
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

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
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
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await _service.updateShareLinkSettings(_urlController.text.trim());
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: 'آدرس لینک‌های عمومی ذخیره شد');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در ذخیره: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
            : _error != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
                      const SizedBox(height: 8),
                      FilledButton.tonal(onPressed: _load, child: const Text('تلاش مجدد')),
                    ],
                  )
                : Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.public, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'آدرس اپ برای لینک‌های عمومی',
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'برای اشتراک فایل از فضای ذخیره‌سازی و لینک کارت حساب (شخص) استفاده می‌شود. '
                          'مقدار در تنظیمات سیستم ذخیره می‌شود؛ نیازی به درج /public در انتهای آدرس نیست.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _urlController,
                          decoration: const InputDecoration(
                            labelText: 'آدرس پایه (مثلاً https://app.example.com)',
                            prefixIcon: Icon(Icons.link),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.isEmpty) return 'آدرس الزامی است';
                            final lower = text.toLowerCase();
                            if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
                              return 'با http:// یا https:// شروع شود';
                            }
                            if (lower.endsWith('/public')) {
                              return 'پسوند /public را ننویسید';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _saving ? null : _save,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.save, size: 18),
                              label: Text(_saving ? 'در حال ذخیره...' : 'ذخیره'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => context.go('/user/profile/system-settings/share-links'),
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: const Text('صفحهٔ کامل تنظیمات لینک'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
