import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/auth_store.dart';
import '../../services/catalog_spec_field_service.dart';
import '../../services/list_filter_preferences_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/permission/permission_widgets.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

class CatalogSpecFieldItem {
  final int id;
  final int businessId;
  final String title;
  final String? description;
  final String dataType;
  final List<String>? options;
  final int sortOrder;
  final bool isRequired;
  final bool isActive;

  CatalogSpecFieldItem({
    required this.id,
    required this.businessId,
    required this.title,
    this.description,
    this.dataType = 'text',
    this.options,
    this.sortOrder = 0,
    this.isRequired = false,
    this.isActive = true,
  });

  factory CatalogSpecFieldItem.fromJson(Map<String, dynamic> json) {
    List<String>? optionsList;
    final optionsRaw = json['options'];
    if (optionsRaw is List) {
      optionsList = optionsRaw.map((e) => e.toString()).toList();
    } else if (optionsRaw is Map) {
      final items = optionsRaw['items'];
      if (items is List) {
        optionsList = items.map((e) => e.toString()).toList();
      }
    }
    return CatalogSpecFieldItem(
      id: json['id'] as int,
      businessId: json['business_id'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
      dataType: json['data_type'] as String? ?? 'text',
      options: optionsList,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isRequired: json['is_required'] == true,
      isActive: json['is_active'] != false,
    );
  }
}

class CatalogSpecFieldsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const CatalogSpecFieldsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<CatalogSpecFieldsPage> createState() => _CatalogSpecFieldsPageState();
}

