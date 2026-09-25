import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/support/operator_ticket_list_item.dart';

/// Preset inbox views for operators.
enum OperatorInboxView {
  all,
  mine,
  unread,
  unassigned,
  waitingOnCustomer,
  overdue,
}

extension OperatorInboxViewLabel on OperatorInboxView {
  String get label => switch (this) {
        OperatorInboxView.all => 'همه',
        OperatorInboxView.mine => 'تیکت‌های من',
        OperatorInboxView.unread => 'خوانده‌نشده',
        OperatorInboxView.unassigned => 'بدون تخصیص',
        OperatorInboxView.waitingOnCustomer => 'منتظر کاربر',
        OperatorInboxView.overdue => 'معوق SLA',
      };

  IconData get icon => switch (this) {
        OperatorInboxView.all => Icons.inbox_outlined,
        OperatorInboxView.mine => Icons.person_outline,
        OperatorInboxView.unread => Icons.mark_email_unread_outlined,
        OperatorInboxView.unassigned => Icons.person_off_outlined,
        OperatorInboxView.waitingOnCustomer => Icons.hourglass_empty,
        OperatorInboxView.overdue => Icons.warning_amber_outlined,
      };
}

/// Backend search fields for operator ticket inbox queries.
const operatorInboxSearchFields = [
  'title',
  'description',
  'user.first_name',
  'user.last_name',
  'user.email',
];

/// Scrollable operator ticket inbox (list view) backed by search API.
class OperatorInboxList extends StatefulWidget {
  final OperatorInboxView view;
  final int? currentUserId;
  final int? selectedTicketId;
  final int refreshToken;
  final CalendarController? calendarController;
  final ValueChanged<Map<String, dynamic>> onTicketTap;
  final List<FilterItem> extraFilters;
  final Set<int>? selectedIds;
  final ValueChanged<Set<int>>? onSelectionChanged;
  final bool selectionEnabled;

  const OperatorInboxList({
    super.key,
    required this.view,
    this.currentUserId,
    this.selectedTicketId,
    this.refreshToken = 0,
    this.calendarController,
    required this.onTicketTap,
    this.extraFilters = const [],
    this.selectedIds,
    this.onSelectionChanged,
    this.selectionEnabled = false,
  });

  @override
  State<OperatorInboxList> createState() => _OperatorInboxListState();
}

