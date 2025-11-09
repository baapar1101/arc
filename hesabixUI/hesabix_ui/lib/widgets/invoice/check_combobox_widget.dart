import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/check_service.dart';

class CheckOption {
  final String id;
  final String number;
  final String? personName;
  final String? bankName;
  final String? sayadCode;
  final int? currencyId;
  const CheckOption({
    required this.id,
    required this.number,
    this.personName,
    this.bankName,
    this.sayadCode,
    this.currencyId,
  });
}

class CheckComboboxWidget extends StatefulWidget {
  final int businessId;
  final String? selectedCheckId;
  final ValueChanged<CheckOption?> onChanged;
  final String label;
  final String hintText;
  final int? filterCurrencyId;

  const CheckComboboxWidget({
    super.key,
    required this.businessId,
    required this.onChanged,
    this.selectedCheckId,
    this.label = 'چک',
    this.hintText = 'جست‌وجو و انتخاب چک',
    this.filterCurrencyId,
  });

  @override
  State<CheckComboboxWidget> createState() => _CheckComboboxWidgetState();
}

class _CheckComboboxWidgetState extends State<CheckComboboxWidget> {
  final CheckService _service = CheckService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  void Function(void Function())? _setModalState;

  List<CheckOption> _items = <CheckOption>[];
  bool _isLoading = false;
  bool _isSearching = false;
  bool _hasSearched = false;
  int _seq = 0;
  String _latestQuery = '';

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
          if (query.isNotEmpty) 'search_fields': ['check_number', 'sayad_code', 'person_name'],
        },
      );
      if (seq != _seq || query != _latestQuery) return;
      final dynamic itemsRaw = (res['data'] != null && res['data'] is Map && (res['data'] as Map)['items'] != null)
          ? (res['data'] as Map)['items']
          : res['items'];
      var items = ((itemsRaw as List<dynamic>? ?? const <dynamic>[])).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return CheckOption(
          id: '${m['id']}',
          number: (m['check_number'] ?? '').toString(),
          personName: (m['person_name'] ?? m['holder_name'])?.toString(),
          bankName: (m['bank_name'] ?? '').toString(),
          sayadCode: (m['sayad_code'] ?? '').toString(),
          currencyId: (m['currency_id'] ?? m['currencyId']) is int
              ? (m['currency_id'] ?? m['currencyId']) as int
              : int.tryParse('${m['currency_id'] ?? m['currencyId'] ?? ''}'),
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
        _items = <CheckOption>[];
        if (query.isEmpty) {
          _isLoading = false;
          _hasSearched = false;
        } else {
          _isSearching = false;
        }
      });
      _setModalState?.call(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در دریافت لیست چک‌ها: $e')));
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
      (e) => e.id == widget.selectedCheckId,
      orElse: () => const CheckOption(id: '', number: ''),
    );
    final text = (widget.selectedCheckId != null && widget.selectedCheckId!.isNotEmpty)
        ? (selected.number.isNotEmpty ? selected.number : widget.hintText)
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
}
