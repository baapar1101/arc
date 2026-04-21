import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/customer_model.dart';
import '../../services/customer_service.dart';
import '../../core/auth_store.dart';
import '../../core/api_client.dart';
import '../../widgets/person/person_form_dialog.dart';
import '../../widgets/person/person_financial_balance_banner.dart';
import '../../models/person_model.dart';

class _CustomerPickerState {
  final List<Customer> customers;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasSearched;
  final bool hasMore;

  _CustomerPickerState({
    required this.customers,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasSearched,
    required this.hasMore,
  });

  _CustomerPickerState copyWith({
    List<Customer>? customers,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasSearched,
    bool? hasMore,
  }) {
    return _CustomerPickerState(
      customers: customers ?? this.customers,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasSearched: hasSearched ?? this.hasSearched,
      hasMore: hasMore ?? this.hasMore,
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
  /// مانده طرف حساب زیر نام داخل همان فیلد (شناسه مشتری همان شخص است)
  final bool showFinancialBalance;

  const CustomerComboboxWidget({
    super.key,
    this.selectedCustomer,
    required this.onCustomerChanged,
    required this.businessId,
    required this.authStore,
    this.isRequired = false,
    this.label = 'طرف حساب',
    this.hintText = 'انتخاب طرف حساب',
    this.showFinancialBalance = false,
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
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _currentPage = 1;
  String _currentQuery = '';
  final ValueNotifier<_CustomerPickerState> _pickerStateNotifier = ValueNotifier<_CustomerPickerState>(
    _CustomerPickerState(
      customers: [],
      isLoading: false,
      isLoadingMore: false,
      hasSearched: false,
      hasMore: false,
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
        _isLoadingMore = false;
        _hasMore = false; // در حالت "اخیرها" صفحه‌بندی نداریم
        _currentPage = 1;
        _currentQuery = '';
      });
      // به‌روزرسانی ValueNotifier
      _pickerStateNotifier.value = _CustomerPickerState(
        customers: _customers,
        isLoading: _isLoading,
        isLoadingMore: _isLoadingMore,
        hasSearched: _hasSearched,
        hasMore: _hasMore,
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasLoadedRecent = true;
        _isSearchMode = false;
        _isLoadingMore = false;
        _hasMore = false;
        _currentPage = 1;
        _currentQuery = '';
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
      _isLoadingMore = false;
      _hasMore = false;
      _currentPage = 1;
      _currentQuery = query;
    });
    // به‌روزرسانی ValueNotifier
    _pickerStateNotifier.value = _pickerStateNotifier.value.copyWith(
      isLoading: _isLoading,
      hasSearched: _hasSearched,
      isLoadingMore: _isLoadingMore,
      hasMore: _hasMore,
    );

    try {
      print('[CustomerCombobox] Calling _customerService.searchCustomers...');
      final result = await _customerService.searchCustomers(
        businessId: widget.businessId,
        searchQuery: query,
        page: 1,
        limit: 20,
      );

      final customers = result['customers'] as List<Customer>;
      print('[CustomerCombobox] Search completed - received ${customers.length} customers');

      setState(() {
        _customers = customers;
        _isLoading = false;
        _hasMore = (result['hasMore'] as bool?) ?? false;
        _currentPage = 1;
        _isLoadingMore = false;
      });
      // به‌روزرسانی ValueNotifier
      _pickerStateNotifier.value = _CustomerPickerState(
        customers: _customers,
        isLoading: _isLoading,
        isLoadingMore: _isLoadingMore,
        hasSearched: _hasSearched,
        hasMore: _hasMore,
      );
      print('[CustomerCombobox] ValueNotifier updated - customers count: ${_pickerStateNotifier.value.customers.length}');
    } catch (e) {
      print('[CustomerCombobox] ERROR in _searchCustomers: $e');
      setState(() {
        _customers.clear();
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
        _currentPage = 1;
      });
      // به‌روزرسانی ValueNotifier
      _pickerStateNotifier.value = _CustomerPickerState(
        customers: [],
        isLoading: _isLoading,
        isLoadingMore: _isLoadingMore,
        hasSearched: _hasSearched,
        hasMore: _hasMore,
      );
    }
  }

  Future<void> _loadMoreCustomers() async {
    // فقط برای حالت جست‌وجو و وقتی صفحه بعدی داریم
    if (!_isSearchMode) return;
    if (_isLoading) return;
    if (_isLoadingMore) return;
    if (!_hasMore) return;
    if (_currentQuery.trim().isEmpty) return;

    final nextPage = _currentPage + 1;
    setState(() {
      _isLoadingMore = true;
    });
    _pickerStateNotifier.value = _pickerStateNotifier.value.copyWith(
      isLoadingMore: true,
    );

    try {
      final result = await _customerService.searchCustomers(
        businessId: widget.businessId,
        searchQuery: _currentQuery,
        page: nextPage,
        limit: 20,
      );

      final newCustomers = result['customers'] as List<Customer>;
      final existingIds = _customers.map((c) => c.id).toSet();
      final uniqueNewCustomers = newCustomers.where((c) => !existingIds.contains(c.id)).toList();

      setState(() {
        _customers = [..._customers, ...uniqueNewCustomers];
        _currentPage = nextPage;
        _hasMore = (result['hasMore'] as bool?) ?? false;
        _isLoadingMore = false;
      });

      _pickerStateNotifier.value = _CustomerPickerState(
        customers: _customers,
        isLoading: _isLoading,
        isLoadingMore: _isLoadingMore,
        hasSearched: _hasSearched,
        hasMore: _hasMore,
      );
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
      });
      _pickerStateNotifier.value = _pickerStateNotifier.value.copyWith(
        isLoadingMore: false,
      );
    }
  }



