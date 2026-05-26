import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/models/ai_models.dart';
import 'ai_chat_design.dart';

class AIChatSidebar extends StatefulWidget {
  final List<AIChatSession> sessions;
  final AIChatSession? currentSession;
  final bool loading;
  final bool isJalali;
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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'گفت‌وگوهای اخیر',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
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
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        itemCount: widget.sessions.length,
                        itemBuilder: (context, index) {
                          final session = widget.sessions[index];
                          return _SessionTile(
                            session: session,
                            selected: widget.currentSession?.id == session.id,
                            isJalali: widget.isJalali,
                            onTap: () => widget.onSelectSession(session),
                            onDelete: () => widget.onDeleteSession(session),
                          );
                        },
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
  final bool isJalali;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.session,
    required this.selected,
    required this.isJalali,
    required this.onTap,
    required this.onDelete,
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
      padding: const EdgeInsets.only(bottom: 4),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
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
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      tooltip: 'حذف',
                      onPressed: widget.onDelete,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
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
