import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/customer_model.dart';
import '../../services/customer_service.dart';
import '../../core/auth_store.dart';
import '../../core/api_client.dart';

class _CustomerPickerState {
  final List<Customer> customers;
  final bool isLoading;
  final bool hasSearched;

  _CustomerPickerState({
    required this.customers,
    required this.isLoading,
    required this.hasSearched,
  });

  _CustomerPickerState copyWith({
    List<Customer>? customers,
    bool? isLoading,
    bool? hasSearched,
  }) {
    return _CustomerPickerState(
      customers: customers ?? this.customers,
      isLoading: isLoading ?? this.isLoading,
      hasSearched: hasSearched ?? this.hasSearched,
    );
  }
}

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
    this.label = 'طرف حساب',
    this.hintText = 'انتخاب طرف حساب',
  });

  @override
  State<CustomerComboboxWidget> createState() => _CustomerComboboxWidgetState();
}

class _CustomerComboboxWidgetState extends State<CustomerComboboxWidget> {
  final CustomerService _customerService = CustomerService(ApiClient());
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  List<Customer> _customers = [];
  bool _isLoading = false;
  bool _hasLoadedRecent = false;
  bool _isSearchMode = false;
  bool _hasSearched = false;
  final ValueNotifier<_CustomerPickerState> _pickerStateNotifier = ValueNotifier<_CustomerPickerState>(
    _CustomerPickerState(
      customers: [],
      isLoading: false,
      hasSearched: false,
    ),
  );

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.selectedCustomer?.name ?? '';
    _loadRecentCustomers();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _pickerStateNotifier.dispose();
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
        _hasSearched = false;
      });
      // به‌روزرسانی ValueNotifier
      _pickerStateNotifier.value = _CustomerPickerState(
        customers: _customers,
        isLoading: _isLoading,
        hasSearched: _hasSearched,
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasLoadedRecent = true;
        _isSearchMode = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    print('[CustomerCombobox] _onSearchChanged called with query: "$query"');
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      print('[CustomerCombobox] Debounce timer fired, calling _searchCustomers with: "${query.trim()}"');
      _searchCustomers(query.trim());
    });
  }

  Future<void> _searchCustomers(String query) async {
    print('[CustomerCombobox] _searchCustomers called with query: "$query"');
    if (query.isEmpty) {
      await _loadRecentCustomers();
      return;
    }

    setState(() {
      _isLoading = true;
      _isSearchMode = true;
      _hasSearched = true;
    });
    // به‌روزرسانی ValueNotifier
    _pickerStateNotifier.value = _pickerStateNotifier.value.copyWith(
      isLoading: _isLoading,
      hasSearched: _hasSearched,
    );

    try {
      print('[CustomerCombobox] Calling _customerService.searchCustomers...');
      final result = await _customerService.searchCustomers(
        businessId: widget.businessId,
        searchQuery: query,
        limit: 20,
      );

      final customers = result['customers'] as List<Customer>;
      print('[CustomerCombobox] Search completed - received ${customers.length} customers');

      setState(() {
        _customers = customers;
        _isLoading = false;
      });
      // به‌روزرسانی ValueNotifier
      _pickerStateNotifier.value = _CustomerPickerState(
        customers: _customers,
        isLoading: _isLoading,
        hasSearched: _hasSearched,
      );
      print('[CustomerCombobox] ValueNotifier updated - customers count: ${_pickerStateNotifier.value.customers.length}');
    } catch (e) {
      print('[CustomerCombobox] ERROR in _searchCustomers: $e');
      setState(() {
        _customers.clear();
        _isLoading = false;
      });
      // به‌روزرسانی ValueNotifier
      _pickerStateNotifier.value = _CustomerPickerState(
        customers: [],
        isLoading: _isLoading,
        hasSearched: _hasSearched,
      );
    }
  }



  void _showCustomerPicker() {
    print('[CustomerCombobox] _showCustomerPicker called - _customers count: ${_customers.length}');
    // مقداردهی اولیه ValueNotifier
    _pickerStateNotifier.value = _CustomerPickerState(
      customers: _customers,
      isLoading: _isLoading,
      hasSearched: _hasSearched,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        print('[CustomerCombobox] BottomSheet builder called - _customers count: ${_customers.length}, _isLoading: $_isLoading');
        return _CustomerPickerBottomSheet(
          pickerStateNotifier: _pickerStateNotifier,
          selectedCustomer: widget.selectedCustomer,
          onCustomerSelected: (customer) {
            widget.onCustomerChanged(customer);
            Navigator.pop(context);
          },
          searchController: _searchController,
          onSearchChanged: (query) {
            print('[CustomerCombobox] onSearchChanged callback called with: "$query"');
            _onSearchChanged(query);
          },
        );
      },
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
  final ValueNotifier<_CustomerPickerState> pickerStateNotifier;
  final Customer? selectedCustomer;
  final Function(Customer) onCustomerSelected;
  final TextEditingController searchController;
  final Function(String) onSearchChanged;

  const _CustomerPickerBottomSheet({
    required this.pickerStateNotifier,
    required this.selectedCustomer,
    required this.onCustomerSelected,
    required this.searchController,
    required this.onSearchChanged,
  });

  @override
  State<_CustomerPickerBottomSheet> createState() => _CustomerPickerBottomSheetState();
}

class _CustomerPickerBottomSheetState extends State<_CustomerPickerBottomSheet> {
  @override
  Widget build(BuildContext context) {
    print('[CustomerPickerBottomSheet] build called');
    final theme = Theme.of(context);

    return ValueListenableBuilder<_CustomerPickerState>(
      valueListenable: widget.pickerStateNotifier,
      builder: (context, pickerState, _) {
        print('[CustomerPickerBottomSheet] ValueListenableBuilder rebuild - customers count: ${pickerState.customers.length}, isLoading: ${pickerState.isLoading}, hasSearched: ${pickerState.hasSearched}');
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // هدر
              Row(
                children: [
                  Text(
                    'انتخاب طرف حساب',
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
                  hintText: 'جست‌وجو در طرف حساب‌ها...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: pickerState.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                onChanged: (value) {
                  print('[CustomerPickerBottomSheet] TextField onChanged called with: "$value"');
                  print('[CustomerPickerBottomSheet] Current customers count: ${pickerState.customers.length}');
                  print('[CustomerPickerBottomSheet] Calling onSearchChanged callback...');
                  widget.onSearchChanged(value);
                  print('[CustomerPickerBottomSheet] onSearchChanged callback completed');
                },
              ),
              const SizedBox(height: 16),
              
              // لیست طرف حساب‌ها
              Expanded(
                child: _buildCustomersList(context, pickerState),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCustomersList(BuildContext context, _CustomerPickerState pickerState) {
    print('[CustomerPickerBottomSheet] _buildCustomersList called - customers count: ${pickerState.customers.length}, isLoading: ${pickerState.isLoading}');
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (pickerState.isLoading) {
      print('[CustomerPickerBottomSheet] Showing loading indicator');
      return const Center(child: CircularProgressIndicator());
    }

    if (pickerState.customers.isEmpty) {
      print('[CustomerPickerBottomSheet] Showing empty state');
      return Center(
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
              pickerState.hasSearched ? 'طرف حسابی یافت نشد' : 'هیچ طرف حسابی ثبت نشده است',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    print('[CustomerPickerBottomSheet] Building ListView with ${pickerState.customers.length} items');
    return ListView.builder(
      itemCount: pickerState.customers.length,
      itemBuilder: (context, index) {
        final customer = pickerState.customers[index];
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
    );
  }
}
