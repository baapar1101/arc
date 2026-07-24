import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../models/person_model.dart';
import '../../../models/person_social_platforms.dart';
import '../../../models/product_form_data.dart';
import '../../../models/product_supplier_item.dart';
import '../../../services/person_service.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/snackbar_helper.dart';
import '../../invoice/person_combobox_widget.dart';

class ProductSuppliersSection extends StatefulWidget {
  final int businessId;
  final ProductFormData formData;
  final ValueChanged<ProductFormData> onChanged;

  const ProductSuppliersSection({
    super.key,
    required this.businessId,
    required this.formData,
    required this.onChanged,
  });

  @override
  State<ProductSuppliersSection> createState() => _ProductSuppliersSectionState();
}

class _ProductSuppliersSectionState extends State<ProductSuppliersSection> {
  final _personService = PersonService();
  final Map<int, Person?> _selectedPersons = {};

  void _update(ProductFormData data) => widget.onChanged(data);

  void _addSupplier() {
    final rows = List<ProductSupplierItem>.from(widget.formData.suppliers);
    rows.add(ProductSupplierItem(sortOrder: rows.length));
    _update(widget.formData.copyWith(suppliers: rows));
  }

  void _removeSupplier(int index) {
    final rows = List<ProductSupplierItem>.from(widget.formData.suppliers);
    if (index < 0 || index >= rows.length) return;
    rows.removeAt(index);
    _update(widget.formData.copyWith(suppliers: rows));
  }

  void _updateSupplier(int index, ProductSupplierItem next) {
    final rows = List<ProductSupplierItem>.from(widget.formData.suppliers);
    if (index < 0 || index >= rows.length) return;
    rows[index] = next;
    _update(widget.formData.copyWith(suppliers: rows));
  }

  void _setPreferred(int index) {
    final rows = widget.formData.suppliers
        .asMap()
        .entries
        .map((e) => e.value.copyWith(isPreferred: e.key == index))
        .toList();
    _update(widget.formData.copyWith(suppliers: rows));
  }

