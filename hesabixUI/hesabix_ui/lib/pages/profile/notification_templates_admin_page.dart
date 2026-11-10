import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../services/admin_notification_templates_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/data_table/helpers/data_table_utils.dart';
import '../../models/notification_template_model.dart';
import '../../models/event_key_info.dart';
import '../../utils/error_extractor.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import '../admin/admin_compact_scaffold.dart';

class NotificationTemplatesAdminPage extends StatefulWidget {
  const NotificationTemplatesAdminPage({super.key});

  @override
  State<NotificationTemplatesAdminPage> createState() => _NotificationTemplatesAdminPageState();
}

class _NotificationTemplatesAdminPageState extends State<NotificationTemplatesAdminPage> {
  final _svc = AdminNotificationTemplatesService(ApiClient());
  final GlobalKey<State<DataTableWidget<NotificationTemplate>>> _tableKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return AdminCompactScaffold(
      title: adminTx(context, 'قالب‌های اعلان', 'Notification templates'),
      subtitle: adminTx(context, 'قالب رویدادها برای کانال‌های ارسال', 'Event templates for delivery channels'),
      body: DataTableWidget<NotificationTemplate>(
        key: _tableKey,
        config: _buildDataTableConfig(),
        fromJson: NotificationTemplate.fromJson,
      ),
    );
  }

  DataTableConfig<NotificationTemplate> _buildDataTableConfig() {
    return DataTableConfig<NotificationTemplate>(
      endpoint: '/api/v1/admin/notification-templates/list',
      showBackButton: false,
      showTableIcon: false,
      showSearch: true,
      showFilters: true,
      showPagination: true,
      showColumnSearch: true,
      enableSorting: true,
      enableGlobalSearch: true,
      defaultPageSize: 20,
      expandBodyHeightToFitRows: true,
      pageSizeOptions: [10, 20, 50, 100],
      searchFields: ['event_key', 'channel', 'subject', 'body'],
      filterFields: ['event_key', 'channel', 'is_active'],
      columns: [
        NumberColumn(
          'id',
          adminTx(context, 'شناسه', 'ID'),
          width: ColumnWidth.small,
          textAlign: TextAlign.center,
          formatter: (item) {
            final template = item as NotificationTemplate;
            return template.id.toString();
          },
        ),
        TextColumn(
          'event_key',
          adminTx(context, 'کلید رویداد', 'Event key'),
          width: ColumnWidth.medium,
          filterType: ColumnFilterType.text,
          formatter: (item) {
            final template = item as NotificationTemplate;
            return template.eventKey;
          },
        ),
        TextColumn(
          'channel',
          adminTx(context, 'کانال', 'Channel'),
          width: ColumnWidth.small,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: [
            FilterOption(value: 'telegram', label: adminTx(context, 'تلگرام', 'Telegram'), icon: Icons.send),
            FilterOption(value: 'email', label: adminTx(context, 'ایمیل', 'Email'), icon: Icons.email),
            FilterOption(value: 'sms', label: adminTx(context, 'پیامک', 'SMS'), icon: Icons.sms),
            FilterOption(value: 'inapp', label: adminTx(context, 'درون‌برنامه', 'In-app'), icon: Icons.notifications),
          ],
          formatter: (item) {
            final template = item as NotificationTemplate;
            return template.channel;
          },
        ),
        TextColumn(
          'locale',
          adminTx(context, 'زبان', 'Language'),
          width: ColumnWidth.small,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: [
            FilterOption(value: 'fa', label: adminTx(context, 'فارسی', 'Persian')),
            FilterOption(value: 'en', label: adminTx(context, 'انگلیسی', 'English')),
            FilterOption(value: 'ar', label: adminTx(context, 'عربی', 'Arabic')),
            FilterOption(value: 'tr', label: adminTx(context, 'ترکی', 'Turkish')),
          ],
          formatter: (item) => item.locale ?? '-',
        ),
        TextColumn(
          'subject',
          adminTx(context, 'موضوع', 'Subject'),
          width: ColumnWidth.medium,
          formatter: (item) => item.subject ?? '-',
        ),
        CustomColumn(
          'body',
          adminTx(context, 'محتوا', 'Body'),
          width: ColumnWidth.large,
          formatter: (item) {
            final body = item.body;
            return body.length > 100 ? '${body.substring(0, 100)}...' : body;
          },
          builder: (item, index) {
            final body = item.body;
            final preview = body.length > 100 ? '${body.substring(0, 100)}...' : body;
            return InkWell(
              onTap: () => _showBodyDialog(item),
              child: Tooltip(
                message: adminTx(context, 'برای دیدن متن کامل بزنید', 'Tap to read the full text'),
                child: Text(
                  preview,
                  style: TextStyle(
                    color: SemanticColorResolver.info(context),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            );
          },
        ),
        CustomColumn(
          'is_active',
          adminTx(context, 'وضعیت', 'Status'),
          width: ColumnWidth.small,
          formatter: (item) => item.isActive ? adminTx(context, 'فعال', 'Active') : adminTx(context, 'غیرفعال', 'Inactive'),
          builder: (item, index) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item.isActive ? Icons.check_circle : Icons.cancel,
                  color: item.isActive ? SemanticColorResolver.positive(context) : SemanticColorResolver.negative(context),
                  size: 20,
                ),
                SizedBox(width: 4),
                Text(
                  item.isActive ? adminTx(context, 'فعال', 'Active') : adminTx(context, 'غیرفعال', 'Inactive'),
                  style: TextStyle(
                    color: item.isActive ? SemanticColorResolver.positive(context) : SemanticColorResolver.negative(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          },
        ),
        DateColumn(
          'created_at',
          'تاریخ ایجاد',
          width: ColumnWidth.medium,
          showTime: true,
          formatter: (item) {
            final template = item as NotificationTemplate;
            return DataTableUtils.formatDate(
              template.createdAt,
              showTime: true,
            );
          },
        ),
        DateColumn(
          'updated_at',
          'تاریخ به‌روزرسانی',
          width: ColumnWidth.medium,
          showTime: true,
          formatter: (item) {
            final template = item as NotificationTemplate;
            return DataTableUtils.formatDate(
              template.updatedAt,
              showTime: true,
            );
          },
        ),
        ActionColumn(
          'actions',
          adminTx(context, 'عملیات', 'Actions'),
          width: ColumnWidth.small,
          actions: [
            DataTableAction(
              icon: Icons.edit,
              label: adminTx(context, 'ویرایش', 'Edit'),
              onTap: (item) => _openEditDialog(item: item as NotificationTemplate),
            ),
            DataTableAction(
              icon: Icons.delete_outline,
              label: adminTx(context, 'حذف', 'Delete'),
              onTap: (item) => _deleteTemplate(item as NotificationTemplate),
              isDestructive: true,
            ),
          ],
        ),
      ],
      customHeaderActions: [
        FilledButton.icon(
          onPressed: () => _openEditDialog(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('ایجاد قالب جدید'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
      onRefresh: () {
        // Refresh callback - called after data is fetched
      },
    );
  }

  Future<void> _openEditDialog({NotificationTemplate? item}) async {
    final formKey = GlobalKey<FormState>();
    
    // تعیین حالت اولیه بر اساس اینکه آیا کلید در لیست است یا نه
    EventKeyInfo? existingInfo;
    if (item?.eventKey != null) {
      try {
        existingInfo = eventKeysList.firstWhere(
          (e) => e.key == item!.eventKey,
        );
      } catch (e) {
        existingInfo = null;
      }
    }
    
    EventKeyInputMode eventKeyMode = existingInfo != null
        ? EventKeyInputMode.selection
        : EventKeyInputMode.custom;
    String? selectedEventKey = existingInfo?.key;
    EventKeyInfo? selectedEventKeyInfo = existingInfo;
    final customEventKeyCtrl = TextEditingController(
      text: existingInfo == null ? (item?.eventKey ?? '') : '',
    );
    
    String? selectedChannel = item?.channel;
    final localeCtrl = TextEditingController(text: item?.locale ?? '');
    final subjectCtrl = TextEditingController(text: item?.subject ?? '');
    final bodyCtrl = TextEditingController(text: item?.body ?? '');
    final contextCtrl = TextEditingController(text: '{}'); // برای پیش‌نمایش پارامترها
    bool isActive = item?.isActive ?? true;
    
    // گزینه‌های کانال
    final channelOptions = [
      {'value': 'telegram', 'label': adminTx(context, 'تلگرام', 'Telegram'), 'icon': Icons.send},
      {'value': 'email', 'label': adminTx(context, 'ایمیل', 'Email'), 'icon': Icons.email},
      {'value': 'sms', 'label': adminTx(context, 'پیامک', 'SMS'), 'icon': Icons.sms},
      {'value': 'inapp', 'label': adminTx(context, 'درون‌برنامه', 'In-app'), 'icon': Icons.notifications},
    ];
    
    // تابع برای دریافت کلید رویداد نهایی
    String getEventKey() {
      if (eventKeyMode == EventKeyInputMode.selection) {
        return selectedEventKey ?? '';
      } else {
        return customEventKeyCtrl.text.trim();
      }
    }

    await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              child: Container(
                width: 700,
                constraints: const BoxConstraints(maxHeight: 800),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          item == null ? Icons.add_circle_outline : Icons.edit_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          item == null ? adminTx(context, 'قالب جدید', 'New template') : adminTx(context, 'ویرایش قالب', 'Edit template'),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // فیلد کلید رویداد
                              DropdownButtonFormField<String>(
                                value: eventKeyMode == EventKeyInputMode.selection
                                    ? selectedEventKey
                                    : 'custom',
                                decoration: InputDecoration(
                                  labelText: adminTx(context, 'کلید رویداد *', 'Event key *'),
                                  prefixIcon: Icon(Icons.key),
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  // کلیدهای از پیش تعریف‌شده
                                  ...eventKeysList.map((info) {
                                    return DropdownMenuItem<String>(
                                      value: info.key,
                                      child: Row(
                                        children: [
                                          Icon(info.icon, size: 20),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(info.title),
                                                Text(
                                                  info.key,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  // جداکننده
                                  const DropdownMenuItem<String>(
                                    value: 'separator',
                                    enabled: false,
                                    child: Divider(),
                                  ),
                                  // گزینه کاستوم
                                  const DropdownMenuItem<String>(
                                    value: 'custom',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 20),
                                        SizedBox(width: 8),
                                        Text('سفارشی (Custom)'),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    if (value == 'custom') {
                                      eventKeyMode = EventKeyInputMode.custom;
                                      selectedEventKey = null;
                                      selectedEventKeyInfo = null;
                                    } else if (value != null && value != 'separator') {
                                      eventKeyMode = EventKeyInputMode.selection;
                                      selectedEventKey = value;
                                      selectedEventKeyInfo = eventKeysList.firstWhere(
                                        (e) => e.key == value,
                                      );
                                      customEventKeyCtrl.clear();
                                    }
                                  });
                                },
                                validator: (v) {
                                  if (eventKeyMode == EventKeyInputMode.selection) {
                                    return selectedEventKey == null || selectedEventKey!.isEmpty
                                        ? 'لطفاً یک کلید رویداد انتخاب کنید'
                                        : null;
                                  } else {
                                    return customEventKeyCtrl.text.trim().isEmpty
                                        ? 'لطفاً کلید رویداد را وارد کنید'
                                        : null;
                                  }
                                },
                              ),
                              // TextField برای حالت کاستوم
                              if (eventKeyMode == EventKeyInputMode.custom) ...[
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: customEventKeyCtrl,
                                  decoration: InputDecoration(
                                    labelText: adminTx(context, 'کلید رویداد سفارشی *', 'Custom event key *'),
                                    hintText: 'مثال: invoice.payment_received',
                                    prefixIcon: Icon(Icons.edit),
                                    border: OutlineInputBorder(),
                                    helperText: adminTx(context, 'فرمت category.event_name', 'Format: category.event_name'),
                                  ),
                                  textDirection: TextDirection.ltr,
                                  textAlign: TextAlign.left,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return adminTx(context, 'الزامی', 'Required');
                                    }
                                    final trimmed = v.trim();
                                    if (trimmed.length > 100) {
                                      return adminTx(context, 'حداکثر ۱۰۰ نویسه', 'At most 100 characters');
                                    }
                                    if (!trimmed.contains('.')) {
                                      return adminTx(context, 'باید به شکل category.event_name باشد', 'Must look like category.event_name');
                                    }
                                    if (!RegExp(r'^[a-z0-9_]+\.[a-z0-9_]+$').hasMatch(trimmed)) {
                                      return adminTx(context, 'فقط حروف کوچک، عدد و زیرخط', 'Only lowercase letters, numbers, and underscore');
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                Card(
                                  color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          color: Theme.of(context).colorScheme.error,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'توجه: برای کلیدهای سفارشی راهنمایی موجود نیست. '
                                            'مطمئن شوید که کلید را به درستی وارد کرده‌اید و '
                                            'پارامترهای مورد نیاز را می‌شناسید.',
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.onErrorContainer,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              // کارت راهنمایی برای کلیدهای از پیش تعریف‌شده
                              if (eventKeyMode == EventKeyInputMode.selection &&
                                  selectedEventKeyInfo != null)
                                Builder(
                                  builder: (context) {
                                    final info = selectedEventKeyInfo!;
                                    return Column(
                                      children: [
                                        const SizedBox(height: 16),
                                        Card(
                                          color: Theme.of(context).colorScheme.surfaceVariant,
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Icon(
                                                      info.icon,
                                                      color: Theme.of(context).colorScheme.primary,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        info.title,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleMedium
                                                            ?.copyWith(
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                const Text(
                                                  'توضیحات:',
                                                  style: TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                                Text(info.description),
                                                const SizedBox(height: 12),
                                                const Text(
                                                  '⏰ زمان ارسال:',
                                                  style: TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                                Text(info.when),
                                                const SizedBox(height: 12),
                                                const Text(
                                                  '👤 گیرنده:',
                                                  style: TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                                Text(info.recipient),
                                                if (info.availableParams.isNotEmpty) ...[
                                                  const SizedBox(height: 12),
                                                  const Text(
                                                    '📝 پارامترهای موجود:',
                                                    style: TextStyle(fontWeight: FontWeight.bold),
                                                  ),
                                                  ...info.availableParams.map((param) {
                                                    return Padding(
                                                      padding: const EdgeInsets.only(left: 16, top: 4),
                                                      child: Row(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          const Text('• '),
                                                          Expanded(
                                                            child: RichText(
                                                              text: TextSpan(
                                                                style: DefaultTextStyle.of(context).style,
                                                                children: [
                                                                  TextSpan(
                                                                    text: '$param: ',
                                                                    style: const TextStyle(
                                                                      fontWeight: FontWeight.w500,
                                                                    ),
                                                                  ),
                                                                  TextSpan(
                                                                    text: info.paramExamples[param] ??
                                                                        '(بدون مثال)',
                                                                    style: TextStyle(
                                                                      fontFamily: 'monospace',
                                                                      color: Theme.of(context)
                                                                          .colorScheme
                                                                          .primary,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  }),
                                                  const SizedBox(height: 12),
                                                  const Text(
                                                    '💡 مثال استفاده در قالب:',
                                                    style: TextStyle(fontWeight: FontWeight.bold),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Container(
                                                    padding: const EdgeInsets.all(12),
                                                    decoration: BoxDecoration(
                                                      color: Theme.of(context).colorScheme.surface,
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .outline
                                                            .withOpacity(0.3),
                                                      ),
                                                    ),
                                                    child: SelectableText(
                                                      buildExampleTemplate(info),
                                                      style: const TextStyle(fontFamily: 'monospace'),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              const SizedBox(height: 16),
                              // فیلد کانال
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: selectedChannel,
                                      decoration: InputDecoration(
                                        labelText: adminTx(context, 'کانال *', 'Channel *'),
                                        hintText: adminTx(context, 'انتخاب کانال', 'Choose a channel'),
                                        prefixIcon: Icon(Icons.send),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: channelOptions.map((option) {
                                        return DropdownMenuItem<String>(
                                          value: option['value'] as String,
                                          child: Row(
                                            children: [
                                              Icon(
                                                option['icon'] as IconData,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(option['label'] as String),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          selectedChannel = value;
                                        });
                                      },
                                      validator: (v) {
                                        if (v == null || v.isEmpty) return adminTx(context, 'الزامی', 'Required');
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: localeCtrl,
                                      decoration: InputDecoration(
                                        labelText: adminTx(context, 'زبان (اختیاری)', 'Language (optional)'),
                                        hintText: 'fa|en|ar|tr',
                                        prefixIcon: Icon(Icons.language),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextFormField(
                                      controller: subjectCtrl,
                                      decoration: InputDecoration(
                                        labelText: adminTx(context, 'موضوع (اختیاری)', 'Subject (optional)'),
                                        hintText: 'موضوع ناتیفیکیشن',
                                        prefixIcon: Icon(Icons.subject),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: bodyCtrl,
                                decoration: InputDecoration(
                                  labelText: adminTx(context, 'محتوا *', 'Body *'),
                                  hintText: adminTx(context, 'متن با الگوی Jinja2', 'Text using a Jinja2 template'),
                                  prefixIcon: Icon(Icons.text_fields),
                                  border: OutlineInputBorder(),
                                  alignLabelWithHint: true,
                                ),
                                minLines: 6,
                                maxLines: 12,
                                validator: (v) => (v == null || v.isEmpty) ? adminTx(context, 'الزامی', 'Required') : null,
                              ),
                              const SizedBox(height: 16),
                              Card(
                                color: Theme.of(context).colorScheme.surfaceVariant,
                                child: SwitchListTile(
                                  title: Text(adminTx(context, 'فعال', 'Active')),
                                  subtitle: Text(adminTx(context, 'این قالب برای ارسال استفاده می‌شود', 'This template is used for sending')),
                                  value: isActive,
                                  onChanged: (v) {
                                    setState(() {
                                      isActive = v;
                                    });
                                  },
                                  secondary: Icon(
                                    isActive ? Icons.check_circle : Icons.cancel,
                                    color: isActive ? SemanticColorResolver.positive(context) : SemanticColorResolver.negative(context),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ExpansionTile(
                                title: Text(adminTx(context, 'پارامترهای پیش‌نمایش', 'Preview parameters')),
                                subtitle: Text(adminTx(context, 'برای آزمودن قالب با مقدارهای نمونه', 'Try the template with sample values')),
                                leading: const Icon(Icons.settings_input_component, size: 20),
                                initiallyExpanded: false,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'پارامترها (JSON):',
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 8),
                                        TextFormField(
                                          controller: contextCtrl,
                                          decoration: InputDecoration(
                                            hintText: '{"code": "31524", "user_name": "علی"}',
                                            prefixIcon: const Icon(Icons.code),
                                            border: const OutlineInputBorder(),
                                            helperText: 'برای مثال: {"code": "31524", "user_name": "علی"}',
                                          ),
                                          minLines: 4,
                                          maxLines: 8,
                                          style: const TextStyle(fontFamily: 'monospace'),
                                          textDirection: TextDirection.ltr,
                                          textAlign: TextAlign.left,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  try {
                                    // Parse کردن JSON context
                                    Map<String, dynamic> previewContext = const <String, dynamic>{};
                                    try {
                                      if (contextCtrl.text.trim().isNotEmpty) {
                                        previewContext = Map<String, dynamic>.from(
                                          jsonDecode(contextCtrl.text.trim()) as Map,
                                        );
                                      }
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      SnackBarHelper.showError(
                                        context,
                                        message:
                                            'خطا در فرمت JSON: ${ErrorExtractor.forContext(e, context)}',
                                      );
                                      return;
                                    }

                                    final res = await _svc.preview(
                                      channel: selectedChannel ?? '',
                                      subject: subjectCtrl.text.trim().isEmpty
                                          ? null
                                          : subjectCtrl.text.trim(),
                                      body: bodyCtrl.text,
                                      context: previewContext,
                                    );
                                    if (!context.mounted) return;
                                    await _showPreviewDialog(res);
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    SnackBarHelper.showError(
                                      context,
                                      message:
                                          'خطا در پیش‌نمایش: ${ErrorExtractor.forContext(e, context)}',
                                    );
                                  }
                                },
                                icon: const Icon(Icons.visibility, size: 18),
                                label: const Text('پیش‌نمایش قالب'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(adminTx(context, 'انصراف', 'Cancel')),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            try {
                              final eventKey = getEventKey();
                              if (item == null) {
                                await _svc.create(
                                  eventKey: eventKey,
                                  channel: selectedChannel ?? '',
                                  locale: localeCtrl.text.trim().isEmpty
                                      ? null
                                      : localeCtrl.text.trim(),
                                  subject: subjectCtrl.text.trim().isEmpty
                                      ? null
                                      : subjectCtrl.text.trim(),
                                  body: bodyCtrl.text,
                                  isActive: isActive,
                                );
                              } else {
                                await _svc.update(
                                  id: item.id,
                                  eventKey: eventKey,
                                  channel: selectedChannel ?? '',
                                  locale: localeCtrl.text.trim().isEmpty
                                      ? null
                                      : localeCtrl.text.trim(),
                                  subject: subjectCtrl.text.trim().isEmpty
                                      ? null
                                      : subjectCtrl.text.trim(),
                                  body: bodyCtrl.text,
                                  isActive: isActive,
                                );
                              }
                              if (!context.mounted) return;
                              Navigator.of(context).pop(true);
                              if (mounted) {
                                SnackBarHelper.showSuccess(
                                  context,
                                  message: item == null ? 'قالب با موفقیت ایجاد شد' : 'قالب با موفقیت به‌روزرسانی شد',
                                );
                                // Refresh table by calling refresh method
                                final state = _tableKey.currentState;
                                if (state != null) {
                                  (state as dynamic).refresh();
                                }
                              }
                            } catch (e) {
                              if (!context.mounted) return;
                              SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
                            }
                          },
                          icon: const Icon(Icons.save, size: 18),
                          label: Text(adminTx(context, 'ذخیره', 'Save')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteTemplate(NotificationTemplate item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: SemanticColorResolver.warning(dialogContext), size: 40),
        title: Text(adminTx(context, 'حذف قالب', 'Delete template')),
        content: Text(adminTx(
          context,
          'قالب «${item.eventKey}» (${item.channel}) حذف شود؟ این کار برگشت‌پذیر نیست.',
          'Delete the “${item.eventKey}” (${item.channel}) template? This cannot be undone.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(adminTx(context, 'انصراف', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: SemanticColorResolver.negative(dialogContext)),
            child: Text(adminTx(context, 'حذف', 'Delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _svc.delete(item.id);
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: adminTx(context, 'قالب حذف شد', 'Template deleted'));
        // Refresh table by calling refresh method
        final state = _tableKey.currentState;
        if (state != null) {
          (state as dynamic).refresh();
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
      }
    }
  }

  Future<void> _showBodyDialog(NotificationTemplate item) async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 700,
          constraints: const BoxConstraints(maxHeight: 600),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.description, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'محتوا',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 32),
              if (item.subject != null && item.subject!.isNotEmpty) ...[
                Text(
                  'موضوع:',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(item.subject!),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                'محتوا:',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      item.body,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('بستن'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPreviewDialog(Map<String, dynamic> preview) async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 700,
          constraints: const BoxConstraints(maxHeight: 600),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.preview, size: 28, color: SemanticColorResolver.info(context)),
                  const SizedBox(width: 12),
                  Text(
                    'پیش‌نمایش قالب',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 32),
              Text(
                'کانال: ${preview['channel'] ?? ''}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if ((preview['subject'] ?? '').toString().isNotEmpty) ...[
                Text(
                  'موضوع:',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(preview['subject']?.toString() ?? ''),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                'محتوا:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      preview['body']?.toString() ?? '',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('بستن'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
