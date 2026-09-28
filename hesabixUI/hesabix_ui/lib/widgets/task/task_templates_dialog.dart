import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:intl/intl.dart';

class TaskTemplatesDialog extends StatefulWidget {
  final int businessId;
  final TaskService service;
  final bool canCreateProject;
  final bool canDeleteTemplate;
  final VoidCallback onInstantiated;

  const TaskTemplatesDialog({
    super.key,
    required this.businessId,
    required this.service,
    required this.canCreateProject,
    required this.canDeleteTemplate,
    required this.onInstantiated,
  });

  @override
  State<TaskTemplatesDialog> createState() => _TaskTemplatesDialogState();
}

class _TaskTemplatesDialogState extends State<TaskTemplatesDialog> {
  List<TaskProjectTemplateModel> _templates = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.service.listTemplates(widget.businessId);
      if (!mounted) return;
      setState(() {
        _templates = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorExtractor.forContext(e, context);
      });
    }
  }

  Future<void> _instantiate(TaskProjectTemplateModel template) async {
    if (!widget.canCreateProject || _busy) return;
    final code = TextEditingController();
    final name = TextEditingController(text: template.name);
    DateTime start = DateTime.now();

    final payload = await showGlassDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInnerState) => AlertDialog(
          title: Text('ایجاد پروژه از «${template.name}»'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'کد پروژه',
                    prefixIcon: Icon(Icons.tag),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'نام پروژه',
                    prefixIcon: Icon(Icons.folder_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('تاریخ پایه'),
                  subtitle: Text(DateFormat('yyyy/MM/dd').format(start)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final value = await showDatePicker(
                      context: ctx,
                      initialDate: start,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(
                        const Duration(days: 3650),
                      ),
                    );
                    if (value != null) {
                      setInnerState(() => start = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                final c = code.text.trim();
                final n = name.text.trim();
                if (c.isEmpty || n.isEmpty) return;
                Navigator.pop(ctx, {
                  'code': c,
                  'name': n,
                  'start': start,
                });
              },
              child: const Text('ایجاد'),
            ),
          ],
        ),
      ),
    );
    code.dispose();
    name.dispose();
    if (payload == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.instantiateTemplate(
        businessId: widget.businessId,
        templateId: template.id,
        projectCode: payload['code'] as String,
        projectName: payload['name'] as String,
        startDate: payload['start'] as DateTime,
      );
      if (!mounted) return;
      widget.onInstantiated();
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(TaskProjectTemplateModel template) async {
    if (!widget.canDeleteTemplate || _busy) return;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف قالب'),
        content: Text('قالب «${template.name}» حذف شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await widget.service.deleteTemplate(
        businessId: widget.businessId,
        templateId: template.id,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_awesome_motion_outlined),
          SizedBox(width: 8),
          Text('قالب‌های پروژه و کار'),
        ],
      ),
      content: SizedBox(
        width: 720,
        height: 520,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_error!),
                    ),
                  Expanded(
                    child: _templates.isEmpty
                        ? const Center(
                            child: Text(
                              'هنوز قالبی ندارید. از فضای یک پروژه، «ذخیره به‌عنوان قالب» را انتخاب کنید.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            itemCount: _templates.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = _templates[index];
                              return GlassSurface(
                                padding: const EdgeInsets.all(12),
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.view_list_outlined),
                                  ),
                                  title: Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      '${item.taskCount} کار',
                                      if (item.description
                                              ?.trim()
                                              .isNotEmpty ==
                                          true)
                                        item.description!,
                                    ].join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Wrap(
                                    spacing: 4,
                                    children: [
                                      FilledButton.tonalIcon(
                                        onPressed: widget.canCreateProject &&
                                                !_busy
                                            ? () => _instantiate(item)
                                            : null,
                                        icon: const Icon(
                                          Icons.add_box_outlined,
                                          size: 18,
                                        ),
                                        label: const Text('ایجاد پروژه'),
                                      ),
                                      if (widget.canDeleteTemplate)
                                        IconButton(
                                          tooltip: 'حذف قالب',
                                          onPressed: _busy
                                              ? null
                                              : () => _delete(item),
                                          icon: Icon(
                                            Icons.delete_outline,
                                            color: scheme.error,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('بستن'),
        ),
      ],
    );
  }
}
