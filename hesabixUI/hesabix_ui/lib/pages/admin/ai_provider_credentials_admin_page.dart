import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

class AIProviderCredentialsAdminPage extends StatefulWidget {
  final bool embedded;
  const AIProviderCredentialsAdminPage({super.key, this.embedded = false});

  @override
  State<AIProviderCredentialsAdminPage> createState() =>
      _AIProviderCredentialsAdminPageState();
}

class _AIProviderCredentialsAdminPageState
    extends State<AIProviderCredentialsAdminPage> {
  late final AIService _aiService;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _credentials = [];

  static const _providers = [
    ('openai', 'OpenAI'),
    ('anthropic', 'Anthropic'),
    ('local', 'Local / Ollama'),
    ('custom', 'Custom Gateway'),
  ];

  @override
  void initState() {
    super.initState();
    _aiService = AIService(ApiClient());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _aiService.listAIProviderCredentials();
      if (!mounted) return;
      setState(() {
        _credentials = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.userMessage(e);
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? _credFor(String provider) {
    for (final c in _credentials) {
      if (c['provider'] == provider) return c;
    }
    return null;
  }

  Future<void> _editCredential(String provider, String label) async {
    final existing = _credFor(provider);
    final apiKeyCtrl = TextEditingController();
    final baseUrlCtrl = TextEditingController(
      text: existing?['api_base_url']?.toString() ?? '',
    );
    final testModelCtrl = TextEditingController();
    bool isActive = existing?['is_active'] as bool? ?? true;
    bool fce = existing?['function_calling_enabled'] as bool? ?? true;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(adminTx(context, 'اعتبارنامه $label', '$label credential')),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: baseUrlCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: adminTx(context, 'آدرس پایه API', 'API base URL'),
                    helperText: adminTx(context, 'اختیاری؛ برای درگاه سفارشی', 'Optional, for a custom gateway'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: apiKeyCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: adminTx(context, 'کلید API', 'API key'),
                    helperText: existing?['api_key'] != null
                        ? adminTx(context, 'خالی بگذارید تا کلید فعلی بماند', 'Leave empty to keep the current key')
                        : null,
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: testModelCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: adminTx(context, 'مدل تست (اختیاری)', 'Test model (optional)'),
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(adminTx(context, 'فعال', 'Active')),
                  value: isActive,
                  onChanged: (v) => setDialogState(() => isActive = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(adminTx(context, 'پشتیبانی از ابزارها', 'Tool support')),
                  value: fce,
                  onChanged: (v) => setDialogState(() => fce = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(adminTx(context, 'لغو', 'Cancel')),
            ),
            OutlinedButton(
              onPressed: () async {
                try {
                  await _aiService.testAIProviderConnection(
                    provider,
                    model: testModelCtrl.text.trim().isEmpty ? null : testModelCtrl.text.trim(),
                  );
                  if (!context.mounted) return;
                  SnackBarHelper.show(context, message: adminTx(context, 'اتصال برقرار شد', 'Connected'));
                } catch (e) {
                  if (!context.mounted) return;
                  SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                }
              },
              child: Text(adminTx(context, 'تست اتصال', 'Test connection')),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final payload = <String, dynamic>{
                    'display_name': label,
                    'api_base_url': baseUrlCtrl.text.trim().isEmpty ? null : baseUrlCtrl.text.trim(),
                    'is_active': isActive,
                    'function_calling_enabled': fce,
                  };
                  if (apiKeyCtrl.text.trim().isNotEmpty) {
                    payload['api_key'] = apiKeyCtrl.text.trim();
                  }
                  await _aiService.upsertAIProviderCredential(provider, payload);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  _load();
                } catch (e) {
                  if (!context.mounted) return;
                  SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                }
              },
              child: Text(adminTx(context, 'ذخیره', 'Save')),
            ),
          ],
        ),
      ),
    );

    apiKeyCtrl.dispose();
    baseUrlCtrl.dispose();
    testModelCtrl.dispose();
  }

  Future<void> _syncFromConfig() async {
    try {
      await _aiService.syncAIProviderCredentialsFromConfig();
      if (!mounted) return;
      SnackBarHelper.show(context, message: adminTx(context, 'از تنظیمات AI همگام شد', 'Synced from AI settings'));
      _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: aiHubAppBar(
        embedded: widget.embedded,
        title: Text(adminTx(context, 'اعتبارنامه ارائه‌دهنده‌ها', 'Provider credentials')),
        actions: [
          IconButton(
            tooltip: adminTx(context, 'اگر اعتبارنامه کلید نداشته باشد، از تنظیمات قدیمی پر می‌شود', 'Fills a credential only when it has no key yet'),
            icon: const Icon(Icons.sync, size: 20),
            onPressed: _syncFromConfig,
          ),
          IconButton(
            tooltip: adminTx(context, 'بازخوانی', 'Refresh'),
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: context.settingsHub.pagePadding,
                  children: [
                    Text(
                      adminTx(
                        context,
                        'کلید هر ارائه‌دهنده جدا ذخیره می‌شود. هنگام انتخاب مدل، اعتبارنامهٔ همان ارائه‌دهنده استفاده می‌شود.',
                        'Each provider keeps its own key. Choosing a model uses that provider’s credential.',
                      ),
                      style: context.settingsHub.cardSubtitleStyle(
                        Theme.of(context).textTheme,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._providers.map((entry) {
                      final provider = entry.$1;
                      final label = entry.$2;
                      final cred = _credFor(provider);
                      final configured = cred != null && cred['api_key'] != null;
                      final active = cred?['is_active'] == true;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            configured ? Icons.vpn_key : Icons.vpn_key_off,
                            size: 18,
                            color: configured
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                          ),
                          title: Text(
                            label,
                            style: context.settingsHub.cardTitleStyle(
                              Theme.of(context).textTheme,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            configured
                                ? '${adminTx(context, 'پیکربندی شده', 'Configured')} · ${active ? adminTx(context, 'فعال', 'Active') : adminTx(context, 'غیرفعال', 'Inactive')}'
                                : adminTx(context, 'تنظیم نشده', 'Not configured'),
                          ),
                          trailing: Icon(
                            Directionality.of(context) == TextDirection.rtl
                                ? Icons.chevron_left
                                : Icons.chevron_right,
                            size: 18,
                          ),
                          onTap: () => _editCredential(provider, label),
                        ),
                      );
                    }),
                  ],
                ),
    );
  }
}