  Future<void> _onPersonSelected(int index, Person? person) async {
    if (person == null) {
      _updateSupplier(index, widget.formData.suppliers[index].copyWith(clearPerson: true));
      return;
    }
    _selectedPersons[index] = person;
    try {
      final full = await _personService.getPerson(person.id!);
      final social = full.socialContacts
          .map(
            (s) => ProductSupplierSocialContact(
              platformKey: s.platformKey,
              customLabel: s.customLabel,
              value: s.value,
            ),
          )
          .toList();
      _updateSupplier(
        index,
        widget.formData.suppliers[index].copyWith(
          personId: full.id,
          personName: full.aliasName,
          name: full.aliasName,
          website: full.website,
          phone: full.phone ?? full.mobile,
          email: full.email,
          socialContacts: social,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: e.toString());
      _updateSupplier(
        index,
        widget.formData.suppliers[index].copyWith(
          personId: person.id,
          personName: person.aliasName,
          name: person.aliasName,
        ),
      );
    }
  }

  void _addSocialRow(int supplierIndex) {
    final supplier = widget.formData.suppliers[supplierIndex];
    final contacts = List<ProductSupplierSocialContact>.from(supplier.socialContacts);
    contacts.add(const ProductSupplierSocialContact());
    _updateSupplier(supplierIndex, supplier.copyWith(socialContacts: contacts));
  }

  void _removeSocialRow(int supplierIndex, int socialIndex) {
    final supplier = widget.formData.suppliers[supplierIndex];
    final contacts = List<ProductSupplierSocialContact>.from(supplier.socialContacts);
    if (socialIndex < 0 || socialIndex >= contacts.length) return;
    contacts.removeAt(socialIndex);
    _updateSupplier(supplierIndex, supplier.copyWith(socialContacts: contacts));
  }

  void _updateSocialRow(int supplierIndex, int socialIndex, ProductSupplierSocialContact next) {
    final supplier = widget.formData.suppliers[supplierIndex];
    final contacts = List<ProductSupplierSocialContact>.from(supplier.socialContacts);
    if (socialIndex < 0 || socialIndex >= contacts.length) return;
    contacts[socialIndex] = next;
    _updateSupplier(supplierIndex, supplier.copyWith(socialContacts: contacts));
  }

  List<String> _platformOptionsForRow(ProductSupplierSocialContact s) {
    final o = <String>{...kPersonSocialPlatformKeys};
    if (s.platformKey.isNotEmpty && !o.contains(s.platformKey)) {
      o.add(s.platformKey);
    }
    final u = o.toList();
    u.sort((a, b) {
      final ia = kPersonSocialPlatformKeys.indexOf(a);
      final ib = kPersonSocialPlatformKeys.indexOf(b);
      if (ia < 0 && ib < 0) return a.compareTo(b);
      if (ia < 0) return 1;
      if (ib < 0) return -1;
      return ia.compareTo(ib);
    });
    return u;
  }

  Person? _personForRow(ProductSupplierItem row, int index) {
    if (row.personId == null) return null;
    final cached = _selectedPersons[index];
    if (cached != null && cached.id == row.personId) return cached;
    return Person(
      id: row.personId,
      businessId: widget.businessId,
      aliasName: row.personName ?? row.name,
      personTypes: const [PersonType.supplier],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
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
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تأمین‌کنندگان کالا', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'منابع تأمین این کالا با اطلاعات تماس و پیام‌رسان‌ها',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _addSupplier,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('افزودن تأمین‌کننده'),
            ),
          ],
        ),
        SizedBox(height: spacing),
        if (widget.formData.suppliers.isEmpty)
          Container(
            padding: EdgeInsets.all(spacing * 1.5),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'هنوز تأمین‌کننده‌ای ثبت نشده. با دکمهٔ بالا می‌توانید منبع تأمین اضافه کنید.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...widget.formData.suppliers.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            return _buildSupplierCard(context, t, index, row, spacing);
          }),
      ],
    );
  }

  Widget _buildSupplierCard(
    BuildContext context,
    AppLocalizations t,
    int index,
    ProductSupplierItem row,
    double spacing,
  ) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.only(bottom: spacing),
      child: Padding(
        padding: EdgeInsets.all(spacing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.displayLabel(),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                FilterChip(
                  label: const Text('ترجیحی'),
                  selected: row.isPreferred,
                  onSelected: (_) => _setPreferred(index),
                  avatar: Icon(
                    row.isPreferred ? Icons.star : Icons.star_border,
                    size: 18,
                  ),
                ),
                IconButton(
                  tooltip: 'حذف',
                  onPressed: () => _removeSupplier(index),
                  icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                ),
              ],
            ),
            SizedBox(height: spacing),
            PersonComboboxWidget(
              businessId: widget.businessId,
              label: 'انتخاب از اشخاص (اختیاری)',
              hintText: 'جست‌وجوی تأمین‌کنندهٔ ثبت‌شده',
              personTypes: const ['تامین‌کننده'],
              selectedPerson: _personForRow(row, index),
              onChanged: (p) => _onPersonSelected(index, p),
              dense: true,
            ),
            SizedBox(height: spacing),
            TextFormField(
              initialValue: row.name,
              decoration: const InputDecoration(
                labelText: 'نام / شرکت *',
                helperText: 'در صورت انتخاب شخص، به‌صورت خودکار پر می‌شود',
              ),
              onChanged: (v) => _updateSupplier(index, row.copyWith(name: v)),
            ),
            SizedBox(height: spacing),
            TextFormField(
              initialValue: row.website ?? '',
              decoration: const InputDecoration(
                labelText: 'وب‌سایت',
                prefixIcon: Icon(Icons.language_outlined),
              ),
              keyboardType: TextInputType.url,
              onChanged: (v) => _updateSupplier(
                index,
                row.copyWith(website: v.trim().isEmpty ? null : v),
              ),
            ),
            SizedBox(height: spacing),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: row.phone ?? '',
                    decoration: const InputDecoration(
                      labelText: 'تلفن',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                    onChanged: (v) => _updateSupplier(
                      index,
                      row.copyWith(phone: v.trim().isEmpty ? null : v),
                    ),
                  ),
                ),
                SizedBox(width: spacing),
                Expanded(
                  child: TextFormField(
                    initialValue: row.email ?? '',
                    decoration: const InputDecoration(
                      labelText: 'ایمیل',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (v) => _updateSupplier(
                      index,
                      row.copyWith(email: v.trim().isEmpty ? null : v),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing),
            TextFormField(
              initialValue: row.notes ?? '',
              decoration: const InputDecoration(
                labelText: 'توضیحات',
                helperText: 'شرایط سفارش، آدرس انبار، یادداشت و …',
              ),
              maxLines: 3,
              onChanged: (v) => _updateSupplier(
                index,
                row.copyWith(notes: v.trim().isEmpty ? null : v),
              ),
            ),
            SizedBox(height: spacing * 1.5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(t.personSocialNetworks, style: theme.textTheme.titleSmall),
                TextButton.icon(
                  onPressed: () => _addSocialRow(index),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(t.addPersonSocialRow),
                ),
              ],
            ),
            if (row.socialContacts.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: spacing * 0.5),
                child: Text(
                  t.noPersonSocialRows,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...row.socialContacts.asMap().entries.map((scEntry) {
                final scIndex = scEntry.key;
                final sc = scEntry.value;
                final options = _platformOptionsForRow(sc);
                return Card(
                  margin: EdgeInsets.only(top: spacing),
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  child: Padding(
                    padding: EdgeInsets.all(spacing),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: options.contains(sc.platformKey) ? sc.platformKey : options.first,
                                decoration: InputDecoration(labelText: t.personSocialPlatform),
                                items: options
                                    .map(
                                      (k) => DropdownMenuItem(
                                        value: k,
                                        child: Text(
                                          kPersonSocialPlatformLabelsFa[k] ?? k,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  _updateSocialRow(
                                    index,
                                    scIndex,
                                    sc.copyWith(
                                      platformKey: v,
                                      customLabel: v == 'other' ? sc.customLabel : null,
                                    ),
                                  );
                                },
                              ),
                            ),
                            IconButton(
                              onPressed: () => _removeSocialRow(index, scIndex),
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                            ),
                          ],
                        ),
                        if (sc.platformKey == 'other') ...[
                          SizedBox(height: spacing),
                          TextFormField(
                            initialValue: sc.customLabel ?? '',
                            decoration: InputDecoration(labelText: t.personSocialCustomName),
                            onChanged: (v) => _updateSocialRow(
                              index,
                              scIndex,
                              sc.copyWith(customLabel: v),
                            ),
                          ),
                        ],
                        SizedBox(height: spacing),
                        TextFormField(
                          initialValue: sc.value,
                          decoration: InputDecoration(
                            labelText: t.personSocialValue,
                            hintText: t.personSocialValue,
                          ),
                          onChanged: (v) => _updateSocialRow(
                            index,
                            scIndex,
                            sc.copyWith(value: v),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
