import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../services/inventory_lot_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/date_input_field.dart';

class InvoiceLineLotPickerDialog extends StatefulWidget {
  final int businessId;
  final int productId;
  final String productName;
  final num lineQuantity;
  final int? warehouseId;
  final int? variantId;
  final List<Map<String, dynamic>> initialAllocations;
  final bool inbound;
  final bool includeUnsellable;
  final CalendarController? calendarController;

  const InvoiceLineLotPickerDialog({
    super.key,
    required this.businessId,
    required this.productId,
    required this.productName,
    required this.lineQuantity,
    this.warehouseId,
    this.variantId,
    this.initialAllocations = const [],
    this.inbound = false,
    this.includeUnsellable = false,
    this.calendarController,
  });

  @override
  State<InvoiceLineLotPickerDialog> createState() => _InvoiceLineLotPickerDialogState();
}

class _InvoiceLineLotPickerDialogState extends State<InvoiceLineLotPickerDialog> {
  final _svc = InventoryLotService();
  final _rows = <_LotDraft>[];
  CalendarController? _calendar;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _calendar = widget.calendarController ?? ApiClient.getCalendarController();
    if (_calendar == null) {
      CalendarController.load().then((c) {
        if (mounted) setState(() => _calendar = c);
      });
    }
    _bootstrap();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      if (widget.initialAllocations.isNotEmpty) {
        for (final item in widget.initialAllocations) {
          _rows.add(_LotDraft.fromMap(item));
        }
      } else if (widget.inbound) {
        _rows.add(_LotDraft(quantity: widget.lineQuantity.toString()));
      } else {
        final lots = await _svc.listLots(
          businessId: widget.businessId,
          productId: widget.productId,
          warehouseId: widget.warehouseId,
          variantId: widget.variantId,
          sellableOnly: !widget.includeUnsellable,
        );
        if (lots.isEmpty) {
          _rows.add(_LotDraft(quantity: widget.lineQuantity.toString()));
        } else {
          var remaining = widget.lineQuantity;
          for (final lot in lots) {
            if (remaining <= 0) break;
            final avail = parseFormattedNumber(lot['quantity_secondary']?.toString()) ??
                parseFormattedNumber(lot['quantity_main']?.toString()) ??
                0;
            if (avail <= 0) continue;
            final take = avail < remaining ? avail : remaining;
            remaining -= take;
            _rows.add(_LotDraft.fromMap({
              ...lot,
              'quantity': take,
            }));
          }
          if (_rows.isEmpty) {
            _rows.add(_LotDraft(quantity: widget.lineQuantity.toString()));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
      if (_rows.isEmpty) {
        _rows.add(_LotDraft(quantity: widget.lineQuantity.toString()));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  String? _iso(DateTime? value) => value?.toIso8601String().split('T').first;

  void _submit() {
    final allocations = <Map<String, dynamic>>[];
    num total = 0;
    for (final row in _rows) {
      final qty = parseFormattedNumber(row.quantity.text) ?? 0;
      if (qty <= 0) continue;
      if (widget.inbound && row.manufacturingDate == null && row.expiryDate == null) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(context, message: t.lotPickerDatesRequired);
        return;
      }
      total += qty;
      allocations.add({
        if (row.lotId != null) 'lot_id': row.lotId,
        'lot_code': row.lotCode.text.trim().isEmpty ? '-' : row.lotCode.text.trim(),
        'manufacturing_date': _iso(row.manufacturingDate),
        'expiry_date': _iso(row.expiryDate),
        'quantity': qty,
      });
    }
    if (allocations.isEmpty) {
      final t = AppLocalizations.of(context);
      SnackBarHelper.showError(context, message: t.lotPickerMinOne);
      return;
    }
    if ((total - widget.lineQuantity).abs() > 0.000001) {
      final t = AppLocalizations.of(context);
      SnackBarHelper.showError(context, message: t.lotPickerQtyMismatch);
      return;
    }
    Navigator.pop(context, allocations);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final calendar = _calendar;
    return AlertDialog(
      title: Text('${t.lotPickerTitlePrefix} ${widget.productName}'),
      content: SizedBox(
        width: 560,
        child: _loading || calendar == null
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  children: [
                    Text(
                      widget.inbound
                          ? t.lotPickerInboundHelp
                          : t.lotPickerOutboundHelp,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    ..._rows.asMap().entries.map((e) {
                      final i = e.key;
                      final row = e.value;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              TextField(
                                controller: row.lotCode,
                                decoration: InputDecoration(labelText: t.lotPickerCode),
                              ),
                              const SizedBox(height: 8),
                              DateInputField(
                                calendarController: calendar,
                                value: row.manufacturingDate,
                                labelText: t.expiryColManufacturing,
                                onChanged: (v) => setState(() => row.manufacturingDate = v),
                              ),
                              const SizedBox(height: 8),
                              DateInputField(
                                calendarController: calendar,
                                value: row.expiryDate,
                                labelText: t.expiryDate,
                                onChanged: (v) => setState(() => row.expiryDate = v),
                              ),
                              if (row.bestBeforeDate != null) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    '${t.lotPickerBestBeforePrefix} ${_iso(row.bestBeforeDate)}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              TextField(
                                controller: row.quantity,
                                decoration: InputDecoration(labelText: t.quantity),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ),
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: IconButton(
                                  onPressed: _rows.length == 1
                                      ? null
                                      : () => setState(() {
                                            row.dispose();
                                            _rows.removeAt(i);
                                          }),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _rows.add(_LotDraft())),
                        icon: const Icon(Icons.add),
                        label: Text(t.lotPickerAddAnother),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(t.save)),
      ],
    );
  }
}

class _LotDraft {
  _LotDraft({
    this.lotId,
    String lotCode = '',
    this.manufacturingDate,
    this.expiryDate,
    this.bestBeforeDate,
    String quantity = '',
  })  : lotCode = TextEditingController(text: lotCode),
        quantity = TextEditingController(text: quantity);

  factory _LotDraft.fromMap(Map<String, dynamic> map) {
    return _LotDraft(
      lotId: (map['lot_id'] as num?)?.toInt() ?? (map['id'] as num?)?.toInt(),
      lotCode: map['lot_code']?.toString() ?? '',
      manufacturingDate: HesabixDateUtils.parseApiDate(map['manufacturing_date']),
      expiryDate: HesabixDateUtils.parseApiDate(map['expiry_date']),
      bestBeforeDate: HesabixDateUtils.parseApiDate(map['best_before_date']),
      quantity: map['quantity']?.toString() ??
          map['quantity_main']?.toString() ??
          '',
    );
  }

  final int? lotId;
  final TextEditingController lotCode;
  DateTime? manufacturingDate;
  DateTime? expiryDate;
  DateTime? bestBeforeDate;
  final TextEditingController quantity;

  void dispose() {
    lotCode.dispose();
    quantity.dispose();
  }
}

List<Map<String, dynamic>> lotAllocationsFromExtra(Map<String, dynamic>? extra) {
  final raw = extra?['lot_allocations'];
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}
