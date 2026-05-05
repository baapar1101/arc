import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import '../../services/bank_account_service.dart';
import '../../core/api_client.dart';
import '../../services/currency_service.dart';
import '../../widgets/banking/bank_account_form_dialog.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class BankAccountOption {
  final String id;
  final String name;
  final int? currencyId;
  final double? balance;
  const BankAccountOption(this.id, this.name, {this.currencyId, this.balance});
}

class BankAccountComboboxWidget extends StatefulWidget {
  final int businessId;
  final String? selectedAccountId;
  final ValueChanged<BankAccountOption?> onChanged;
  final String label;
  final String hintText;
  final bool isRequired;
  final int? filterCurrencyId;
  /// نمایش به‌صورت [TextFormField] outline فشرده (هم‌ارتفاع با فیلدهای فرم).
  final bool dense;

  const BankAccountComboboxWidget({
    super.key,
    required this.businessId,
    required this.onChanged,
    this.selectedAccountId,
    this.label = 'بانک',
    this.hintText = 'جست‌وجو و انتخاب بانک',
    this.isRequired = false,
    this.filterCurrencyId,
    this.dense = false,
  });

  @override
  State<BankAccountComboboxWidget> createState() => _BankAccountComboboxWidgetState();
}

class _BankAccountComboboxWidgetState extends State<BankAccountComboboxWidget> {
  final BankAccountService _service = BankAccountService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _displayFieldController = TextEditingController();
  Timer? _debounceTimer;
  int _seq = 0;
  String _latestQuery = '';
  void Function(void Function())? _setModalState;
  final CurrencyService _currencyService = CurrencyService(ApiClient());
  Map<int, Map<String, dynamic>> _currencyById = <int, Map<String, dynamic>>{};

