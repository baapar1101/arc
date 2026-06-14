import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/models/ai_models.dart';
import 'ai_chat_design.dart';
import 'ai_session_pins_store.dart';

/// گروه‌بندی زمانی session‌ها
enum _SessionGroup {
  pinned,
  today,
  yesterday,
  thisWeek,
  lastMonth,
  older,
}

extension _SessionGroupLabel on _SessionGroup {
  String label() {
    switch (this) {
      case _SessionGroup.pinned:
        return 'پین‌شده';
      case _SessionGroup.today:
        return 'امروز';
      case _SessionGroup.yesterday:
        return 'دیروز';
      case _SessionGroup.thisWeek:
        return 'این هفته';
      case _SessionGroup.lastMonth:
        return 'ماه گذشته';
      case _SessionGroup.older:
        return 'قدیمی‌تر';
    }
  }
}

_SessionGroup _groupForSession(AIChatSession s, Set<int> pinnedIds) {
  if (s.id != null && pinnedIds.contains(s.id)) {
    return _SessionGroup.pinned;
  }
  final stamp = s.updatedAt ?? s.createdAt;
  if (stamp == null) return _SessionGroup.older;
  final now = DateTime.now();
  final diff = now.difference(stamp);
  if (diff.inDays == 0 && now.day == stamp.day) return _SessionGroup.today;
  if (diff.inDays <= 1) return _SessionGroup.yesterday;
  if (diff.inDays <= 7) return _SessionGroup.thisWeek;
  if (diff.inDays <= 30) return _SessionGroup.lastMonth;
  return _SessionGroup.older;
}

class AIChatSidebar extends StatefulWidget {
  final List<AIChatSession> sessions;
  final AIChatSession? currentSession;
  final bool loading;
  final bool isJalali;
  final int? businessId;
  final VoidCallback onNewChat;
  final ValueChanged<AIChatSession> onSelectSession;
  final ValueChanged<AIChatSession> onDeleteSession;
  final ValueChanged<String>? onSearch;

  const AIChatSidebar({
    super.key,
    required this.sessions,
    required this.currentSession,
    required this.loading,
    required this.isJalali,
    this.businessId,
    required this.onNewChat,
    required this.onSelectSession,
    required this.onDeleteSession,
    this.onSearch,
  });

  @override
  State<AIChatSidebar> createState() => _AIChatSidebarState();
}

class _AIChatSidebarState extends State<AIChatSidebar> {
  final TextEditingController _searchCtrl = TextEditingController();
  Set<int> _pinnedIds = {};

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  Future<void> _loadPins() async {
    final pins = await AISessionPinsStore.load(widget.businessId);
    if (mounted) setState(() => _pinnedIds = pins);
  }

  Future<void> _persistPins() async {
    await AISessionPinsStore.save(widget.businessId, _pinnedIds);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _togglePin(AIChatSession s) {
    if (s.id == null) return;
    setState(() {
      if (_pinnedIds.contains(s.id)) {
        _pinnedIds.remove(s.id);
      } else {
        _pinnedIds.add(s.id!);
      }
    });
    unawaited(_persistPins());
  }

  List<Widget> _buildGroupedList(
    ThemeData theme,
    ColorScheme scheme,
    List<AIChatSession> sessions,
  ) {
    final groups = <_SessionGroup, List<AIChatSession>>{};
    for (final s in sessions) {
      final g = _groupForSession(s, _pinnedIds);
      groups.putIfAbsent(g, () => []).add(s);
    }

    final order = [
      _SessionGroup.pinned,
      _SessionGroup.today,
      _SessionGroup.yesterday,
      _SessionGroup.thisWeek,
      _SessionGroup.lastMonth,
      _SessionGroup.older,
    ];

    final widgets = <Widget>[];
    for (final group in order) {
      final list = groups[group];
      if (list == null || list.isEmpty) continue;

      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Text(
            group.label(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
      );
      for (final session in list) {
        widgets.add(
          _SessionTile(
            session: session,
            selected: widget.currentSession?.id == session.id,
            isPinned: session.id != null && _pinnedIds.contains(session.id),
            isJalali: widget.isJalali,
            onTap: () => widget.onSelectSession(session),
            onDelete: () => widget.onDeleteSession(session),
            onTogglePin: () => _togglePin(session),
          ),
        );
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: AIChatDesign.sidebarWidth,
      decoration: BoxDecoration(
        color: isDark ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest,
        border: Border(
          left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                widget.onSearch?.call(v);
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: 'جستجو در گفت‌وگوها…',
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          widget.onSearch?.call('');
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: FilledButton.tonalIcon(
              onPressed: widget.onNewChat,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('گفت‌وگوی جدید'),
              style: FilledButton.styleFrom(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          Expanded(
            child: widget.loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : widget.sessions.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'هنوز گفت‌وگویی ندارید',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 12),
                        children: _buildGroupedList(theme, scheme, widget.sessions),
                      ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatefulWidget {
  final AIChatSession session;
  final bool selected;
  final bool isPinned;
  final bool isJalali;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;

  const _SessionTile({
    required this.session,
    required this.selected,
    required this.isPinned,
    required this.isJalali,
    required this.onTap,
    required this.onDelete,
    required this.onTogglePin,
  });

  @override
  State<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends State<_SessionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stamp = widget.session.updatedAt ?? widget.session.createdAt ?? DateTime.now();
    final dateText = HesabixDateUtils.formatForDisplay(stamp, widget.isJalali);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: widget.selected
              ? scheme.primaryContainer.withValues(alpha: 0.55)
              : (_hovered ? scheme.surfaceContainerHigh : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.selected
                      ? scheme.primary.withValues(alpha: 0.24)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  // آیکون pin
                  if (widget.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.push_pin_rounded,
                        size: 13,
                        color: scheme.primary.withValues(alpha: 0.7),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dateText,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_hovered || widget.selected)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 16,
                          tooltip: widget.isPinned ? 'برداشتن پین' : 'پین کردن',
                          onPressed: widget.onTogglePin,
                          icon: Icon(
                            widget.isPinned
                                ? Icons.push_pin_rounded
                                : Icons.push_pin_outlined,
                            color: widget.isPinned
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 16,
                          tooltip: 'حذف',
                          onPressed: widget.onDelete,
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// محتوای drawer تاریخچه (موبایل/تبلت).
class AIChatHistoryDrawer extends StatelessWidget {
  final List<AIChatSession> sessions;
  final AIChatSession? currentSession;
  final bool loading;
  final bool isJalali;
  final int? businessId;
  final VoidCallback onNewChat;
  final ValueChanged<AIChatSession> onSelectSession;
  final ValueChanged<AIChatSession> onDeleteSession;
  final ValueChanged<String>? onSearch;

  const AIChatHistoryDrawer({
    super.key,
    required this.sessions,
    required this.currentSession,
    required this.loading,
    required this.isJalali,
    this.businessId,
    required this.onNewChat,
    required this.onSelectSession,
    required this.onDeleteSession,
    this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: AIChatSidebar(
          sessions: sessions,
          currentSession: currentSession,
          loading: loading,
          isJalali: isJalali,
          businessId: businessId,
          onNewChat: () {
            Navigator.of(context).pop();
            onNewChat();
          },
          onSelectSession: (s) {
            Navigator.of(context).pop();
            onSelectSession(s);
          },
          onDeleteSession: onDeleteSession,
          onSearch: onSearch,
        ),
      ),
    );
  }
}
