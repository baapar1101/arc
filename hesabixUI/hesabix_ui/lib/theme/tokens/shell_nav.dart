import 'package:flutter/material.dart';

/// متریک و تایپوگرافی فشردهٔ منوی کناری shell (ریل دسکتاپ و دراور).
///
/// مقادیر اینجا منبع حقیقت هستند؛ ویجت‌های شِل نباید padding/font/width را هاردکد کنند.
@immutable
class AppShellNavMetrics extends ThemeExtension<AppShellNavMetrics> {
  final double extendedWidth;
  final double collapsedWidth;
  final EdgeInsetsGeometry listPadding;
  final EdgeInsetsGeometry parentPaddingExtended;
  final EdgeInsetsGeometry parentPaddingCollapsed;
  final EdgeInsetsGeometry childPaddingExtended;
  final EdgeInsetsGeometry childPaddingCollapsed;
  final EdgeInsetsGeometry separatorPaddingExtended;
  final EdgeInsetsGeometry separatorPaddingCollapsed;
  final double iconLabelGap;
  final double parentIconExtended;
  final double parentIconCollapsed;
  final double childIconExtended;
  final double childIconCollapsed;
  final double expandIconSize;
  final double expandBadgeSize;
  final double addButtonSize;
  final double addIconSize;
  final double addButtonRadius;
  final double itemRadius;
  final double parentFontSize;
  final double childFontSize;
  final double separatorFontSize;
  final double labelHeight;

  const AppShellNavMetrics({
    this.extendedWidth = 200,
    this.collapsedWidth = 56,
    this.listPadding = const EdgeInsets.symmetric(vertical: 4),
    this.parentPaddingExtended = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.parentPaddingCollapsed = const EdgeInsets.symmetric(vertical: 6),
    this.childPaddingExtended = const EdgeInsetsDirectional.fromSTEB(16, 3, 8, 3),
    this.childPaddingCollapsed = const EdgeInsets.symmetric(vertical: 5),
    this.separatorPaddingExtended = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    this.separatorPaddingCollapsed = const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    this.iconLabelGap = 8,
    this.parentIconExtended = 18,
    this.parentIconCollapsed = 20,
    this.childIconExtended = 15,
    this.childIconCollapsed = 18,
    this.expandIconSize = 16,
    this.expandBadgeSize = 12,
    this.addButtonSize = 18,
    this.addIconSize = 12,
    this.addButtonRadius = 4,
    this.itemRadius = 4,
    this.parentFontSize = 12,
    this.childFontSize = 11.5,
    this.separatorFontSize = 10,
    this.labelHeight = 1.15,
  });

  double widthFor({required bool extended}) => extended ? extendedWidth : collapsedWidth;

  EdgeInsetsGeometry parentPaddingFor({required bool extended}) =>
      extended ? parentPaddingExtended : parentPaddingCollapsed;

  EdgeInsetsGeometry childPaddingFor({required bool extended}) =>
      extended ? childPaddingExtended : childPaddingCollapsed;

  EdgeInsetsGeometry separatorPaddingFor({required bool extended}) =>
      extended ? separatorPaddingExtended : separatorPaddingCollapsed;

  double iconSizeFor({required bool extended, required bool child}) {
    if (child) return extended ? childIconExtended : childIconCollapsed;
    return extended ? parentIconExtended : parentIconCollapsed;
  }

  BorderRadius itemBorderRadius({required bool flush}) =>
      flush ? BorderRadius.zero : BorderRadius.circular(itemRadius);

  TextStyle parentLabelStyle(
    TextTheme textTheme, {
    required Color color,
    required bool active,
  }) {
    return (textTheme.labelLarge ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
      fontSize: parentFontSize,
      height: labelHeight,
    );
  }

  TextStyle childLabelStyle(
    TextTheme textTheme, {
    required Color color,
    required bool active,
  }) {
    return (textTheme.labelMedium ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
      fontSize: childFontSize,
      height: labelHeight,
    );
  }

  TextStyle separatorLabelStyle(TextTheme textTheme, {required Color color}) {
    return (textTheme.labelSmall ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: FontWeight.w600,
      fontSize: separatorFontSize,
      height: 1.1,
      letterSpacing: 0.3,
    );
  }

