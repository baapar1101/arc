import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'ai_chat_design.dart';

/// باکس متن تفکر/استدلال با ارتفاع محدود، اسکرول داخلی و fade پایین.
class AIThinkingScrollBox extends StatefulWidget {
  final String markdown;
  final ThemeData theme;
  final ColorScheme scheme;
  final Color? accent;

  const AIThinkingScrollBox({
    super.key,
    required this.markdown,
    required this.theme,
    required this.scheme,
    this.accent,
  });

  @override
  State<AIThinkingScrollBox> createState() => _AIThinkingScrollBoxState();
}

class _AIThinkingScrollBoxState extends State<AIThinkingScrollBox> {
  final ScrollController _scroll = ScrollController();
  bool _overflows = false;
  bool _showBottomFade = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void didUpdateWidget(covariant AIThinkingScrollBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdown != widget.markdown) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || !_overflows) return;
    final atBottom = _scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 4;
    if (_showBottomFade != !atBottom) {
      setState(() => _showBottomFade = !atBottom);
    }
  }

  void _checkOverflow() {
    if (!_scroll.hasClients) return;
    final overflows = _scroll.position.maxScrollExtent > 4;
    if (overflows != _overflows) {
      setState(() {
        _overflows = overflows;
        _showBottomFade = overflows;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = AIChatDesign.reasoningBoxMaxHeight(context);
    final accentColor = widget.accent ?? widget.scheme.primary;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Container(
      decoration: AIChatDesign.subtlePanel(widget.theme, accent: accentColor)
          .copyWith(
        border: Border(
          left: isRtl
              ? BorderSide.none
              : BorderSide(
                  color: accentColor.withValues(alpha: 0.55),
                  width: 3,
                ),
          right: isRtl
              ? BorderSide(
                  color: accentColor.withValues(alpha: 0.55),
                  width: 3,
                )
              : BorderSide.none,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Stack(
            children: [
              Scrollbar(
                controller: _scroll,
                thumbVisibility: widget.markdown.length > 280,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification ||
                        notification is OverscrollNotification) {
                      return true;
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                    child: MarkdownBody(
                      data: widget.markdown,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: widget.theme.textTheme.bodySmall?.copyWith(
                          color: widget.scheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_showBottomFade)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 28,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            widget.scheme.surface.withValues(alpha: 0),
                            widget.scheme.surface.withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
