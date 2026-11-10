import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../services/admin_notification_event_types_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import '../admin/admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

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

  String _categoryLabel(String key) {
    switch (key) {
      case 'sales':
        return adminTx(context, 'فروش', 'Sales');
      case 'purchases':
        return adminTx(context, 'خرید', 'Purchases');
      case 'financial':
        return adminTx(context, 'مالی', 'Finance');
      case 'crm':
        return 'CRM';
      case 'documents':
        return adminTx(context, 'اسناد', 'Documents');
      case 'people':
        return adminTx(context, 'اشخاص', 'People');
      case 'warehouse':
        return adminTx(context, 'انبار', 'Warehouse');
      case 'distribution':
        return adminTx(context, 'پخش', 'Distribution');
      case 'repair_shop':
        return adminTx(context, 'تعمیرگاه', 'Repair shop');
      case 'warranty':
        return adminTx(context, 'گارانتی', 'Warranty');
      default:
        return key;
    }
  }

  static const _categoryKeys = [
    'sales',
    'purchases',
    'financial',
    'crm',
    'documents',
    'people',
    'warehouse',
    'distribution',
    'repair_shop',
    'warranty',
  ];

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
        _error = ErrorExtractor.extractErrorMessage(e);
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
        title: Text('${adminTx(context, 'قالب پیش‌فرض', 'Default template')} — ${item['name'] ?? code}'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${adminTx(context, 'کد رویداد', 'Event code')}: $code', style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 8),
                TextField(
                  controller: smsCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: adminTx(context, 'قالب پیش‌فرض پیامک', 'Default SMS template'),
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailSubjectCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: adminTx(context, 'موضوع پیش‌فرض ایمیل', 'Default email subject'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailBodyCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: adminTx(context, 'متن پیش‌فرض ایمیل', 'Default email body'),
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 8,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(adminTx(context, 'انصراف', 'Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(adminTx(context, 'ذخیره', 'Save')),
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
      SnackBarHelper.show(context, message: adminTx(context, 'قالب‌های پیش‌فرض ذخیره شد', 'Default templates saved'));
      await _load();
    } catch (e) {
      smsCtrl.dispose();
      emailBodyCtrl.dispose();
      emailSubjectCtrl.dispose();
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.extractErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminCompactScaffold(
      title: adminTx(context, 'قالب‌های پیش‌فرض', 'Default templates'),
      subtitle: adminTx(
        context,
        'اگر کسب‌وکار قالب خودش را نداشته باشد، پیامک و ایمیل از این متن‌ها می‌روند',
        'SMS and email use these texts when a business has no template of its own',
      ),
      body: Padding(
        padding: context.settingsHub.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: adminTx(context, 'جستجو در نام یا کد رویداد', 'Search by event name or code'),
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
                  hint: Text(adminTx(context, 'دسته', 'Category')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(adminTx(context, 'همه دسته‌ها', 'All categories'))),
                    ..._categoryKeys.map(
                      (key) => DropdownMenuItem(value: key, child: Text(_categoryLabel(key))),
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
                          ? Center(child: Text(adminTx(context, 'رویدادی یافت نشد', 'No events found')))
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
                                    '${item['code']} — ${_categoryLabel('${item['category'] ?? ''}')}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (hasSms)
                                        Tooltip(
                                          message: adminTx(context, 'پیامک', 'SMS'),
                                          child: Icon(Icons.sms, size: 18, color: SemanticColorResolver.positive(context)),
                                        ),
                                      if (hasEmail)
                                        Padding(
                                          padding: EdgeInsets.only(left: 6),
                                          child: Tooltip(
                                            message: adminTx(context, 'ایمیل', 'Email'),
                                            child: Icon(Icons.email, size: 18, color: SemanticColorResolver.info(context)),
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
