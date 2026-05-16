import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../models/person_group_model.dart';
import '../../models/person_model.dart';
import '../../services/person_group_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

/// ایجاد یا ویرایش گروه اشخاص + مقادیر پیش‌فرض (فقط فیلدهای غیرخالی ذخیره می‌شوند)
class PersonGroupFormDialog extends StatefulWidget {
  final int businessId;
  final PersonGroup? group;

  const PersonGroupFormDialog({
    super.key,
    required this.businessId,
    this.group,
  });

  @override
  State<PersonGroupFormDialog> createState() => _PersonGroupFormDialogState();
}

class _PersonGroupFormDialogState extends State<PersonGroupFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _service = PersonGroupService();
  bool _loading = false;

  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _sortOrderController;

  final Set<PersonType> _personTypes = {};
  String _legalEntityType = 'natural';
  String _namePrefixSelection = '';

  static const List<String> _prefixChoices = [
    '',
    'آقای',
    'خانم',
    'شرکت',
    'دکتر',
    'مهندس',
    'موسسه',
    'اداره',
    'سازمان',
    'بنیاد',
    'انجمن',
  ];

  final Map<String, TextEditingController> _textDefaults = {
    'company_name': TextEditingController(),
    'payment_id': TextEditingController(),
    'national_id': TextEditingController(),
    'registration_number': TextEditingController(),
    'economic_id': TextEditingController(),
    'country': TextEditingController(),
    'province': TextEditingController(),
    'city': TextEditingController(),
    'address': TextEditingController(),
    'postal_code': TextEditingController(),
    'phone': TextEditingController(),
    'mobile': TextEditingController(),
    'mobile_2': TextEditingController(),
    'mobile_3': TextEditingController(),
    'fax': TextEditingController(),
    'email': TextEditingController(),
    'website': TextEditingController(),
    'share_count': TextEditingController(),
    'commission_sale_percent': TextEditingController(),
    'commission_sales_return_percent': TextEditingController(),
    'commission_sales_amount': TextEditingController(),
    'commission_sales_return_amount': TextEditingController(),
    'credit_limit': TextEditingController(),
  };

  bool _isActive = true;
  bool _commissionExcludeDiscounts = false;
  bool _commissionExcludeAdditionsDeductions = false;
  bool _commissionPostInInvoiceDocument = false;
  bool? _creditCheckEnabled;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    _nameController = TextEditingController(text: g?.name ?? '');
    _codeController = TextEditingController(text: g?.code?.toString() ?? '');
    _descriptionController = TextEditingController(text: g?.description ?? '');
    _sortOrderController = TextEditingController(text: (g?.sortOrder ?? 0).toString());
    _isActive = g?.isActive ?? true;
    if (g != null) {
      final m = g.profileDefaults;
      final pt = m['person_types'];
      if (pt is List) {
        for (final e in pt) {
          try {
            _personTypes.add(PersonType.fromString(e.toString()));
          } catch (_) {}
        }
      }
      final let = m['legal_entity_type']?.toString();
      if (let == 'legal' || let == 'natural') _legalEntityType = let!;
      final np = m['name_prefix']?.toString();
      if (np != null && np.isNotEmpty && _prefixChoices.contains(np)) {
        _namePrefixSelection = np;
      }
      for (final entry in _textDefaults.entries) {
        final v = m[entry.key];
        if (v != null && v.toString().trim().isNotEmpty) {
          entry.value.text = v.toString();
        }
      }
      _commissionExcludeDiscounts = m['commission_exclude_discounts'] == true || m['commission_exclude_discounts'] == 1;
      _commissionExcludeAdditionsDeductions =
          m['commission_exclude_additions_deductions'] == true || m['commission_exclude_additions_deductions'] == 1;
      _commissionPostInInvoiceDocument =
          m['commission_post_in_invoice_document'] == true || m['commission_post_in_invoice_document'] == 1;
      if (m.containsKey('credit_check_enabled')) {
        final c = m['credit_check_enabled'];
        _creditCheckEnabled = c == true || c == 1;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _descriptionController.dispose();
    _sortOrderController.dispose();
    for (final c in _textDefaults.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _buildProfileDefaults() {
    final out = <String, dynamic>{};
    if (_personTypes.isNotEmpty) {
      out['person_types'] = _personTypes.map((e) => e.persianName).toList();
    }
    out['legal_entity_type'] = _legalEntityType;
    if (_namePrefixSelection.isNotEmpty) {
      out['name_prefix'] = _namePrefixSelection;
    }
    for (final e in _textDefaults.entries) {
      final t = e.value.text.trim();
      if (t.isEmpty) continue;
      if (e.key == 'share_count') {
        final n = int.tryParse(t);
        if (n != null && n > 0) out['share_count'] = n;
        continue;
      }
      if (e.key.startsWith('commission_')) {
        final n = double.tryParse(t);
        if (n != null) {
          out[e.key] = n;
        }
        continue;
      }
      if (e.key == 'credit_limit') {
        final n = double.tryParse(t);
        if (n != null) out['credit_limit'] = n;
        continue;
      }
      out[e.key] = t;
    }
    out['commission_exclude_discounts'] = _commissionExcludeDiscounts;
    out['commission_exclude_additions_deductions'] = _commissionExcludeAdditionsDeductions;
    out['commission_post_in_invoice_document'] = _commissionPostInInvoiceDocument;
    if (_creditCheckEnabled != null) {
      out['credit_check_enabled'] = _creditCheckEnabled;
    }
    return out;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final sort = int.tryParse(_sortOrderController.text.trim()) ?? 0;
      final profile = _buildProfileDefaults();
      if (widget.group == null) {
        await _service.createGroup(
          widget.businessId,
          PersonGroupCreateRequest(
            name: _nameController.text.trim(),
            code: int.tryParse(_codeController.text.trim()),
            description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            profileDefaults: profile,
            sortOrder: sort,
            isActive: _isActive,
          ),
        );
      } else {
        await _service.updateGroup(
          widget.businessId,
          widget.group!.id,
          PersonGroupUpdateRequest(
            name: _nameController.text.trim(),
            code: int.tryParse(_codeController.text.trim()),
            description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            profileDefaults: profile,
            sortOrder: sort,
            isActive: _isActive,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا: ${ErrorExtractor.forContext(e, context)}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isEdit = widget.group != null;
    return AlertDialog(
      title: Text(isEdit ? '${t.edit} ${t.personGroup}' : '${t.addPerson} (${t.personGroup})'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: '${t.personGroup} *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'الزامی' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(labelText: 'کد گروه (اختیاری)'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'توضیحات'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _sortOrderController,
                  decoration: const InputDecoration(labelText: 'ترتیب نمایش'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                SwitchListTile(
                  title: const Text('فعال'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const Divider(),
                Text('مقادیر پیش‌فرض (برای اشخاص جدید)', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Text('انواع شخص', style: Theme.of(context).textTheme.bodySmall),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: PersonType.values.map((pt) {
                    final sel = _personTypes.contains(pt);
                    return FilterChip(
                      label: Text(pt.persianName),
                      selected: sel,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _personTypes.add(pt);
                          } else {
                            _personTypes.remove(pt);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _legalEntityType,
                  decoration: InputDecoration(labelText: t.personLegalEntityType),
                  items: [
                    DropdownMenuItem(value: 'natural', child: Text(t.personLegalEntityNatural)),
                    DropdownMenuItem(value: 'legal', child: Text(t.personLegalEntityLegal)),
                  ],
                  onChanged: (v) => setState(() => _legalEntityType = v ?? 'natural'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _namePrefixSelection.isEmpty ? '' : _namePrefixSelection,
                  decoration: InputDecoration(labelText: t.personNamePrefix),
                  items: _prefixChoices
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.isEmpty ? t.personNamePrefixNone : p)))
                      .toList(),
                  onChanged: (v) => setState(() => _namePrefixSelection = v ?? ''),
                ),
                const SizedBox(height: 8),
                ..._textDefaults.entries.map((e) {
                  final labels = <String, String>{
                    'company_name': t.personCompanyName,
                    'payment_id': t.personPaymentId,
                    'national_id': t.personNationalId,
                    'registration_number': t.personRegistrationNumber,
                    'economic_id': t.personEconomicId,
                    'country': t.personCountry,
                    'province': t.personProvince,
                    'city': t.personCity,
                    'address': t.personAddress,
                    'postal_code': t.personPostalCode,
                    'phone': t.personPhone,
                    'mobile': t.personMobile,
                    'mobile_2': t.personMobile2,
                    'mobile_3': t.personMobile3,
                    'fax': t.personFax,
                    'email': t.personEmail,
                    'website': t.personWebsite,
                    'share_count': t.shareCount,
                    'commission_sale_percent': t.commissionSalePercentLabel,
                    'commission_sales_return_percent': t.commissionSalesReturnPercentLabel,
                    'commission_sales_amount': t.commissionSalesAmountLabel,
                    'commission_sales_return_amount': t.commissionSalesReturnAmountLabel,
                    'credit_limit': t.creditTabTitle,
                  };
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextFormField(
                      controller: e.value,
                      decoration: InputDecoration(labelText: labels[e.key] ?? e.key),
                      keyboardType: e.key == 'phone' || e.key == 'mobile' || e.key == 'mobile_2' || e.key == 'mobile_3'
                          ? TextInputType.phone
                          : e.key.contains('commission') || e.key == 'credit_limit'
                              ? const TextInputType.numberWithOptions(decimal: true)
                              : TextInputType.text,
                    ),
                  );
                }),
                CheckboxListTile(
                  title: Text(t.commissionExcludeDiscounts),
                  value: _commissionExcludeDiscounts,
                  onChanged: (v) => setState(() => _commissionExcludeDiscounts = v ?? false),
                ),
                CheckboxListTile(
                  title: Text(t.commissionExcludeAdditionsDeductions),
                  value: _commissionExcludeAdditionsDeductions,
                  onChanged: (v) => setState(() => _commissionExcludeAdditionsDeductions = v ?? false),
                ),
                CheckboxListTile(
                  title: Text(t.commissionPostInInvoiceDocument),
                  value: _commissionPostInInvoiceDocument,
                  onChanged: (v) => setState(() => _commissionPostInInvoiceDocument = v ?? false),
                ),
                SwitchListTile(
                  title: const Text('اعتبار: بررسی فعال (پیش‌فرض)'),
                  value: _creditCheckEnabled ?? false,
                  onChanged: (v) => setState(() => _creditCheckEnabled = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _loading ? null : () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _loading ? null : _save, child: Text(t.save)),
      ],
    );
  }
}
