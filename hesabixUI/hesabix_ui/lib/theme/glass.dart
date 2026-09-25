import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Shared glass constants used across the application.
abstract final class GlassStyle {
  static const double surfaceBlur = 18;
  static const double modalBlur = 14;
  static const double strongModalBlur = 20;

  static Color surfaceTint(BuildContext context, {double? opacity}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? Colors.white.withValues(alpha: opacity ?? 0.075)
        : Colors.white.withValues(alpha: opacity ?? 0.62);
  }

  static Color border(BuildContext context, {double? opacity}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? Colors.white.withValues(alpha: opacity ?? 0.16)
        : const Color(0xFF2563EB).withValues(alpha: opacity ?? 0.11);
  }

  static Color modalBarrier(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const Color(0xFF020617).withValues(alpha: 0.42)
        : const Color(0xFF0F172A).withValues(alpha: 0.18);
  }
}

/// A real frosted-glass surface. The content underneath this widget is
/// Gaussian-blurred before the translucent tint is painted.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final double? opacity;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final Clip clipBehavior;

  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.padding,
    this.blur = GlassStyle.surfaceBlur,
    this.opacity,
    this.border,
    this.boxShadow,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: boxShadow ??
            [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark ? 0.24 : 0.10,
                ),
                blurRadius: 28,
                spreadRadius: -8,
                offset: const Offset(0, 14),
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: GlassStyle.surfaceTint(context, opacity: opacity),
              borderRadius: borderRadius,
              border: border ??
                  Border.all(
                    color: GlassStyle.border(context),
                    width: 1,
                  ),
            ),
            child: padding == null
                ? child
                : Padding(padding: padding!, child: child),
          ),
        ),
      ),
    );
  }
}

/// Dialog route whose modal barrier performs a real backdrop blur.
/// This blurs the page behind forms/dialogs and then applies a subtle scrim,
/// increasing contrast while preserving visual context.
class _GlassDialogRoute<T> extends PopupRoute<T> {
  final WidgetBuilder builder;
  final CapturedThemes themes;
  final bool useSafeArea;
  final AnimationStyle? animationStyle;
  final Color _barrierColor;
  final bool _barrierDismissible;
  final String? _barrierLabel;
  final Offset? _anchorPoint;

  _GlassDialogRoute({
    required BuildContext context,
    required this.builder,
    required this.themes,
    required this.useSafeArea,
    required Color barrierColor,
    required bool barrierDismissible,
    String? barrierLabel,
    required RouteSettings? settings,
    required bool? requestFocus,
    required Offset? anchorPoint,
    required TraversalEdgeBehavior? traversalEdgeBehavior,
    required bool fullscreenDialog,
    required this.animationStyle,
    required double blurSigma,
  })  : _barrierColor = barrierColor,
        _barrierDismissible = barrierDismissible,
        _barrierLabel =
            barrierLabel ?? MaterialLocalizations.of(context).modalBarrierDismissLabel,
        _anchorPoint = anchorPoint,
        super(
          settings: settings,
          requestFocus: requestFocus,
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          traversalEdgeBehavior:
              traversalEdgeBehavior ?? TraversalEdgeBehavior.closedLoop,
        );

  @override
  Color? get barrierColor => _barrierColor;

  @override
  bool get barrierDismissible => _barrierDismissible;

  @override
  String? get barrierLabel => _barrierLabel;

  @override
  Duration get transitionDuration =>
      animationStyle?.duration ?? const Duration(milliseconds: 180);

  @override
  Duration get reverseTransitionDuration =>
      animationStyle?.reverseDuration ?? const Duration(milliseconds: 140);

  @override
  Offset? get anchorPoint => _anchorPoint;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    Widget page = Builder(builder: builder);
    page = themes.wrap(page);
    if (useSafeArea) page = SafeArea(child: page);
    return page;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.975, end: 1).animate(curved),
        child: child,
      ),
    );
  }
}

/// Drop-in replacement for Material [showDialog] with a blurred modal barrier.
/// Existing dialogs keep their content and behavior; only the presentation
/// layer changes.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool fullscreenDialog = false,
  bool? requestFocus,
  AnimationStyle? animationStyle,
  double blurSigma = GlassStyle.strongModalBlur,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);

  return navigator.push<T>(
    _GlassDialogRoute<T>(
      context: context,
      builder: builder,
      themes: themes,
      useSafeArea: useSafeArea,
      barrierColor: barrierColor ?? GlassStyle.modalBarrier(context),
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      settings: routeSettings,
      requestFocus: requestFocus,
      anchorPoint: anchorPoint,
      traversalEdgeBehavior: traversalEdgeBehavior,
      fullscreenDialog: fullscreenDialog,
      animationStyle: animationStyle,
      blurSigma: blurSigma,
    ),
  );
}


/// Drop-in glass replacement for Material [showModalBottomSheet].
/// The sheet itself uses a real BackdropFilter while retaining the standard
/// bottom-sheet route behavior (dragging, scrolling, safe-area handling, etc.).
Future<T?> showGlassModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  double scrollControlDisabledMaxHeightRatio = 9.0 / 16.0,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  bool? requestFocus,
}) {
  const radius = BorderRadius.vertical(top: Radius.circular(22));

  return showModalBottomSheet<T>(
    context: context,
    builder: (sheetContext) => GlassSurface(
      borderRadius: radius,
      blur: GlassStyle.strongModalBlur,
      opacity: Theme.of(sheetContext).brightness == Brightness.dark ? 0.22 : 0.56,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          blurRadius: 36,
          spreadRadius: -10,
          offset: const Offset(0, -8),
        ),
      ],
      child: builder(sheetContext),
    ),
    backgroundColor: Colors.transparent,
    barrierLabel: barrierLabel,
    elevation: elevation ?? 0,
    shape: shape ?? const RoundedRectangleBorder(borderRadius: radius),
    clipBehavior: clipBehavior ?? Clip.antiAlias,
    constraints: constraints,
    barrierColor: barrierColor ?? GlassStyle.modalBarrier(context),
    isScrollControlled: isScrollControlled,
    scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    anchorPoint: anchorPoint,
    sheetAnimationStyle: sheetAnimationStyle,
    requestFocus: requestFocus,
  );
}
