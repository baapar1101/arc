import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

class AIModelsAdminPage extends StatefulWidget {
  final bool embedded;
  const AIModelsAdminPage({super.key, this.embedded = false});

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
        title: Text(adminTx(context, 'ایجاد خودکار مدل‌ها', 'Create models automatically')),
        content: Text(
          adminTx(
            context,
            'مدل فعال تنظیمات و پیش‌تنظیم‌های همان ارائه‌دهنده اضافه می‌شوند. اگر فهرست خالی نباشد، کاری انجام نمی‌شود.',
            'The active settings model and that provider’s presets are added. Nothing happens if the catalog is not empty.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(adminTx(context, 'لغو', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(adminTx(context, 'اجرا', 'Run'))),
        ],
      ),
    );
    if (force != true) return;
    try {
      final result = await _aiService.seedAIModelsFromConfig(includePresets: true);
      if (!mounted) return;
      final created = result['created'] ?? 0;
      SnackBarHelper.show(context, message: adminTx(context, '$created مدل ایجاد شد', '$created models created'));
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
    bool supportsReasoning = model?.supportsReasoning ?? false;
    String? reasoningEffort = model?.reasoningEffort;
    bool isActive = model?.isActive ?? true;
    int sortOrder = 0;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEdit ? adminTx(context, 'ویرایش مدل', 'Edit model') : adminTx(context, 'مدل جدید', 'New model')),
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
                        decoration: InputDecoration(isDense: true, labelText: adminTx(context, 'کد مدل', 'Model code')),
                        enabled: !isEdit,
                        validator: (v) => v == null || v.trim().isEmpty ? adminTx(context, 'الزامی', 'Required') : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: InputDecoration(isDense: true, labelText: adminTx(context, 'نام نمایشی', 'Display name')),
                        validator: (v) => v == null || v.trim().isEmpty ? adminTx(context, 'الزامی', 'Required') : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: provider,
                        decoration: InputDecoration(isDense: true, labelText: adminTx(context, 'ارائه‌دهنده', 'Provider')),
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
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: adminTx(context, 'شناسه API مدل', 'Model API id'),
                          helperText: adminTx(context, 'نامی که به ارائه‌دهنده فرستاده می‌شود، مثل gpt-4o-mini', 'Name sent to the provider, for example gpt-4o-mini'),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? adminTx(context, 'الزامی', 'Required') : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: maxTokensCtrl,
                        decoration: InputDecoration(isDense: true, labelText: adminTx(context, 'حداکثر توکن پیش‌فرض', 'Default max tokens')),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: tierCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: adminTx(context, 'سطح (اختیاری)', 'Tier (optional)'),
                          helperText: 'basic, pro, enterprise',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: descCtrl,
                        decoration: InputDecoration(isDense: true, labelText: adminTx(context, 'توضیحات', 'Description')),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: refInCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: adminTx(context, 'هزینه مرجع ورودی / ۱۰۰۰ توکن', 'Reference input cost / 1k tokens'),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: refOutCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: adminTx(context, 'هزینه مرجع خروجی / ۱۰۰۰ توکن', 'Reference output cost / 1k tokens'),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      SwitchListTile(
                        title: Text(adminTx(context, 'پشتیبانی از ابزارها', 'Tool support')),
                        value: supportsTools,
                        onChanged: (v) => setDialogState(() => supportsTools = v),
                      ),
                      SwitchListTile(
                        title: Text(adminTx(context, 'مدل استدلالی', 'Reasoning model')),
                        subtitle: Text(adminTx(context, 'برای سری o، gpt-5 و تفکر گستردهٔ Claude', 'For o-series, gpt-5, and Claude extended thinking')),
                        value: supportsReasoning,
                        onChanged: (v) => setDialogState(() {
                          supportsReasoning = v;
                          if (!v) reasoningEffort = null;
                        }),
                      ),
                      if (supportsReasoning)
                        DropdownButtonFormField<String?>(
                          value: reasoningEffort,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: adminTx(context, 'سطح تلاش استدلال', 'Reasoning effort'),
                            helperText: adminTx(context, 'خالی یعنی خودکار', 'Empty means automatic'),
                          ),
                          items: [
                            DropdownMenuItem<String?>(value: null, child: Text(adminTx(context, 'خودکار', 'Automatic'))),
                            DropdownMenuItem(value: 'minimal', child: Text('minimal')),
                            DropdownMenuItem(value: 'low', child: Text('low')),
                            DropdownMenuItem(value: 'medium', child: Text('medium')),
                            DropdownMenuItem(value: 'high', child: Text('high')),
                          ],
                          onChanged: (v) =>
                              setDialogState(() => reasoningEffort = v),
                        ),
                      SwitchListTile(
                        title: Text(adminTx(context, 'فعال', 'Active')),
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
                child: Text(adminTx(context, 'لغو', 'Cancel')),
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
                    'supports_reasoning': supportsReasoning,
                    'reasoning_effort': supportsReasoning ? reasoningEffort : null,
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
                child: Text(isEdit ? adminTx(context, 'ذخیره', 'Save') : adminTx(context, 'ایجاد', 'Create')),
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
      appBar: aiHubAppBar(
        embedded: widget.embedded,
        title: Text(adminTx(context, 'مدل‌های هوش مصنوعی', 'AI models')),
        actions: [
          IconButton(
            tooltip: adminTx(context, 'ایجاد خودکار از تنظیمات', 'Create from settings'),
            icon: const Icon(Icons.auto_fix_high, size: 20),
            onPressed: _seedFromConfig,
          ),
          IconButton(
            tooltip: adminTx(context, 'بازخوانی', 'Refresh'),
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _load,
          ),
          IconButton(
            tooltip: adminTx(context, 'مدل جدید', 'New model'),
            icon: const Icon(Icons.add, size: 20),
            onPressed: () => _showModelDialog(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _models.isEmpty
                  ? Center(child: Text(adminTx(context, 'مدلی تعریف نشده است', 'No models yet')))
                  : ListView.separated(
                      padding: context.settingsHub.pagePadding,
                      itemCount: _models.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final m = _models[index];
                        return Card(
                          child: ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              backgroundColor: m.isActive
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.smart_toy_outlined,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            title: Text(
                              m.displayName,
                              style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                            ),
                            subtitle: Text(
                              '${m.code} · ${m.provider} · ${m.modelId}'
                              '${m.tier != null ? ' · ${m.tier}' : ''}'
                              '${m.supportsReasoning ? ' · reasoning' : ''}'
                              '${m.reasoningEffort != null ? ' (${m.reasoningEffort})' : ''}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!m.isActive)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Chip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text(adminTx(context, 'غیرفعال', 'Inactive'), style: const TextStyle(fontSize: 11)),
                                    ),
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
                                        title: Text(adminTx(context, 'غیرفعال کردن مدل', 'Deactivate model')),
                                        content: Text(adminTx(context, 'مدل «${m.displayName}» غیرفعال شود؟', 'Deactivate “${m.displayName}”?')),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: Text(adminTx(context, 'لغو', 'Cancel')),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: Text(adminTx(context, 'تأیید', 'Confirm')),
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