  List<BankAccountOption> _items = <BankAccountOption>[];
  bool _isLoading = false;
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _loadCurrencies();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDenseDisplayText();
    });
  }

  @override
  void didUpdateWidget(covariant BankAccountComboboxWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterCurrencyId != widget.filterCurrencyId) {
      // بازخوانی با فیلتر جدید ارز
      _performSearch(_latestQuery);
    }
    if (oldWidget.selectedAccountId != widget.selectedAccountId ||
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
    final selected = _items.firstWhere(
      (e) => e.id == widget.selectedAccountId,
      orElse: () => const BankAccountOption('', ''),
    );
    final currencyText = _formatCurrencyLabel(selected.currencyId);
    if (widget.selectedAccountId != null && widget.selectedAccountId!.isNotEmpty) {
      if (selected.name.isNotEmpty) {
        return currencyText.isNotEmpty ? '${selected.name} - $currencyText' : selected.name;
      }
      return widget.hintText;
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
  }

  Future<void> _loadCurrencies() async {
    try {
      final list = await _currencyService.listBusinessCurrencies(businessId: widget.businessId);
      final map = <int, Map<String, dynamic>>{};
      for (final m in list) {
        final id = m['id'];
        if (id is int) {
          map[id] = m;
        }
      }
      if (!mounted) return;
      setState(() {
        _currencyById = map;
      });
      _syncDenseDisplayText();
    } catch (_) {
      // ignore errors, currency labels will be omitted
    }
  }

  String _formatCurrencyLabel(int? currencyId) {
    if (currencyId == null) return '';
    final m = _currencyById[currencyId];
    if (m == null) return '';
    final code = (m['code'] ?? '').toString();
    final title = (m['title'] ?? '').toString();
    if (code.isNotEmpty && title.isNotEmpty) return code;
    return code.isNotEmpty ? code : title;
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
      final res = await _service.list(
        businessId: widget.businessId,
        queryInfo: {
          'take': query.isEmpty ? 50 : 20,
          'skip': 0,
          if (query.isNotEmpty) 'search': query,
          if (query.isNotEmpty)
            'search_fields': ['code', 'name', 'branch', 'account_number', 'sheba_number', 'card_number', 'owner_name', 'pos_number', 'payment_id'],
        },
      );
      if (seq != _seq || query != _latestQuery) return;
      // پشتیبانی از هر دو ساختار: data.items و items سطح بالا
      final dynamic itemsRaw = (res['data'] != null && res['data'] is Map && (res['data'] as Map)['items'] != null)
          ? (res['data'] as Map)['items']
          : res['items'];
      var items = ((itemsRaw as List<dynamic>? ?? const <dynamic>[])).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = m['id']?.toString();
        final name = m['name']?.toString() ?? 'نامشخص';
        final currencyId = (m['currency_id'] ?? m['currencyId']);
        final balance = m['balance'];
        final balanceValue = balance is num ? balance.toDouble() : (balance != null ? double.tryParse(balance.toString()) : null);
        log('Bank account item: id=$id, name=$name, currencyId=$currencyId, balance=$balanceValue');
        return BankAccountOption(
          id ?? '', 
          name, 
          currencyId: currencyId is int ? currencyId : int.tryParse('${currencyId ?? ''}'),
          balance: balanceValue,
        );
      }).toList();
      // Filter by currency if requested
      if (widget.filterCurrencyId != null) {
        items = items.where((it) => it.currencyId == widget.filterCurrencyId).toList();
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        if (query.isEmpty) {
          _isLoading = false;
          _hasSearched = false;
        } else {
          _isSearching = false;
        }
      });
      _syncDenseDisplayText();
      _setModalState?.call(() {});
    } catch (e) {
      if (seq != _seq || query != _latestQuery) return;
      if (!mounted) return;
      setState(() {
        _items = <BankAccountOption>[];
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
          'خطا در دریافت لیست بانک‌ها: ${ErrorExtractor.forContext(e, context)}',
    );
    }
  }

  Future<void> _addNewBankAccount() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => BankAccountFormDialog(
        businessId: widget.businessId,
        onSuccess: () {},
      ),
    );
    
    if (result == true && mounted) {
      // Refresh لیست
      await _performSearch(_latestQuery);
      
      // پیدا کردن آخرین آیتم اضافه شده (احتمالاً آخرین آیتم در لیست)
      if (_items.isNotEmpty) {
        final lastItem = _items.last;
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
          return _BankPickerBottomSheet(
            label: widget.label,
            hintText: widget.hintText,
            items: _items,
            searchController: _searchController,
            isLoading: _isLoading,
            isSearching: _isSearching,
            hasSearched: _hasSearched,
            onSearchChanged: _onSearchChanged,
            currencyLabelBuilder: _formatCurrencyLabel,
            onSelected: (opt) {
              widget.onChanged(opt);
              Navigator.pop(context);
            },
            onAddNew: _addNewBankAccount,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _items.firstWhere(
      (e) => e.id == widget.selectedAccountId,
      orElse: () => const BankAccountOption('', ''),
    );
    final currencyText = _formatCurrencyLabel(selected.currencyId);
    final text = (widget.selectedAccountId != null && widget.selectedAccountId!.isNotEmpty)
        ? (selected.name.isNotEmpty
            ? (currencyText.isNotEmpty ? '${selected.name} - $currencyText' : selected.name)
            : widget.hintText)
        : widget.hintText;

    if (widget.dense) {
      return TextFormField(
        controller: _displayFieldController,
        readOnly: true,
        onTap: _openPicker,
        validator: widget.isRequired
            ? (_) {
                if (widget.selectedAccountId == null || widget.selectedAccountId!.isEmpty) {
                  return 'انتخاب ${widget.label} الزامی است';
                }
                return null;
              }
            : null,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hintText,
          isDense: true,
          contentPadding: const EdgeInsetsDirectional.only(start: 12, top: 10, bottom: 10, end: 12),
          suffixIconConstraints: const BoxConstraints(maxHeight: 44, maxWidth: 48),
          suffixIcon: Icon(Icons.arrow_drop_down, size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          prefixIcon: Icon(Icons.account_balance, color: theme.colorScheme.primary, size: 20),
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
            Icon(Icons.account_balance, color: theme.colorScheme.primary, size: 20),
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

class _BankPickerBottomSheet extends StatelessWidget {
  final String label;
  final String hintText;
  final List<BankAccountOption> items;
  final TextEditingController searchController;
  final bool isLoading;
  final bool isSearching;
  final bool hasSearched;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<BankAccountOption?> onSelected;
  final String Function(int?)? currencyLabelBuilder;
  final VoidCallback? onAddNew;

  const _BankPickerBottomSheet({
    required this.label,
    required this.hintText,
    required this.items,
    required this.searchController,
    required this.isLoading,
    required this.isSearching,
    required this.hasSearched,
    required this.onSearchChanged,
    required this.currencyLabelBuilder,
    required this.onSelected,
    this.onAddNew,
  });

  String _formatBalance(double balance) {
    final formatter = RegExp(r'\B(?=(\d{3})+(?!\d))');
    final parts = balance.abs().toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(formatter, (m) => ',');
    final formatted = '$intPart.${parts[1]}';
    return balance < 0 ? '-$formatted' : formatted;
  }

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
              if (onAddNew != null)
                IconButton(
                  onPressed: onAddNew,
                  icon: const Icon(Icons.add),
                  tooltip: 'افزودن حساب بانکی جدید',
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
                            Icon(Icons.account_balance, size: 48, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                            const SizedBox(height: 16),
                            Text(
                              hasSearched ? 'بانکی با این مشخصات یافت نشد' : 'بانکی ثبت نشده است',
                              style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7)),
                            ),
                          ],
                        ),
                      )
                      : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final it = items[index];
                          final currencyText = (it.currencyId != null) ? (currencyLabelBuilder?.call(it.currencyId) ?? '') : '';
                          final balanceText = it.balance != null 
                              ? _formatBalance(it.balance!)
                              : null;
                          final subtitleText = balanceText != null 
                              ? (currencyText.isNotEmpty ? '$balanceText $currencyText' : balanceText)
                              : (currencyText.isNotEmpty ? currencyText : null);
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              child: Icon(Icons.account_balance, color: colorScheme.onPrimaryContainer),
                            ),
                            title: Text(it.name),
                            subtitle: subtitleText != null 
                                ? Text(
                                    subtitleText,
                                    style: TextStyle(
                                      color: (it.balance != null && it.balance! < 0)
                                          ? colorScheme.error 
                                          : colorScheme.onSurface,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  )
                                : null,
                            trailing: currencyText.isNotEmpty
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      currencyText,
                                      style: TextStyle(
                                        color: colorScheme.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : null,
                            onTap: () => onSelected(it),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
