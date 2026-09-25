import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

class AIProviderCredentialsAdminPage extends StatefulWidget {
  const AIProviderCredentialsAdminPage({super.key});

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
          title: Text('اعتبارنامه $label'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: baseUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'API Base URL',
                    helperText: 'اختیاری — برای gateway سفارشی',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKeyCtrl,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    helperText: existing?['api_key'] != null
                        ? 'خالی بگذارید تا کلید فعلی حفظ شود'
                        : null,
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: testModelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'مدل تست (اختیاری)',
                  ),
                ),
                SwitchListTile(
                  title: const Text('فعال'),
                  value: isActive,
                  onChanged: (v) => setDialogState(() => isActive = v),
                ),
                SwitchListTile(
                  title: const Text('پشتیبانی از ابزارها'),
                  value: fce,
                  onChanged: (v) => setDialogState(() => fce = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('لغو'),
            ),
            OutlinedButton(
              onPressed: () async {
                try {
                  await _aiService.testAIProviderConnection(
                    provider,
                    model: testModelCtrl.text.trim().isEmpty
                        ? null
                        : testModelCtrl.text.trim(),
                  );
                  if (!context.mounted) return;
                  SnackBarHelper.show(context, message: 'اتصال موفق بود');
                } catch (e) {
                  if (!context.mounted) return;
                  SnackBarHelper.showError(
                    context,
                    message: ErrorExtractor.forContext(e, context),
                  );
                }
              },
              child: const Text('تست اتصال'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final payload = <String, dynamic>{
                    'display_name': label,
                    'api_base_url': baseUrlCtrl.text.trim().isEmpty
                        ? null
                        : baseUrlCtrl.text.trim(),
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
                  SnackBarHelper.showError(
                    context,
                    message: ErrorExtractor.forContext(e, context),
                  );
                }
              },
              child: const Text('ذخیره'),
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
      SnackBarHelper.show(context, message: 'همگام‌سازی از تنظیمات AI انجام شد');
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
      appBar: AppBar(
        title: const Text('اعتبارنامه Providerها'),
        actions: [
          IconButton(
            tooltip: 'همگام‌سازی از تنظیمات AI',
            icon: const Icon(Icons.sync),
            onPressed: _syncFromConfig,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'برای هر provider می‌توانید API Key جداگانه تنظیم کنید. '
                          'هنگام انتخاب مدل توسط کاربر، سیستم credential همان provider را استفاده می‌کند.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._providers.map((entry) {
                      final provider = entry.$1;
                      final label = entry.$2;
                      final cred = _credFor(provider);
                      final configured = cred != null && cred['api_key'] != null;
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            configured ? Icons.vpn_key : Icons.vpn_key_off,
                            color: configured
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                          ),
                          title: Text(label),
                          subtitle: Text(
                            configured
                                ? 'پیکربندی شده · ${cred['is_active'] == true ? 'فعال' : 'غیرفعال'}'
                                : 'تنظیم نشده',
                          ),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () => _editCredential(provider, label),
                        ),
                      );
                    }),
                  ],
                ),
    );
  }
}
