import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/check_service.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../pages/business/check_form_page.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

enum CheckPickerMode { any, receipt, payment }

class CheckOption {
  final String id;
  final String number;
  final String? personName;
  final String? bankName;
  final String? sayadCode;
  final int? currencyId;
  final String? status;
  final String? type;
  final double? amount;
  const CheckOption({
    required this.id,
    required this.number,
    this.personName,
    this.bankName,
    this.sayadCode,
    this.currencyId,
    this.status,
    this.type,
    this.amount,
  });
}

class CheckComboboxWidget extends StatefulWidget {
  final int businessId;
  final String? selectedCheckId;
  final String? selectedCheckNumber;
  final ValueChanged<CheckOption?> onChanged;
  final String label;
  final String hintText;
  final int? filterCurrencyId;
  final CheckPickerMode mode;
  final AuthStore? authStore;
  final CalendarController? calendarController;
  /// نمایش به‌صورت [TextFormField] outline فشرده (هم‌ارتفاع با فیلدهای فرم).
  final bool dense;

  const CheckComboboxWidget({
    super.key,
    required this.businessId,
    required this.onChanged,
    this.selectedCheckId,
    this.selectedCheckNumber,
    this.label = 'چک',
    this.hintText = 'جست‌وجو و انتخاب چک',
    this.filterCurrencyId,
    this.mode = CheckPickerMode.any,
    this.authStore,
    this.calendarController,
    this.dense = false,
  });

  @override
  State<CheckComboboxWidget> createState() => _CheckComboboxWidgetState();
}

class _CheckComboboxWidgetState extends State<CheckComboboxWidget> {
  final CheckService _service = CheckService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _displayFieldController = TextEditingController();
  Timer? _debounceTimer;
  void Function(void Function())? _setModalState;

