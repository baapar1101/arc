import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../theme/tokens/extensions.dart';
import 'admin_compact_scaffold.dart';

class AISettingsPage extends StatefulWidget {
  final bool embedded;
  const AISettingsPage({super.key, this.embedded = false});

  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage> {
  late final AIService _aiService;
  bool _loading = true;
  String? _error;
  AIConfig? _config;
  bool _testing = false;

  final _formKey = GlobalKey<FormState>();
  final _providerController = TextEditingController();
  final _modelController = TextEditingController();
  final _apiBaseUrlController = TextEditingController();
  final _maxTokensController = TextEditingController(text: '2000');
  final _temperatureController = TextEditingController(text: '0.7');
  bool _isActive = false;
  bool _functionCallingEnabled = true;

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _aiService = AIService(api);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _aiService.getAIConfig();
      setState(() {
        _config = config;
        _providerController.text = config.provider;
        _modelController.text = config.modelName;
        _apiBaseUrlController.text = config.apiBaseUrl ?? '';
        _maxTokensController.text = config.maxTokens.toString();
        _temperatureController.text = config.temperature.toString();
        _isActive = config.isActive;
        _functionCallingEnabled = config.functionCallingEnabled;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = ErrorExtractor.userMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final data = {
        'provider': _providerController.text.trim(),
        'model_name': _modelController.text.trim(),
        'api_base_url': _apiBaseUrlController.text.trim().isEmpty
            ? null
            : _apiBaseUrlController.text.trim(),
        'max_tokens': int.parse(_maxTokensController.text),
        'temperature': double.parse(_temperatureController.text),
        'is_active': _isActive,
        'function_calling_enabled': _functionCallingEnabled,
      };

      await _aiService.updateAIConfig(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminTx(context, 'تنظیمات ذخیره شد', 'Settings saved'))),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorExtractor.forContext(e, context))),
        );
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() => _testing = true);
    try {
      final result = await _aiService.testAIConnection();
      if (mounted) {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(adminTx(context, 'تست اتصال', 'Connection test')),
            content: Text(
              '${result['message'] ?? adminTx(context, 'اتصال برقرار شد', 'Connected')}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(adminTx(context, 'بستن', 'Close')),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${adminTx(context, 'خطا در تست اتصال', 'Connection test failed')}: ${ErrorExtractor.forContext(e, context)}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hub = context.settingsHub;
    final scheme = theme.colorScheme;
    final appBar = aiHubAppBar(
      embedded: widget.embedded,
      title: Text(adminTx(context, 'تنظیمات AI', 'AI settings')),
      actions: [
        if (_testing)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          IconButton(
            icon: const Icon(Icons.wifi_tethering_outlined, size: 20),
            onPressed: _testConnection,
            tooltip: adminTx(context, 'تست اتصال با اعتبارنامه', 'Test connection with credentials'),
          ),
      ],
    );

    if (_loading) {
      return Scaffold(appBar: appBar, body: const Center(child: CircularProgressIndicator()));
    }

    if (_error != null && _config == null) {
      return Scaffold(
        appBar: appBar,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${adminTx(context, 'خطا', 'Error')}: $_error',
                style: hub.cardSubtitleStyle(theme.textTheme, color: scheme.error),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                child: Text(adminTx(context, 'تلاش مجدد', 'Retry')),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: SingleChildScrollView(
        padding: hub.pagePadding,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        adminTx(context, 'ارائه‌دهنده', 'Provider'),
                        style: hub.cardTitleStyle(theme.textTheme, color: scheme.onSurface),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _providerController.text.isEmpty ? null : _providerController.text,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: adminTx(context, 'ارائه‌دهنده', 'Provider'),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                          DropdownMenuItem(value: 'anthropic', child: Text('Anthropic')),
                          DropdownMenuItem(value: 'local', child: Text('Local (Ollama)')),
                        ],
                        onChanged: (v) => setState(() => _providerController.text = v ?? ''),
                        validator: (v) => v == null ? adminTx(context, 'ارائه‌دهنده الزامی است', 'Provider is required') : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _modelController,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: adminTx(context, 'نام مدل', 'Model name'),
                        ),
                        validator: (v) => (v?.isEmpty ?? true) ? adminTx(context, 'نام مدل الزامی است', 'Model name is required') : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _apiBaseUrlController,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: adminTx(context, 'آدرس API (اختیاری)', 'API address (optional)'),
                          helperText: adminTx(context, 'برای ارائه‌دهندهٔ محلی الزامی است', 'Required for a local provider'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        adminTx(
                          context,
                          'کلید API فقط در زبانهٔ اعتبارنامه‌ها ذخیره می‌شود.',
                          'API keys are stored only on the credentials tab.',
                        ),
                        style: hub.cardSubtitleStyle(theme.textTheme, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        adminTx(context, 'پیش‌فرض‌ها', 'Defaults'),
                        style: hub.cardTitleStyle(theme.textTheme, color: scheme.onSurface),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _maxTokensController,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: adminTx(context, 'حداکثر توکن', 'Max tokens'),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v?.isEmpty ?? true) return adminTx(context, 'الزامی است', 'Required');
                          final val = int.tryParse(v!);
                          if (val == null || val <= 0) return adminTx(context, 'باید عدد مثبت باشد', 'Must be a positive number');
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _temperatureController,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: 'Temperature',
                          helperText: adminTx(context, 'بین ۰ و ۲', 'Between 0 and 2'),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v?.isEmpty ?? true) return adminTx(context, 'الزامی است', 'Required');
                          final val = double.tryParse(v!);
                          if (val == null || val < 0 || val > 2) {
                            return adminTx(context, 'باید بین ۰ و ۲ باشد', 'Must be between 0 and 2');
                          }
                          return null;
                        },
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(adminTx(context, 'فعال', 'Active')),
                        subtitle: Text(adminTx(context, 'هوش مصنوعی برای کاربران در دسترس باشد', 'Make AI available to users')),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(adminTx(context, 'فراخوانی ابزارها', 'Tool calling')),
                        subtitle: Text(
                          adminTx(
                            context,
                            'برای OpenAI یا vLLM با tool parser روشن بماند. اگر درگاه خطای tool choice می‌دهد، خاموش کنید.',
                            'Leave on for OpenAI or vLLM with a tool parser. Turn off if the gateway rejects tool choice.',
                          ),
                        ),
                        value: _functionCallingEnabled,
                        onChanged: (v) => setState(() => _functionCallingEnabled = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(adminTx(context, 'ذخیره تنظیمات', 'Save settings')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _providerController.dispose();
    _modelController.dispose();
    _apiBaseUrlController.dispose();
    _maxTokensController.dispose();
    _temperatureController.dispose();
    super.dispose();
  }
}