  @override
  AppShellNavMetrics copyWith({
    double? extendedWidth,
    double? collapsedWidth,
    EdgeInsetsGeometry? listPadding,
    EdgeInsetsGeometry? parentPaddingExtended,
    EdgeInsetsGeometry? parentPaddingCollapsed,
    EdgeInsetsGeometry? childPaddingExtended,
    EdgeInsetsGeometry? childPaddingCollapsed,
    EdgeInsetsGeometry? separatorPaddingExtended,
    EdgeInsetsGeometry? separatorPaddingCollapsed,
    double? iconLabelGap,
    double? parentIconExtended,
    double? parentIconCollapsed,
    double? childIconExtended,
    double? childIconCollapsed,
    double? expandIconSize,
    double? expandBadgeSize,
    double? addButtonSize,
    double? addIconSize,
    double? addButtonRadius,
    double? itemRadius,
    double? parentFontSize,
    double? childFontSize,
    double? separatorFontSize,
    double? labelHeight,
  }) {
    return AppShellNavMetrics(
      extendedWidth: extendedWidth ?? this.extendedWidth,
      collapsedWidth: collapsedWidth ?? this.collapsedWidth,
      listPadding: listPadding ?? this.listPadding,
      parentPaddingExtended: parentPaddingExtended ?? this.parentPaddingExtended,
      parentPaddingCollapsed: parentPaddingCollapsed ?? this.parentPaddingCollapsed,
      childPaddingExtended: childPaddingExtended ?? this.childPaddingExtended,
      childPaddingCollapsed: childPaddingCollapsed ?? this.childPaddingCollapsed,
      separatorPaddingExtended: separatorPaddingExtended ?? this.separatorPaddingExtended,
      separatorPaddingCollapsed: separatorPaddingCollapsed ?? this.separatorPaddingCollapsed,
      iconLabelGap: iconLabelGap ?? this.iconLabelGap,
      parentIconExtended: parentIconExtended ?? this.parentIconExtended,
      parentIconCollapsed: parentIconCollapsed ?? this.parentIconCollapsed,
      childIconExtended: childIconExtended ?? this.childIconExtended,
      childIconCollapsed: childIconCollapsed ?? this.childIconCollapsed,
      expandIconSize: expandIconSize ?? this.expandIconSize,
      expandBadgeSize: expandBadgeSize ?? this.expandBadgeSize,
      addButtonSize: addButtonSize ?? this.addButtonSize,
      addIconSize: addIconSize ?? this.addIconSize,
      addButtonRadius: addButtonRadius ?? this.addButtonRadius,
      itemRadius: itemRadius ?? this.itemRadius,
      parentFontSize: parentFontSize ?? this.parentFontSize,
      childFontSize: childFontSize ?? this.childFontSize,
      separatorFontSize: separatorFontSize ?? this.separatorFontSize,
      labelHeight: labelHeight ?? this.labelHeight,
    );
  }

  @override
  AppShellNavMetrics lerp(ThemeExtension<AppShellNavMetrics>? other, double t) {
    if (other is! AppShellNavMetrics) return this;
    double l(double a, double b) => a + (b - a) * t;
    EdgeInsetsGeometry i(EdgeInsetsGeometry a, EdgeInsetsGeometry b) =>
        EdgeInsetsGeometry.lerp(a, b, t) ?? a;
    return AppShellNavMetrics(
      extendedWidth: l(extendedWidth, other.extendedWidth),
      collapsedWidth: l(collapsedWidth, other.collapsedWidth),
      listPadding: i(listPadding, other.listPadding),
      parentPaddingExtended: i(parentPaddingExtended, other.parentPaddingExtended),
      parentPaddingCollapsed: i(parentPaddingCollapsed, other.parentPaddingCollapsed),
      childPaddingExtended: i(childPaddingExtended, other.childPaddingExtended),
      childPaddingCollapsed: i(childPaddingCollapsed, other.childPaddingCollapsed),
      separatorPaddingExtended: i(separatorPaddingExtended, other.separatorPaddingExtended),
      separatorPaddingCollapsed: i(separatorPaddingCollapsed, other.separatorPaddingCollapsed),
      iconLabelGap: l(iconLabelGap, other.iconLabelGap),
      parentIconExtended: l(parentIconExtended, other.parentIconExtended),
      parentIconCollapsed: l(parentIconCollapsed, other.parentIconCollapsed),
      childIconExtended: l(childIconExtended, other.childIconExtended),
      childIconCollapsed: l(childIconCollapsed, other.childIconCollapsed),
      expandIconSize: l(expandIconSize, other.expandIconSize),
      expandBadgeSize: l(expandBadgeSize, other.expandBadgeSize),
      addButtonSize: l(addButtonSize, other.addButtonSize),
      addIconSize: l(addIconSize, other.addIconSize),
      addButtonRadius: l(addButtonRadius, other.addButtonRadius),
      itemRadius: l(itemRadius, other.itemRadius),
      parentFontSize: l(parentFontSize, other.parentFontSize),
      childFontSize: l(childFontSize, other.childFontSize),
      separatorFontSize: l(separatorFontSize, other.separatorFontSize),
      labelHeight: l(labelHeight, other.labelHeight),
    );
  }
}
