import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';

Map<String, dynamic> crmCustomValuesFromRecord(Map<String, dynamic>? record) {
  final direct = record?['custom_fields'];
  if (direct is Map) return Map<String, dynamic>.from(direct);
  final extra = record?['extra_info'];
  if (extra is Map && extra['_custom'] is Map) {
    return Map<String, dynamic>.from(extra['_custom'] as Map);
  }
  return {};
}

/// ورودی فیلدهای سفارشی یک موجودیت، وصل به API تعریف فیلد.
class CrmCustomFieldInputs extends StatefulWidget {
  final int businessId;
  final CrmService crmService;
  final String entityType;
  final Map<String, dynamic> initialValues;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const CrmCustomFieldInputs({
    super.key,
    required this.businessId,
    required this.crmService,
    required this.entityType,
    required this.initialValues,
    required this.onChanged,
  });

  @override
  State<CrmCustomFieldInputs> createState() => _CrmCustomFieldInputsState();
}

class _CrmCustomFieldInputsState extends State<CrmCustomFieldInputs> {
  List<Map<String, dynamic>> _defs = [];
  late Map<String, dynamic> _values;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.initialValues);
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.crmService.listCustomFields(
        businessId: widget.businessId,
        entityType: widget.entityType,
      );
      if (!mounted) return;
      setState(() {
        _defs = rows.where((d) => d['is_active'] != false).toList();
        _loading = false;
      });
      widget.onChanged(_values);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _set(String key, dynamic value, {bool rebuild = true}) {
    _values[key] = value;
    widget.onChanged(Map<String, dynamic>.from(_values));
    if (rebuild && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _defs.isEmpty) return const SizedBox.shrink();
    return CrmSectionCard(
      title: 'فیلدهای سفارشی',
      child: Column(
        children: [
          for (final def in _defs) ...[
            _field(def),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  DateTime? _localDate(String stored) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(stored.trim());
    if (match == null) return DateTime.tryParse(stored);
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  Widget _field(Map<String, dynamic> def) {
    final key = def['field_key']?.toString() ?? '';
    final label = def['label']?.toString() ?? key;
    final type = def['field_type']?.toString() ?? 'text';
    final requiredMark = def['is_required'] == true ? ' *' : '';
    final current = _values[key];
    if (type == 'boolean') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('$label$requiredMark'),
        value: current == true || current == 'true',
        onChanged: (v) => _set(key, v),
      );
    }
    if (type == 'date') {
      final stored = current?.toString() ?? '';
      final parsed = _localDate(stored);
      final isJalali = ApiClient.getCalendarController()?.isJalali ?? false;
      final shown = parsed == null ? '' : HesabixDateUtils.formatForDisplay(parsed, isJalali);
      return OutlinedButton.icon(
        onPressed: () async {
          final picked = await showAdaptiveDatePicker(
            context: context,
            initialDate: parsed ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            helpText: label,
          );
          if (picked == null) return;
          _set(key, HesabixDateUtils.formatForApiDate(picked));
        },
        icon: const Icon(Icons.event_outlined),
        label: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(shown.isEmpty ? '$label$requiredMark' : '$label$requiredMark · $shown'),
        ),
      );
    }
    if (type == 'select') {
      final options = def['options'];
      final choices = options is Map && options['choices'] is List
          ? (options['choices'] as List).map((e) => e.toString()).where((c) => c.isNotEmpty).toList()
          : <String>[];
      if (choices.isEmpty) {
        return TextFormField(
          initialValue: current?.toString() ?? '',
          decoration: InputDecoration(labelText: '$label$requiredMark', border: const OutlineInputBorder()),
          onChanged: (v) => _set(key, v, rebuild: false),
        );
      }
      final selected = choices.contains(current?.toString()) ? current.toString() : null;
      return DropdownButtonFormField<String>(
        value: selected,
        decoration: InputDecoration(labelText: '$label$requiredMark', border: const OutlineInputBorder()),
        items: choices.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
        onChanged: (v) => _set(key, v),
      );
    }
    return TextFormField(
      initialValue: current?.toString() ?? '',
      decoration: InputDecoration(labelText: '$label$requiredMark', border: const OutlineInputBorder()),
      keyboardType: type == 'number' ? TextInputType.number : TextInputType.text,
      onChanged: (v) => _set(key, type == 'number' ? num.tryParse(v) ?? v : v, rebuild: false),
    );
  }
}

/// مدیریت تعریف فیلد سفارشی در تنظیمات CRM.
class CrmCustomFieldAdmin extends StatefulWidget {
  final int businessId;
  final CrmService crmService;
  final bool canWrite;

  const CrmCustomFieldAdmin({
    super.key,
    required this.businessId,
    required this.crmService,
    required this.canWrite,
  });

  @override
  State<CrmCustomFieldAdmin> createState() => _CrmCustomFieldAdminState();
}

class _CrmCustomFieldAdminState extends State<CrmCustomFieldAdmin> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.crmService.listCustomFields(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context), isError: true);
    }
  }

  Future<void> _add() async {
    final keyCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final choicesCtrl = TextEditingController();
    String entity = 'lead';
    String type = 'text';
    var requiredField = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('فیلد سفارشی'),
          content: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: entity,
                decoration: const InputDecoration(labelText: 'موجودیت'),
                items: const [
                  DropdownMenuItem(value: 'lead', child: Text('سرنخ')),
                  DropdownMenuItem(value: 'deal', child: Text('فرصت')),
                  DropdownMenuItem(value: 'activity', child: Text('فعالیت')),
                ],
                onChanged: (v) => setLocal(() => entity = v ?? 'lead'),
              ),
              const SizedBox(height: 8),
              TextField(controller: keyCtrl, decoration: const InputDecoration(labelText: 'کلید لاتین')),
              TextField(controller: labelCtrl, decoration: const InputDecoration(labelText: 'برچسب')),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'نوع'),
                items: const [
                  DropdownMenuItem(value: 'text', child: Text('متن')),
                  DropdownMenuItem(value: 'number', child: Text('عدد')),
                  DropdownMenuItem(value: 'date', child: Text('تاریخ')),
                  DropdownMenuItem(value: 'boolean', child: Text('بله/خیر')),
                  DropdownMenuItem(value: 'select', child: Text('انتخابی')),
                ],
                onChanged: (v) => setLocal(() => type = v ?? 'text'),
              ),
              if (type == 'select') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: choicesCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'گزینه‌ها',
                    helperText: 'هر گزینه در یک خط',
                  ),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('الزامی'),
                value: requiredField,
                onChanged: (v) => setLocal(() => requiredField = v),
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
    if (ok != true || !mounted) {
      keyCtrl.dispose();
      labelCtrl.dispose();
      choicesCtrl.dispose();
      return;
    }
    final fieldKey = keyCtrl.text.trim();
    final label = labelCtrl.text.trim();
    final choices = choicesCtrl.text
        .split(RegExp(r'[\n,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    keyCtrl.dispose();
    labelCtrl.dispose();
    choicesCtrl.dispose();
    if (fieldKey.isEmpty || label.isEmpty) {
      SnackBarHelper.show(context, message: 'کلید و برچسب الزامی است', isError: true);
      return;
    }
    if (type == 'select' && choices.isEmpty) {
      SnackBarHelper.show(context, message: 'برای فیلد انتخابی حداقل یک گزینه بنویسید', isError: true);
      return;
    }
    try {
      await widget.crmService.createCustomField(
        businessId: widget.businessId,
        entityType: entity,
        fieldKey: fieldKey,
        label: label,
        fieldType: type,
        options: type == 'select' ? choices : null,
        isRequired: requiredField,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context), isError: true);
    }
  }

  Future<void> _delete(int id) async {
    try {
      await widget.crmService.deleteCustomField(businessId: widget.businessId, fieldId: id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CrmSectionCard(
      title: 'فیلدهای سفارشی',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const LinearProgressIndicator()
          else if (_items.isEmpty)
            const Text('فیلدی تعریف نشده است. فیلدهای متن، عدد، تاریخ و بله/خیر روی سرنخ و فرصت دیده می‌شوند.')
          else
            ..._items.map((item) {
              final id = (item['id'] as num?)?.toInt();
              final entity = item['entity_type']?.toString() ?? '';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item['label']?.toString() ?? ''),
                subtitle: Text('$entity · ${item['field_key']} · ${item['field_type']}'),
                trailing: widget.canWrite && id != null
                    ? IconButton(onPressed: () => _delete(id), icon: const Icon(Icons.delete_outline))
                    : null,
              );
            }),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: widget.canWrite ? _add : null,
              icon: const Icon(Icons.add),
              label: const Text('افزودن فیلد'),
            ),
          ),
        ],
      ),
    );
  }
}