class _CatalogSpecFieldsPageState extends State<CatalogSpecFieldsPage> {
  final _service = CatalogSpecFieldService();
  final GlobalKey _tableKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!widget.authStore.hasBusinessPermission('products', 'view')) {
      return const AccessDeniedPage();
    }

    return Scaffold(
      body: SingleChildScrollView(
        child: DataTableWidget<CatalogSpecFieldItem>(
          key: _tableKey,
          config: _buildConfig(t),
          fromJson: CatalogSpecFieldItem.fromJson,
        ),
      ),
    );
  }

  void _refreshTable() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = _tableKey.currentState;
      if (state != null) {
        // ignore: avoid_dynamic_calls
        (state as dynamic).refresh();
      }
    });
  }

  DataTableConfig<CatalogSpecFieldItem> _buildConfig(AppLocalizations t) {
    return DataTableConfig<CatalogSpecFieldItem>(
      endpoint: '/api/v1/catalog-spec-fields/business/${widget.businessId}/search',
      businessId: widget.businessId,
      persistTableFiltersPageId: ListFilterPageIds.catalogSpecFieldsTable,
      title: 'قالب‌های مشخصات شبکهٔ تأمین',
      showBackButton: true,
      onBack: () {
        if (context.canPop()) context.pop();
      },
      showTableIcon: false,
      columns: [
        TextColumn('title', t.title, width: ColumnWidth.large, formatter: (e) => e.title),
        TextColumn('description', t.description, width: ColumnWidth.extraLarge, formatter: (e) => e.description ?? '-'),
        TextColumn('data_type', 'نوع', width: ColumnWidth.medium, formatter: (e) => _formatDataType(e.dataType)),
        TextColumn('options', 'گزینه‌ها', width: ColumnWidth.large, formatter: (e) => _formatOptions(e.options)),
        TextColumn('sort_order', 'ترتیب', width: ColumnWidth.small, formatter: (e) => e.sortOrder.toString()),
        TextColumn('is_required', 'اجباری', width: ColumnWidth.small, formatter: (e) => e.isRequired ? 'بله' : 'خیر'),
        TextColumn('is_active', t.status, width: ColumnWidth.small, formatter: (e) => e.isActive ? t.active : t.inactive),
        ActionColumn('actions', t.actions, actions: [
          DataTableAction(icon: Icons.edit, label: t.edit, onTap: (e) => _openForm(editing: e)),
          DataTableAction(icon: Icons.delete, label: t.delete, color: SemanticColorResolver.negative(context), onTap: (e) => _confirmDelete(e)),
        ]),
      ],
      searchFields: ['title', 'description'],
      defaultPageSize: 20,
      expandBodyHeightToFitRows: true,
      customHeaderActions: [
        PermissionButton(
          section: 'products',
          action: 'edit',
          authStore: widget.authStore,
          child: Tooltip(
            message: 'افزودن قالب فیلد',
            child: IconButton(onPressed: () => _openForm(), icon: const Icon(Icons.add)),
          ),
        ),
      ],
    );
  }

  static String _formatDataType(String dataType) {
    switch (dataType) {
      case 'text':
        return 'متن';
      case 'number':
        return 'عدد';
      case 'date':
        return 'تاریخ';
      case 'select':
        return 'انتخابی';
      case 'boolean':
        return 'بله/خیر';
      default:
        return dataType;
    }
  }

  static String _formatOptions(List<String>? options) {
    if (options == null || options.isEmpty) return '-';
    return options.join('، ');
  }

  Future<void> _openForm({CatalogSpecFieldItem? editing}) async {
    final t = AppLocalizations.of(context);
    final titleCtrl = TextEditingController(text: editing?.title ?? '');
    final descCtrl = TextEditingController(text: editing?.description ?? '');
    final sortCtrl = TextEditingController(text: (editing?.sortOrder ?? 0).toString());
    String? selectedDataType = editing?.dataType ?? 'text';
    var isRequired = editing?.isRequired ?? false;
    var isActive = editing?.isActive ?? true;
    final optionControllers = <TextEditingController>[];
    if (editing?.options != null) {
      for (final o in editing!.options!) {
        optionControllers.add(TextEditingController(text: o));
      }
    }
    if (optionControllers.isEmpty && selectedDataType == 'select') {
      optionControllers.add(TextEditingController());
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(editing == null ? 'قالب فیلد جدید' : t.edit),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: titleCtrl, decoration: InputDecoration(labelText: '${t.title} *')),
                  const SizedBox(height: 8),
                  TextField(controller: descCtrl, decoration: InputDecoration(labelText: t.description), maxLines: 2),
                  const SizedBox(height: 8),
                  TextField(controller: sortCtrl, decoration: const InputDecoration(labelText: 'ترتیب نمایش'), keyboardType: TextInputType.number),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedDataType,
                    decoration: const InputDecoration(labelText: 'نوع داده'),
                    items: const [
                      DropdownMenuItem(value: 'text', child: Text('متن')),
                      DropdownMenuItem(value: 'number', child: Text('عدد')),
                      DropdownMenuItem(value: 'date', child: Text('تاریخ')),
                      DropdownMenuItem(value: 'select', child: Text('انتخابی')),
                      DropdownMenuItem(value: 'boolean', child: Text('بله/خیر')),
                    ],
                    onChanged: (v) => setLocal(() {
                      selectedDataType = v ?? 'text';
                      if (selectedDataType == 'select' && optionControllers.isEmpty) {
                        optionControllers.add(TextEditingController());
                      }
                    }),
                  ),
                  if (selectedDataType == 'select') ...[
                    const SizedBox(height: 8),
                    ...optionControllers.asMap().entries.map((e) {
                      return Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: e.value,
                              decoration: InputDecoration(labelText: 'گزینه ${e.key + 1}'),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: optionControllers.length > 1
                                ? () => setLocal(() {
                                      e.value.dispose();
                                      optionControllers.removeAt(e.key);
                                    })
                                : null,
                          ),
                        ],
                      );
                    }),
                    TextButton.icon(
                      onPressed: () => setLocal(() => optionControllers.add(TextEditingController())),
                      icon: const Icon(Icons.add),
                      label: const Text('گزینه'),
                    ),
                  ],
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('اجباری هنگام انتشار در شبکهٔ تأمین'),
                    value: isRequired,
                    onChanged: (v) => setLocal(() => isRequired = v == true),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.active),
                    value: isActive,
                    onChanged: (v) => setLocal(() => isActive = v != false),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
          ],
        ),
      ),
    );
    if (saved != true) return;

    final title = titleCtrl.text.trim();
    if (title.isEmpty) {
      if (mounted) SnackBarHelper.showError(context, message: 'عنوان الزامی است');
      return;
    }
    final options = selectedDataType == 'select'
        ? optionControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList()
        : null;
    if (selectedDataType == 'select' && (options == null || options.isEmpty)) {
      if (mounted) SnackBarHelper.showError(context, message: 'حداقل یک گزینه برای نوع انتخابی لازم است');
      return;
    }
    final sortOrder = int.tryParse(sortCtrl.text.trim()) ?? 0;

    try {
      if (editing == null) {
        await _service.create(
          businessId: widget.businessId,
          title: title,
          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
          dataType: selectedDataType ?? 'text',
          options: options,
          sortOrder: sortOrder,
          isRequired: isRequired,
        );
      } else {
        await _service.update(
          businessId: widget.businessId,
          fieldId: editing.id,
          title: title,
          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
          dataType: selectedDataType,
          options: options,
          sortOrder: sortOrder,
          isRequired: isRequired,
          isActive: isActive,
        );
      }
      _refreshTable();
      if (mounted) SnackBarHelper.showSuccess(context, message: t.savedSuccessfully);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _confirmDelete(CatalogSpecFieldItem item) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.delete),
        content: Text('قالب «${item.title}» حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.delete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.delete(businessId: widget.businessId, fieldId: item.id);
      _refreshTable();
      if (mounted) SnackBarHelper.showSuccess(context, message: t.deletedSuccessfully);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }
}
