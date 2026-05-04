import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../services/currency_service.dart';
import '../../utils/error_extractor.dart';

class CurrencyPickerWidget extends StatefulWidget {
  final int? selectedCurrencyId;
  final int businessId;
  final ValueChanged<int?> onChanged;
  final String? label;
  final String? hintText;
  final bool enabled;
  /// هم‌ارتفاع‌تر با [TextField] فشرده و [DateInputField] با `isDense`.
  final bool isDense;

  const CurrencyPickerWidget({
    super.key,
    this.selectedCurrencyId,
    required this.businessId,
    required this.onChanged,
    this.label,
    this.hintText,
    this.enabled = true,
    this.isDense = false,
  });

  @override
  State<CurrencyPickerWidget> createState() => _CurrencyPickerWidgetState();
}

class _CurrencyPickerWidgetState extends State<CurrencyPickerWidget> {
  final CurrencyService _currencyService = CurrencyService(ApiClient());
  List<Map<String, dynamic>> _currencies = [];
  bool _isLoading = false;
  String? _error;
  int? _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.selectedCurrencyId;
    _loadCurrencies();
  }

  @override
  void didUpdateWidget(CurrencyPickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCurrencyId != widget.selectedCurrencyId) {
      setState(() {
        _selectedValue = widget.selectedCurrencyId;
      });
    }
  }

  Future<void> _loadCurrencies() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final currencies = await _currencyService.listBusinessCurrencies(
        businessId: widget.businessId,
      );
      setState(() {
        _currencies = currencies;
        _isLoading = false;
        
        // اگر ارزی انتخاب نشده و ارز پیشفرض موجود است، آن را انتخاب کن
        if (_selectedValue == null && currencies.isNotEmpty) {
          final defaultCurrency = currencies.firstWhere(
            (currency) => currency['is_default'] == true,
            orElse: () => currencies.first,
          );
          _selectedValue = defaultCurrency['id'] as int;
          widget.onChanged(_selectedValue);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _isLoading = false;
      });
    }
  }

  InputDecoration _decoration({
    OutlineInputBorder? border,
    bool enabled = true,
    String? errorText,
  }) {
    final base = InputDecoration(
      labelText: widget.label ?? 'ارز',
      hintText: widget.hintText ?? 'انتخاب ارز',
      border: border ?? const OutlineInputBorder(),
      enabled: enabled,
      errorText: errorText,
      isDense: widget.isDense,
      contentPadding: widget.isDense
          ? const EdgeInsetsDirectional.only(start: 12, top: 8, bottom: 8, end: 12)
          : null,
    );
    return base;
  }

  Widget _maybeFixedHeight({required Widget child}) {
    if (widget.isDense) return child;
    return SizedBox(height: 56, child: child);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _maybeFixedHeight(
        child: InputDecorator(
          decoration: _decoration(enabled: false),
          child: const Center(
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return _maybeFixedHeight(
        child: InputDecorator(
          decoration: _decoration(
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
            enabled: false,
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'خطا در بارگذاری ارزها',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              TextButton(
                onPressed: _loadCurrencies,
                child: const Text('تلاش مجدد'),
              ),
            ],
          ),
        ),
      );
    }

    if (_currencies.isEmpty) {
      return _maybeFixedHeight(
        child: InputDecorator(
          decoration: _decoration(enabled: false),
          child: const Center(
            child: Text('هیچ ارزی یافت نشد'),
          ),
        ),
      );
    }

    return _maybeFixedHeight(
      child: InputDecorator(
        decoration: _decoration(enabled: widget.enabled),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _selectedValue,
            isExpanded: true,
            iconSize: widget.isDense ? 20 : 24,
            isDense: widget.isDense,
            onChanged: widget.enabled ? (value) {
              setState(() {
                _selectedValue = value;
              });
              widget.onChanged(value);
            } : null,
            items: _currencies.map((currency) {
              final isDefault = currency['is_default'] == true;
              return DropdownMenuItem<int>(
                value: currency['id'] as int,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${currency['title']} (${currency['code']})',
                        style: TextStyle(
                          fontWeight: isDefault ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (isDefault)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'پیش‌فرض',
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
