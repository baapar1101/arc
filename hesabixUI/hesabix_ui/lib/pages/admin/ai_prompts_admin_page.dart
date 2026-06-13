import 'package:flutter/material.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import '../../utils/snackbar_helper.dart';

class AIPromptsAdminPage extends StatefulWidget {
  const AIPromptsAdminPage({super.key});

  @override
  State<AIPromptsAdminPage> createState() => _AIPromptsAdminPageState();
}

class _AIPromptsAdminPageState extends State<AIPromptsAdminPage> {
  late final AIService _aiService;
  bool _loading = true;
  String? _error;
  List<AIPrompt> _prompts = [];
  String? _selectedCategory;

  static const _categories = <String, String>{
    'chat': 'چت اصلی',
    'auxiliary': 'کمکی',
    'support': 'پشتیبانی',
    'crm': 'CRM',
    'moderation': 'بررسی محتوا',
    'scheduled': 'زمان‌بندی‌شده',
    'insight': 'بینش و پیشنهاد',
    'memory': 'حافظه',
  };

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _aiService = AIService(api);
    _load();
  }

  Future<void> _load({String? category}) async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedCategory = category;
    });
    try {
      final prompts = await _aiService.listDefaultPrompts(category: category);
      setState(() {
        _prompts = prompts;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<void> _showPromptFormDialog(AIPrompt prompt) async {
    final formKey = GlobalKey<FormState>();
    final contentController = TextEditingController(text: prompt.content);
    final promptKey = prompt.promptKey;
    if (promptKey == null) return;

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        prompt.title ?? promptKey,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: Theme.of(context).colorScheme.onPrimary,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('کلید: $promptKey'),
                        const SizedBox(height: 8),
                        Text('دسته: ${_categories[prompt.category] ?? prompt.category ?? '-'}'),
                        const SizedBox(height: 8),
                        Text('منبع: ${prompt.source == 'database' ? 'دیتابیس' : 'پیش‌فرض کد'}'),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: contentController,
                          decoration: const InputDecoration(
                            labelText: 'محتوای Prompt',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 18,
                          validator: (v) => v?.isEmpty ?? true ? 'الزامی است' : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('لغو'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () async {
                        try {
                          await _aiService.resetDefaultPrompt(promptKey);
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          _load(category: _selectedCategory);
                          SnackBarHelper.showSuccess(context, message: 'به پیش‌فرض کد بازگردانده شد');
                        } catch (e) {
                          if (!context.mounted) return;
                          SnackBarHelper.showError(
                            context,
                            message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
                          );
                        }
                      },
                      child: const Text('بازگشت به پیش‌فرض'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        try {
                          await _aiService.updateDefaultPromptByKey(
                            promptKey,
                            contentController.text.trim(),
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          _load(category: _selectedCategory);
                          SnackBarHelper.showSuccess(context, message: 'ذخیره شد');
                        } catch (e) {
                          if (!context.mounted) return;
                          SnackBarHelper.showError(
                            context,
                            message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
                          );
                        }
                      },
                      child: const Text('ذخیره'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Prompt های پیش‌فرض AI')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prompt های پیش‌فرض AI'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('فیلتر دسته:'),
                ChoiceChip(
                  label: const Text('همه'),
                  selected: _selectedCategory == null,
                  onSelected: (_) => _load(),
                ),
                ..._categories.entries.map(
                  (entry) => ChoiceChip(
                    label: Text(entry.value),
                    selected: _selectedCategory == entry.key,
                    onSelected: (_) => _load(category: entry.key),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _error != null && _prompts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('خطا: $_error'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _load(category: _selectedCategory),
                          child: const Text('تلاش مجدد'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _load(category: _selectedCategory),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _prompts.length,
                      itemBuilder: (context, index) {
                        final prompt = _prompts[index];
                        final sourceLabel =
                            prompt.source == 'database' ? 'دیتابیس' : 'پیش‌فرض کد';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ExpansionTile(
                            title: Text(prompt.title ?? prompt.promptKey ?? '-'),
                            subtitle: Text(
                              '${_categories[prompt.category] ?? prompt.category ?? '-'} • $sourceLabel • ${prompt.promptKey ?? ''}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showPromptFormDialog(prompt),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  prompt.content,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
