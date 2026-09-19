import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefKey = 'operator_inbox_list_width';
const _defaultWidth = 360.0;
const _minWidth = 280.0;
const _maxWidth = 520.0;
const _handleWidth = 5.0;

/// Horizontal resizable split between operator inbox list (left) and detail (right).
class OperatorInboxSplitter extends StatefulWidget {
  final Widget left;
  final Widget right;

  const OperatorInboxSplitter({
    super.key,
    required this.left,
    required this.right,
  });

  @override
  State<OperatorInboxSplitter> createState() => _OperatorInboxSplitterState();
}

class _OperatorInboxSplitterState extends State<OperatorInboxSplitter> {
  double? _leftWidth;
  bool _handleHovered = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _loadWidth();
  }

  Future<void> _loadWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_prefKey);
    if (!mounted) return;
    setState(() {
      _leftWidth = (saved ?? _defaultWidth).clamp(_minWidth, _maxWidth);
    });
  }

  Future<void> _saveWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKey, width);
  }

  void _onDragUpdate(DragUpdateDetails details, double totalWidth, {required bool isRtl}) {
    // In RTL the list pane is visually on the right; invert drag so expanding feels natural.
    final delta = isRtl ? -details.delta.dx : details.delta.dx;
    final next = (_leftWidth ?? _defaultWidth) + delta;
    setState(() {
      _leftWidth = next.clamp(_minWidth, _maxWidth.clamp(_minWidth, totalWidth - _handleWidth));
    });
  }

  void _onDragEnd() {
    setState(() => _dragging = false);
    final width = _leftWidth;
    if (width != null) {
      _saveWidth(width);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leftWidth = _leftWidth ?? _defaultWidth;

    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final effectiveLeft = leftWidth.clamp(_minWidth, _maxWidth.clamp(_minWidth, totalWidth - _handleWidth));

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: effectiveLeft,
              child: widget.left,
            ),
            MouseRegion(
              onEnter: (_) => setState(() => _handleHovered = true),
              onExit: (_) => setState(() => _handleHovered = false),
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) => setState(() => _dragging = true),
                onHorizontalDragUpdate: (d) => _onDragUpdate(d, totalWidth, isRtl: isRtl),
                onHorizontalDragEnd: (_) => _onDragEnd(),
                onHorizontalDragCancel: _onDragEnd,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: _handleWidth,
                  color: _dragging || _handleHovered
                      ? theme.colorScheme.primary.withValues(alpha: 0.35)
                      : theme.dividerColor.withValues(alpha: 0.6),
                  child: Center(
                    child: Container(
                      width: 2,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _dragging || _handleHovered
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: widget.right,
            ),
          ],
        );
      },
    );
  }
}
