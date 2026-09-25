import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// دادهٔ نمایشی یک فروش باز برای نوار صندوق.
class QuickSalesParkedSaleChipData {
  final String id;
  final String title;
  final String subtitle;
  final bool isActive;
  final bool isBlank;
  final bool showDiscard;
  final String? customerInitial;

  const QuickSalesParkedSaleChipData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.isBlank,
    required this.showDiscard,
    this.customerInitial,
  });
}

/// نوار فشردهٔ سبدهای باز — هم‌ارتفاع تب‌های پنل کسب‌وکار (~۴۴px).
class QuickSalesParkedSalesBar extends StatelessWidget {
  static const double barHeight = 44;
  static const double _verticalPadding = 6;
  static const double chipHeight = barHeight - (_verticalPadding * 2);

  final List<QuickSalesParkedSaleChipData> sales;
  final bool compact;
  final bool enabled;
  final bool newSaleEnabled;
  final String newSaleLabel;
  final String newSaleTooltip;
  final String discardTooltip;
  final VoidCallback onNewSale;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDiscard;

  const QuickSalesParkedSalesBar({
    super.key,
    required this.sales,
    required this.compact,
    required this.enabled,
    required this.newSaleEnabled,
    required this.newSaleLabel,
    required this.newSaleTooltip,
    required this.discardTooltip,
    required this.onNewSale,
    required this.onSelect,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hPad = compact ? 8.0 : 10.0;

    return Material(
      color: cs.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: cs.outline.withValues(alpha: isDark ? 0.45 : 0.28)),
          ),
        ),
        child: SizedBox(
          height: barHeight,
          child: Padding(
            padding: EdgeInsetsDirectional.only(start: hPad, end: hPad),
            child: Row(
              children: [
                _NewSaleButton(
                  enabled: enabled && newSaleEnabled,
                  label: newSaleLabel,
                  tooltip: newSaleTooltip,
                  onPressed: enabled && newSaleEnabled ? onNewSale : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ParkedSalesScroller(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < sales.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          _ParkedSaleChip(
                            data: sales[i],
                            compact: compact,
                            enabled: enabled,
                            discardTooltip: discardTooltip,
                            onSelect: () => onSelect(sales[i].id),
                            onDiscard: sales[i].showDiscard
                                ? () => onDiscard(sales[i].id)
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewSaleButton extends StatelessWidget {
  final bool enabled;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  const _NewSaleButton({
    required this.enabled,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: cs.secondaryContainer,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: QuickSalesParkedSalesBar.chipHeight,
                height: QuickSalesParkedSalesBar.chipHeight,
                child: Icon(Icons.add, size: 18, color: cs.onSecondaryContainer),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ParkedSalesScroller extends StatefulWidget {
  final Widget child;

  const _ParkedSalesScroller({required this.child});

  @override
  State<_ParkedSalesScroller> createState() => _ParkedSalesScrollerState();
}

class _ParkedSalesScrollerState extends State<_ParkedSalesScroller> {
  final ScrollController _controller = ScrollController();
  bool _canScroll = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncOverflow);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
  }

  @override
  void didUpdateWidget(covariant _ParkedSalesScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncOverflow);
    _controller.dispose();
    super.dispose();
  }

  void _syncOverflow() {
    if (!mounted || !_controller.hasClients) return;
    final can = _controller.position.maxScrollExtent > 0.5;
    if (can != _canScroll) setState(() => _canScroll = can);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final offset = event.scrollDelta.dy.abs() > event.scrollDelta.dx.abs()
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (offset == 0) return;
    final position = _controller.position;
    final target = (position.pixels + offset).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    _controller.jumpTo(target.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final scrollBehavior = ScrollConfiguration.of(context).copyWith(
      scrollbars: false,
      dragDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.unknown,
      },
    );

    Widget scroller = ScrollConfiguration(
      behavior: scrollBehavior,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        primary: false,
        child: widget.child,
      ),
    );

    if (_canScroll) {
      scroller = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) {
          return LinearGradient(
            begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
            end: rtl ? Alignment.centerLeft : Alignment.centerRight,
            colors: const [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: const [0.0, 0.05, 0.95, 1.0],
          ).createShader(rect);
        },
        child: scroller,
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _onPointerSignal,
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: _canScroll,
        thickness: 3,
        radius: const Radius.circular(3),
        child: scroller,
      ),
    );
  }
}

class _ParkedSaleChip extends StatelessWidget {
  final QuickSalesParkedSaleChipData data;
  final bool compact;
  final bool enabled;
  final String discardTooltip;
  final VoidCallback onSelect;
  final VoidCallback? onDiscard;

  const _ParkedSaleChip({
    required this.data,
    required this.compact,
    required this.enabled,
    required this.discardTooltip,
    required this.onSelect,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final active = data.isActive;
    final chipRadius = BorderRadius.circular(11);
    final label = data.subtitle.trim().isEmpty
        ? data.title
        : '${data.title} · ${data.subtitle}';

    final chipFg = active ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.92);
    final chipBg = active
        ? Color.alphaBlend(
            cs.primary.withValues(alpha: isDark ? 0.26 : 0.13),
            cs.surface,
          )
        : cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.52 : 0.72);
    final chipBorder = active
        ? cs.primary.withValues(alpha: isDark ? 0.72 : 0.52)
        : cs.outline.withValues(alpha: isDark ? 0.38 : 0.22);

    return Tooltip(
      message: data.subtitle.trim().isEmpty ? data.title : '${data.title}\n${data.subtitle}',
      waitDuration: const Duration(milliseconds: 500),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: compact ? 88 : 96,
          maxWidth: compact ? 148 : 168,
        ),
        child: Material(
          color: chipBg,
          elevation: active ? 2 : 0,
          shadowColor: cs.shadow.withValues(alpha: 0.18),
          shape: RoundedRectangleBorder(
            borderRadius: chipRadius,
            side: BorderSide(color: chipBorder, width: active ? 1.5 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled && !active ? onSelect : null,
            borderRadius: chipRadius,
            hoverColor: cs.primary.withValues(alpha: isDark ? 0.09 : 0.06),
            child: SizedBox(
              height: QuickSalesParkedSalesBar.chipHeight,
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: 10,
                  end: onDiscard != null ? 2 : 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsetsDirectional.only(end: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active ? cs.primary : cs.outline.withValues(alpha: 0.55),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontSize: 12.5,
                          height: 1.15,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          color: chipFg,
                        ),
                      ),
                    ),
                    if (onDiscard != null)
                      SizedBox(
                        width: 26,
                        height: 26,
                        child: IconButton(
                          tooltip: discardTooltip,
                          onPressed: enabled ? onDiscard : null,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: chipFg.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
