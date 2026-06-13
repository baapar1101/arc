import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../services/admin_notification_event_types_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class NotificationEventTypesAdminPage extends StatefulWidget {
  const NotificationEventTypesAdminPage({super.key});

  @override
  State<NotificationEventTypesAdminPage> createState() =>
      _NotificationEventTypesAdminPageState();
}

class _NotificationEventTypesAdminPageState
    extends State<NotificationEventTypesAdminPage> {
  final _svc = AdminNotificationEventTypesService(ApiClient());
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String? _categoryFilter;

  static const _categories = <String, String>{
    'sales': 'فروش',
    'purchases': 'خرید',
    'financial': 'مالی',
    'crm': 'CRM',
    'documents': 'اسناد',
    'people': 'اشخاص',
    'warehouse': 'انبار',
    'distribution': 'پخش',
    'repair_shop': 'تعمیرگاه',
    'warranty': 'گارانتی',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _svc.list(
        category: _categoryFilter,
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = extractErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _openEditor(Map<String, dynamic> item) async {
    final code = item['code'] as String? ?? '';
    final smsCtrl = TextEditingController(
      text: item['default_sms_template'] as String? ?? '',
    );
    final emailBodyCtrl = TextEditingController(
      text: item['default_email_template'] as String? ?? '',
    );
    final emailSubjectCtrl = TextEditingController(
      text: item['default_email_subject'] as String? ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('قالب پیش‌فرض — ${item['name'] ?? code}'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('کد رویداد: $code', style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 12),
                TextField(
                  controller: smsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'قالب پیش‌فرض پیامک',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailSubjectCtrl,
                  decoration: const InputDecoration(
                    labelText: 'موضوع پیش‌فرض ایمیل',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailBodyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'متن پیش‌فرض ایمیل',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 8,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );

    if (saved != true) {
      smsCtrl.dispose();
      emailBodyCtrl.dispose();
      emailSubjectCtrl.dispose();
      return;
    }

    try {
      await _svc.updateDefaults(
        code: code,
        defaultSmsTemplate: smsCtrl.text,
        defaultEmailTemplate: emailBodyCtrl.text,
        defaultEmailSubject: emailSubjectCtrl.text,
      );
      smsCtrl.dispose();
      emailBodyCtrl.dispose();
      emailSubjectCtrl.dispose();
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'قالب‌های پیش‌فرض ذخیره شد');
      await _load();
    } catch (e) {
      smsCtrl.dispose();
      emailBodyCtrl.dispose();
      emailSubjectCtrl.dispose();
      if (!mounted) return;
      SnackBarHelper.showError(context, message: extractErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'قالب‌های پیش‌فرض نوتیفیکیشن کسب‌وکار',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'اگر کسب‌وکار قالب اختصاصی نداشته باشد، از این متن‌ها برای ارسال SMS/Email استفاده می‌شود.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'جستجو در نام یا کد رویداد…',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _load();
                        },
                      ),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String?>(
                  value: _categoryFilter,
                  hint: const Text('دسته'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('همه دسته‌ها')),
                    ..._categories.entries.map(
                      (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => _categoryFilter = v);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _items.isEmpty
                          ? const Center(child: Text('رویدادی یافت نشد'))
                          : ListView.separated(
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                final hasSms = item['has_sms_default'] == true;
                                final hasEmail = item['has_email_default'] == true;
                                return ListTile(
                                  title: Text(item['name'] as String? ?? ''),
                                  subtitle: Text(
                                    '${item['code']} — ${_categories[item['category']] ?? item['category'] ?? ''}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (hasSms)
                                        const Tooltip(
                                          message: 'پیامک',
                                          child: Icon(Icons.sms, size: 18, color: Colors.green),
                                        ),
                                      if (hasEmail)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 6),
                                          child: Tooltip(
                                            message: 'ایمیل',
                                            child: Icon(Icons.email, size: 18, color: Colors.blue),
                                          ),
                                        ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.chevron_left),
                                    ],
                                  ),
                                  onTap: () => _openEditor(item),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
