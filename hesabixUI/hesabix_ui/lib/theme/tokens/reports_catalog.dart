import 'package:flutter/material.dart';

/// متریک فشردهٔ فهرست گزارش‌های پنل کسب‌وکار.
///
/// مقادیر اینجا منبع حقیقت هستند؛ [ReportsPage] نباید padding/font را هاردکد کند.
@immutable
class AppReportsCatalogMetrics extends ThemeExtension<AppReportsCatalogMetrics> {
  final EdgeInsets pagePadding;
  final double pageMaxWidth;
  final double searchHeight;
  final double searchRadius;
  final EdgeInsets searchContentPadding;
  final double headerGap;
  final double sectionGap;
  final double blockGap;
  final EdgeInsets cardPadding;
  final double cardRadius;
  final EdgeInsets itemPadding;
  final double itemRadius;
  final double itemIconSize;
  final double starIconSize;
  final double lockIconSize;
  final double chevronSize;
  final double iconButtonSize;
  final double titleFontSize;
  final double subtitleFontSize;
  final double sectionTitleFontSize;
  final double chipFontSize;
  final double labelHeight;
  final double gridSpacing;
  final double gridRowHeight;
  final double chipSpacing;
  final EdgeInsets chipPadding;
  final EdgeInsets chipLabelPadding;
  final double chipRowHeight;
  final double sortButtonSize;
  final double pinnedHeaderSearchOnly;
  final double pinnedHeaderWithChips;
  final EdgeInsets expansionTilePadding;
  final EdgeInsets expansionChildrenPadding;
  final EdgeInsets tileContentPadding;
  final double emptyStateVertical;

  const AppReportsCatalogMetrics({
    this.pagePadding = const EdgeInsets.fromLTRB(10, 8, 10, 8),
    this.pageMaxWidth = 1280,
    this.searchHeight = 36,
    this.searchRadius = 8,
    this.searchContentPadding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.headerGap = 6,
    this.sectionGap = 6,
    this.blockGap = 8,
    this.cardPadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.cardRadius = 8,
    this.itemPadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.itemRadius = 6,
    this.itemIconSize = 18,
    this.starIconSize = 16,
    this.lockIconSize = 14,
    this.chevronSize = 16,
    this.iconButtonSize = 28,
    this.titleFontSize = 12.5,
    this.subtitleFontSize = 11,
    this.sectionTitleFontSize = 13,
    this.chipFontSize = 11.5,
    this.labelHeight = 1.15,
    this.gridSpacing = 6,
    this.gridRowHeight = 56,
    this.chipSpacing = 6,
    this.chipPadding = const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
    this.chipLabelPadding = const EdgeInsets.symmetric(horizontal: 4),
    this.chipRowHeight = 32,
    this.sortButtonSize = 36,
    this.pinnedHeaderSearchOnly = 48,
    this.pinnedHeaderWithChips = 88,
    this.expansionTilePadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
    this.expansionChildrenPadding = const EdgeInsets.fromLTRB(8, 0, 8, 8),
    this.tileContentPadding = const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
    this.emptyStateVertical = 16,
  });

  int gridColumns(double width) {
    if (width >= 1400) return 4;
    if (width >= 1100) return 3;
    if (width >= 900) return 2;
    return 1;
  }