  List<CheckOption> _items = <CheckOption>[];
  CheckOption? _selectedOption;
  bool _isLoading = false;
  bool _isSearching = false;
  bool _hasSearched = false;
  int _seq = 0;
  String _latestQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDenseDisplayText();
    });
  }

  @override
  void didUpdateWidget(covariant CheckComboboxWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCheckId != widget.selectedCheckId) {
      _ensureSelectedCheckLoaded();
    }
    if (oldWidget.selectedCheckNumber != widget.selectedCheckNumber ||
        oldWidget.dense != widget.dense) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncDenseDisplayText();
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _displayFieldController.dispose();
    super.dispose();
  }

  String _displayLineText() {
    if (_selectedOption != null && _selectedOption!.number.isNotEmpty) {
      return _selectedOption!.number;
    }
    if (widget.selectedCheckNumber != null && widget.selectedCheckNumber!.isNotEmpty) {
      return widget.selectedCheckNumber!;
    }
    return widget.hintText;
  }

  void _syncDenseDisplayText() {
    if (!widget.dense) return;
    final next = _displayLineText();
    if (_displayFieldController.text != next) {
      _displayFieldController.text = next;
    }
  }

  Future<void> _load() async {
    await _performSearch('');
    await _ensureSelectedCheckLoaded();
  }

  Future<void> _ensureSelectedCheckLoaded() async {
    final selectedId = widget.selectedCheckId;
    if (selectedId == null || selectedId.isEmpty) {
      if (_selectedOption != null) {
        setState(() => _selectedOption = null);
      }
      _syncDenseDisplayText();
      return;
    }
    final existing = _items.firstWhere(
      (opt) => opt.id == selectedId,
      orElse: () => const CheckOption(id: '', number: ''),
    );
    if (existing.id.isNotEmpty) {
      setState(() {
        _selectedOption = existing;
      });
      _syncDenseDisplayText();
      return;
    }
    try {
      final checkId = int.tryParse(selectedId);
      if (checkId == null) return;
      final res = await _service.getById(checkId);
      if (!mounted || res.isEmpty) return;
      final option = _mapToOption(res);
      setState(() {
        _items = [..._items, option];
        _selectedOption = option;
      });
      _syncDenseDisplayText();
    } catch (_) {
      // نادیده گرفتن خطا برای جلوگیری از قطع تجربه کاربر
    }
  }

  CheckOption _mapToOption(Map<dynamic, dynamic> raw) {
    final m = Map<String, dynamic>.from(raw);
    int? currencyId;
    final currencyRaw = m['currency_id'] ?? m['currencyId'];
    if (currencyRaw is int) {
      currencyId = currencyRaw;
    } else if (currencyRaw != null) {
      currencyId = int.tryParse('$currencyRaw');
    }
    double? amount;
    final amountRaw = m['amount'];
    if (amountRaw is num) {
      amount = amountRaw.toDouble();
    } else if (amountRaw != null) {
      amount = double.tryParse('$amountRaw');
    }
    return CheckOption(
      id: '${m['id']}',
      number: (m['check_number'] ?? '').toString(),
      personName: (m['person_name'] ?? m['holder_name'] ?? m['current_holder_name'])?.toString(),
      bankName: (m['bank_name'] ?? '').toString(),
      sayadCode: (m['sayad_code'] ?? '').toString(),
      currencyId: currencyId,
      status: (m['status'] ?? '').toString(),
      type: (m['type'] ?? '').toString(),
      amount: amount,
    );
  }

  List<Map<String, dynamic>> _buildFilters() {
    final filters = <Map<String, dynamic>>[];
    switch (widget.mode) {
      case CheckPickerMode.receipt:
        filters.add({'property': 'type', 'operator': '=', 'value': 'RECEIVED'});
        filters.add({'property': 'status', 'operator': 'in', 'value': ['RECEIVED_ON_HAND']});
        break;
      case CheckPickerMode.payment:
        filters.add({'property': 'type', 'operator': '=', 'value': 'TRANSFERRED'});
        filters.add({'property': 'status', 'operator': 'in', 'value': ['TRANSFERRED_ISSUED']});
        break;
      case CheckPickerMode.any:
        break;
    }
    if (widget.filterCurrencyId != null) {
      filters.add({
        'property': 'currency',
        'operator': '=',
        'value': widget.filterCurrencyId,
      });
    }
    return filters;
  }

  void _onSearchChanged(String q) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () => _performSearch(q.trim()));
  }

  Future<void> _performSearch(String query) async {
    final int seq = ++_seq;
    _latestQuery = query;
    if (!mounted) return;
    setState(() {
      if (query.isEmpty) {
        _isLoading = true;
        _hasSearched = false;
      } else {
        _isSearching = true;
        _hasSearched = true;
      }
    });
    _setModalState?.call(() {});

    try {
      final filters = _buildFilters();
      final queryInfo = {
        'take': query.isEmpty ? 50 : 20,
        'skip': 0,
        if (query.isNotEmpty) 'search': query,
        if (query.isNotEmpty) 'search_fields': ['check_number', 'sayad_code', 'person_name'],
        if (filters.isNotEmpty) 'filters': filters,
      };
      final res = await _service.list(
        businessId: widget.businessId,
        queryInfo: queryInfo,
      );
      if (seq != _seq || query != _latestQuery) return;
      final dynamic itemsRaw = (res['data'] != null && res['data'] is Map && (res['data'] as Map)['items'] != null)
          ? (res['data'] as Map)['items']
          : res['items'];
      final items = ((itemsRaw as List<dynamic>? ?? const <dynamic>[]))
          .map((e) => _mapToOption(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = items;
        if (query.isEmpty) {
          _isLoading = false;
          _hasSearched = false;
        } else {
          _isSearching = false;
        }
        if (widget.selectedCheckId != null && widget.selectedCheckId!.isNotEmpty) {
          final match = items.firstWhere(
            (e) => e.id == widget.selectedCheckId,
            orElse: () => const CheckOption(id: '', number: ''),
          );
          if (match.id.isNotEmpty) {
            _selectedOption = match;
          }
        }
      });
      _syncDenseDisplayText();
      _setModalState?.call(() {});
    } catch (e) {
      if (seq != _seq || query != _latestQuery) return;
      if (!mounted) return;
      setState(() {
        _items = <CheckOption>[];
        if (query.isEmpty) {
          _isLoading = false;
          _hasSearched = false;
        } else {
          _isSearching = false;
        }
      });
      _syncDenseDisplayText();
      _setModalState?.call(() {});
      SnackBarHelper.showError(
      context,
      message:
          'خطا در دریافت لیست چک‌ها: ${ErrorExtractor.forContext(e, context)}',
    );
    }
  }

  Future<void> _addNewCheck() async {
    if (widget.authStore == null || widget.calendarController == null) {
      SnackBarHelper.show(context, message: 'برای افزودن چک جدید، AuthStore و CalendarController مورد نیاز است');
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => CheckFormDialog(
        businessId: widget.businessId,
        authStore: widget.authStore!,
        calendarController: widget.calendarController,
        onSuccess: () {},
      ),
    );
    
    if (result == true && mounted) {
      // Refresh لیست
      await _performSearch(_latestQuery);
      
      // پیدا کردن آخرین آیتم اضافه شده (احتمالاً آخرین آیتم در لیست)
      if (_items.isNotEmpty) {
        final lastItem = _items.last;
        if (mounted) {
          setState(() {
            _selectedOption = lastItem;
          });
        }
        widget.onChanged(lastItem);
      }
    }
  }

  void _openPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          _setModalState = setModalState;
          return _CheckPickerBottomSheet(
            label: widget.label,
            hintText: widget.hintText,
            items: _items,
            searchController: _searchController,
            isLoading: _isLoading,
            isSearching: _isSearching,
            hasSearched: _hasSearched,
            onSearchChanged: _onSearchChanged,
            onSelected: (opt) {
              if (mounted) {
                setState(() {
                  _selectedOption = opt;
                });
              }
              widget.onChanged(opt);
              _syncDenseDisplayText();
              Navigator.pop(context);
            },
            onAddNew: _addNewCheck,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _displayLineText();

    if (widget.dense) {
      return TextFormField(
        controller: _displayFieldController,
        readOnly: true,
        onTap: _openPicker,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hintText,
          isDense: true,
          contentPadding: const EdgeInsetsDirectional.only(start: 12, top: 10, bottom: 10, end: 12),
          suffixIconConstraints: const BoxConstraints(maxHeight: 44, maxWidth: 48),
          suffixIcon: Icon(Icons.arrow_drop_down, size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          prefixIcon: Icon(Icons.receipt_long, color: theme.colorScheme.primary, size: 20),
          prefixIconConstraints: const BoxConstraints(maxHeight: 44, maxWidth: 48),
          border: const OutlineInputBorder(),
        ),
        style: theme.textTheme.bodyMedium,
      );
    }

    return InkWell(
      onTap: _openPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surface,
        ),
        child: Row(
          children: [
            Icon(Icons.receipt_long, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

class _CheckPickerBottomSheet extends StatelessWidget {
  final String label;
  final String hintText;
  final List<CheckOption> items;
  final TextEditingController searchController;
  final bool isLoading;
  final bool isSearching;
  final bool hasSearched;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<CheckOption?> onSelected;
  final VoidCallback? onAddNew;

  const _CheckPickerBottomSheet({
    required this.label,
    required this.hintText,
    required this.items,
    required this.searchController,
    required this.isLoading,
    required this.isSearching,
    required this.hasSearched,
    required this.onSearchChanged,
    required this.onSelected,
    this.onAddNew,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Text(label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                onPressed: onAddNew ?? () {
                  SnackBarHelper.show(context, message: 'برای افزودن چک جدید، AuthStore و CalendarController مورد نیاز است');
                },
                icon: const Icon(Icons.add),
                tooltip: 'افزودن چک جدید',
                color: colorScheme.primary,
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: hintText,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: onSearchChanged,
                ),
              ),
              SizedBox(
                width: 40,
                height: kMinInteractiveDimension,
                child: isSearching
                    ? const Padding(
                        padding: EdgeInsetsDirectional.only(start: 8, top: 12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long, size: 48, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                            const SizedBox(height: 16),
                            Text(
                              hasSearched ? 'چکی با این مشخصات یافت نشد' : 'چکی ثبت نشده است',
                              style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7)),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final it = items[index];
                          final subtitle = [
                            if ((it.personName ?? '').isNotEmpty) it.personName,
                            if ((it.bankName ?? '').isNotEmpty) it.bankName,
                            if ((it.sayadCode ?? '').isNotEmpty) 'صیاد: ${it.sayadCode}',
                            if ((it.status ?? '').isNotEmpty) _statusLabel(it.status!),
                          ].whereType<String>().join(' | ');
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              child: Icon(Icons.receipt_long, color: colorScheme.onPrimaryContainer),
                            ),
                            title: Text(it.number.isNotEmpty ? it.number : 'چک #${it.id}'),
                            subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
                            onTap: () => onSelected(it),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'RECEIVED_ON_HAND':
        return 'در دست';
      case 'TRANSFERRED_ISSUED':
        return 'صادر شده';
      case 'DEPOSITED':
        return 'سپرده شده';
      case 'CLEARED':
        return 'وصول شده';
      case 'RETURNED':
        return 'عودت شده';
      case 'BOUNCED':
        return 'برگشت خورده';
      case 'ENDORSED':
        return 'واگذار شده';
      default:
        return status;
    }
  }
}
