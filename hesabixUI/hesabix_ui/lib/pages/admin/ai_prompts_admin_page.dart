import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/models/ai_models.dart';

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
  String? _selectedRole;

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _aiService = AIService(api);
    _load();
  }

  Future<void> _load({String? role}) async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedRole = role;
    });
    try {
      final prompts = await _aiService.listDefaultPrompts(role: role);
      setState(() {
        _prompts = prompts;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _showPromptFormDialog({AIPrompt? prompt}) async {
    final isEdit = prompt != null;
    final formKey = GlobalKey<FormState>();
    final contentController = TextEditingController(text: prompt?.content ?? '');
    
    String? selectedRole = prompt?.role ?? _selectedRole ?? 'user';
    String? selectedType = prompt?.promptType ?? 'system';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          return Dialog(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          isEdit ? 'ویرایش Prompt' : 'ایجاد Prompt جدید',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          color: theme.colorScheme.onPrimary,
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
                            DropdownButtonFormField<String>(
                              value: selectedRole,
                              decoration: const InputDecoration(labelText: 'نقش'),
                              items: const [
                                DropdownMenuItem(value: 'admin', child: Text('مدیر سیستم')),
                                DropdownMenuItem(value: 'operator', child: Text('اپراتور')),
                                DropdownMenuItem(value: 'user', child: Text('کاربر')),
                              ],
                              onChanged: (v) => setDialogState(() => selectedRole = v),
                              validator: (v) => v == null ? 'الزامی است' : null,
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: selectedType,
                              decoration: const InputDecoration(labelText: 'نوع'),
                              items: const [
                                DropdownMenuItem(value: 'system', child: Text('System Prompt')),
                                DropdownMenuItem(value: 'user', child: Text('User Prompt')),
                              ],
                              onChanged: (v) => setDialogState(() => selectedType = v),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: contentController,
                              decoration: const InputDecoration(
                                labelText: 'محتوای Prompt',
                                alignLabelWithHint: true,
                              ),
                              maxLines: 10,
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
                        FilledButton(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            try {
                              final data = {
                                'role': selectedRole,
                                'prompt_type': selectedType,
                                'content': contentController.text.trim(),
                                'is_default': true,
                              };
                              if (isEdit && prompt.id != null) {
                                await _aiService.updateDefaultPrompt(prompt.id!, data);
                              } else {
                                await _aiService.createDefaultPrompt(data);
                              }
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              _load(role: _selectedRole);
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('خطا: $e')),
                              );
                            }
                          },
                          child: Text(isEdit ? 'ذخیره' : 'ایجاد'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showPromptFormDialog(),
            tooltip: 'ایجاد Prompt جدید',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter by role
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                const Text('فیلتر بر اساس نقش:'),
                const SizedBox(width: 16),
                ChoiceChip(
                  label: const Text('همه'),
                  selected: _selectedRole == null,
                  onSelected: (v) => _load(),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('مدیر'),
                  selected: _selectedRole == 'admin',
                  onSelected: (v) => _load(role: 'admin'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('اپراتور'),
                  selected: _selectedRole == 'operator',
                  onSelected: (v) => _load(role: 'operator'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('کاربر'),
                  selected: _selectedRole == 'user',
                  onSelected: (v) => _load(role: 'user'),
                ),
              ],
            ),
          ),
          // List
          Expanded(
            child: _error != null && _prompts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('خطا: $_error'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _load(role: _selectedRole),
                          child: const Text('تلاش مجدد'),
                        ),
                      ],
                    ),
                  )
                : _prompts.isEmpty
                    ? const Center(child: Text('Promptی وجود ندارد'))
                    : RefreshIndicator(
                        onRefresh: () => _load(role: _selectedRole),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _prompts.length,
                          itemBuilder: (context, index) {
                            final prompt = _prompts[index];
                            String roleLabel;
                            switch (prompt.role) {
                              case 'admin':
                                roleLabel = 'مدیر سیستم';
                                break;
                              case 'operator':
                                roleLabel = 'اپراتور';
                                break;
                              case 'user':
                                roleLabel = 'کاربر';
                                break;
                              default:
                                roleLabel = prompt.role;
                            }
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ExpansionTile(
                                title: Text('$roleLabel - ${prompt.promptType ?? 'system'}'),
                                subtitle: Text(
                                  prompt.content.length > 100
                                      ? '${prompt.content.substring(0, 100)}...'
                                      : prompt.content,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      onPressed: () => _showPromptFormDialog(prompt: prompt),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: () async {
                                        if (await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text('حذف Prompt'),
                                                content: const Text(
                                                    'آیا از حذف این Prompt اطمینان دارید؟'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(context, false),
                                                    child: const Text('لغو'),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(context, true),
                                                    child: const Text('حذف'),
                                                  ),
                                                ],
                                              ),
                                            ) ??
                                            false) {
                                          try {
                                            if (prompt.id != null) {
                                              await _aiService.deleteDefaultPrompt(prompt.id!);
                                              _load(role: _selectedRole);
                                            }
                                          } catch (e) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('خطا: $e')),
                                              );
                                            }
                                          }
                                        }
                                      },
                                    ),
                                  ],
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

