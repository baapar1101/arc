import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import '../../services/bank_account_service.dart';

class BankAccountOption {
  final String id;
  final String name;
  const BankAccountOption(this.id, this.name);
}

class BankAccountComboboxWidget extends StatefulWidget {
  final int businessId;
  final String? selectedAccountId;
  final ValueChanged<BankAccountOption?> onChanged;
  final String label;
  final String hintText;
  final bool isRequired;

  const BankAccountComboboxWidget({
    super.key,
    required this.businessId,
    required this.onChanged,
    this.selectedAccountId,
    this.label = 'بانک',
    this.hintText = 'جست‌وجو و انتخاب بانک',
    this.isRequired = false,
  });

  @override
  State<BankAccountComboboxWidget> createState() => _BankAccountComboboxWidgetState();
}

class _BankAccountComboboxWidgetState extends State<BankAccountComboboxWidget> {
  final BankAccountService _service = BankAccountService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  int _seq = 0;
  String _latestQuery = '';
  void Function(void Function())? _setModalState;

  List<BankAccountOption> _items = <BankAccountOption>[];
  bool _isLoading = false;
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _load();
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
      final items = ((itemsRaw as List<dynamic>? ?? const <dynamic>[])).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = m['id']?.toString();
        final name = m['name']?.toString() ?? 'نامشخص';
        log('Bank account item: id=$id, name=$name');
        return BankAccountOption(id ?? '', name);
      }).toList();
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
        _items = <BankAccountOption>[];
        if (query.isEmpty) {
          _isLoading = false;
          _hasSearched = false;
        } else {
          _isSearching = false;
        }
      });
      _setModalState?.call(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در دریافت لیست بانک‌ها: $e')));
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
            onSelected: (opt) {
              widget.onChanged(opt);
              Navigator.pop(context);
            },
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
    final text = (widget.selectedAccountId != null && widget.selectedAccountId!.isNotEmpty)
        ? (selected.name.isNotEmpty ? selected.name : widget.hintText)
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

  const _BankPickerBottomSheet({
    required this.label,
    required this.hintText,
    required this.items,
    required this.searchController,
    required this.isLoading,
    required this.isSearching,
    required this.hasSearched,
    required this.onSearchChanged,
    required this.onSelected,
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
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              child: Icon(Icons.account_balance, color: colorScheme.onPrimaryContainer),
                            ),
                            title: Text(it.name),
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
