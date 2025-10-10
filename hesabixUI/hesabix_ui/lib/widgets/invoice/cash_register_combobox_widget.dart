import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/cash_register_service.dart';

class CashRegisterOption {
  final String id;
  final String name;
  const CashRegisterOption(this.id, this.name);
}

class CashRegisterComboboxWidget extends StatefulWidget {
  final int businessId;
  final String? selectedRegisterId;
  final ValueChanged<CashRegisterOption?> onChanged;
  final String label;
  final String hintText;
  final bool isRequired;

  const CashRegisterComboboxWidget({
    super.key,
    required this.businessId,
    required this.onChanged,
    this.selectedRegisterId,
    this.label = 'صندوق',
    this.hintText = 'جست‌وجو و انتخاب صندوق',
    this.isRequired = false,
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
          if (query.isNotEmpty) 'search_fields': ['name', 'code', 'description', 'payment_switch_number', 'payment_terminal_number', 'merchant_id'],
        },
      );
      if (seq != _seq || query != _latestQuery) return;
      final dynamic itemsRaw = (res['data'] != null && res['data'] is Map && (res['data'] as Map)['items'] != null)
          ? (res['data'] as Map)['items']
          : res['items'];
      final items = ((itemsRaw as List<dynamic>? ?? const <dynamic>[])).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return CashRegisterOption('${m['id']}', (m['name']?.toString() ?? 'نامشخص'));
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
        _items = <CashRegisterOption>[];
        if (query.isEmpty) {
          _isLoading = false;
          _hasSearched = false;
        } else {
          _isSearching = false;
        }
      });
      _setModalState?.call(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در دریافت لیست صندوق‌ها: $e')));
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
      (e) => e.id == widget.selectedRegisterId,
      orElse: () => const CashRegisterOption('', ''),
    );
    final text = (widget.selectedRegisterId != null && widget.selectedRegisterId!.isNotEmpty)
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

  const _CashRegisterPickerBottomSheet({
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
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              child: Icon(Icons.point_of_sale, color: colorScheme.onPrimaryContainer),
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
