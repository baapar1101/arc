import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/petty_cash_service.dart';
import '../../core/api_client.dart';
import '../../services/currency_service.dart';
import '../../widgets/banking/petty_cash_form_dialog.dart';
import '../../utils/snackbar_helper.dart';

class PettyCashOption {
  final String id;
  final String name;
  final int? currencyId;
  const PettyCashOption(this.id, this.name, {this.currencyId});
}

class PettyCashComboboxWidget extends StatefulWidget {
  final int businessId;
  final String? selectedPettyCashId;
  final ValueChanged<PettyCashOption?> onChanged;
  final String label;
  final String hintText;
  final bool isRequired;
  final int? filterCurrencyId;

  const PettyCashComboboxWidget({
    super.key,
    required this.businessId,
    required this.onChanged,
    this.selectedPettyCashId,
    this.label = 'تنخواه‌گردان',
    this.hintText = 'جست‌وجو و انتخاب تنخواه‌گردان',
    this.isRequired = false,
    this.filterCurrencyId,
  });

  @override
  State<PettyCashComboboxWidget> createState() => _PettyCashComboboxWidgetState();
}

class _PettyCashComboboxWidgetState extends State<PettyCashComboboxWidget> {
  final PettyCashService _service = PettyCashService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  int _seq = 0;
  String _latestQuery = '';
  void Function(void Function())? _setModalState;

  List<PettyCashOption> _items = <PettyCashOption>[];
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
  void didUpdateWidget(covariant PettyCashComboboxWidget oldWidget) {
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
          if (query.isNotEmpty) 'search_fields': ['name', 'code', 'description'],
        },
      );
      if (seq != _seq || query != _latestQuery) return;
      final dynamic itemsRaw = (res['data'] != null && res['data'] is Map && (res['data'] as Map)['items'] != null)
          ? (res['data'] as Map)['items']
          : res['items'];
      var items = ((itemsRaw as List<dynamic>? ?? const <dynamic>[])).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final currencyId = (m['currency_id'] ?? m['currencyId']);
        return PettyCashOption(
          '${m['id']}',
          (m['name']?.toString() ?? 'نامشخص'),
          currencyId: currencyId is int ? currencyId : int.tryParse('${currencyId ?? ''}'),
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
        _items = <PettyCashOption>[];
        if (query.isEmpty) {
          _isLoading = false;
          _hasSearched = false;
        } else {
          _isSearching = false;
        }
      });
      _setModalState?.call(() {});
      SnackBarHelper.showError(context, message: 'خطا در دریافت لیست تنخواه‌گردان‌ها: $e');
    }
  }

  Future<void> _addNewPettyCash() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PettyCashFormDialog(
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
          return _PettyCashPickerBottomSheet(
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
            onAddNew: _addNewPettyCash,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _items.firstWhere(
      (e) => e.id == widget.selectedPettyCashId,
      orElse: () => const PettyCashOption('', ''),
    );
    final currencyText = _formatCurrencyLabel(selected.currencyId);
    final text = (widget.selectedPettyCashId != null && widget.selectedPettyCashId!.isNotEmpty)
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
            Icon(Icons.wallet, color: theme.colorScheme.primary, size: 20),
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

class _PettyCashPickerBottomSheet extends StatelessWidget {
  final String label;
  final String hintText;
  final List<PettyCashOption> items;
  final TextEditingController searchController;
  final bool isLoading;
  final bool isSearching;
  final bool hasSearched;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<PettyCashOption?> onSelected;
  final String Function(int?)? currencyLabelBuilder;
  final VoidCallback? onAddNew;

  const _PettyCashPickerBottomSheet({
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
                  tooltip: 'افزودن تنخواه گردان جدید',
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
                            Icon(Icons.wallet, size: 48, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                            const SizedBox(height: 16),
                            Text(
                              hasSearched ? 'تنخواه‌گردانی با این مشخصات یافت نشد' : 'تنخواه‌گردانی ثبت نشده است',
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
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              child: Icon(Icons.wallet, color: colorScheme.onPrimaryContainer),
                            ),
                            title: Text(it.name),
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
