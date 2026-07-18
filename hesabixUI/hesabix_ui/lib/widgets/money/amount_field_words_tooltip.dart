import 'package:flutter/material.dart';

import 'package:hesabix_ui/utils/amount_to_words.dart';

/// در دسکتاپ با hover و در موبایل با long-press، معادل نوشتاری مبلغ را نشان می‌دهد.
///
/// متن tooltip از طریق [OverlayEntry] به‌روز می‌شود تا [child] (معمولاً TextField)
/// با تغییر مقدار دوباره ساخته نشود و فوکوس از دست نرود.
class AmountFieldWordsTooltip extends StatefulWidget {
  final Widget child;
  final TextEditingController controller;
  final String currencyUnit;

  const AmountFieldWordsTooltip({
    super.key,
    required this.child,
    required this.controller,
    this.currencyUnit = 'ریال',
  });

  @override
  State<AmountFieldWordsTooltip> createState() => _AmountFieldWordsTooltipState();
}

class _AmountFieldWordsTooltipState extends State<AmountFieldWordsTooltip> {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _targetKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _hovering = false;
  bool _longPressVisible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AmountFieldWordsTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onControllerChanged() {
    _overlayEntry?.markNeedsBuild();
  }

  String? _currentMessage() {
    if (!mounted) return null;
    final locale = Localizations.localeOf(context);
    final persian = locale.languageCode.toLowerCase().startsWith('fa');
    return amountFormattedInputToWords(
      widget.controller.text,
      usePersian: persian,
      currencyUnit: widget.currencyUnit,
    );
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final text = _currentMessage();
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(overlayContext);
    final box = _targetKey.currentContext?.findRenderObject() as RenderBox?;
    final fieldWidth = (box != null && box.hasSize) ? box.size.width : 200.0;
    final screenHeight = MediaQuery.sizeOf(overlayContext).height;
    final maxWidth = fieldWidth.clamp(120.0, 260.0);
    final maxHeight = (screenHeight * 0.22).clamp(72.0, 140.0);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.topCenter,
          offset: const Offset(0, 6),
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.inverseSurface,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onInverseSurface,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showOverlay() {
    final msg = _currentMessage();
    if (msg == null || msg.isEmpty) {
      _removeOverlay();
      return;
    }

    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    final overlay = Overlay.of(context, rootOverlay: true);

    _overlayEntry = OverlayEntry(
      builder: _buildOverlay,
    );
    overlay.insert(_overlayEntry!);
  }

  void _handleHoverEnter(_) {
    _hovering = true;
    Future<void>.delayed(const Duration(milliseconds: 380), () {
      if (!mounted || !_hovering) return;
      _showOverlay();
    });
  }

  void _handleHoverExit(_) {
    _hovering = false;
    if (!_longPressVisible) {
      _removeOverlay();
    }
  }

  void _handleLongPressStart(LongPressStartDetails _) {
    _longPressVisible = true;
    _showOverlay();
  }

  void _handleLongPressEnd(LongPressEndDetails _) {
    _longPressVisible = false;
    if (!_hovering) {
      _removeOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: KeyedSubtree(
        key: _targetKey,
        child: MouseRegion(
          onEnter: _handleHoverEnter,
          onExit: _handleHoverExit,
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onLongPressStart: _handleLongPressStart,
            onLongPressEnd: _handleLongPressEnd,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
