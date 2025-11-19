import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../services/admin_notification_templates_service.dart';

class NotificationTemplatesAdminPage extends StatefulWidget {
  const NotificationTemplatesAdminPage({super.key});

  @override
  State<NotificationTemplatesAdminPage> createState() => _NotificationTemplatesAdminPageState();
}

class _NotificationTemplatesAdminPageState extends State<NotificationTemplatesAdminPage> {
  final _svc = AdminNotificationTemplatesService(ApiClient());
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  String _eventKeyFilter = '';
  String _channelFilter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final data = await _svc.list(eventKey: _eventKeyFilter.isEmpty ? null : _eventKeyFilter, channel: _channelFilter.isEmpty ? null : _channelFilter);
      final items = (data['items'] as List? ?? const <dynamic>[])
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _openEditDialog({Map<String, dynamic>? item}) async {
    final formKey = GlobalKey<FormState>();
    final eventKeyCtrl = TextEditingController(text: '${item?['event_key'] ?? ''}');
    final channelCtrl = TextEditingController(text: '${item?['channel'] ?? ''}');
    final localeCtrl = TextEditingController(text: '${item?['locale'] ?? ''}');
    final subjectCtrl = TextEditingController(text: '${item?['subject'] ?? ''}');
    final bodyCtrl = TextEditingController(text: '${item?['body'] ?? ''}');
    bool isActive = (item?['is_active'] ?? true) == true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(item == null ? 'ایجاد قالب' : 'ویرایش قالب'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: eventKeyCtrl,
                    decoration: const InputDecoration(labelText: 'event_key'),
                    validator: (v) => (v == null || v.isEmpty) ? 'الزامی' : null,
                  ),
                  TextFormField(
                    controller: channelCtrl,
                    decoration: const InputDecoration(labelText: 'channel (telegram|email|sms|inapp)'),
                    validator: (v) => (v == null || v.isEmpty) ? 'الزامی' : null,
                  ),
                  TextFormField(
                    controller: localeCtrl,
                    decoration: const InputDecoration(labelText: 'locale (اختیاری)'),
                  ),
                  TextFormField(
                    controller: subjectCtrl,
                    decoration: const InputDecoration(labelText: 'subject (اختیاری)'),
                  ),
                  TextFormField(
                    controller: bodyCtrl,
                    decoration: const InputDecoration(labelText: 'body'),
                    minLines: 3,
                    maxLines: 8,
                    validator: (v) => (v == null || v.isEmpty) ? 'الزامی' : null,
                  ),
                  SwitchListTile(
                    title: const Text('فعال'),
                    value: isActive,
                    onChanged: (v) {
                      isActive = v;
                      (context as Element).markNeedsBuild();
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final res = await _svc.preview(
                            channel: channelCtrl.text.trim(),
                            subject: subjectCtrl.text.trim().isEmpty ? null : subjectCtrl.text.trim(),
                            body: bodyCtrl.text,
                            context: const <String, dynamic>{},
                          );
                          if (!context.mounted) return;
                          final ctx = context;
                          await showDialog(
                            context: ctx,
                            builder: (ctx) => AlertDialog(
                              title: const Text('پیش‌نمایش'),
                              content: SizedBox(
                                width: 600,
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Channel: ${res['channel'] ?? ''}'),
                                      const SizedBox(height: 8),
                                      if ((res['subject'] ?? '').toString().isNotEmpty) Text('Subject: ${res['subject']}'),
                                      const SizedBox(height: 8),
                                      Text((res['body'] ?? '').toString()),
                                    ],
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
                              ],
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در پیش‌نمایش: $e')));
                        }
                      },
                      icon: const Icon(Icons.visibility, size: 18),
                      label: const Text('پیش‌نمایش'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('انصراف')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  if (item == null) {
                    await _svc.create(
                      eventKey: eventKeyCtrl.text.trim(),
                      channel: channelCtrl.text.trim(),
                      locale: localeCtrl.text.trim().isEmpty ? null : localeCtrl.text.trim(),
                      subject: subjectCtrl.text.trim().isEmpty ? null : subjectCtrl.text.trim(),
                      body: bodyCtrl.text,
                      isActive: isActive,
                    );
                  } else {
                    final id = item['id'] as int;
                    await _svc.update(
                      id: id,
                      eventKey: eventKeyCtrl.text.trim(),
                      channel: channelCtrl.text.trim(),
                      locale: localeCtrl.text.trim().isEmpty ? null : localeCtrl.text.trim(),
                      subject: subjectCtrl.text.trim().isEmpty ? null : subjectCtrl.text.trim(),
                      body: bodyCtrl.text,
                      isActive: isActive,
                    );
                  }
                  if (!context.mounted) return;
                  Navigator.of(context).pop(true);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
        );
      },
    );
    if (result == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ذخیره شد')));
      }
    }
  }

  Future<void> _delete(int id) async {
    try {
      await _svc.delete(id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حذف شد')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56),
            const SizedBox(height: 8),
            Text('خطا: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _load, child: const Text('تلاش مجدد')),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('قالب‌های نوتیفیکیشن', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('بازخوانی'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _openEditDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('ایجاد'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  decoration: const InputDecoration(labelText: 'event_key'),
                  onChanged: (v) => _eventKeyFilter = v,
                ),
              ),
              SizedBox(
                width: 240,
                child: TextField(
                  decoration: const InputDecoration(labelText: 'channel'),
                  onChanged: (v) => _channelFilter = v,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('فیلتر'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('ID')),
                  DataColumn(label: Text('event_key')),
                  DataColumn(label: Text('channel')),
                  DataColumn(label: Text('locale')),
                  DataColumn(label: Text('subject')),
                  DataColumn(label: Text('فعال')),
                  DataColumn(label: Text('عملیات')),
                ],
                rows: _items.map((it) {
                  return DataRow(
                    cells: [
                      DataCell(Text('${it['id']}')),
                      DataCell(Text('${it['event_key']}')),
                      DataCell(Text('${it['channel']}')),
                      DataCell(Text('${it['locale'] ?? ''}')),
                      DataCell(Text('${it['subject'] ?? ''}')),
                      DataCell(Icon((it['is_active'] ?? true) ? Icons.check_circle : Icons.cancel, color: (it['is_active'] ?? true) ? Colors.green : Colors.red)),
                      DataCell(Row(
                        children: [
                          IconButton(
                            tooltip: 'ویرایش',
                            icon: const Icon(Icons.edit),
                            onPressed: () => _openEditDialog(item: it),
                          ),
                          IconButton(
                            tooltip: 'حذف',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () {
                              final id = it['id'] as int?;
                              if (id != null) _delete(id);
                            },
                          ),
                        ],
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


