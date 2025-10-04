import 'package:flutter/material.dart';
import '../../models/customer_model.dart';
import '../../services/customer_service.dart';
import '../../core/auth_store.dart';
import '../../core/api_client.dart';

class CustomerComboboxWidget extends StatefulWidget {
  final Customer? selectedCustomer;
  final ValueChanged<Customer?> onCustomerChanged;
  final int businessId;
  final AuthStore authStore;
  final bool isRequired;
  final String? label;
  final String? hintText;

  const CustomerComboboxWidget({
    super.key,
    this.selectedCustomer,
    required this.onCustomerChanged,
    required this.businessId,
    required this.authStore,
    this.isRequired = false,
    this.label = 'مشتری',
    this.hintText = 'انتخاب مشتری',
  });

  @override
  State<CustomerComboboxWidget> createState() => _CustomerComboboxWidgetState();
}

class _CustomerComboboxWidgetState extends State<CustomerComboboxWidget> {
  final CustomerService _customerService = CustomerService(ApiClient());
  final TextEditingController _searchController = TextEditingController();
  List<Customer> _customers = [];
  bool _isLoading = false;
  bool _hasLoadedRecent = false;
  bool _isSearchMode = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.selectedCustomer?.name ?? '';
    _loadRecentCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentCustomers() async {
    if (_hasLoadedRecent && !_isSearchMode) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _customerService.searchCustomers(
        businessId: widget.businessId,
        limit: 5,
      );

      setState(() {
        _customers = result['customers'] as List<Customer>;
        _isLoading = false;
        _hasLoadedRecent = true;
        _isSearchMode = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasLoadedRecent = true;
        _isSearchMode = false;
      });
    }
  }

  Future<void> _searchCustomers(String query) async {
    if (query.trim().isEmpty) {
      await _loadRecentCustomers();
      return;
    }

    setState(() {
      _isLoading = true;
      _isSearchMode = true;
    });

    try {
      final result = await _customerService.searchCustomers(
        businessId: widget.businessId,
        searchQuery: query.trim(),
        limit: 20,
      );

      setState(() {
        _customers = result['customers'] as List<Customer>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _customers.clear();
        _isLoading = false;
      });
    }
  }



  void _showCustomerPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CustomerPickerBottomSheet(
        customers: _customers,
        selectedCustomer: widget.selectedCustomer,
        onCustomerSelected: (customer) {
          widget.onCustomerChanged(customer);
          Navigator.pop(context);
        },
        searchController: _searchController,
        onSearchChanged: _searchCustomers,
        isLoading: _isLoading,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: _showCustomerPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(8),
          color: colorScheme.surface,
        ),
        child: Row(
          children: [
            Icon(
              Icons.person_search,
              color: colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: widget.selectedCustomer != null
                  ? Text(
                      widget.selectedCustomer!.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    )
                  : Text(
                      widget.hintText!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

}

class _CustomerPickerBottomSheet extends StatefulWidget {
  final List<Customer> customers;
  final Customer? selectedCustomer;
  final Function(Customer) onCustomerSelected;
  final TextEditingController searchController;
  final Function(String) onSearchChanged;
  final bool isLoading;

  const _CustomerPickerBottomSheet({
    required this.customers,
    required this.selectedCustomer,
    required this.onCustomerSelected,
    required this.searchController,
    required this.onSearchChanged,
    required this.isLoading,
  });

  @override
  State<_CustomerPickerBottomSheet> createState() => _CustomerPickerBottomSheetState();
}

class _CustomerPickerBottomSheetState extends State<_CustomerPickerBottomSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // هدر
          Row(
            children: [
              Text(
                'انتخاب مشتری',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // فیلد جست‌وجو
          TextField(
            controller: widget.searchController,
            decoration: InputDecoration(
              hintText: 'جست‌وجو در مشتریان...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: widget.onSearchChanged,
          ),
          const SizedBox(height: 16),
          
          // لیست مشتریان
          Expanded(
            child: widget.isLoading
                ? const Center(child: CircularProgressIndicator())
                : widget.customers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_off,
                              size: 48,
                              color: colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'مشتری‌ای یافت نشد',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: widget.customers.length,
                        itemBuilder: (context, index) {
                          final customer = widget.customers[index];
                          final isSelected = widget.selectedCustomer?.id == customer.id;
                          
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              child: Icon(
                                Icons.person,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                            title: Text(customer.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (customer.code != null)
                                  Text('کد: ${customer.code}'),
                                if (customer.phone != null)
                                  Text('تلفن: ${customer.phone}'),
                              ],
                            ),
                            trailing: isSelected
                                ? Icon(
                                    Icons.check_circle,
                                    color: colorScheme.primary,
                                  )
                                : null,
                            onTap: () => widget.onCustomerSelected(customer),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

}
