import 'package:flutter/material.dart';

class BusinessHubSwipeAction {
  final IconData icon;
  final Color background;
  final Color foreground;
  final String label;
  final VoidCallback onTap;

  const BusinessHubSwipeAction({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.label,
    required this.onTap,
  });
}

/// کشیدن افقی کارت برای نمایش اقدامات سریع (موبایل).
class BusinessHubSwipeWrapper extends StatefulWidget {
  final Widget child;
  final List<BusinessHubSwipeAction> actions;
  final bool enabled;

  const BusinessHubSwipeWrapper({
    super.key,
    required this.child,
    required this.actions,
    this.enabled = true,
  });

  @override
  State<BusinessHubSwipeWrapper> createState() => _BusinessHubSwipeWrapperState();
}

class _BusinessHubSwipeWrapperState extends State<BusinessHubSwipeWrapper>
    with SingleTickerProviderStateMixin {
  static const double _actionWidth = 76;

  late AnimationController _controller;
  double _dragOffset = 0;
  bool _open = false;

  double get _maxExtent => widget.actions.length * _actionWidth;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _controller.stop();
    final start = _dragOffset;
    _controller.reset();
    final anim = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    void tick() => setState(() => _dragOffset = anim.value);
    anim.addListener(tick);
    _controller.forward().whenComplete(() {
      anim.removeListener(tick);
      _dragOffset = target;
      _open = target != 0;
    });
  }

  void _close() {
    if (_dragOffset == 0 && !_open) return;
    _animateTo(0);
  }

  void _openActions() => _animateTo(-_maxExtent);

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.actions.isEmpty) return widget.child;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: widget.actions.map(_buildActionButton).toList(),
            ),
          ),
          GestureDetector(
            onHorizontalDragUpdate: (d) {
              setState(() {
                _dragOffset = (_dragOffset + d.delta.dx).clamp(-_maxExtent, 0);
              });
            },
            onHorizontalDragEnd: (d) {
              final velocity = d.primaryVelocity ?? 0;
              if (velocity < -300 || _dragOffset < -_maxExtent * 0.4) {
                _openActions();
              } else {
                _close();
              }
            },
            onTap: _open ? _close : null,
            child: Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BusinessHubSwipeAction action) {
    return Material(
      color: action.background,
      child: InkWell(
        onTap: () {
          _close();
          action.onTap();
        },
        child: SizedBox(
          width: _actionWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(action.icon, color: action.foreground, size: 22),
              const SizedBox(height: 4),
              Text(
                action.label,
                style: TextStyle(color: action.foreground, fontSize: 11, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
