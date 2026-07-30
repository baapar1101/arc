import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../services/currency_service.dart';
import '../../utils/error_extractor.dart';
import '../multi_currency_gate.dart';

/// فیلتر ارز گزارش/اسناد با گزینهٔ «همه ارزها» (value = null).
///
/// فقط وقتی [isMultiCurrency] و بیش از یک ارز فعال باشد نمایش داده می‌شود.
class ReportCurrencyFilterDropdown extends StatefulWidget {
  const ReportCurrencyFilterDropdown({
    super.key,
    required this.businessId,
    required this.isMultiCurrency,
    required this.selectedCurrencyId,
    required this.onChanged,
    this.label = 'ارز',
    this.allCurrenciesLabel = 'همه ارزها (معادل پایه)',
    this.width = 220,
    this.dense = true,
    this.autoSelectDefault = false,
  });

  final int businessId;
  final bool isMultiCurrency;
  final int? selectedCurrencyId;
  final ValueChanged<int?> onChanged;
  final String label;
  final String allCurrenciesLabel;
  final double width;
  final bool dense;

  /// اگر true باشد و انتخاب فعلی null باشد، ارز پیش‌فرض را انتخاب می‌کند
  /// (مناسب گزارش‌هایی که قبلاً بدون «همه» بودند و می‌خواهند رفتار قبلی حفظ شود مگر کاربر عوض کند).
  final bool autoSelectDefault;

  @override
  State<ReportCurrencyFilterDropdown> createState() =>
      _ReportCurrencyFilterDropdownState();
}

class _ReportCurrencyFilterDropdownState
    extends State<ReportCurrencyFilterDropdown> {
  final CurrencyService _currencyService = CurrencyService(ApiClient());
  List<Map<String, dynamic>> _currencies = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isMultiCurrency) {
      _load();
    }
  }

  @override
  void didUpdateWidget(ReportCurrencyFilterDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.isMultiCurrency != widget.isMultiCurrency) {
      if (widget.isMultiCurrency) {
        _load();
      } else {
        setState(() {
          _currencies = const [];
          _error = null;
        });
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _currencyService.listBusinessCurrencies(
        businessId: widget.businessId,
      );
      if (!mounted) return;
      setState(() {
        _currencies = list;
        _loading = false;
      });
      if (widget.autoSelectDefault &&
          widget.selectedCurrencyId == null &&
          list.isNotEmpty) {
        final def = list.firstWhere(
          (c) => c['is_default'] == true,
          orElse: () => list.first,
        );
        final id = (def['id'] as num?)?.toInt();
        if (id != null) widget.onChanged(id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  String _itemLabel(Map<String, dynamic> c) {
    final title = (c['title'] ?? c['code'] ?? c['symbol'] ?? '').toString();
    final code = (c['code'] ?? '').toString();
    final isDefault = c['is_default'] == true;
    final base = code.isNotEmpty && title != code ? '$title ($code)' : title;
    return isDefault ? '$base — پایه' : base;
  }

  @override
  Widget build(BuildContext context) {
    return MultiCurrencyGate(
      isMultiCurrency: widget.isMultiCurrency,
      child: SizedBox(
        width: widget.width,
        child: _loading
            ? const LinearProgressIndicator(minHeight: 2)
            : DropdownButtonFormField<int?>(
                value: widget.selectedCurrencyId,
                isDense: widget.dense,
                decoration: InputDecoration(
                  labelText: widget.label,
                  border: const OutlineInputBorder(),
                  isDense: widget.dense,
                  errorText: _error,
                  contentPadding: widget.dense
                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                      : null,
                ),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text(widget.allCurrenciesLabel),
                  ),
                  ..._currencies.map((c) {
                    final id = (c['id'] as num?)?.toInt();
                    return DropdownMenuItem<int?>(
                      value: id,
                      child: Text(_itemLabel(c), overflow: TextOverflow.ellipsis),
                    );
                  }),
                ],
                onChanged: widget.onChanged,
              ),
      ),
    );
  }
}
