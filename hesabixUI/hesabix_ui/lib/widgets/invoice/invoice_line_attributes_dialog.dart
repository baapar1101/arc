import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/number_normalizer.dart' show parseFormattedNumber;
import '../date_input_field.dart';
import '../../core/calendar_controller.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../services/product_attribute_service.dart';

void _invoiceLineAttrsDialogLog(String message) {
  if (kDebugMode) {
    debugPrint('[InvoiceLineAttrs:dialog] $message');
  }
}

/// ویرایش ویژگی‌های کالا برای یک ردیف فاکتور (ذخیره در extra_info.line_custom_attributes)
class InvoiceLineAttributesDialog extends StatefulWidget {
  final String productName;
  final List<Map<String, dynamic>> productAttributes;
  final Map<String, dynamic>? initialValues;
  final CalendarController? calendarController;

  const InvoiceLineAttributesDialog({
    super.key,
    required this.productName,
    required this.productAttributes,
    this.initialValues,
    this.calendarController,
  });

  @override
  State<InvoiceLineAttributesDialog> createState() => _InvoiceLineAttributesDialogState();
}

class _InvoiceLineAttributesDialogState extends State<InvoiceLineAttributesDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _values = {};
  CalendarController? _calendarController;

  @override
  void initState() {
    super.initState();
    _calendarController = widget.calendarController;
    if (widget.initialValues != null && widget.initialValues!.isNotEmpty) {
      _values.addAll(Map<String, dynamic>.from(widget.initialValues!));
    }
    if (_calendarController == null) {
      CalendarController.load().then((c) {
        if (mounted) setState(() => _calendarController = c);
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final out = <String, dynamic>{};
    for (final e in _values.entries) {
      final v = e.value;
      if (v == null) continue;
      if (v is bool) {
        out[e.key] = v;
        continue;
      }
      if (v.toString().trim().isEmpty) continue;
      out[e.key] = v;
    }
    Navigator.of(context).pop(out);
  }

  Widget _fieldFor(Map<String, dynamic> attribute) {
    final title = (attribute['title'] ?? '').toString();
    final dataType = (attribute['data_type'] ?? 'text').toString();
    final current = _values[title];

    switch (dataType) {
      case 'number':
        return TextFormField(
          key: ValueKey('num_$title'),
          initialValue: current?.toString() ?? '',
          decoration: InputDecoration(
            labelText: title,
            border: const OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          onSaved: (v) {
            if (v != null && v.trim().isNotEmpty) {
              _values[title] = parseFormattedNumber(v);
            } else {
              _values.remove(title);
            }
          },
          onChanged: (v) {
            if (v.trim().isNotEmpty) {
              _values[title] = parseFormattedNumber(v);
            } else {
              _values.remove(title);
            }
          },
        );
      case 'date':
        DateTime? dateValue;
        if (current is String && current.isNotEmpty) {
          dateValue = DateTime.tryParse(current);
        } else if (current is DateTime) {
          dateValue = current;
        }
        if (_calendarController == null) {
          return TextFormField(
            decoration: InputDecoration(
              labelText: title,
              border: const OutlineInputBorder(),
              hintText: '...',
            ),
            enabled: false,
          );
        }
        return DateInputField(
          value: dateValue,
          onChanged: (date) {
            if (date != null) {
              _values[title] = date.toIso8601String().split('T').first;
            } else {
              _values.remove(title);
            }
            setState(() {});
          },
          calendarController: _calendarController!,
          labelText: title,
        );
      case 'select':
        final rawOpts = attribute['options'];
        final options = <String>[];
        if (rawOpts is List) {
          for (final o in rawOpts) {
            options.add(o.toString());
          }
        }
        final sel = current?.toString();
        return DropdownButtonFormField<String>(
          value: (sel != null && sel.isNotEmpty && options.contains(sel)) ? sel : null,
          decoration: InputDecoration(
            labelText: title,
            border: const OutlineInputBorder(),
          ),
          items: options
              .map((o) => DropdownMenuItem<String>(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) {
            setState(() {
              if (v != null) {
                _values[title] = v;
              } else {
                _values.remove(title);
              }
            });
          },
        );
      case 'boolean':
        final boolVal = current is bool
            ? current
            : (current?.toString().toLowerCase() == 'true' || current?.toString() == '1');
        return SwitchListTile(
          title: Text(title),
          value: boolVal,
          onChanged: (v) {
            setState(() => _values[title] = v);
          },
        );
      default:
        return TextFormField(
          key: ValueKey('txt_$title'),
          initialValue: current?.toString() ?? '',
          decoration: InputDecoration(
            labelText: title,
            border: const OutlineInputBorder(),
          ),
          onSaved: (v) {
            if (v != null && v.trim().isNotEmpty) {
              _values[title] = v.trim();
            } else {
              _values.remove(title);
            }
          },
          onChanged: (v) {
            if (v.trim().isNotEmpty) {
              _values[title] = v.trim();
            } else {
              _values.remove(title);
            }
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('ویژگی‌های کالا: ${widget.productName}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.productAttributes.isEmpty)
                  const Text('ویژگی‌ای برای این کالا تعریف نشده است.')
                else
                  ...widget.productAttributes.map((attr) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _fieldFor(attr),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(<String, dynamic>{}),
          child: const Text('پاک کردن'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: () {
            _formKey.currentState?.save();
            _submit();
          },
          child: const Text('تأیید'),
        ),
      ],
    );
  }
}

/// بارگذاری تعاریف ویژگی بر اساس attribute_ids و باز کردن دیالوگ؛ خروجی map ویژگی‌ها یا null
Future<Map<String, dynamic>?> showInvoiceLineAttributesEditor({
  required BuildContext context,
  required int businessId,
  required int productId,
  required String productName,
  required Map<String, dynamic> productMap,
  Map<String, dynamic>? initialLineAttributes,
  CalendarController? calendarController,
}) async {
  _invoiceLineAttrsDialogLog(
    'showEditor enter productId=$productId businessId=$businessId keys=${productMap.keys.toList()}',
  );
  final ids = productMap['attribute_ids'];
  if (ids is! List || ids.isEmpty) {
    _invoiceLineAttrsDialogLog('blocked: attribute_ids empty or not list raw=$ids (${ids.runtimeType})');
    SnackBarHelper.show(context, message: 'این کالا ویژگی تعریف‌شده‌ای ندارد');
    return null;
  }
  final mode = productMap['inventory_mode']?.toString() ?? 'bulk';
  if (mode == 'unique') {
    _invoiceLineAttrsDialogLog('blocked: inventory_mode=unique');
    SnackBarHelper.show(context, message: 'برای کالای یونیک ویژگی‌ها از طریق انتخاب سریال/نمونه ثبت می‌شود');
    return null;
  }

  final attrService = ProductAttributeService();
  List<Map<String, dynamic>> definitions;
  try {
    _invoiceLineAttrsDialogLog('search product-attributes limit=1000 ...');
    final search = await attrService.search(businessId: businessId, limit: 1000);
    final all = (search['items'] as List<dynamic>?) ?? [];
    _invoiceLineAttrsDialogLog('search returned items count=${all.length}');
    final idSet = ids.map((e) {
      if (e is int) return e;
      if (e is num) return e.toInt();
      return int.tryParse(e.toString()) ?? 0;
    }).where((id) => id > 0).toSet();
    definitions = all
        .where((a) => idSet.contains((a as Map)['id'] as int?))
        .map((a) => Map<String, dynamic>.from(a as Map))
        .toList();
    definitions.sort((a, b) => ((a['id'] as num?)?.toInt() ?? 0).compareTo((b['id'] as num?)?.toInt() ?? 0));
    _invoiceLineAttrsDialogLog(
      'matched definitions count=${definitions.length} idSet=$idSet titles=${definitions.map((a) => a['title']).toList()}',
    );
  } catch (e) {
    _invoiceLineAttrsDialogLog('search FAILED error=$e');
    if (context.mounted) {
      SnackBarHelper.showError(
        context,
        message:
            'خطا در بارگذاری ویژگی‌ها: ${ErrorExtractor.forContext(e, context)}',
      );
    }
    return null;
  }

  if (!context.mounted) return null;
  if (definitions.isEmpty) {
    _invoiceLineAttrsDialogLog('blocked: definitions empty after filter (permission یا id اشتباه؟)');
    SnackBarHelper.show(context, message: 'تعریف ویژگی‌ها یافت نشد');
    return null;
  }

  _invoiceLineAttrsDialogLog('opening AlertDialog');
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => InvoiceLineAttributesDialog(
      productName: productName,
      productAttributes: definitions,
      initialValues: initialLineAttributes,
      calendarController: calendarController,
    ),
  );
}
