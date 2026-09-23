import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/customer_model.dart';
import '../../services/customer_service.dart';
import '../../core/auth_store.dart';
import '../../core/api_client.dart';
import '../../utils/customer_quick_entry.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/person/person_form_dialog.dart';
import '../../widgets/person/person_financial_balance_banner.dart';
import 'invoice_form_layout.dart';
import '../../models/person_model.dart';
import '../../utils/responsive_helper.dart';

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
  final bool dense;
  final bool enableQuickCreateOnSubmit;

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
    this.dense = false,
    this.enableQuickCreateOnSubmit = false,
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
  final ValueNotifier<_CustomerPickerState> _pickerStateNotifier =
      ValueNotifier<_CustomerPickerState>(
        _CustomerPickerState(
          customers: [],
          isLoading: false,
          isLoadingMore: false,
          hasSearched: false,
          hasMore: false,
        ),
      );
  final FocusNode _fieldFocus = FocusNode();
  final LayerLink _layerLink = LayerLink();
  final ScrollController _overlayScrollController = ScrollController();
  OverlayEntry? _desktopOverlayEntry;
  int _highlightedIndex = -1;
  double _desktopFieldWidth = 0;
  bool _suppressFieldNotifications = false;
  bool _navigatedByKeyboard = false;
  bool _isEditingQuery = false;
  bool _isQuickResolving = false;
  bool _mobilePickerOpen = false;
  int _searchGeneration = 0;
  String _loadedQuery = '';

  double _desktopOverlayHeight(_CustomerPickerState state) {
    if (state.isLoading && state.customers.isEmpty) return 120;
    if (!state.isLoading && state.customers.isEmpty) return 95;
    final extraRow =
        (state.isLoadingMore || (state.isLoading && state.customers.isNotEmpty))
        ? 1
        : 0;
    final rows = state.customers.length + extraRow;
    const rowHeight = 62.0;
    final raw = (rows * rowHeight) + (state.isLoading ? 4 : 0);
    return raw.clamp(95.0, 360.0);
  }

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.selectedCustomer?.name ?? '';
    _fieldFocus.addListener(_onDesktopFocusChanged);
    _overlayScrollController.addListener(_onDesktopOverlayScroll);
    _loadRecentCustomers();
  }

  @override
  void didUpdateWidget(covariant CustomerComboboxWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCustomer?.id != widget.selectedCustomer?.id) {
      if (_fieldFocus.hasFocus && _isEditingQuery) return;
      _setFieldQuiet(widget.selectedCustomer?.name ?? '');
    }
  }

  void _setFieldQuiet(String text) {
    _suppressFieldNotifications = true;
    _searchController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _suppressFieldNotifications = false;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _removeDesktopOverlay();
    _fieldFocus.removeListener(_onDesktopFocusChanged);
    _fieldFocus.dispose();
    _overlayScrollController.removeListener(_onDesktopOverlayScroll);
    _overlayScrollController.dispose();
    _searchController.dispose();
    _pickerStateNotifier.dispose();
    super.dispose();
  }

  bool get _isMobile => ResponsiveHelper.isShellCompactWidth(context);

  void _onDesktopFocusChanged() {
    if (!mounted || _isMobile) return;
    if (_fieldFocus.hasFocus) {
      // TextField's web tap handling can collapse the selection after focus.
      // Apply the selection at the end of the frame so the first keystroke
      // reliably replaces the current customer name.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_fieldFocus.hasFocus) return;
        final textLength = _searchController.text.length;
        _searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: textLength,
        );
      });
      _showDesktopOverlay();
      if (_searchController.text.trim().isEmpty) {
        _loadRecentCustomers();
      }
    } else {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!mounted || _fieldFocus.hasFocus) return;
        _removeDesktopOverlay();
        if (_isEditingQuery) {
          _isEditingQuery = false;
          _setFieldQuiet(widget.selectedCustomer?.name ?? '');
        }
      });
    }
  }

  void _showDesktopOverlay() {
    if (!mounted || _isMobile) return;
    if (_desktopOverlayEntry != null) {
      _desktopOverlayEntry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.of(context);
    _desktopOverlayEntry = OverlayEntry(
      builder: (context) => _buildDesktopOverlay(context),
    );
    overlay.insert(_desktopOverlayEntry!);
  }

  void _removeDesktopOverlay() {
    _desktopOverlayEntry?.remove();
    _desktopOverlayEntry = null;
    _highlightedIndex = -1;
    _navigatedByKeyboard = false;
  }

  void _onDesktopOverlayScroll() {
    if (!_overlayScrollController.hasClients) return;
    final pos = _overlayScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 140) {
      _loadMoreCustomers();
    }
  }

  Widget _buildDesktopOverlay(BuildContext context) {
    final width = _desktopFieldWidth > 280 ? _desktopFieldWidth : 280.0;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (_) {
              _fieldFocus.unfocus();
              _removeDesktopOverlay();
            },
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.topCenter,
          offset: const Offset(0, 6),
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SizedBox(
                width: width,
                child: ValueListenableBuilder<_CustomerPickerState>(
                  valueListenable: _pickerStateNotifier,
                  builder: (context, state, _) => SizedBox(
                    height: _desktopOverlayHeight(state),
                    child: _buildDesktopCustomersList(context, state),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopCustomersList(
    BuildContext context,
    _CustomerPickerState state,
  ) {
    final cs = Theme.of(context).colorScheme;
    if (state.isLoading && state.customers.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (!state.isLoading && state.customers.isEmpty) {
      return const SizedBox(
        height: 90,
        child: Center(child: Text('طرف حسابی یافت نشد')),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.isLoading) const LinearProgressIndicator(minHeight: 2),
        Flexible(
          child: ListView.builder(
            controller: _overlayScrollController,
            itemCount:
                state.customers.length +
                ((state.isLoadingMore ||
                        (state.isLoading && state.customers.isNotEmpty))
                    ? 1
                    : 0),
            itemBuilder: (context, index) {
              if (index == state.customers.length &&
                  (state.isLoadingMore ||
                      (state.isLoading && state.customers.isNotEmpty))) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final customer = state.customers[index];
              final selected = index == _highlightedIndex;
              return Material(
                color: selected
                    ? cs.primary.withValues(alpha: 0.10)
                    : Colors.transparent,
                child: InkWell(
                  onTapDown: (_) => _selectCustomerFromOverlay(customer),
                  child: ListTile(
                    dense: true,
                    title: Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: customer.code != null
                        ? Text('کد: ${customer.code}')
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _selectCustomerFromOverlay(Customer customer) {
    _debounceTimer?.cancel();
    _searchGeneration++;
    _isEditingQuery = false;
    _navigatedByKeyboard = false;
    _setFieldQuiet(customer.name);
    widget.onCustomerChanged(customer);
    _removeDesktopOverlay();
    _fieldFocus.unfocus();
    if (_mobilePickerOpen && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _moveHighlight(int delta) {
    final items = _pickerStateNotifier.value.customers;
    if (items.isEmpty) return;
    _navigatedByKeyboard = true;
    var idx = _highlightedIndex;
    if (idx < 0 || idx >= items.length) {
      idx = delta > 0 ? 0 : items.length - 1;
    } else {
      idx = (idx + delta).clamp(0, items.length - 1);
    }
    if (idx == _highlightedIndex) return;
    setState(() => _highlightedIndex = idx);
    _desktopOverlayEntry?.markNeedsBuild();
  }

  void _selectHighlighted() {
    final items = _pickerStateNotifier.value.customers;
    if (items.isEmpty) return;
    final idx = (_highlightedIndex >= 0 && _highlightedIndex < items.length)
        ? _highlightedIndex
        : 0;
    _selectCustomerFromOverlay(items[idx]);
  }

  KeyEventResult _onFieldKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_desktopOverlayEntry == null) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _removeDesktopOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _loadRecentCustomers() async {
    if (_hasLoadedRecent && !_isSearchMode) return;

    final requestGeneration = ++_searchGeneration;

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _customerService.searchCustomers(
        businessId: widget.businessId,
        limit: 5,
      );

      if (!mounted || requestGeneration != _searchGeneration) return;

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
        _loadedQuery = '';
      });
      // به‌روزرسانی ValueNotifier
      _pickerStateNotifier.value = _CustomerPickerState(
        customers: _customers,
        isLoading: _isLoading,
        isLoadingMore: _isLoadingMore,
        hasSearched: _hasSearched,
        hasMore: _hasMore,
      );
      _highlightedIndex = -1;
      _navigatedByKeyboard = false;
      _desktopOverlayEntry?.markNeedsBuild();
    } catch (e) {
      if (!mounted || requestGeneration != _searchGeneration) return;
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
    _debounceTimer?.cancel();
    _isEditingQuery = true;
    _navigatedByKeyboard = false;
    _highlightedIndex = -1;
    // پاسخ جست‌وجوی قبلی نباید متن یا پیشنهادهای ورودی جدید را بازنویسی کند.
    _searchGeneration++;
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_searchCustomers(query.trim()));
    });
  }

  Future<bool> _searchCustomers(String query) async {
    if (query.isEmpty) {
      await _loadRecentCustomers();
      return true;
    }

    final requestGeneration = ++_searchGeneration;

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
      final result = await _customerService.searchCustomers(
        businessId: widget.businessId,
        searchQuery: query,
        page: 1,
        limit: 20,
      );

      final customers = result['customers'] as List<Customer>;
      if (!mounted || requestGeneration != _searchGeneration) return false;

      setState(() {
        _customers = customers;
        _isLoading = false;
        _hasMore = (result['hasMore'] as bool?) ?? false;
        _currentPage = 1;
        _isLoadingMore = false;
        _loadedQuery = query;
      });
      // به‌روزرسانی ValueNotifier
      _pickerStateNotifier.value = _CustomerPickerState(
        customers: _customers,
        isLoading: _isLoading,
        isLoadingMore: _isLoadingMore,
        hasSearched: _hasSearched,
        hasMore: _hasMore,
      );
      _highlightedIndex = -1;
      _navigatedByKeyboard = false;
      _desktopOverlayEntry?.markNeedsBuild();
      return true;
    } catch (e) {
      if (!mounted || requestGeneration != _searchGeneration) return false;
      setState(() {
        _customers.clear();
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
        _currentPage = 1;
        _loadedQuery = '';
      });
      // به‌روزرسانی ValueNotifier
      _pickerStateNotifier.value = _CustomerPickerState(
        customers: [],
        isLoading: _isLoading,
        isLoadingMore: _isLoadingMore,
        hasSearched: _hasSearched,
        hasMore: _hasMore,
      );
      _highlightedIndex = -1;
      _navigatedByKeyboard = false;
      _desktopOverlayEntry?.markNeedsBuild();
      return false;
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
    final requestGeneration = _searchGeneration;
    final requestQuery = _currentQuery;
    setState(() {
      _isLoadingMore = true;
    });
    _pickerStateNotifier.value = _pickerStateNotifier.value.copyWith(
      isLoadingMore: true,
    );

    try {
      final result = await _customerService.searchCustomers(
        businessId: widget.businessId,
        searchQuery: requestQuery,
        page: nextPage,
        limit: 20,
      );

      if (!mounted ||
          requestGeneration != _searchGeneration ||
          requestQuery != _currentQuery) {
        return;
      }

      final newCustomers = result['customers'] as List<Customer>;
      final existingIds = _customers.map((c) => c.id).toSet();
      final uniqueNewCustomers = newCustomers
          .where((c) => !existingIds.contains(c.id))
          .toList();

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
      _desktopOverlayEntry?.markNeedsBuild();
    } catch (e) {
      if (!mounted ||
          requestGeneration != _searchGeneration ||
          requestQuery != _currentQuery) {
        return;
      }
      setState(() {
        _isLoadingMore = false;
      });
      _pickerStateNotifier.value = _pickerStateNotifier.value.copyWith(
        isLoadingMore: false,
      );
    }
  }

  Future<void> _submitField() async {
    if (_isQuickResolving) return;
    _debounceTimer?.cancel();
    final query = _searchController.text.trim();
    final quickEntry = widget.enableQuickCreateOnSubmit
        ? parseCustomerQuickEntry(query)
        : null;
    var action = resolveCustomerSearchSubmitAction(
      input: query,
      loadedQuery: _loadedQuery,
      suggestionCount: _customers.length,
      hasMoreSuggestions: _hasMore,
      navigatedByKeyboard: _navigatedByKeyboard,
      isLoading: _isLoading,
      quickCreateEnabled: widget.enableQuickCreateOnSubmit,
      inputHasMobile: quickEntry?.mobile != null,
    );

    if (action == CustomerSearchSubmitAction.search) {
      final searched = await _searchCustomers(query);
      if (!searched || !mounted || _searchController.text.trim() != query) {
        if (mounted && !searched) {
          SnackBarHelper.showError(
            context,
            message: 'جست‌وجوی مشتری انجام نشد؛ دوباره تلاش کنید.',
          );
        }
        return;
      }
      action = resolveCustomerSearchSubmitAction(
        input: query,
        loadedQuery: _loadedQuery,
        suggestionCount: _customers.length,
        hasMoreSuggestions: _hasMore,
        navigatedByKeyboard: _navigatedByKeyboard,
        isLoading: _isLoading,
        quickCreateEnabled: widget.enableQuickCreateOnSubmit,
        inputHasMobile: quickEntry?.mobile != null,
      );
    }

    switch (action) {
      case CustomerSearchSubmitAction.selectSuggestion:
        _selectHighlighted();
        break;
      case CustomerSearchSubmitAction.quickCreate:
        await _quickResolveCustomer(query);
        break;
      case CustomerSearchSubmitAction.search:
      case CustomerSearchSubmitAction.waitForSelection:
        break;
    }
  }

  Future<void> _quickResolveCustomer(String query) async {
    final entry = parseCustomerQuickEntry(query);
    if (entry == null) {
      SnackBarHelper.showError(
        context,
        message: 'ورودی مشتری مبهم است؛ یک نام یا یک شماره موبایل وارد کنید.',
      );
      return;
    }

    setState(() => _isQuickResolving = true);
    _desktopOverlayEntry?.markNeedsBuild();
    try {
      final result = await _customerService.quickResolveCustomer(
        businessId: widget.businessId,
        aliasName: entry.aliasName,
        mobile: entry.mobile,
      );
      if (!mounted || _searchController.text.trim() != query) return;

      final customers = result['customers'] as List<Customer>;
      final created = result['created'] == true;
      if (customers.length == 1) {
        final customer = customers.single;
        _selectCustomerFromOverlay(customer);
        if (created) {
          SnackBarHelper.show(
            context,
            message: '${customer.name} ثبت و انتخاب شد',
          );
        }
        return;
      }

      if (customers.isNotEmpty) {
        setState(() {
          _customers = customers;
          _isLoading = false;
          _isSearchMode = true;
          _hasSearched = true;
          _isLoadingMore = false;
          _hasMore = false;
          _loadedQuery = query;
          _currentQuery = query;
          _highlightedIndex = -1;
          _navigatedByKeyboard = false;
        });
        _pickerStateNotifier.value = _CustomerPickerState(
          customers: customers,
          isLoading: false,
          isLoadingMore: false,
          hasSearched: true,
          hasMore: false,
        );
        _showDesktopOverlay();
        _desktopOverlayEntry?.markNeedsBuild();
        SnackBarHelper.show(
          context,
          message: 'چند مشتری مشابه پیدا شد؛ مشتری موردنظر را انتخاب کنید.',
        );
        return;
      }

      SnackBarHelper.showError(
        context,
        message: 'مشتری ثبت نشد؛ دوباره تلاش کنید.',
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isQuickResolving = false);
        _desktopOverlayEntry?.markNeedsBuild();
      }
    }
  }

  Future<void> _applyNewCustomerDialogResult(Person? result) async {
    if (result == null || !mounted) return;

    final personId = result.id;

    if (personId != null) {
      try {
        final customer = await _customerService.getCustomerById(
          businessId: widget.businessId,
          customerId: personId,
        );

        if (customer != null && mounted) {
          widget.onCustomerChanged(customer);
          return;
        }
      } catch (_) {}
    }

    await _loadRecentCustomers();

    if (_customers.isEmpty) return;

    Customer pickLatestCustomer() {
      final sorted = List<Customer>.from(_customers);
      sorted.sort((a, b) => b.id.compareTo(a.id));
      return sorted.first;
    }

    final Customer resolved;
    if (personId != null) {
      final sameId = _customers.where((c) => c.id == personId).toList();
      resolved = sameId.isNotEmpty ? sameId.first : pickLatestCustomer();
    } else {
      resolved = pickLatestCustomer();
    }

    widget.onCustomerChanged(resolved);
  }

  Future<void> _addNewPerson(BuildContext bottomSheetContext) async {
    final searchQuery = _searchController.text.trim();
    Navigator.pop(bottomSheetContext);

    final result = await showDialog<Person?>(
      context: context,
      builder: (context) => PersonFormDialog(
        businessId: widget.businessId,
        onSuccess: () {},
        initialAliasName: searchQuery.isNotEmpty ? searchQuery : null,
      ),
    );

    await _applyNewCustomerDialogResult(result);
  }

  /// افزودن طرف حساب از دکمه + داخل فیلد
  Future<void> _addNewCustomerFromField() async {
    _removeDesktopOverlay();
    FocusManager.instance.primaryFocus?.unfocus();
    final searchQuery = _searchController.text.trim();

    final result = await showDialog<Person?>(
      context: context,
      builder: (context) => PersonFormDialog(
        businessId: widget.businessId,
        onSuccess: () {},
        initialAliasName: searchQuery.isNotEmpty ? searchQuery : null,
      ),
    );

    await _applyNewCustomerDialogResult(result);
  }

  void _showCustomerPicker() {
    // مقداردهی اولیه ValueNotifier
    _pickerStateNotifier.value = _CustomerPickerState(
      customers: _customers,
      isLoading: _isLoading,
      isLoadingMore: _isLoadingMore,
      hasSearched: _hasSearched,
      hasMore: _hasMore,
    );
    _mobilePickerOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        return _CustomerPickerBottomSheet(
          pickerStateNotifier: _pickerStateNotifier,
          selectedCustomer: widget.selectedCustomer,
          onCustomerSelected: (customer) {
            _isEditingQuery = false;
            _navigatedByKeyboard = false;
            _searchGeneration++;
            _setFieldQuiet(customer.name);
            widget.onCustomerChanged(customer);
            Navigator.pop(bottomSheetContext);
          },
          searchController: _searchController,
          onSearchChanged: (query) {
            _onSearchChanged(query);
          },
          onSubmitted: () => unawaited(_submitField()),
          onLoadMore: _loadMoreCustomers,
          onAddNew: () => _addNewPerson(bottomSheetContext),
        );
      },
    ).whenComplete(() => _mobilePickerOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = _isMobile;

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

    if (isMobile) {
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
              Icon(Icons.person_search, color: colorScheme.primary, size: 20),
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
              Tooltip(
                message: 'افزودن طرف حساب جدید',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.add, color: colorScheme.primary, size: 22),
                  onPressed: _addNewCustomerFromField,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
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

    return CompositedTransformTarget(
      link: _layerLink,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          if ((_desktopFieldWidth - w).abs() > 0.5) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if ((_desktopFieldWidth - w).abs() > 0.5) {
                setState(() => _desktopFieldWidth = w);
                _desktopOverlayEntry?.markNeedsBuild();
              }
            });
          }
          return Focus(
            onKeyEvent: _onFieldKeyEvent,
            child: TextField(
              controller: _searchController,
              focusNode: _fieldFocus,
              selectAllOnFocus: true,
              decoration: widget.dense
                  ? InvoiceFormFieldMetrics.mergeDecoration(
                      context,
                      InputDecoration(
                        labelText: widget.label,
                        hintText: widget.hintText,
                        suffixIconConstraints: const BoxConstraints(
                          minHeight: 36,
                          maxHeight: 36,
                          minWidth: 72,
                          maxWidth: 80,
                        ),
                        suffixIcon: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isQuickResolving)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              IconButton(
                                tooltip: 'افزودن طرف حساب جدید',
                                icon: Icon(
                                  Icons.add,
                                  color: colorScheme.primary,
                                  size: 20,
                                ),
                                onPressed: _addNewCustomerFromField,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: InvoiceFormFieldMetrics
                                    .compactSuffixIconConstraints,
                              ),
                              IconButton(
                                tooltip: 'انتخاب پیشرفته',
                                icon: Icon(
                                  Icons.manage_search_rounded,
                                  color: colorScheme.primary,
                                  size: 20,
                                ),
                                onPressed: _showCustomerPicker,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: InvoiceFormFieldMetrics
                                    .compactSuffixIconConstraints,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : InputDecoration(
                      labelText: widget.label,
                      hintText: widget.hintText,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person_search),
                      suffixIconConstraints: const BoxConstraints(
                        minHeight: 40,
                        maxHeight: 40,
                        minWidth: 72,
                        maxWidth: 80,
                      ),
                      suffixIcon: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isQuickResolving)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            IconButton(
                              tooltip: 'افزودن طرف حساب جدید',
                              icon: Icon(Icons.add, color: colorScheme.primary),
                              onPressed: _addNewCustomerFromField,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                            ),
                            IconButton(
                              tooltip: 'انتخاب پیشرفته',
                              icon: Icon(
                                Icons.manage_search_rounded,
                                color: colorScheme.primary,
                              ),
                              onPressed: _showCustomerPicker,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              onTap: () {
                _showDesktopOverlay();
                if (_searchController.text.trim().isEmpty) {
                  _loadRecentCustomers();
                }
              },
              onChanged: (query) {
                if (_suppressFieldNotifications) return;
                // In quick entry, text is a local draft and the invoice customer
                // changes only after an explicit selection or successful create.
                // Other uses keep their existing clear-on-edit behavior.
                if (!widget.enableQuickCreateOnSubmit) {
                  final trimmed = query.trim();
                  if (widget.selectedCustomer != null &&
                      trimmed != (widget.selectedCustomer?.name ?? '').trim()) {
                    widget.onCustomerChanged(null);
                  }
                }
                _onSearchChanged(query);
                _showDesktopOverlay();
              },
              onSubmitted: (_) => unawaited(_submitField()),
            ),
          );
        },
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
  final VoidCallback onSubmitted;
  final VoidCallback onLoadMore;
  final VoidCallback? onAddNew;

  const _CustomerPickerBottomSheet({
    required this.pickerStateNotifier,
    required this.selectedCustomer,
    required this.onCustomerSelected,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSubmitted,
    required this.onLoadMore,
    this.onAddNew,
  });

  @override
  State<_CustomerPickerBottomSheet> createState() =>
      _CustomerPickerBottomSheetState();
}

class _CustomerPickerBottomSheetState
    extends State<_CustomerPickerBottomSheet> {
  late final ScrollController _scrollController;
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchFocus.dispose();
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
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: widget.searchController,
                  focusNode: _searchFocus,
                  selectAllOnFocus: true,
                  decoration: InputDecoration(
                    hintText: 'جست‌وجو در طرف حساب‌ها...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: widget.onSearchChanged,
                  onSubmitted: (_) => widget.onSubmitted(),
                ),
              ),
              SizedBox(
                width: 40,
                height: kMinInteractiveDimension,
                child: ValueListenableBuilder<_CustomerPickerState>(
                  valueListenable: widget.pickerStateNotifier,
                  builder: (context, pickerState, _) {
                    if (!pickerState.isLoading) {
                      return const SizedBox.shrink();
                    }
                    return const Padding(
                      padding: EdgeInsetsDirectional.only(start: 8, top: 12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ValueListenableBuilder<_CustomerPickerState>(
              valueListenable: widget.pickerStateNotifier,
              builder: (context, pickerState, _) {
                return _buildCustomersList(context, pickerState);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomersList(
    BuildContext context,
    _CustomerPickerState pickerState,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // لودینگ اولیه (وقتی هنوز دیتایی نداریم)
    if (pickerState.isLoading && pickerState.customers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (pickerState.customers.isEmpty) {
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
              pickerState.hasSearched
                  ? 'طرف حسابی یافت نشد'
                  : 'هیچ طرف حسابی ثبت نشده است',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // وقتی کاربر عبارت جست‌وجو را عوض می‌کند، یک لودینگ سبک نشان بده بدون اینکه لیست محو شود
        if (pickerState.isLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount:
                pickerState.customers.length +
                ((pickerState.isLoadingMore ||
                        (pickerState.isLoading &&
                            pickerState.customers.isNotEmpty))
                    ? 1
                    : 0),
            itemBuilder: (context, index) {
              // فوتر برای بارگذاری صفحه بعد
              if ((pickerState.isLoadingMore ||
                      (pickerState.isLoading &&
                          pickerState.customers.isNotEmpty)) &&
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
                    ? Icon(Icons.check_circle, color: colorScheme.primary)
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
