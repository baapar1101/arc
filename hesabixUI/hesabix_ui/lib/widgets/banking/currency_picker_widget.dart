import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../services/currency_service.dart';

class CurrencyPickerWidget extends StatefulWidget {
  final int? selectedCurrencyId;
  final int businessId;
  final ValueChanged<int?> onChanged;
  final String? label;
  final String? hintText;
  final bool enabled;

  const CurrencyPickerWidget({
    super.key,
    this.selectedCurrencyId,
    required this.businessId,
    required this.onChanged,
    this.label,
    this.hintText,
    this.enabled = true,
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
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return SizedBox(
        height: 56,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: widget.label ?? 'ارز',
            hintText: widget.hintText ?? 'انتخاب ارز',
            border: const OutlineInputBorder(),
            enabled: false,
          ),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (_error != null) {
      return SizedBox(
        height: 56,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: widget.label ?? 'ارز',
            hintText: widget.hintText ?? 'انتخاب ارز',
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.red),
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
      return SizedBox(
        height: 56,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: widget.label ?? 'ارز',
            hintText: widget.hintText ?? 'انتخاب ارز',
            border: const OutlineInputBorder(),
            enabled: false,
          ),
          child: const Center(
            child: Text('هیچ ارزی یافت نشد'),
          ),
        ),
      );
    }

    return SizedBox(
      height: 56, // ارتفاع ثابت مثل سایر فیلدها
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label ?? 'ارز',
          hintText: widget.hintText ?? 'انتخاب ارز',
          border: const OutlineInputBorder(),
          enabled: widget.enabled,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _selectedValue,
            isExpanded: true,
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
