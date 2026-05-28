import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'ai_chat_design.dart';
import 'ai_conversation_scroll_sync.dart';

/// نوار عمودی پرش بین پیام‌های thread — همگام با scroll.
class AIConversationRail extends StatefulWidget {
  final List<AIChatMessage> messages;
  final ScrollController scrollController;
  final List<GlobalKey> messageKeys;
  final int activeIndex;
  final void Function(int index)? onJumpToIndex;

  const AIConversationRail({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.messageKeys,
    required this.activeIndex,
    this.onJumpToIndex,
  });

  @override
  State<AIConversationRail> createState() => _AIConversationRailState();
}

class _AIConversationRailState extends State<AIConversationRail> {
  final ScrollController _railScroll = ScrollController();
  int? _lastSyncedActive;

  @override
  void didUpdateWidget(covariant AIConversationRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex) {
      _syncRailScrollToActive();
    }
  }

  @override
  void dispose() {
    _railScroll.dispose();
    super.dispose();
  }

  void _syncRailScrollToActive() {
    if (!_railScroll.hasClients) return;
    final index = widget.activeIndex;
    if (_lastSyncedActive == index) return;
    _lastSyncedActive = index;

    const itemExtent = 16.0;
    final target = (index * itemExtent) -
        (_railScroll.position.viewportDimension / 2) +
        itemExtent;
    final clamped = target.clamp(
      0.0,
      _railScroll.position.maxScrollExtent,
    );
    _railScroll.animateTo(
      clamped,
      duration: AIChatDesign.fadeTransition,
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToIndex(int index) {
    HapticFeedback.selectionClick();
    if (widget.onJumpToIndex != null) {
      widget.onJumpToIndex!(index);
      return;
    }
    if (index < 0 || index >= widget.messageKeys.length) return;
    final ctx = widget.messageKeys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: AIChatDesign.layoutTransition,
      curve: Curves.easeOutCubic,
      alignment: 0.2,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final l10n = AppLocalizations.of(context);

    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRailScrollToActive());

    return Positioned(
      top: 8,
      bottom: 8,
      right: isRtl ? 4 : null,
      left: isRtl ? null : 4,
      child: SizedBox(
        width: AIChatDesign.timelineRailWidth + 8,
        child: Row(
          children: [
            Expanded(
              child: CustomPaint(
                painter: _RailConnectorPainter(
                  count: widget.messages.length,
                  activeIndex: widget.activeIndex,
                  isRtl: isRtl,
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                  activeColor: scheme.primary.withValues(alpha: 0.5),
                ),
                child: ListView.builder(
                  controller: _railScroll,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: widget.messages.length,
                  itemBuilder: (context, index) {
                    return _RailDot(
                      index: index,
                      message: widget.messages[index],
                      isActive: widget.activeIndex == index,
                      l10n: l10n,
                      onTap: () => _scrollToIndex(index),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailDot extends StatelessWidget {
  final int index;
  final AIChatMessage message;
  final bool isActive;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  const _RailDot({
    required this.index,
    required this.message,
    required this.isActive,
    required this.l10n,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == MessageRole.user;
    final hasError = message.content.contains('خطا در دریافت');

    final color = hasError
        ? scheme.error
        : isUser
            ? scheme.secondary
            : scheme.primary;

    final preview = message.content.trim();
    final tip = preview.length > 48 ? '${preview.substring(0, 48)}…' : preview;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Tooltip(
        message: isUser
            ? '${l10n.aiConversationNavUser}\n$tip'
            : '${l10n.aiConversationNavAssistant}\n$tip',
        preferBelow: false,
        child: Semantics(
          label: isUser ? l10n.aiConversationNavUser : l10n.aiConversationNavAssistant,
          button: true,
          selected: isActive,
          child: GestureDetector(
            onTap: onTap,
            onLongPress: () {
              HapticFeedback.mediumImpact();
              onTap();
            },
            child: AnimatedContainer(
              duration: AIChatDesign.fadeTransition,
              curve: Curves.easeOutCubic,
              width: isActive ? 11 : 7,
              height: isActive ? 11 : 7,
              margin: EdgeInsets.only(
                left: isActive ? 0 : 2,
                right: isActive ? 0 : 2,
              ),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? color : color.withValues(alpha: 0.42),
                border: isActive
                    ? Border.all(color: scheme.surface, width: 2)
                    : null,
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.45),
                          blurRadius: 8,
                          spreadRadius: 0.5,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailConnectorPainter extends CustomPainter {
  final int count;
  final int activeIndex;
  final bool isRtl;
  final Color color;
  final Color activeColor;

  _RailConnectorPainter({
    required this.count,
    required this.activeIndex,
    required this.isRtl,
    required this.color,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (count < 2) return;
    final paint = Paint()
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final x = isRtl ? size.width - 6 : 6.0;
    const dotSpacing = 16.0;
    const topPad = 12.0;

    for (var i = 0; i < count - 1; i++) {
      final y1 = topPad + i * dotSpacing + 5;
      final y2 = topPad + (i + 1) * dotSpacing + 5;
      paint.color = (i < activeIndex) ? activeColor : color;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RailConnectorPainter oldDelegate) {
    return oldDelegate.activeIndex != activeIndex ||
        oldDelegate.count != count;
  }
}

/// Host: گوش دادن به scroll و expose کردن activeIndex + jump.
class AIConversationScrollScope extends StatefulWidget {
  final ScrollController scrollController;
  final List<GlobalKey> messageKeys;
  final int messageCount;
  final Widget Function(BuildContext context, int activeIndex, void Function(int) jumpToIndex) builder;

  const AIConversationScrollScope({
    super.key,
    required this.scrollController,
    required this.messageKeys,
    required this.messageCount,
    required this.builder,
  });

  @override
  State<AIConversationScrollScope> createState() =>
      _AIConversationScrollScopeState();
}

class _AIConversationScrollScopeState extends State<AIConversationScrollScope> {
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateActiveIndex());
  }

  @override
  void didUpdateWidget(covariant AIConversationScrollScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageCount != widget.messageCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateActiveIndex());
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() => _scheduleUpdate();

  void _scheduleUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateActiveIndex();
    });
  }

  void _updateActiveIndex() {
    if (widget.messageKeys.isEmpty) return;
    final next = AIConversationScrollSync.computeActiveIndex(
      scrollController: widget.scrollController,
      messageKeys: widget.messageKeys,
    );
    if (next != _activeIndex) {
      setState(() => _activeIndex = next);
    }
  }

  void _jumpToIndex(int index) {
    if (index < 0 || index >= widget.messageKeys.length) return;
    final ctx = widget.messageKeys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: AIChatDesign.layoutTransition,
      curve: Curves.easeOutCubic,
      alignment: 0.2,
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _activeIndex, _jumpToIndex);
  }
}
