import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

class AIModelsAdminPage extends StatefulWidget {
  const AIModelsAdminPage({super.key});

  @override
  State<AIModelsAdminPage> createState() => _AIModelsAdminPageState();
}

class _AIModelsAdminPageState extends State<AIModelsAdminPage> {
  late final AIService _aiService;
  bool _loading = true;
  String? _error;
  List<AIModelCatalogItem> _models = [];

  @override
  void initState() {
    super.initState();
    _aiService = AIService(ApiClient());
    _load();
  }

  Future<void> _seedFromConfig() async {
    final force = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ایجاد خودکار مدل‌ها'),
        content: const Text(
          'مدل فعال تنظیمات AI و presetهای همان provider اضافه می‌شوند.\n'
          'اگر کاتالوگ خالی نباشد، عملیات نادیده گرفته می‌شود.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اجرا')),
        ],
      ),
    );
    if (force != true) return;
    try {
      final result = await _aiService.seedAIModelsFromConfig(includePresets: true);
      if (!mounted) return;
      final created = result['created'] ?? 0;
      SnackBarHelper.show(context, message: '$created مدل ایجاد شد');
      _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final models = await _aiService.listAIModels();
      if (!mounted) return;
      setState(() {
        _models = models;
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

  Future<void> _showModelDialog({AIModelCatalogItem? model}) async {
    final isEdit = model != null;
    final formKey = GlobalKey<FormState>();
    final codeCtrl = TextEditingController(text: model?.code ?? '');
    final nameCtrl = TextEditingController(text: model?.displayName ?? '');
    final modelIdCtrl = TextEditingController(text: model?.modelId ?? '');
    final descCtrl = TextEditingController(text: model?.description ?? '');
    final tierCtrl = TextEditingController(text: model?.tier ?? '');
    final maxTokensCtrl = TextEditingController(
      text: (model?.maxTokensDefault ?? 4000).toString(),
    );
    final refInCtrl = TextEditingController(
      text: model?.pricing?['reference_input']?.toString() ?? '',
    );
    final refOutCtrl = TextEditingController(
      text: model?.pricing?['reference_output']?.toString() ?? '',
    );

    String provider = model?.provider ?? 'openai';
    bool supportsTools = model?.supportsTools ?? true;
    bool isActive = model?.isActive ?? true;
    int sortOrder = 0;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEdit ? 'ویرایش مدل' : 'مدل جدید'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: codeCtrl,
                        decoration: const InputDecoration(labelText: 'کد مدل'),
                        enabled: !isEdit,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'الزامی' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'نام نمایشی'),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'الزامی' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: provider,
                        decoration: const InputDecoration(labelText: 'Provider'),
                        items: const [
                          DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                          DropdownMenuItem(value: 'anthropic', child: Text('Anthropic')),
                          DropdownMenuItem(value: 'local', child: Text('Local')),
                          DropdownMenuItem(value: 'custom', child: Text('Custom')),
                        ],
                        onChanged: (v) => setDialogState(() => provider = v!),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: modelIdCtrl,
                        decoration: const InputDecoration(
                          labelText: 'شناسه API مدل',
                          helperText: 'نام مدل ارسالی به provider (مثلاً gpt-4o-mini)',
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'الزامی' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: maxTokensCtrl,
                        decoration: const InputDecoration(labelText: 'حداکثر توکن پیش‌فرض'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: tierCtrl,
                        decoration: const InputDecoration(
                          labelText: 'سطح (اختیاری)',
                          helperText: 'مثلاً basic, pro, enterprise',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: descCtrl,
                        decoration: const InputDecoration(labelText: 'توضیحات'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: refInCtrl,
                        decoration: const InputDecoration(
                          labelText: 'هزینه مرجع ورودی / ۱۰۰۰ توکن (اختیاری)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: refOutCtrl,
                        decoration: const InputDecoration(
                          labelText: 'هزینه مرجع خروجی / ۱۰۰۰ توکن (اختیاری)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      SwitchListTile(
                        title: const Text('پشتیبانی از ابزارها'),
                        value: supportsTools,
                        onChanged: (v) => setDialogState(() => supportsTools = v),
                      ),
                      SwitchListTile(
                        title: const Text('فعال'),
                        value: isActive,
                        onChanged: (v) => setDialogState(() => isActive = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('لغو'),
              ),
              FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final payload = <String, dynamic>{
                    'code': codeCtrl.text.trim(),
                    'display_name': nameCtrl.text.trim(),
                    'provider': provider,
                    'model_id': modelIdCtrl.text.trim(),
                    'description': descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                    'tier': tierCtrl.text.trim().isEmpty ? null : tierCtrl.text.trim(),
                    'supports_tools': supportsTools,
                    'max_tokens_default': int.tryParse(maxTokensCtrl.text) ?? 4000,
                    'is_active': isActive,
                    'sort_order': sortOrder,
                    if (refInCtrl.text.trim().isNotEmpty)
                      'reference_input_cost_per_1k':
                          double.tryParse(refInCtrl.text.replaceAll(',', '')),
                    if (refOutCtrl.text.trim().isNotEmpty)
                      'reference_output_cost_per_1k':
                          double.tryParse(refOutCtrl.text.replaceAll(',', '')),
                  };
                  try {
                    if (isEdit) {
                      await _aiService.updateAIModel(model.id!, payload);
                    } else {
                      await _aiService.createAIModel(payload);
                    }
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
                child: Text(isEdit ? 'ذخیره' : 'ایجاد'),
              ),
            ],
          );
        },
      ),
    );

    codeCtrl.dispose();
    nameCtrl.dispose();
    modelIdCtrl.dispose();
    descCtrl.dispose();
    tierCtrl.dispose();
    maxTokensCtrl.dispose();
    refInCtrl.dispose();
    refOutCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت مدل‌های هوش مصنوعی'),
        actions: [
          IconButton(
            tooltip: 'ایجاد خودکار از تنظیمات',
            icon: const Icon(Icons.auto_fix_high),
            onPressed: _seedFromConfig,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showModelDialog(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _models.isEmpty
                  ? const Center(child: Text('مدلی تعریف نشده است'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _models.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final m = _models[index];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: m.isActive
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.smart_toy_outlined,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            title: Text(m.displayName),
                            subtitle: Text(
                              '${m.code} · ${m.provider} · ${m.modelId}'
                              '${m.tier != null ? ' · ${m.tier}' : ''}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!m.isActive)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Chip(label: Text('غیرفعال')),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _showModelDialog(model: m),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('غیرفعال کردن مدل'),
                                        content: Text(
                                          'مدل «${m.displayName}» غیرفعال شود؟',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text('لغو'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('تأیید'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok != true || m.id == null) return;
                                    try {
                                      await _aiService.deleteAIModel(m.id!);
                                      _load();
                                    } catch (e) {
                                      if (!mounted) return;
                                      SnackBarHelper.showError(
                                        context,
                                        message: ErrorExtractor.forContext(e, context),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
