import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/cash_register_service.dart';
import '../../core/api_client.dart';
import '../../services/currency_service.dart';
import '../../widgets/banking/cash_register_form_dialog.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class CashRegisterOption {
  final String id;
  final String name;
  final int? currencyId;
  final double? balance;
  const CashRegisterOption(this.id, this.name, {this.currencyId, this.balance});
}

class CashRegisterComboboxWidget extends StatefulWidget {
  final int businessId;
  final String? selectedRegisterId;
  final ValueChanged<CashRegisterOption?> onChanged;
  final String label;
  final String hintText;
  final bool isRequired;
  final int? filterCurrencyId;

  const CashRegisterComboboxWidget({
    super.key,
    required this.businessId,
    required this.onChanged,
    this.selectedRegisterId,
    this.label = 'صندوق',
    this.hintText = 'جست‌وجو و انتخاب صندوق',
    this.isRequired = false,
    this.filterCurrencyId,
  });

  @override
  State<CashRegisterComboboxWidget> createState() => _CashRegisterComboboxWidgetState();
}

class _CashRegisterComboboxWidgetState extends State<CashRegisterComboboxWidget> {
  final CashRegisterService _service = CashRegisterService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  int _seq = 0;
  String _latestQuery = '';
  void Function(void Function())? _setModalState;

  List<CashRegisterOption> _items = <CashRegisterOption>[];
  bool _isLoading = false;
  bool _isSearching = false;
  bool _hasSearched = false;
  final CurrencyService _currencyService = CurrencyService(ApiClient());
  Map<int, Map<String, dynamic>> _currencyById = <int, Map<String, dynamic>>{};

  @override
  void initState() {
    super.initState();
    _loadCurrencies();
    _load();
  }

  @override
  void didUpdateWidget(covariant CashRegisterComboboxWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterCurrencyId != widget.filterCurrencyId) {
      _performSearch(_latestQuery);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
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
    } catch (_) {
      // ignore errors
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
          if (query.isNotEmpty) 'search_fields': ['name', 'code', 'description', 'payment_switch_number', 'payment_terminal_number', 'merchant_id'],
        },
      );
      if (seq != _seq || query != _latestQuery) return;
      final dynamic itemsRaw = (res['data'] != null && res['data'] is Map && (res['data'] as Map)['items'] != null)
          ? (res['data'] as Map)['items']
          : res['items'];
      var items = ((itemsRaw as List<dynamic>? ?? const <dynamic>[])).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final currencyId = (m['currency_id'] ?? m['currencyId']);
        final balance = m['balance'];
        final balanceValue = balance is num ? balance.toDouble() : (balance != null ? double.tryParse(balance.toString()) : null);
        return CashRegisterOption(
          '${m['id']}',
          (m['name']?.toString() ?? 'نامشخص'),
          currencyId: currencyId is int ? currencyId : int.tryParse('${currencyId ?? ''}'),
          balance: balanceValue,
        );
      }).toList();
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
      _setModalState?.call(() {});
    } catch (e) {
      if (seq != _seq || query != _latestQuery) return;
      if (!mounted) return;
      setState(() {
        _items = <CashRegisterOption>[];
        if (query.isEmpty) {
          _isLoading = false;
          _hasSearched = false;
        } else {
          _isSearching = false;
        }
      });
      _setModalState?.call(() {});
      SnackBarHelper.showError(
      context,
      message:
          'خطا در دریافت لیست صندوق‌ها: ${ErrorExtractor.forContext(e, context)}',
    );
    }
  }

  Future<void> _addNewCashRegister() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => CashRegisterFormDialog(
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
          return _CashRegisterPickerBottomSheet(
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
            onAddNew: _addNewCashRegister,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _items.firstWhere(
      (e) => e.id == widget.selectedRegisterId,
      orElse: () => const CashRegisterOption('', ''),
    );
    final currencyText = _formatCurrencyLabel(selected.currencyId);
    final text = (widget.selectedRegisterId != null && widget.selectedRegisterId!.isNotEmpty)
        ? (selected.name.isNotEmpty
            ? (currencyText.isNotEmpty ? '${selected.name} - $currencyText' : selected.name)
            : widget.hintText)
        : widget.hintText;

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
            Icon(Icons.point_of_sale, color: theme.colorScheme.primary, size: 20),
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

class _CashRegisterPickerBottomSheet extends StatelessWidget {
  final String label;
  final String hintText;
  final List<CashRegisterOption> items;
  final TextEditingController searchController;
  final bool isLoading;
  final bool isSearching;
  final bool hasSearched;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<CashRegisterOption?> onSelected;
  final String Function(int?)? currencyLabelBuilder;
  final VoidCallback? onAddNew;

  const _CashRegisterPickerBottomSheet({
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
                  tooltip: 'افزودن صندوق جدید',
                  color: colorScheme.primary,
                ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
            onChanged: onSearchChanged,
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
                            Icon(Icons.point_of_sale, size: 48, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                            const SizedBox(height: 16),
                            Text(
                              hasSearched ? 'صندوقی با این مشخصات یافت نشد' : 'صندوقی ثبت نشده است',
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
                              child: Icon(Icons.point_of_sale, color: colorScheme.onPrimaryContainer),
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
