import 'package:hesabix_ui/theme/glass.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/support/ticket_details_dialog.dart';
import 'package:hesabix_ui/services/support_realtime_service.dart';
import 'package:hesabix_ui/widgets/support/operator_command_palette.dart';
import 'package:hesabix_ui/widgets/support/operator_inbox_list.dart';
import 'package:hesabix_ui/widgets/support/operator_inbox_splitter.dart';

/// Breakpoint for split inbox + detail workspace.
const kOperatorSplitBreakpoint = 960.0;

/// Primary chips shown in the toolbar; the rest live under «بیشتر».
const _kPrimaryInboxViews = <OperatorInboxView>[
  OperatorInboxView.all,
  OperatorInboxView.mine,
  OperatorInboxView.unread,
  OperatorInboxView.unassigned,
];

const _kSecondaryInboxViews = <OperatorInboxView>[
  OperatorInboxView.waitingOnCustomer,
  OperatorInboxView.overdue,
];

class OperatorTicketsPage extends StatefulWidget {
  final CalendarController? calendarController;
  final int? initialTicketId;
  final AuthStore? authStore;
  final OperatorInboxView? initialInboxView;

  const OperatorTicketsPage({
    super.key,
    this.calendarController,
    this.initialTicketId,
    this.authStore,
    this.initialInboxView,
  });

  @override
  State<OperatorTicketsPage> createState() => _OperatorTicketsPageState();
}

class _OperatorTicketsPageState extends State<OperatorTicketsPage> {
  Set<int> _selectedRows = <int>{};
  final SupportService _supportService = SupportService(ApiClient());

  List<SupportStatus> _statuses = [];
  int _refreshCounter = 0;
  bool _isSuperAdmin = false;
  int? _currentUserId;
  bool _selectionMode = false;

  SupportTicket? _selectedTicket;
  bool _selectedTicketLoading = false;
  int? _selectedTicketId;

  SupportRealtimeService? _realtime;
  Timer? _pollTimer;
  DateTime? _lastRefreshBump;
  Timer? _refreshThrottle;
  bool _wsConnected = false;

  OperatorInboxView _inboxView = OperatorInboxView.unread;

