import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../l10n/app_localizations.dart';
import '../../services/report_template_service.dart';

class ReportTemplatesPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  const ReportTemplatesPage({super.key, required this.businessId, required this.authStore});

  @override
  State<ReportTemplatesPage> createState() => _ReportTemplatesPageState();
}

class _ReportTemplatesPageState extends State<ReportTemplatesPage> {
  late final ReportTemplateService _service;
  final _moduleCtrl = TextEditingController(text: 'invoices');
  final _subtypeCtrl = TextEditingController(text: 'list');
  String? _statusFilter; // draft/published/null

  bool _loading = false;
  List<Map<String, dynamic>> _items = const [];

  // Create/Edit form
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _htmlCtrl = TextEditingController(text: "<html><head></head><body><h3>{{ title_text }}</h3></body></html>");
  final _cssCtrl = TextEditingController(text: "body { font-family: Tahoma, Arial; }");

  bool get _canWrite => widget.authStore.hasBusinessPermission('report_templates', 'write');

  @override
  void initState() {
    super.initState();
    _service = ReportTemplateService(ApiClient());
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final items = await _service.listTemplates(
        businessId: widget.businessId,
        moduleKey: _moduleCtrl.text.trim().isEmpty ? null : _moduleCtrl.text.trim(),
        subtype: _subtypeCtrl.text.trim().isEmpty ? null : _subtypeCtrl.text.trim(),
        status: _statusFilter,
      );
      setState(() {
        _items = items;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createDialog() async {
    final t = AppLocalizations.of(context);
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.templates),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'نام قالب'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(labelText: 'توضیحات'),
                  ),
                  const SizedBox(height: 12),
                  Text('HTML', style: Theme.of(context).textTheme.titleSmall),
                  TextField(
                    controller: _htmlCtrl,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'HTML محتوا (Jinja2 variables allowed)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('CSS', style: Theme.of(context).textTheme.titleSmall),
                  TextField(
                    controller: _cssCtrl,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'CSS اختیاری',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
            FilledButton(
              onPressed: () async {
                try {
                  final id = await _service.createTemplate(
                    businessId: widget.businessId,
                    moduleKey: _moduleCtrl.text.trim().isEmpty ? 'invoices' : _moduleCtrl.text.trim(),
                    subtype: _subtypeCtrl.text.trim().isEmpty ? 'list' : _subtypeCtrl.text.trim(),
                    name: _nameCtrl.text.trim().isEmpty ? 'Template' : _nameCtrl.text.trim(),
                    description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
                    contentHtml: _htmlCtrl.text,
                    contentCss: _cssCtrl.text.trim().isEmpty ? null : _cssCtrl.text,
                  );
                  if (mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('قالب ایجاد شد (ID: $id)')));
                  }
                  await _fetch();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در ایجاد: $e')));
                  }
                }
              },
              child: const Text('ایجاد'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _togglePublish(Map<String, dynamic> item) async {
    final published = (item['status'] == 'published');
    final next = !published;
    await _service.publish(
      businessId: widget.businessId,
      templateId: (item['id'] as num).toInt(),
      published: next,
    );
    await _fetch();
  }

  Future<void> _previewTemplate(Map<String, dynamic> item) async {
    try {
      final full = await _service.getTemplate(
        businessId: widget.businessId,
        templateId: (item['id'] as num).toInt(),
      );
      final res = await _service.preview(
        businessId: widget.businessId,
        contentHtml: (full['content_html'] ?? '').toString(),
        contentCss: (full['content_css'] ?? '').toString().isEmpty ? null : (full['content_css'] ?? '').toString(),
        context: const <String, dynamic>{},
      );
      if (!mounted) return;
      final len = res['content_length'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('پیش‌نمایش موفق (طول PDF: $len بایت)')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در پیش‌نمایش: $e')));
    }
  }

  Future<void> _editDialog(Map<String, dynamic> item) async {
    try {
      final full = await _service.getTemplate(
        businessId: widget.businessId,
        templateId: (item['id'] as num).toInt(),
      );
      _nameCtrl.text = (full['name'] ?? '').toString();
      _descCtrl.text = (full['description'] ?? '').toString();
      _htmlCtrl.text = (full['content_html'] ?? '').toString();
      _cssCtrl.text = (full['content_css'] ?? '').toString();
    } catch (_) {}

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('ویرایش قالب'),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'نام قالب'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(labelText: 'توضیحات'),
                  ),
                  const SizedBox(height: 12),
                  Text('HTML', style: Theme.of(context).textTheme.titleSmall),
                  TextField(
                    controller: _htmlCtrl,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'HTML محتوا (Jinja2 variables allowed)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('CSS', style: Theme.of(context).textTheme.titleSmall),
                  TextField(
                    controller: _cssCtrl,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'CSS اختیاری',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
            TextButton(
              onPressed: () async {
                await _previewTemplate(item);
              },
              child: const Text('پیش‌نمایش'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final changes = <String, dynamic>{
                    'name': _nameCtrl.text.trim(),
                    'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
                    'content_html': _htmlCtrl.text,
                    'content_css': _cssCtrl.text.trim().isEmpty ? null : _cssCtrl.text,
                  };
                  await _service.updateTemplate(
                    businessId: widget.businessId,
                    templateId: (item['id'] as num).toInt(),
                    changes: changes,
                  );
                  if (mounted) Navigator.pop(ctx);
                  await _fetch();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در ویرایش: $e')));
                  }
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _setDefault(Map<String, dynamic> item) async {
    await _service.setDefault(
      businessId: widget.businessId,
      moduleKey: (_moduleCtrl.text.trim().isEmpty ? 'invoices' : _moduleCtrl.text.trim()),
      subtype: (_subtypeCtrl.text.trim().isEmpty ? 'list' : _subtypeCtrl.text.trim()),
      templateId: (item['id'] as num).toInt(),
    );
    await _fetch();
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    await _service.deleteTemplate(
      businessId: widget.businessId,
      templateId: (item['id'] as num).toInt(),
    );
    await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${t.templates} (${_moduleCtrl.text}${_subtypeCtrl.text.isNotEmpty ? '/${_subtypeCtrl.text}' : ''})'),
        actions: [
          if (_canWrite)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FilledButton.icon(
                onPressed: _createDialog,
                icon: const Icon(Icons.add),
                label: const Text('قالب جدید'),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _moduleCtrl,
                    decoration: const InputDecoration(labelText: 'module_key (مثلاً: invoices)'),
                    onSubmitted: (_) => _fetch(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _subtypeCtrl,
                    decoration: const InputDecoration(labelText: 'subtype (مثلاً: list یا detail)'),
                    onSubmitted: (_) => _fetch(),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String?>(
                  value: _statusFilter,
                  hint: const Text('همه وضعیت‌ها'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('همه')),
                    DropdownMenuItem(value: 'published', child: Text('منتشر شده')),
                    DropdownMenuItem(value: 'draft', child: Text('پیش‌نویس')),
                  ],
                  onChanged: (v) {
                    setState(() => _statusFilter = v);
                    _fetch();
                  },
                ),
                const Spacer(),
                IconButton(onPressed: _fetch, icon: const Icon(Icons.refresh)),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: Text(t.presetInvoicesList),
                    onPressed: () {
                      _moduleCtrl.text = 'invoices';
                      _subtypeCtrl.text = 'list';
                      _fetch();
                    },
                  ),
                  ActionChip(
                    label: Text(t.presetInvoicesDetail),
                    onPressed: () {
                      _moduleCtrl.text = 'invoices';
                      _subtypeCtrl.text = 'detail';
                      _fetch();
                    },
                  ),
                  ActionChip(
                    label: Text(t.presetReceiptsPaymentsList),
                    onPressed: () {
                      _moduleCtrl.text = 'receipts_payments';
                      _subtypeCtrl.text = 'list';
                      _fetch();
                    },
                  ),
                  ActionChip(
                    label: Text(t.presetReceiptsPaymentsDetail),
                    onPressed: () {
                      _moduleCtrl.text = 'receipts_payments';
                      _subtypeCtrl.text = 'detail';
                      _fetch();
                    },
                  ),
                  ActionChip(
                    label: Text(t.presetExpenseIncomeList),
                    onPressed: () {
                      _moduleCtrl.text = 'expense_income';
                      _subtypeCtrl.text = 'list';
                      _fetch();
                    },
                  ),
                  ActionChip(
                    label: Text(t.presetDocumentsList),
                    onPressed: () {
                      _moduleCtrl.text = 'documents';
                      _subtypeCtrl.text = 'list';
                      _fetch();
                    },
                  ),
                  ActionChip(
                    label: Text(t.presetDocumentsDetail),
                    onPressed: () {
                      _moduleCtrl.text = 'documents';
                      _subtypeCtrl.text = 'detail';
                      _fetch();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? const Center(child: Text('قالبی یافت نشد'))
                      : Card(
                          clipBehavior: Clip.antiAlias,
                          child: ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, idx) {
                              final it = _items[idx];
                              final isDefault = it['is_default'] == true;
                              final status = (it['status'] ?? '').toString();
                              return ListTile(
                                title: Text(it['name']?.toString() ?? '-'),
                                subtitle: Text(
                                  'status: $status   module: ${it['module_key']}   subtype: ${it['subtype'] ?? '-'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                leading: Icon(isDefault ? Icons.star : Icons.description),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_canWrite)
                                      IconButton(
                                        tooltip: status == 'published' ? 'به پیش‌نویس برگردان' : 'انتشار',
                                        onPressed: () => _togglePublish(it),
                                        icon: Icon(status == 'published' ? Icons.visibility_off : Icons.publish),
                                      ),
                                    if (_canWrite)
                                      IconButton(
                                        tooltip: 'پیش‌نمایش',
                                        onPressed: () => _previewTemplate(it),
                                        icon: const Icon(Icons.visibility),
                                      ),
                                    if (_canWrite)
                                      IconButton(
                                        tooltip: 'ویرایش',
                                        onPressed: () => _editDialog(it),
                                        icon: const Icon(Icons.edit),
                                      ),
                                    if (_canWrite)
                                      IconButton(
                                        tooltip: 'تنظیم به‌عنوان پیش‌فرض',
                                        onPressed: () => _setDefault(it),
                                        icon: const Icon(Icons.star),
                                      ),
                                    if (_canWrite)
                                      IconButton(
                                        tooltip: 'حذف',
                                        onPressed: () => _delete(it),
                                        icon: const Icon(Icons.delete_outline),
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
      ),
    );
  }
}


