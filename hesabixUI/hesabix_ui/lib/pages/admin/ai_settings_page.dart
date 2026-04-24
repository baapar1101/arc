import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import '../../utils/snackbar_helper.dart';

class AISettingsPage extends StatefulWidget {
  const AISettingsPage({super.key});

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
  final _apiKeyController = TextEditingController();
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
        _error = '$e';
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
        if (_apiKeyController.text.trim().isNotEmpty)
          'api_key': _apiKeyController.text.trim(),
        'max_tokens': int.parse(_maxTokensController.text),
        'temperature': double.parse(_temperatureController.text),
        'is_active': _isActive,
        'function_calling_enabled': _functionCallingEnabled,
      };

      await _aiService.updateAIConfig(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تنظیمات با موفقیت ذخیره شد')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا: $e')),
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
          builder: (context) => AlertDialog(
            title: const Text('تست اتصال'),
            content: Text(result['message'] ?? 'اتصال با موفقیت برقرار شد'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('بستن'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در تست اتصال: $e')),
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

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _config == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تنظیمات AI')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('خطا: $_error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                child: const Text('تلاش مجدد'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('تنظیمات AI'),
        actions: [
          if (_testing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _testConnection,
              tooltip: 'تست اتصال',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'تنظیمات Provider',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 24),
                      DropdownButtonFormField<String>(
                        value: _providerController.text.isEmpty
                            ? null
                            : _providerController.text,
                        decoration: const InputDecoration(
                          labelText: 'Provider',
                          prefixIcon: Icon(Icons.cloud_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                          DropdownMenuItem(value: 'anthropic', child: Text('Anthropic')),
                          DropdownMenuItem(value: 'local', child: Text('Local (Ollama)')),
                        ],
                        onChanged: (v) {
                          setState(() => _providerController.text = v ?? '');
                        },
                        validator: (v) => v == null ? 'Provider الزامی است' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _modelController,
                        decoration: const InputDecoration(
                          labelText: 'نام مدل',
                          prefixIcon: Icon(Icons.smart_toy_outlined),
                        ),
                        validator: (v) => v?.isEmpty ?? true ? 'نام مدل الزامی است' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _apiBaseUrlController,
                        decoration: const InputDecoration(
                          labelText: 'آدرس API (اختیاری)',
                          prefixIcon: Icon(Icons.link_outlined),
                          helperText: 'برای Local Provider الزامی است',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _apiKeyController,
                        decoration: const InputDecoration(
                          labelText: 'API Key',
                          prefixIcon: Icon(Icons.key_outlined),
                          helperText: 'برای تغییر API Key، مقدار جدید را وارد کنید',
                        ),
                        obscureText: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'تنظیمات پیش‌فرض',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _maxTokensController,
                        decoration: const InputDecoration(
                          labelText: 'حداکثر توکن',
                          prefixIcon: Icon(Icons.numbers_outlined),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v?.isEmpty ?? true) return 'الزامی است';
                          final val = int.tryParse(v!);
                          if (val == null || val <= 0) return 'باید عدد مثبت باشد';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _temperatureController,
                        decoration: const InputDecoration(
                          labelText: 'Temperature',
                          prefixIcon: Icon(Icons.thermostat_outlined),
                          helperText: 'مقدار بین 0 تا 2',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v?.isEmpty ?? true) return 'الزامی است';
                          final val = double.tryParse(v!);
                          if (val == null || val < 0 || val > 2) {
                            return 'باید بین 0 تا 2 باشد';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('فعال'),
                        subtitle: const Text('AI در دسترس کاربران باشد'),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      SwitchListTile(
                        title: const Text('فراخوانی توابع (ابزارها)'),
                        subtitle: const Text(
                          'برای OpenAI رسمی یا vLLM با tool parser بگذارید روشن. '
                          'برای gatewayهایی مثل برخی deploymentهای Arvan که خطای tool choice می‌دهند، خاموش کنید.',
                        ),
                        value: _functionCallingEnabled,
                        onChanged: (v) =>
                            setState(() => _functionCallingEnabled = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('ذخیره تنظیمات'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
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
    _apiKeyController.dispose();
    _maxTokensController.dispose();
    _temperatureController.dispose();
    super.dispose();
  }
}