  Future<void> _addNewPerson(BuildContext bottomSheetContext) async {
    // ذخیره متن جستجو شده
    final searchQuery = _searchController.text.trim();
    
    // بستن bottom sheet قبل از باز کردن dialog
    Navigator.pop(bottomSheetContext);

    final result = await showDialog<Person?>(
      context: context,
      builder: (context) => PersonFormDialog(
        businessId: widget.businessId,
        onSuccess: () {},
        initialAliasName: searchQuery.isNotEmpty ? searchQuery : null,
      ),
    );
    
    if (result != null && mounted) {
      // Customer ID همان Person ID است (چون Customer یک view از Person است)
      final personId = result.id;
      
      if (personId != null) {
        // سعی می‌کنیم Customer را با ID پیدا کنیم
        try {
          final customer = await _customerService.getCustomerById(
            businessId: widget.businessId,
            customerId: personId,
          );
          
          if (customer != null && mounted) {
            widget.onCustomerChanged(customer);
            return;
          }
        } catch (_) {
          // اگر خطا رخ داد، به روش fallback برمی‌گردیم
        }
      }
      
      // Fallback: Refresh لیست و پیدا کردن Customer جدید
      await _loadRecentCustomers();
      
      // پیدا کردن Customer جدید (با بیشترین ID یا با Person ID)
      if (_customers.isNotEmpty) {
        Customer? foundCustomer;
        if (personId != null) {
          // سعی می‌کنیم Customer را با Person ID پیدا کنیم
          foundCustomer = _customers.firstWhere(
            (c) => c.id == personId,
            orElse: () => _customers.first,
          );
        }
        
        if (foundCustomer == null) {
          // اگر پیدا نشد، جدیدترین Customer را انتخاب می‌کنیم
          final sortedCustomers = List<Customer>.from(_customers);
          sortedCustomers.sort((a, b) => b.id.compareTo(a.id));
          foundCustomer = sortedCustomers.first;
        }
        
        widget.onCustomerChanged(foundCustomer);
      }
    }
  }

  void _showCustomerPicker() {
    print('[CustomerCombobox] _showCustomerPicker called - _customers count: ${_customers.length}');
    // مقداردهی اولیه ValueNotifier
    _pickerStateNotifier.value = _CustomerPickerState(
      customers: _customers,
      isLoading: _isLoading,
      isLoadingMore: _isLoadingMore,
      hasSearched: _hasSearched,
      hasMore: _hasMore,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        print('[CustomerCombobox] BottomSheet builder called - _customers count: ${_customers.length}, _isLoading: $_isLoading');
        return _CustomerPickerBottomSheet(
          pickerStateNotifier: _pickerStateNotifier,
          selectedCustomer: widget.selectedCustomer,
          onCustomerSelected: (customer) {
            widget.onCustomerChanged(customer);
            Navigator.pop(bottomSheetContext);
          },
          searchController: _searchController,
          onSearchChanged: (query) {
            print('[CustomerCombobox] onSearchChanged callback called with: "$query"');
            _onSearchChanged(query);
          },
          onLoadMore: _loadMoreCustomers,
          onAddNew: () => _addNewPerson(bottomSheetContext),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final inlineBalance =
        widget.showFinancialBalance && widget.selectedCustomer != null;

    Person? balancePerson;
    if (inlineBalance) {
      final c = widget.selectedCustomer!;
      balancePerson = Person(
        id: c.id,
        businessId: widget.businessId,
        aliasName: c.name,
        personTypes: const [PersonType.customer],
        createdAt: c.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.person_search,
              color: colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: widget.selectedCustomer != null
                  ? (inlineBalance
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.selectedCustomer!.name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: PersonFinancialBalanceBanner(
                                selectedPerson: balancePerson,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          widget.selectedCustomer!.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ))
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
  final VoidCallback onLoadMore;
  final VoidCallback? onAddNew;

  const _CustomerPickerBottomSheet({
    required this.pickerStateNotifier,
    required this.selectedCustomer,
    required this.onCustomerSelected,
    required this.searchController,
    required this.onSearchChanged,
    required this.onLoadMore,
    this.onAddNew,
  });

  @override
  State<_CustomerPickerBottomSheet> createState() => _CustomerPickerBottomSheetState();
}

class _CustomerPickerBottomSheetState extends State<_CustomerPickerBottomSheet> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // کمی قبل از رسیدن به انتها، صفحه بعدی را بگیر
    if (position.pixels >= position.maxScrollExtent - 200) {
      widget.onLoadMore();
    }
  }

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
                  if (widget.onAddNew != null)
                    IconButton(
                      onPressed: widget.onAddNew,
                      icon: const Icon(Icons.add),
                      tooltip: 'افزودن شخص جدید',
                      color: theme.colorScheme.primary,
                    ),
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

    // لودینگ اولیه (وقتی هنوز دیتایی نداریم)
    if (pickerState.isLoading && pickerState.customers.isEmpty) {
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
    return Column(
      children: [
        // وقتی کاربر عبارت جست‌وجو را عوض می‌کند، یک لودینگ سبک نشان بده بدون اینکه لیست محو شود
        if (pickerState.isLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: pickerState.customers.length +
                ((pickerState.isLoadingMore || (pickerState.isLoading && pickerState.customers.isNotEmpty)) ? 1 : 0),
            itemBuilder: (context, index) {
              // فوتر برای بارگذاری صفحه بعد
              if ((pickerState.isLoadingMore || (pickerState.isLoading && pickerState.customers.isNotEmpty)) &&
                  index == pickerState.customers.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }

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
                    if (customer.code != null) Text('کد: ${customer.code}'),
                    if (customer.phone != null) Text('تلفن: ${customer.phone}'),
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
    );
  }
}