class _OperatorInboxListState extends State<OperatorInboxList> {
  final SupportService _service = SupportService(ApiClient());
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();

  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _refreshing = false;
  String? _error;
  int _page = 0;
  static const _pageSize = 25;
  bool _hasMore = true;
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _search.addListener(_onSearchChanged);
    if (_canLoad()) {
      _load(reset: true);
    }
  }

  bool _canLoad() {
    if (widget.view == OperatorInboxView.mine && widget.currentUserId == null) {
      return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(covariant OperatorInboxList oldWidget) {
    super.didUpdateWidget(oldWidget);

    final viewChanged = oldWidget.view != widget.view;
    final userIdChanged = oldWidget.currentUserId != widget.currentUserId;
    final filtersChanged = _filtersChanged(oldWidget.extraFilters, widget.extraFilters);
    final refreshOnly = oldWidget.refreshToken != widget.refreshToken &&
        !viewChanged &&
        !userIdChanged &&
        !filtersChanged;

    if (viewChanged || filtersChanged) {
      _load(reset: true);
      return;
    }

    if (userIdChanged) {
      if (widget.view == OperatorInboxView.mine) {
        _load(reset: true);
      }
      return;
    }

    if (refreshOnly) {
      _load(reset: true, silent: true);
    }
  }

  bool _filtersChanged(List<FilterItem> a, List<FilterItem> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].property != b[i].property ||
          a[i].operator != b[i].operator ||
          '${a[i].value}' != '${b[i].value}') {
        return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loading || _loadingMore || _refreshing) return;
    if (_scroll.position.extentAfter < 120) {
      _load(reset: false);
    }
  }

  void _onSearchChanged() {
    // Rebuild for clear-button visibility.
    if (mounted) setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      final next = _search.text.trim();
      if (next == _searchQuery) return;
      _searchQuery = next;
      _load(reset: true);
    });
  }

  List<FilterItem> _viewFilters() {
    final uid = widget.currentUserId;
    return switch (widget.view) {
      OperatorInboxView.mine when uid != null => [
          FilterItem(property: 'assigned_operator_id', operator: '==', value: uid),
        ],
      OperatorInboxView.unread => [
        const FilterItem(property: 'is_unread_for_operator', operator: '==', value: 'true'),
      ],
      OperatorInboxView.unassigned => [
        const FilterItem(property: 'assigned_operator_id', operator: 'is_null', value: true),
      ],
      OperatorInboxView.waitingOnCustomer => [
        const FilterItem(property: 'last_message_from_user', operator: '==', value: 'true'),
      ],
      OperatorInboxView.overdue => [
        const FilterItem(property: 'sla_breached', operator: '==', value: true),
      ],
      _ => [],
    };
  }

  Future<void> _load({required bool reset, bool silent = false}) async {
    if (!_canLoad()) return;

    if (reset) {
      if (silent && _items.isNotEmpty) {
        setState(() {
          _refreshing = true;
          _error = null;
        });
      } else {
        setState(() {
          _loading = true;
          _refreshing = false;
          _error = null;
          _page = 0;
          _hasMore = true;
          _items = [];
        });
      }
    } else {
      if (!_hasMore || _loading || _loadingMore || _refreshing) return;
      setState(() => _loadingMore = true);
    }

    final scrollOffset = silent ? _scroll.hasClients ? _scroll.offset : 0.0 : 0.0;
    final take = reset && silent && _items.isNotEmpty
        ? (_items.length < _pageSize ? _pageSize : _items.length)
        : _pageSize;
    final skip = reset ? 0 : _page * _pageSize;

    try {
      final filters = [..._viewFilters(), ...widget.extraFilters];
      final query = QueryInfo(
        search: _searchQuery.isEmpty ? null : _searchQuery,
        searchFields: operatorInboxSearchFields,
        filters: filters.isEmpty ? null : filters,
        sortBy: 'last_message_at',
        sortDesc: true,
        take: take,
        skip: skip,
      ).toJson();

      final result = await _service.searchOperatorTickets(query);
      final rows = result.items.map((t) => t.toJson()).toList();

      if (!mounted) return;
      setState(() {
        if (reset) {
          _items = rows;
          _page = 1;
          _hasMore = rows.length >= take;
        } else {
          _items = [..._items, ...rows];
          _page += 1;
          _hasMore = rows.length >= _pageSize;
        }
        _loading = false;
        _loadingMore = false;
        _refreshing = false;
        _error = null;
      });

      if (silent && _scroll.hasClients && scrollOffset > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            final max = _scroll.position.maxScrollExtent;
            _scroll.jumpTo(scrollOffset.clamp(0.0, max));
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
        _loadingMore = false;
        _refreshing = false;
      });
    }
  }

  void _onSearchSubmitted(String value) {
    _searchDebounce?.cancel();
    final next = value.trim();
    if (next == _searchQuery && !_loading && !_refreshing) return;
    _searchQuery = next;
    _load(reset: true);
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _search.clear();
    if (_searchQuery.isEmpty) return;
    _searchQuery = '';
    _load(reset: true);
  }

  void _toggleSelection(int id, bool? checked) {
    if (widget.onSelectionChanged == null) return;
    final next = Set<int>.from(widget.selectedIds ?? {});
    if (checked == true) {
      next.add(id);
    } else {
      next.remove(id);
    }
    widget.onSelectionChanged!(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waitingForUser = widget.view == OperatorInboxView.mine && widget.currentUserId == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: TextField(
            controller: _search,
            style: theme.textTheme.bodyMedium,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'جستجو عنوان، کاربر، #شماره…',
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              prefixIcon: const Icon(Icons.search, size: 18),
              prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 32),
              suffixIcon: _search.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: _clearSearch,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
            ),
            onSubmitted: _onSearchSubmitted,
          ),
        ),
        if (_refreshing)
          LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        Expanded(
          child: waitingForUser
              ? const Center(child: CircularProgressIndicator())
              : _loading && _items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null && _items.isEmpty
                      ? _ErrorState(message: _error!, onRetry: () => _load(reset: true))
                      : _items.isEmpty
                          ? _EmptyInbox(view: widget.view)
                          : RefreshIndicator(
                              onRefresh: () => _load(reset: true),
                              child: ListView.builder(
                                controller: _scroll,
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: _items.length + (_loadingMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= _items.length) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ),
                                    );
                                  }
                                  final row = _items[index];
                                  final id = row['id'];
                                  final ticketId = id is int ? id : int.tryParse('$id');
                                  final selectionActive = widget.selectionEnabled && widget.onSelectionChanged != null;
                                  return OperatorTicketListItem(
                                    row: row,
                                    isSelected: id == widget.selectedTicketId,
                                    calendarController: widget.calendarController,
                                    onTap: () => widget.onTicketTap(row),
                                    isChecked: selectionActive && ticketId != null
                                        ? (widget.selectedIds?.contains(ticketId) ?? false)
                                        : null,
                                    onToggleSelect: selectionActive && ticketId != null
                                        ? (checked) => _toggleSelection(ticketId, checked)
                                        : null,
                                  );
                                },
                              ),
                            ),
        ),
      ],
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  final OperatorInboxView view;

  const _EmptyInbox({required this.view});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(view.icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              'تیکتی در «${view.label}» یافت نشد',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 40),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('تلاش مجدد')),
          ],
        ),
      ),
    );
  }
}
