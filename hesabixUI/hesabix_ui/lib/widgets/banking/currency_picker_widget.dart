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

  @override
  void initState() {
    super.initState();
    _loadCurrencies();
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
      return const SizedBox(
        height: 56,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Container(
        height: 56,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'خطا در بارگذاری ارزها: $_error',
                style: const TextStyle(color: Colors.red),
              ),
            ),
            TextButton(
              onPressed: _loadCurrencies,
              child: const Text('تلاش مجدد'),
            ),
          ],
        ),
      );
    }

    if (_currencies.isEmpty) {
      return Container(
        height: 56,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text('هیچ ارزی یافت نشد'),
        ),
      );
    }

    return DropdownButtonFormField<int>(
      value: widget.selectedCurrencyId,
      onChanged: widget.enabled ? widget.onChanged : null,
      decoration: InputDecoration(
        labelText: widget.label ?? 'ارز',
        hintText: widget.hintText ?? 'انتخاب ارز',
        border: const OutlineInputBorder(),
        enabled: widget.enabled,
      ),
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
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
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
      validator: (value) {
        if (value == null) {
          return 'انتخاب ارز الزامی است';
        }
        return null;
      },
    );
  }
}