  @override
  void initState() {
    super.initState();
    if (widget.initialInboxView != null) {
      _inboxView = widget.initialInboxView!;
    }
    _loadMetadata();
    _loadSession();
    _startPolling();
    _connectRealtime();
    final ticketId = widget.initialTicketId;
    if (ticketId != null && ticketId > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final wide = MediaQuery.sizeOf(context).width >= kOperatorSplitBreakpoint;
        if (wide) {
          _openTicketInSplitView(ticketId);
        } else {
          context.push('/user/profile/operator/tickets/$ticketId');
        }
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _refreshThrottle?.cancel();
    _realtime?.disconnect();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // Fallback only while WebSocket is down.
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted || _wsConnected) return;
      _bumpRefresh(immediate: true);
    });
  }

  void _bumpRefresh({bool immediate = false}) {
    if (!mounted) return;
    if (immediate) {
      setState(() => _refreshCounter++);
      _lastRefreshBump = DateTime.now();
      return;
    }
    final last = _lastRefreshBump;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 2)) {
      _refreshThrottle?.cancel();
      _refreshThrottle = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _refreshCounter++);
        _lastRefreshBump = DateTime.now();
      });
      return;
    }
    setState(() => _refreshCounter++);
    _lastRefreshBump = DateTime.now();
  }

  void _connectRealtime() {
    final apiKey = widget.authStore?.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    _realtime = createSupportRealtimeService();
    _realtime!.connect(
      apiKey: apiKey,
      onStatus: (connected) {
        if (!mounted) return;
        _wsConnected = connected;
      },
      onEvent: (event) {
        if ('${event['type']}' != 'support') return;
        if (!mounted) return;
        _wsConnected = true;
        _bumpRefresh();
        final eventTicketId = event['ticket_id'];
        if (eventTicketId is int && eventTicketId == _selectedTicketId) {
          _reloadSelectedTicket();
        }
      },
    );
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future<void> _loadMetadata() async {
    try {
      final statuses = await _supportService.getStatuses();
      _safeSetState(() => _statuses = statuses);
    } catch (_) {}
  }

  Future<void> _loadSession() async {
    try {
      final response = await ApiClient().get<Map<String, dynamic>>('/api/v1/auth/me');
      final data = response.data?['data'] as Map<String, dynamic>?;
      final permissions = data?['permissions'] as Map<String, dynamic>?;
      _safeSetState(() {
        _isSuperAdmin = permissions?['is_superadmin'] as bool? ?? false;
        _currentUserId = data?['id'] as int?;
      });
    } catch (_) {}
  }

  Future<void> _assignToMe() async {
    if (_selectedRows.isEmpty || _currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لطفاً حداقل یک تیکت انتخاب کنید')));
      return;
    }
    try {
      final result = await _supportService.bulkAssignTickets(_selectedRows.toList(), _currentUserId!);
      _safeSetState(() {
        _selectedRows.clear();
        _selectionMode = false;
        _refreshCounter++;
      });
      if (mounted) {
        SnackBarHelper.showSuccess(
          context,
          message: '${result['updated_count']} تیکت به شما تخصیص داده شد',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    }
  }

  Future<void> _markResolved() async {
    if (_selectedRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لطفاً حداقل یک تیکت انتخاب کنید')));
      return;
    }
    if (_statuses.isEmpty) return;
    final resolvedStatus = _statuses.firstWhere(
      (s) => s.name.toLowerCase().contains('حل') || s.name.toLowerCase().contains('resolved'),
      orElse: () => _statuses.firstWhere((s) => s.isFinal, orElse: () => _statuses.last),
    );
    try {
      final result = await _supportService.bulkUpdateStatus(
        _selectedRows.toList(),
        resolvedStatus.id,
        assignedOperatorId: _currentUserId,
      );
      _safeSetState(() {
        _selectedRows.clear();
        _selectionMode = false;
        _refreshCounter++;
      });
      if (mounted) {
        SnackBarHelper.showSuccess(
          context,
          message: '${result['updated_count']} تیکت حل‌شده شد',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    }
  }

  bool get _isWide => MediaQuery.sizeOf(context).width >= kOperatorSplitBreakpoint;

  void _navigateToTicketDetail(Map<String, dynamic> ticketData) {
    final ticketId = ticketData['id'];
    if (ticketId is! int) return;
    if (_isWide) {
      _openTicketInSplitView(ticketId);
      return;
    }
    context.push('/user/profile/operator/tickets/$ticketId');
  }

  Future<void> _openTicketInSplitView(int ticketId) async {
    if (_selectedTicketId == ticketId && _selectedTicket != null) return;
    final previousId = _selectedTicketId;
    _safeSetState(() {
      _selectedTicketId = ticketId;
      _selectedTicket = null;
      _selectedTicketLoading = true;
    });
    if (previousId != null && previousId != ticketId) {
      _realtime?.unsubscribeTicket(previousId);
    }
    _realtime?.subscribeTicket(ticketId);
    try {
      final ticket = await _supportService.getOperatorTicket(ticketId);
      _safeSetState(() {
        _selectedTicket = ticket;
        _selectedTicketLoading = false;
      });
    } catch (e) {
      _safeSetState(() => _selectedTicketLoading = false);
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    }
  }

  Future<void> _reloadSelectedTicket() async {
    final id = _selectedTicketId;
    if (id == null) return;
    try {
      final ticket = await _supportService.getOperatorTicket(id);
      _safeSetState(() => _selectedTicket = ticket);
    } catch (_) {}
  }

  Future<void> _deleteTicket(int ticketId) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأیید حذف'),
        content: const Text('آیا مطمئن هستید که می‌خواهید این تیکت را حذف کنید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.delete)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _supportService.deleteTicket(ticketId);
      _safeSetState(() {
        _selectedRows.remove(ticketId);
        if (_selectedTicketId == ticketId) {
          _selectedTicketId = null;
          _selectedTicket = null;
        }
        _refreshCounter++;
      });
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    }
  }

  void _showCommandPalette() {
    OperatorCommandPalette.show(
      context,
      OperatorCommandPalette(
        onSelectView: (view) => _safeSetState(() => _inboxView = view),
        onRefresh: () => _bumpRefresh(immediate: true),
        onAssignToMe: () {
          if (_selectedTicketId != null) {
            _safeSetState(() => _selectedRows = {_selectedTicketId!});
          }
          _assignToMe();
        },
        onMarkResolved: () {
          if (_selectedTicketId != null) {
            _safeSetState(() => _selectedRows = {_selectedTicketId!});
          }
          _markResolved();
        },
        onOpenTicket: (id) {
          if (_isWide) {
            _openTicketInSplitView(id);
          } else {
            context.push('/user/profile/operator/tickets/$id');
          }
        },
      ),
    );
  }

  Widget _buildInboxList() {
    final selectionOn = _selectionMode || _selectedRows.isNotEmpty;
    return OperatorInboxList(
      view: _inboxView,
      currentUserId: _currentUserId,
      selectedTicketId: _selectedTicketId,
      refreshToken: _refreshCounter,
      calendarController: widget.calendarController,
      onTicketTap: _navigateToTicketDetail,
      selectionEnabled: selectionOn,
      selectedIds: _selectedRows,
      onSelectionChanged: (ids) => _safeSetState(() {
        _selectedRows = ids;
        if (ids.isEmpty) _selectionMode = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK): const _OpenCommandPaletteIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK): const _OpenCommandPaletteIntent(),
      },
      child: Actions(
        actions: {
          _OpenCommandPaletteIntent: CallbackAction<_OpenCommandPaletteIntent>(
            onInvoke: (_) {
              _showCommandPalette();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCompactToolbar(t, theme),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final useSplit = constraints.maxWidth >= kOperatorSplitBreakpoint;
                    if (useSplit) {
                      return OperatorInboxSplitter(
                        left: _buildInboxList(),
                        right: _buildSplitDetailPanel(),
                      );
                    }
                    return _buildInboxList();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactToolbar(AppLocalizations t, ThemeData theme) {
    final secondarySelected = _kSecondaryInboxViews.contains(_inboxView);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.support_agent, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  t.operatorPanel,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: _selectionMode ? 'لغو انتخاب' : 'انتخاب چندتایی',
                  icon: Icon(
                    _selectionMode ? Icons.checklist_rtl : Icons.checklist,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _safeSetState(() {
                    _selectionMode = !_selectionMode;
                    if (!_selectionMode) _selectedRows.clear();
                  }),
                ),
                IconButton(
                  tooltip: 'دستورات سریع (Ctrl+K)',
                  icon: const Icon(Icons.bolt_outlined, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: _showCommandPalette,
                ),
                IconButton(
                  tooltip: 'بروزرسانی',
                  icon: const Icon(Icons.refresh, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _bumpRefresh(immediate: true),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ..._kPrimaryInboxViews.map((view) {
                    final selected = _inboxView == view;
                    return Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: ChoiceChip(
                        avatar: Icon(view.icon, size: 14),
                        label: Text(view.label, style: const TextStyle(fontSize: 11)),
                        selected: selected,
                        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        labelPadding: const EdgeInsets.only(left: 2, right: 4),
                        onSelected: (_) => _safeSetState(() => _inboxView = view),
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: PopupMenuButton<OperatorInboxView>(
                      tooltip: 'فیلترهای بیشتر',
                      initialValue: secondarySelected ? _inboxView : null,
                      onSelected: (view) => _safeSetState(() => _inboxView = view),
                      itemBuilder: (context) => _kSecondaryInboxViews
                          .map(
                            (v) => PopupMenuItem(
                              value: v,
                              child: Row(
                                children: [
                                  Icon(v.icon, size: 16),
                                  const SizedBox(width: 8),
                                  Text(v.label),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      child: Chip(
                        avatar: Icon(
                          secondarySelected ? _inboxView.icon : Icons.more_horiz,
                          size: 14,
                        ),
                        label: Text(
                          secondarySelected ? _inboxView.label : 'بیشتر',
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        labelPadding: const EdgeInsets.only(left: 2, right: 4),
                        side: BorderSide(
                          color: secondarySelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_selectedRows.isNotEmpty) ...[
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text(
                      '${_selectedRows.length} انتخاب‌شده',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: _assignToMe,
                      icon: const Icon(Icons.person_add_outlined, size: 16),
                      label: const Text('تخصیص به من'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.tonalIcon(
                      onPressed: _markResolved,
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('حل‌شده'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    if (_isSuperAdmin) ...[
                      const SizedBox(width: 6),
                      FilledButton.tonalIcon(
                        onPressed: () => _deleteTicket(_selectedRows.first),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('حذف'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: () => _safeSetState(() {
                        _selectedRows.clear();
                        _selectionMode = false;
                      }),
                      child: const Text('لغو'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSplitDetailPanel() {
    final theme = Theme.of(context);
    if (_selectedTicketId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 44, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 10),
            Text('تیکتی انتخاب نشده', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'از لیست یک تیکت را انتخاب کنید',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    if (_selectedTicketLoading || _selectedTicket == null) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    return TicketDetailsDialog(
      key: ValueKey(_selectedTicket!.id),
      ticket: _selectedTicket!,
      isOperator: true,
      calendarController: widget.calendarController,
      displayMode: TicketDetailDisplayMode.embedded,
      onTicketUpdated: () {
        _bumpRefresh();
        _reloadSelectedTicket();
      },
    );
  }
}

class _OpenCommandPaletteIntent extends Intent {
  const _OpenCommandPaletteIntent();
}