  SliverGridDelegate gridDelegate(double width) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: gridColumns(width),
      mainAxisSpacing: gridSpacing,
      crossAxisSpacing: gridSpacing,
      mainAxisExtent: gridRowHeight,
    );
  }

  ButtonStyle iconButtonStyle() => IconButton.styleFrom(
        minimumSize: Size(iconButtonSize, iconButtonSize),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      );

  TextStyle titleStyle(TextTheme textTheme, {required Color color}) {
    return (textTheme.labelLarge ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: FontWeight.w600,
      fontSize: titleFontSize,
      height: labelHeight,
    );
  }

  TextStyle subtitleStyle(TextTheme textTheme, {required Color color}) {
    return (textTheme.labelMedium ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: FontWeight.w400,
      fontSize: subtitleFontSize,
      height: labelHeight,
    );
  }

  TextStyle sectionTitleStyle(TextTheme textTheme, {required Color color}) {
    return (textTheme.titleSmall ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: FontWeight.w700,
      fontSize: sectionTitleFontSize,
      height: labelHeight,
    );
  }

  TextStyle chipLabelStyle(TextTheme textTheme, {required Color color}) {
    return (textTheme.labelMedium ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: FontWeight.w500,
      fontSize: chipFontSize,
      height: 1.1,
    );
  }

  @override
  AppReportsCatalogMetrics copyWith({
    EdgeInsets? pagePadding,
    double? pageMaxWidth,
    double? searchHeight,
    double? searchRadius,
    EdgeInsets? searchContentPadding,
    double? headerGap,
    double? sectionGap,
    double? blockGap,
    EdgeInsets? cardPadding,
    double? cardRadius,
    EdgeInsets? itemPadding,
    double? itemRadius,
    double? itemIconSize,
    double? starIconSize,
    double? lockIconSize,
    double? chevronSize,
    double? iconButtonSize,
    double? titleFontSize,
    double? subtitleFontSize,
    double? sectionTitleFontSize,
    double? chipFontSize,
    double? labelHeight,
    double? gridSpacing,
    double? gridRowHeight,
    double? chipSpacing,
    EdgeInsets? chipPadding,
    EdgeInsets? chipLabelPadding,
    double? chipRowHeight,
    double? sortButtonSize,
    double? pinnedHeaderSearchOnly,
    double? pinnedHeaderWithChips,
    EdgeInsets? expansionTilePadding,
    EdgeInsets? expansionChildrenPadding,
    EdgeInsets? tileContentPadding,
    double? emptyStateVertical,
  }) {
    return AppReportsCatalogMetrics(
      pagePadding: pagePadding ?? this.pagePadding,
      pageMaxWidth: pageMaxWidth ?? this.pageMaxWidth,
      searchHeight: searchHeight ?? this.searchHeight,
      searchRadius: searchRadius ?? this.searchRadius,
      searchContentPadding: searchContentPadding ?? this.searchContentPadding,
      headerGap: headerGap ?? this.headerGap,
      sectionGap: sectionGap ?? this.sectionGap,
      blockGap: blockGap ?? this.blockGap,
      cardPadding: cardPadding ?? this.cardPadding,
      cardRadius: cardRadius ?? this.cardRadius,
      itemPadding: itemPadding ?? this.itemPadding,
      itemRadius: itemRadius ?? this.itemRadius,
      itemIconSize: itemIconSize ?? this.itemIconSize,
      starIconSize: starIconSize ?? this.starIconSize,
      lockIconSize: lockIconSize ?? this.lockIconSize,
      chevronSize: chevronSize ?? this.chevronSize,
      iconButtonSize: iconButtonSize ?? this.iconButtonSize,
      titleFontSize: titleFontSize ?? this.titleFontSize,
      subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
      sectionTitleFontSize: sectionTitleFontSize ?? this.sectionTitleFontSize,
      chipFontSize: chipFontSize ?? this.chipFontSize,
      labelHeight: labelHeight ?? this.labelHeight,
      gridSpacing: gridSpacing ?? this.gridSpacing,
      gridRowHeight: gridRowHeight ?? this.gridRowHeight,
      chipSpacing: chipSpacing ?? this.chipSpacing,
      chipPadding: chipPadding ?? this.chipPadding,
      chipLabelPadding: chipLabelPadding ?? this.chipLabelPadding,
      chipRowHeight: chipRowHeight ?? this.chipRowHeight,
      sortButtonSize: sortButtonSize ?? this.sortButtonSize,
      pinnedHeaderSearchOnly: pinnedHeaderSearchOnly ?? this.pinnedHeaderSearchOnly,
      pinnedHeaderWithChips: pinnedHeaderWithChips ?? this.pinnedHeaderWithChips,
      expansionTilePadding: expansionTilePadding ?? this.expansionTilePadding,
      expansionChildrenPadding: expansionChildrenPadding ?? this.expansionChildrenPadding,
      tileContentPadding: tileContentPadding ?? this.tileContentPadding,
      emptyStateVertical: emptyStateVertical ?? this.emptyStateVertical,
    );
  }

  @override
  AppReportsCatalogMetrics lerp(ThemeExtension<AppReportsCatalogMetrics>? other, double t) {
    if (other is! AppReportsCatalogMetrics) return this;
    double l(double a, double b) => a + (b - a) * t;
    EdgeInsets e(EdgeInsets a, EdgeInsets b) => EdgeInsets.lerp(a, b, t) ?? a;
    return AppReportsCatalogMetrics(
      pagePadding: e(pagePadding, other.pagePadding),
      pageMaxWidth: l(pageMaxWidth, other.pageMaxWidth),
      searchHeight: l(searchHeight, other.searchHeight),
      searchRadius: l(searchRadius, other.searchRadius),
      searchContentPadding: e(searchContentPadding, other.searchContentPadding),
      headerGap: l(headerGap, other.headerGap),
      sectionGap: l(sectionGap, other.sectionGap),
      blockGap: l(blockGap, other.blockGap),
      cardPadding: e(cardPadding, other.cardPadding),
      cardRadius: l(cardRadius, other.cardRadius),
      itemPadding: e(itemPadding, other.itemPadding),
      itemRadius: l(itemRadius, other.itemRadius),
      itemIconSize: l(itemIconSize, other.itemIconSize),
      starIconSize: l(starIconSize, other.starIconSize),
      lockIconSize: l(lockIconSize, other.lockIconSize),
      chevronSize: l(chevronSize, other.chevronSize),
      iconButtonSize: l(iconButtonSize, other.iconButtonSize),
      titleFontSize: l(titleFontSize, other.titleFontSize),
      subtitleFontSize: l(subtitleFontSize, other.subtitleFontSize),
      sectionTitleFontSize: l(sectionTitleFontSize, other.sectionTitleFontSize),
      chipFontSize: l(chipFontSize, other.chipFontSize),
      labelHeight: l(labelHeight, other.labelHeight),
      gridSpacing: l(gridSpacing, other.gridSpacing),
      gridRowHeight: l(gridRowHeight, other.gridRowHeight),
      chipSpacing: l(chipSpacing, other.chipSpacing),
      chipPadding: e(chipPadding, other.chipPadding),
      chipLabelPadding: e(chipLabelPadding, other.chipLabelPadding),
      chipRowHeight: l(chipRowHeight, other.chipRowHeight),
      sortButtonSize: l(sortButtonSize, other.sortButtonSize),
      pinnedHeaderSearchOnly: l(pinnedHeaderSearchOnly, other.pinnedHeaderSearchOnly),
      pinnedHeaderWithChips: l(pinnedHeaderWithChips, other.pinnedHeaderWithChips),
      expansionTilePadding: e(expansionTilePadding, other.expansionTilePadding),
      expansionChildrenPadding: e(expansionChildrenPadding, other.expansionChildrenPadding),
      tileContentPadding: e(tileContentPadding, other.tileContentPadding),
      emptyStateVertical: l(emptyStateVertical, other.emptyStateVertical),
    );
  }
}
