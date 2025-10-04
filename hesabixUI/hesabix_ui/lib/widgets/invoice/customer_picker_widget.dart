import 'package:flutter/material.dart';
import '../../models/customer_model.dart';
import '../../services/customer_service.dart';
import '../../core/auth_store.dart';
import '../../core/api_client.dart';

class CustomerPickerWidget extends StatefulWidget {
  final Customer? selectedCustomer;
  final ValueChanged<Customer?> onCustomerChanged;
  final int businessId;
  final AuthStore authStore;
  final bool isRequired;
  final String? label;
  final String? hintText;

  const CustomerPickerWidget({
    super.key,
    this.selectedCustomer,
    required this.onCustomerChanged,
    required this.businessId,
    required this.authStore,
    this.isRequired = false,
    this.label =
        'مشتری',
    this.hintText = 'خویشتنفروش',
  });

  @override
  State<CustomerPickerWidget> createState() => _CustomerPickerWidgetState();
}

class _CustomerPickerWidgetState extends State<CustomerPickerWidget> {
  final CustomerService _customerService = CustomerService(ApiClient());
  final TextEditingController _searchController = TextEditingController();
  List<Customer> _customers = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.selectedCustomer?.name ?? '';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchCustomers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _customers.clear();
        _hasSearched = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _customerService.searchCustomers(
        businessId: widget.businessId,
        searchQuery: query.trim(),
        limit: 50,
      );

      setState(() {
        _customers = result['customers'] as List<Customer>;
        _hasSearched = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _customers.clear();
        _hasSearched = true;
        _isLoading = false;
      });
    }
  }

  void _selectCustomer(Customer customer) {
    setState(() {
      _searchController.text = customer.name;
    });
    widget.onCustomerChanged(customer);
  }

  void _clearSelection() {
    setState(() {
      _searchController.clear();
    });
    widget.onCustomerChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // هدر
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.person_search_outlined,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label!,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.isRequired)
                  Text(
                    ' *',
                    style: TextStyle(
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),

          // فیلد جست‌وجو
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: widget.hintText,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _clearSelection();
                        },
                      )
                    : _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
              ),
              onChanged: (value) {
                if (value.length >= 2) {
                  _searchCustomers(value);
                } else if (value.isEmpty) {
                  _clearSelection();
                }
              },
            ),
          ),

          // لیست نتایج جست‌وجو
          if (_hasSearched && _customers.isNotEmpty) ...[
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _customers.length,
                itemBuilder: (context, index) {
                  final customer = _customers[index];
                  final isSelected = widget.selectedCustomer?.id == customer.id;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.person,
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    title: Text(
                      customer.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (customer.code != null)
                          Text(
                            'کد: ${customer.code}',
                            style: theme.textTheme.bodySmall,
                          ),
                        if (customer.phone != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'تلفن: ${customer.phone}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_circle,
                            color: colorScheme.primary,
                          )
                        : null,
                    selected: isSelected,
                    selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
                    onTap: () => _selectCustomer(customer),
                  );
                },
              ),
            ),
          ],

          // پیام خطا یا عدم وجود نتیجه
          if (_hasSearched && _customers.isEmpty && _errorMessage == null) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_off,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'مشتری‌ای با این مشخصات یافت نشد',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // پیام خطا
          if (_errorMessage != null) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: colorScheme.onErrorContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'خطا در جست‌وجو: ${_errorMessage!.split(':').last}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // نمایش مشتری انتخاب شده
          if (widget.selectedCustomer != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'مشتری انتخاب شده: ${widget.selectedCustomer!.name}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
