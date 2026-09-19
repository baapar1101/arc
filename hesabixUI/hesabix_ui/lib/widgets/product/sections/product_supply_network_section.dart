import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../controllers/product_form_controller.dart';
import '../../../models/business_models.dart';
import '../../../models/catalog_specification_item.dart';
import '../../../models/product_form_data.dart';
import '../../../services/business_api_service.dart';
import '../../../services/catalog_spec_field_service.dart';
import '../../../utils/catalog_business_contact_validator.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/snackbar_helper.dart';
import '../catalog_gallery_editor.dart';
import '../catalog_html_editor.dart';

class ProductSupplyNetworkSection extends StatefulWidget {
  final int businessId;
  final ProductFormData formData;
  final ValueChanged<ProductFormData> onChanged;
  final ProductFormController? controller;
  final AuthStore authStore;

  const ProductSupplyNetworkSection({
    super.key,
    required this.businessId,
    required this.formData,
    required this.onChanged,
    required this.authStore,
    this.controller,
  });

  @override
  State<ProductSupplyNetworkSection> createState() => _ProductSupplyNetworkSectionState();
}

class _ProductSupplyNetworkSectionState extends State<ProductSupplyNetworkSection> {
  final _specFieldService = CatalogSpecFieldService();
  bool _loadingTemplates = false;
  bool _templatesExpanded = false;
  bool _loadingBusinessContact = false;
  List<String> _businessContactWarnings = const [];

  bool get _canEditProducts => widget.authStore.hasBusinessPermission('products', 'edit');

  void _update(ProductFormData data) => widget.onChanged(data);

  List<Map<String, dynamic>> get _templates => widget.controller?.catalogSpecFields ?? const [];

  @override
  void initState() {
    super.initState();
    _ensureTemplateRows();
    if (widget.formData.isPublicCatalog) {
      _loadBusinessContactInfo();
    }
  }

