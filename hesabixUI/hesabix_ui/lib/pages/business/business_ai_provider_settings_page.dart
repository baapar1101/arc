import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/business_route_paths.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import '../../widgets/business_subpage_back_leading.dart';

/// تنظیمات ارائه‌دهنده AI اختصاصی (پلن BYOK) برای کسب‌وکار.
class BusinessAIProviderSettingsPage extends StatefulWidget {
  final int businessId;

  const BusinessAIProviderSettingsPage({super.key, required this.businessId});

  @override
  State<BusinessAIProviderSettingsPage> createState() =>
      _BusinessAIProviderSettingsPageState();
}

class _BusinessAIProviderSettingsPageState
    extends State<BusinessAIProviderSettingsPage> {
  late final AIService _aiService;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _error;

  bool _hasByok = false;
  String? _planName;
  List<String> _allowedProviders = const ['openai', 'anthropic'];
  bool _requireTest = true;

  String _provider = 'openai';
  final _displayNameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _hasApiKey = false;
  bool _functionCalling = true;
  bool _isActive = true;
  bool? _lastTestOk;
  String? _lastTestError;
  String? _lastTestedAt;

  final List<_ModelRow> _models = [];
  String? _defaultModel;

  @override
  void initState() {
    super.initState();
    _aiService = AIService(ApiClient());
    _load();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    for (final m in _models) {
      m.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _aiService.getBusinessAIProvider(widget.businessId);
      _hasByok = data['has_byok_subscription'] == true;
      _planName = data['plan_name'] as String?;
      _allowedProviders = (data['allowed_providers'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['openai', 'anthropic'];
      _requireTest = data['require_connection_test'] != false;
      _provider = (data['provider'] as String?) ??
          (_allowedProviders.isNotEmpty ? _allowedProviders.first : 'openai');
      _displayNameController.text = (data['display_name'] as String?) ?? '';
      _baseUrlController.text = (data['api_base_url'] as String?) ?? '';
      _apiKeyController.clear();
      _hasApiKey = data['has_api_key'] == true || data['api_key'] == '***';
      _functionCalling = data['function_calling_enabled'] != false;
      _isActive = data['is_active'] != false;
      _lastTestOk = data['last_test_ok'] as bool?;
      _lastTestError = data['last_test_error'] as String?;
      _lastTestedAt = data['last_tested_at'] as String?;
      _defaultModel = data['default_model'] as String?;

      for (final m in _models) {
        m.dispose();
      }
      _models.clear();
      final models = data['models'] as List? ?? [];
      for (final raw in models) {
        if (raw is! Map) continue;
        _models.add(
          _ModelRow(
            code: (raw['code'] ?? '').toString(),
            displayName: (raw['display_name'] ?? raw['code'] ?? '').toString(),
            modelId: (raw['model_id'] ?? raw['code'] ?? '').toString(),
            supportsTools: raw['supports_tools'] != false,
          ),
        );
      }
      if (_models.isEmpty) {
        _models.add(_ModelRow(code: 'gpt-4o-mini', displayName: 'GPT-4o Mini', modelId: 'gpt-4o-mini'));
        _defaultModel = 'gpt-4o-mini';
      }
      _defaultModel ??= _models.first.codeController.text.trim();
    } catch (e) {
      _error = ErrorExtractor.forContext(e, context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_hasByok) return;
    final models = <Map<String, dynamic>>[];
    for (final m in _models) {
      final code = m.codeController.text.trim();
      if (code.isEmpty) continue;
      models.add({
        'code': code,
        'display_name': m.displayNameController.text.trim().isEmpty
            ? code
            : m.displayNameController.text.trim(),
        'model_id': m.modelIdController.text.trim().isEmpty
            ? code
            : m.modelIdController.text.trim(),
        'supports_tools': m.supportsTools,
      });
    }
    if (models.isEmpty) {
      SnackBarHelper.showError(context, message: 'حداقل یک مدل لازم است');
      return;
    }
    final defaultCode = _defaultModel ?? models.first['code'] as String;
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'provider': _provider,
        'display_name': _displayNameController.text.trim(),
        'api_base_url': _baseUrlController.text.trim(),
        'models': models,
        'default_model': defaultCode,
        'function_calling_enabled': _functionCalling,
        'is_active': _isActive,
      };
      final key = _apiKeyController.text.trim();
      if (key.isNotEmpty) {
        payload['api_key'] = key;
      }
      await _aiService.saveBusinessAIProvider(widget.businessId, payload);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'تنظیمات ذخیره شد');
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      await _aiService.testBusinessAIProvider(
        widget.businessId,
        model: _defaultModel,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'اتصال برقرار شد');
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
        await _load();
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ارائه‌دهنده هوش مصنوعی'),
        leading: businessSubpageBackLeading(context, widget.businessId),
        actions: [
          if (_hasByok)
            IconButton(
              tooltip: 'بروزرسانی',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('تلاش مجدد')),
                      ],
                    ),
                  ),
                )
              : !_hasByok
                  ? _buildNoByok(theme)
                  : _buildForm(theme),
    );
  }

  Widget _buildNoByok(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.key_off_outlined, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'برای تنظیم ارائه‌دهنده اختصاصی، ابتدا پلن «ارائه‌دهنده اختصاصی» را از بخش اشتراک AI فعال کنید.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                context.go(
                  BusinessRoutePaths.uri(widget.businessId, 0, 'ai/subscription'),
                );
              },
              icon: const Icon(Icons.workspace_premium_outlined),
              label: const Text('رفتن به اشتراک AI'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_planName != null)
          Text('پلن فعال: $_planName', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _statusBanner(theme),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _allowedProviders.contains(_provider) ? _provider : _allowedProviders.first,
          decoration: const InputDecoration(labelText: 'نوع ارائه‌دهنده'),
          items: _allowedProviders
              .map((p) => DropdownMenuItem(value: p, child: Text(_providerLabel(p))))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _provider = v);
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _displayNameController,
          decoration: const InputDecoration(
            labelText: 'نام نمایشی (اختیاری)',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _baseUrlController,
          decoration: InputDecoration(
            labelText: _provider == 'local'
                ? 'آدرس پایه (مثلاً http://localhost:11434)'
                : 'آدرس پایه (اختیاری — برای gateway سازگار با OpenAI)',
            hintText: _provider == 'openai'
                ? 'خالی = api.openai.com'
                : null,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _apiKeyController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: _hasApiKey ? 'API Key (خالی = حفظ کلید قبلی)' : 'API Key',
            helperText: _hasApiKey ? 'کلید قبلاً ذخیره شده است' : null,
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Function Calling / Tools'),
          value: _functionCalling,
          onChanged: (v) => setState(() => _functionCalling = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('فعال'),
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text('مدل‌ها', style: theme.textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _models.add(_ModelRow());
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('افزودن مدل'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._models.asMap().entries.map((entry) {
          final idx = entry.key;
          final m = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: m.codeController,
                          decoration: const InputDecoration(labelText: 'کد مدل'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        onPressed: _models.length <= 1
                            ? null
                            : () {
                                setState(() {
                                  final removed = _models.removeAt(idx);
                                  if (_defaultModel == removed.codeController.text.trim()) {
                                    _defaultModel = _models.isEmpty
                                        ? null
                                        : _models.first.codeController.text.trim();
                                  }
                                  removed.dispose();
                                });
                              },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: m.displayNameController,
                    decoration: const InputDecoration(labelText: 'نام نمایشی'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: m.modelIdController,
                    decoration: const InputDecoration(
                      labelText: 'شناسه مدل در API',
                      helperText: 'معمولاً همان کد مدل است',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('پشتیبانی از Tools'),
                    value: m.supportsTools,
                    onChanged: (v) => setState(() => m.supportsTools = v),
                  ),
                ],
              ),
            ),
          );
        }),
        DropdownButtonFormField<String>(
          value: () {
            final codes = _models
                .map((m) => m.codeController.text.trim())
                .where((c) => c.isNotEmpty)
                .toList();
            if (codes.isEmpty) return null;
            if (_defaultModel != null && codes.contains(_defaultModel)) {
              return _defaultModel;
            }
            return codes.first;
          }(),
          decoration: const InputDecoration(labelText: 'مدل پیش‌فرض'),
          items: _models
              .map((m) => m.codeController.text.trim())
              .where((c) => c.isNotEmpty)
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) => setState(() => _defaultModel = v),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_saving || _testing) ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: const Text('تست اتصال'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: (_saving || _testing) ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('ذخیره'),
              ),
            ),
          ],
        ),
        if (_requireTest) ...[
          const SizedBox(height: 12),
          Text(
            'برای استفاده از چت، پس از ذخیره باید تست اتصال موفق باشد.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _statusBanner(ThemeData theme) {
    Color bg;
    String text;
    if (_lastTestOk == true) {
      bg = Colors.green.withValues(alpha: 0.12);
      text = 'آماده استفاده — آخرین تست موفق${_lastTestedAt != null ? ' ($_lastTestedAt)' : ''}';
    } else if (_lastTestOk == false) {
      bg = theme.colorScheme.errorContainer;
      text = 'آخرین تست ناموفق${_lastTestError != null ? ': $_lastTestError' : ''}';
    } else if (_hasApiKey) {
      bg = Colors.orange.withValues(alpha: 0.15);
      text = 'ذخیره شده — هنوز تست اتصال انجام نشده';
    } else {
      bg = theme.colorScheme.surfaceContainerHighest;
      text = 'هنوز پیکربندی نشده است';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text),
    );
  }

  String _providerLabel(String p) {
    switch (p) {
      case 'openai':
        return 'OpenAI / سازگار با OpenAI';
      case 'anthropic':
        return 'Anthropic';
      case 'local':
        return 'Local / Ollama';
      default:
        return p;
    }
  }
}

class _ModelRow {
  final TextEditingController codeController;
  final TextEditingController displayNameController;
  final TextEditingController modelIdController;
  bool supportsTools;

  _ModelRow({
    String code = '',
    String displayName = '',
    String modelId = '',
    this.supportsTools = true,
  })  : codeController = TextEditingController(text: code),
        displayNameController = TextEditingController(text: displayName),
        modelIdController = TextEditingController(text: modelId);

  void dispose() {
    codeController.dispose();
    displayNameController.dispose();
    modelIdController.dispose();
  }
}