  @override
  void didUpdateWidget(covariant ProductSupplyNetworkSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.formData.isPublicCatalog != widget.formData.isPublicCatalog) {
      if (widget.formData.isPublicCatalog) {
        _loadBusinessContactInfo();
        _ensureTemplateRows();
      } else {
        setState(() => _businessContactWarnings = const []);
      }
    }
    if (oldWidget.controller?.catalogSpecFields != widget.controller?.catalogSpecFields) {
      _ensureTemplateRows();
    }
  }

  Future<void> _loadBusinessContactInfo() async {
    setState(() => _loadingBusinessContact = true);
    try {
      final business = await BusinessApiService.getBusiness(widget.businessId);
      if (!mounted) return;
      setState(() {
        _businessContactWarnings = _buildBusinessContactWarnings(business);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _businessContactWarnings = const [
          'بارگذاری اطلاعات تماس کسب‌وکار ناموفق بود. قبل از انتشار، تنظیمات کسب‌وکار را بررسی کنید.',
        ];
      });
    } finally {
      if (mounted) setState(() => _loadingBusinessContact = false);
    }
  }

  List<String> _buildBusinessContactWarnings(BusinessResponse business) {
    return CatalogBusinessContactValidator.warnings(business);
  }

  Widget _buildBusinessContactWarningBanner() {
    if (!widget.formData.isPublicCatalog) return const SizedBox.shrink();
    final theme = Theme.of(context);
    if (_loadingBusinessContact) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'در حال بررسی اطلاعات تماس کسب‌وکار…',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );
    }
    if (_businessContactWarnings.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: theme.colorScheme.error,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'اطلاعات تماس کسب‌وکار برای نمایش در شبکهٔ تأمین ناقص است',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._businessContactWarnings.map(
                (w) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $w',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () => context.push(
                    context.businessPanelUrl(widget.businessId, 'settings/business'),
                  ),
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('تکمیل اطلاعات کسب‌وکار'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _ensureTemplateRows() {
    if (!widget.formData.isPublicCatalog || _templates.isEmpty) return;
    final existingByFieldId = <int, CatalogSpecificationItem>{};
    final customRows = <CatalogSpecificationItem>[];
    for (final row in widget.formData.catalogSpecifications) {
      if (row.fieldId != null) {
        existingByFieldId[row.fieldId!] = row;
      } else {
        customRows.add(row);
      }
    }

    final merged = <CatalogSpecificationItem>[];
    for (final tpl in _templates) {
      final id = (tpl['id'] as num?)?.toInt();
      if (id == null) continue;
      final title = (tpl['title'] ?? '').toString();
      final sortOrder = (tpl['sort_order'] as num?)?.toInt() ?? 0;
      merged.add(
        existingByFieldId[id] ??
            CatalogSpecificationItem(
              fieldId: id,
              label: title,
              sortOrder: sortOrder,
            ),
      );
    }
    merged.addAll(customRows);
    merged.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final changed = merged.length != widget.formData.catalogSpecifications.length ||
        !_listsEqual(merged, widget.formData.catalogSpecifications);
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _update(widget.formData.copyWith(catalogSpecifications: merged));
      });
    }
  }

  bool _listsEqual(List<CatalogSpecificationItem> a, List<CatalogSpecificationItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].fieldId != b[i].fieldId ||
          a[i].label != b[i].label ||
          a[i].value != b[i].value) {
        return false;
      }
    }
    return true;
  }

  Future<void> _reloadTemplates() async {
    setState(() => _loadingTemplates = true);
    try {
      await widget.controller?.refreshCatalogSpecFields();
      _ensureTemplateRows();
    } finally {
      if (mounted) setState(() => _loadingTemplates = false);
    }
  }

  Future<void> _addTemplateField() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var isRequired = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('فیلد مشخصات جدید'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'عنوان فیلد *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'راهنما (اختیاری)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('اجباری هنگام انتشار'),
                  value: isRequired,
                  onChanged: (v) => setLocal(() => isRequired = v == true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ذخیره')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) {
      if (mounted) SnackBarHelper.showError(context, message: 'عنوان فیلد الزامی است');
      return;
    }
    try {
      await _specFieldService.create(
        businessId: widget.businessId,
        title: title,
        description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        isRequired: isRequired,
        sortOrder: _templates.length,
      );
      await _reloadTemplates();
      if (mounted) SnackBarHelper.showSuccess(context, message: 'فیلد مشخصات ثبت شد');
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: e.toString());
    }
  }

  void _updateSpecValue(int index, String value) {
    final rows = List<CatalogSpecificationItem>.from(widget.formData.catalogSpecifications);
    if (index < 0 || index >= rows.length) return;
    rows[index] = rows[index].copyWith(value: value);
    _update(widget.formData.copyWith(catalogSpecifications: rows));
  }

  void _addCustomSpecRow() {
    final rows = List<CatalogSpecificationItem>.from(widget.formData.catalogSpecifications);
    rows.add(CatalogSpecificationItem(label: '', sortOrder: rows.length));
    _update(widget.formData.copyWith(catalogSpecifications: rows));
  }

  void _removeSpecRow(int index) {
    final rows = List<CatalogSpecificationItem>.from(widget.formData.catalogSpecifications);
    if (index < 0 || index >= rows.length) return;
    final row = rows[index];
    if (row.fieldId != null) {
      final tpl = _templates.cast<Map<String, dynamic>?>().firstWhere(
            (t) => (t?['id'] as num?)?.toInt() == row.fieldId,
            orElse: () => null,
          );
      if (tpl != null && tpl['is_required'] == true) {
        SnackBarHelper.showError(context, message: 'فیلد اجباری قابل حذف نیست');
        return;
      }
    }
    rows.removeAt(index);
    _update(widget.formData.copyWith(catalogSpecifications: rows));
  }

  void _updateCustomSpecLabel(int index, String label) {
    final rows = List<CatalogSpecificationItem>.from(widget.formData.catalogSpecifications);
    if (index < 0 || index >= rows.length) return;
    rows[index] = rows[index].copyWith(label: label);
    _update(widget.formData.copyWith(catalogSpecifications: rows));
  }

  Widget _buildSpecInput(int index, CatalogSpecificationItem row, Map<String, dynamic>? template) {
    final dataType = (template?['data_type'] ?? 'text').toString();
    final options = template?['options'];
    List<String> selectOptions = const [];
    if (options is List) {
      selectOptions = options.map((e) => e.toString()).toList();
    }

    if (dataType == 'boolean') {
      final checked = row.value == 'true' || row.value == '1';
      return CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(row.label),
        value: checked,
        onChanged: (v) => _updateSpecValue(index, v == true ? 'true' : 'false'),
      );
    }

    if (dataType == 'select' && selectOptions.isNotEmpty) {
      return DropdownButtonFormField<String>(
        value: row.value.isEmpty ? null : row.value,
        decoration: InputDecoration(labelText: row.label),
        items: selectOptions
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: (v) => _updateSpecValue(index, v ?? ''),
      );
    }

    return TextFormField(
      initialValue: row.value,
      decoration: InputDecoration(
        labelText: row.label.isEmpty ? 'عنوان مشخصه' : row.label,
        helperText: template?['description']?.toString(),
      ),
      keyboardType: dataType == 'number' ? TextInputType.number : TextInputType.text,
      onChanged: (v) => _updateSpecValue(index, v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final spacing = ResponsiveHelper.getGridSpacing(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('شبکهٔ تأمین کالا'),
          subtitle: Text(t.productPublicCatalogSubtitle),
          value: widget.formData.isPublicCatalog,
          onChanged: (v) {
            _update(widget.formData.copyWith(isPublicCatalog: v));
            if (v) {
              _loadBusinessContactInfo();
            } else {
              setState(() => _businessContactWarnings = const []);
            }
          },
        ),
        _buildBusinessContactWarningBanner(),
        if (!widget.formData.isPublicCatalog) ...[
          SizedBox(height: spacing),
          Text(
            'برای تکمیل پروفایل کاتالوگ (بررسی تخصصی، مشخصات فنی و …) ابتدا انتشار در شبکهٔ تأمین را فعال کنید.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (widget.formData.isPublicCatalog) ...[
          SizedBox(height: spacing * 2),
          Text('پروفایل کاتالوگ', style: theme.textTheme.titleSmall),
          SizedBox(height: spacing),
          TextFormField(
            initialValue: widget.formData.catalogShortDescription ?? '',
            decoration: const InputDecoration(
              labelText: 'خلاصه کوتاه',
              helperText: 'متن کوتاه برای کارت و لیست کاتالوگ',
            ),
            maxLines: 2,
            onChanged: (v) => _update(
              widget.formData.copyWith(
                catalogShortDescription: v.trim().isEmpty ? null : v,
              ),
            ),
          ),
          SizedBox(height: spacing),
          CatalogHtmlEditor(
            initialValue: widget.formData.catalogExpertReview,
            label: 'بررسی تخصصی',
            helperText: 'متن غنی با قالب‌بندی HTML برای نمایش در شبکهٔ تأمین',
            onChanged: (v) => _update(widget.formData.copyWith(catalogExpertReview: v)),
          ),
          SizedBox(height: spacing * 2),
          CatalogGalleryEditor(
            businessId: widget.businessId,
            fileIds: widget.formData.catalogGalleryFileIds,
            onChanged: (ids) => _update(widget.formData.copyWith(catalogGalleryFileIds: ids)),
          ),
          SizedBox(height: spacing * 2),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: widget.formData.catalogBrand ?? '',
                  decoration: const InputDecoration(labelText: 'برند'),
                  onChanged: (v) => _update(
                    widget.formData.copyWith(catalogBrand: v.trim().isEmpty ? null : v),
                  ),
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: TextFormField(
                  initialValue: widget.formData.catalogModel ?? '',
                  decoration: const InputDecoration(labelText: 'مدل'),
                  onChanged: (v) => _update(
                    widget.formData.copyWith(catalogModel: v.trim().isEmpty ? null : v),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing),
          TextFormField(
            initialValue: widget.formData.catalogCountryOfOrigin ?? '',
            decoration: const InputDecoration(labelText: 'کشور سازنده'),
            onChanged: (v) => _update(
              widget.formData.copyWith(
                catalogCountryOfOrigin: v.trim().isEmpty ? null : v,
              ),
            ),
          ),
          SizedBox(height: spacing),
          TextFormField(
            initialValue: widget.formData.catalogVideoUrl ?? '',
            decoration: const InputDecoration(
              labelText: 'لینک ویدیو معرفی',
              helperText: 'آدرس YouTube، Aparat یا سایر سرویس‌ها',
            ),
            onChanged: (v) => _update(
              widget.formData.copyWith(catalogVideoUrl: v.trim().isEmpty ? null : v),
            ),
          ),
          SizedBox(height: spacing * 2),
          Row(
            children: [
              Text('مشخصات فنی', style: theme.textTheme.titleSmall),
              const Spacer(),
              if (_canEditProducts)
                TextButton.icon(
                  onPressed: _loadingTemplates ? null : _addTemplateField,
                  icon: const Icon(Icons.add_outlined, size: 18),
                  label: const Text('قالب فیلد'),
                ),
              if (_canEditProducts)
                TextButton.icon(
                  onPressed: () => context.push(
                    context.businessPanelUrl(widget.businessId, 'catalog-spec-fields'),
                  ),
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('مدیریت قالب‌ها'),
                ),
              TextButton.icon(
                onPressed: _addCustomSpecRow,
                icon: const Icon(Icons.playlist_add_outlined, size: 18),
                label: const Text('ردیف سفارشی'),
              ),
            ],
          ),
          if (_canEditProducts) ...[
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('مدیریت قالب‌های مشخصات'),
              subtitle: Text('${_templates.length} فیلد تعریف‌شده'),
              initiallyExpanded: _templatesExpanded,
              onExpansionChanged: (v) => setState(() => _templatesExpanded = v),
              children: [
                if (_loadingTemplates)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_templates.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('هنوز قالب فیلدی تعریف نشده. با «قالب فیلد» می‌توانید فیلدهای استاندارد بسازید.'),
                  )
                else
                  ..._templates.map((tpl) {
                    final id = (tpl['id'] as num).toInt();
                    final required = tpl['is_required'] == true;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(tpl['title']?.toString() ?? ''),
                      subtitle: Text(
                        [
                          tpl['data_type']?.toString() ?? 'text',
                          if (required) 'اجباری',
                        ].join(' · '),
                      ),
                      trailing: required
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                try {
                                  await _specFieldService.delete(
                                    businessId: widget.businessId,
                                    fieldId: id,
                                  );
                                  await _reloadTemplates();
                                } catch (e) {
                                  if (mounted) SnackBarHelper.showError(context, message: e.toString());
                                }
                              },
                            ),
                    );
                  }),
              ],
            ),
          ],
          SizedBox(height: spacing),
          if (widget.formData.catalogSpecifications.isEmpty)
            Text(
              'مشخصه‌ای ثبت نشده. از قالب فیلد یا ردیف سفارشی استفاده کنید.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            ...widget.formData.catalogSpecifications.asMap().entries.map((entry) {
              final index = entry.key;
              final row = entry.value;
              final template = row.fieldId == null
                  ? null
                  : _templates.cast<Map<String, dynamic>?>().firstWhere(
                        (t) => (t?['id'] as num?)?.toInt() == row.fieldId,
                        orElse: () => null,
                      );
              final isCustom = row.fieldId == null;
              return Card(
                margin: EdgeInsets.only(bottom: spacing),
                child: Padding(
                  padding: EdgeInsets.all(spacing),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isCustom)
                        TextFormField(
                          initialValue: row.label,
                          decoration: const InputDecoration(labelText: 'عنوان مشخصه *'),
                          onChanged: (v) => _updateCustomSpecLabel(index, v),
                        ),
                      if (isCustom) SizedBox(height: spacing),
                      _buildSpecInput(index, row, template),
                      if (isCustom || (template?['is_required'] != true))
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton.icon(
                            onPressed: () => _removeSpecRow(index),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('حذف'),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          SizedBox(height: spacing),
          Text(
            'حداقل سفارش (${widget.formData.minOrderQty ?? 0}) و زمان تحویل (${widget.formData.leadTimeDays ?? 0} روز) از تب «قیمت و موجودی» خوانده می‌شود و در API عمومی نمایش داده می‌شود.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
