import 'package:flutter/material.dart';

/// متریک فشردهٔ هاب تنظیمات کسب‌وکار.
///
/// مقادیر اینجا منبع حقیقت هستند؛ ویجت‌های هاب نباید padding/font را هاردکد کنند.
@immutable
class AppSettingsHubMetrics extends ThemeExtension<AppSettingsHubMetrics> {
  final EdgeInsets pagePadding;
  final EdgeInsets pagePaddingNarrow;
  final double sectionGap;
  final double sectionGapNarrow;
  final double innerGap;
  final double bottomGap;
  final double pageTitleFontSize;
  final double pageSubtitleFontSize;
  final double pageSubtitleHeight;
  final double headerTitleGap;
  final EdgeInsets roleBadgePadding;
  final double roleBadgeIconSize;
  final double roleBadgeGap;
  final double roleBadgeFontSize;
  final EdgeInsets searchMargin;
  final EdgeInsets searchMarginNarrow;
  final EdgeInsets searchContentPadding;
  final EdgeInsets searchContentPaddingNarrow;
  final double searchIconSize;
  final double searchRadius;
  final EdgeInsets controlButtonPadding;
  final double controlButtonFontSize;
  final EdgeInsets setupPadding;
  final EdgeInsets setupMargin;
  final double setupIconSize;
  final double setupTitleFontSize;
  final double setupTitleGap;
  final double listTitleFontSize;
  final double listTitleGap;
  final EdgeInsets categoryHeaderPadding;
  final EdgeInsets categoryHeaderPaddingNarrow;
  final EdgeInsets categoryBodyPadding;
  final EdgeInsets categoryBodyPaddingNarrow;
  final double categorySectionBottom;
  final double categorySectionBottomNarrow;
  final double categoryRadius;
  final double categoryIconSize;
  final double categoryIconGap;
  final double categoryTitleFontSize;
  final double categorySubtitleFontSize;
  final double categoryTitleGap;
  final int categorySubtitleMaxLines;
  final EdgeInsets cardPadding;
  final double cardRadius;
  final double cardIconSize;
  final EdgeInsets cardIconPadding;
  final double cardIconRadius;
  final double cardIconGap;
  final double cardTitleFontSize;
  final double cardSubtitleFontSize;
  final double cardTitleGap;
  final int cardTitleMaxLines;
  final int cardSubtitleMaxLines;
  final double labelHeight;
  final double chevronSize;
  final double gridGap;
  final double gridRunSpacing;
  final double twoColumnMinWidth;
  final double threeColumnMinWidth;
  final double wideMinWidth;
  final EdgeInsets emptyStatePadding;
  final double emptyStateIconSize;

  const AppSettingsHubMetrics({
    this.pagePadding = const EdgeInsets.fromLTRB(10, 6, 10, 10),
    this.pagePaddingNarrow = const EdgeInsets.fromLTRB(12, 10, 12, 12),
    this.sectionGap = 8,
    this.sectionGapNarrow = 12,
    this.innerGap = 8,
    this.bottomGap = 10,
    this.pageTitleFontSize = 18,
    this.pageSubtitleFontSize = 12,
    this.pageSubtitleHeight = 1.25,
    this.headerTitleGap = 2,
    this.roleBadgePadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    this.roleBadgeIconSize = 14,
    this.roleBadgeGap = 4,
    this.roleBadgeFontSize = 11.5,
    this.searchMargin = const EdgeInsets.only(bottom: 6),
    this.searchMarginNarrow = const EdgeInsets.only(bottom: 10),
    this.searchContentPadding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.searchContentPaddingNarrow =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.searchIconSize = 18,
    this.searchRadius = 8,
    this.controlButtonPadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.controlButtonFontSize = 12,
    this.setupPadding = const EdgeInsets.all(10),
    this.setupMargin = const EdgeInsets.only(top: 6, bottom: 4),
    this.setupIconSize = 16,
    this.setupTitleFontSize = 13,
    this.setupTitleGap = 2,
    this.listTitleFontSize = 13.5,
    this.listTitleGap = 8,
    this.categoryHeaderPadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.categoryHeaderPaddingNarrow =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.categoryBodyPadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.categoryBodyPaddingNarrow =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.categorySectionBottom = 6,
    this.categorySectionBottomNarrow = 8,
    this.categoryRadius = 8,
    this.categoryIconSize = 16,
    this.categoryIconGap = 8,
    this.categoryTitleFontSize = 13.5,
    this.categorySubtitleFontSize = 11,
    this.categoryTitleGap = 2,
    this.categorySubtitleMaxLines = 1,
    this.cardPadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    this.cardRadius = 6,
    this.cardIconSize = 16,
    this.cardIconPadding = const EdgeInsets.all(5),
    this.cardIconRadius = 6,
    this.cardIconGap = 8,
    this.cardTitleFontSize = 13,
    this.cardSubtitleFontSize = 11,
    this.cardTitleGap = 2,
    this.cardTitleMaxLines = 1,
    this.cardSubtitleMaxLines = 1,
    this.labelHeight = 1.2,
    this.chevronSize = 16,
    this.gridGap = 6,
    this.gridRunSpacing = 4,
    this.twoColumnMinWidth = 768,
    this.threeColumnMinWidth = 1200,
    this.wideMinWidth = 900,
    this.emptyStatePadding = const EdgeInsets.all(20),
    this.emptyStateIconSize = 40,
  });

  bool isWide(double width) => width >= wideMinWidth;

  int gridColumns(double width) {
    if (width >= threeColumnMinWidth) return 3;
    if (width >= twoColumnMinWidth) return 2;
    return 1;
  }

  EdgeInsets pagePaddingFor(double width) =>
      isWide(width) ? pagePadding : pagePaddingNarrow;

  double sectionGapFor(double width) => isWide(width) ? sectionGap : sectionGapNarrow;

  EdgeInsets searchMarginFor({required bool dense}) =>
      dense ? searchMargin : searchMarginNarrow;

  EdgeInsets searchContentPaddingFor({required bool dense}) =>
      dense ? searchContentPadding : searchContentPaddingNarrow;

  EdgeInsets categoryHeaderPaddingFor(double width) =>
      isWide(width) ? categoryHeaderPadding : categoryHeaderPaddingNarrow;

  EdgeInsets categoryBodyPaddingFor(double width) =>
      isWide(width) ? categoryBodyPadding : categoryBodyPaddingNarrow;

  double categorySectionBottomFor(double width) =>
      isWide(width) ? categorySectionBottom : categorySectionBottomNarrow;

  TextStyle pageTitleStyle(TextTheme textTheme, {required Color color}) {
    return (textTheme.titleLarge ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: FontWeight.w700,
      fontSize: pageTitleFontSize,
      height: labelHeight,
    );
  }

  TextStyle pageSubtitleStyle(TextTheme textTheme, {required Color color}) {
    return (textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: FontWeight.w400,
      fontSize: pageSubtitleFontSize,
      height: pageSubtitleHeight,
    );
  }

  TextStyle listTitleStyle(TextTheme textTheme, {required Color color}) {
    return (textTheme.titleSmall ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: FontWeight.w700,
      fontSize: listTitleFontSize,
      height: labelHeight,
    );
  }

  TextStyle categoryTitleStyle(TextTheme textTheme, {required Color color}) {
    return (textTheme.titleSmall ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: FontWeight.w600,
      fontSize: categoryTitleFontSize,
      height: labelHeight,
    );
  }

  TextStyle categorySubtitleStyle(TextTheme textTheme, {required Color color}) {
    return (textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: FontWeight.w400,
      fontSize: categorySubtitleFontSize,
      height: labelHeight,
    );
  }

  TextStyle cardTitleStyle(TextTheme textTheme, {required Color color}) {
    return (textTheme.labelLarge ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: FontWeight.w600,
      fontSize: cardTitleFontSize,
      height: labelHeight,
    );
  }

  TextStyle cardSubtitleStyle(TextTheme textTheme, {required Color color}) {
    return (textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: FontWeight.w400,
      fontSize: cardSubtitleFontSize,
      height: labelHeight,
    );
  }

  @override
  AppSettingsHubMetrics copyWith({
    EdgeInsets? pagePadding,
    EdgeInsets? pagePaddingNarrow,
    double? sectionGap,
    double? sectionGapNarrow,
    double? innerGap,
    double? bottomGap,
    double? pageTitleFontSize,
    double? pageSubtitleFontSize,
    double? pageSubtitleHeight,
    double? headerTitleGap,
    EdgeInsets? roleBadgePadding,
    double? roleBadgeIconSize,
    double? roleBadgeGap,
    double? roleBadgeFontSize,
    EdgeInsets? searchMargin,
    EdgeInsets? searchMarginNarrow,
    EdgeInsets? searchContentPadding,
    EdgeInsets? searchContentPaddingNarrow,
    double? searchIconSize,
    double? searchRadius,
    EdgeInsets? controlButtonPadding,
    double? controlButtonFontSize,
    EdgeInsets? setupPadding,
    EdgeInsets? setupMargin,
    double? setupIconSize,
    double? setupTitleFontSize,
    double? setupTitleGap,
    double? listTitleFontSize,
    double? listTitleGap,
    EdgeInsets? categoryHeaderPadding,
    EdgeInsets? categoryHeaderPaddingNarrow,
    EdgeInsets? categoryBodyPadding,
    EdgeInsets? categoryBodyPaddingNarrow,
    double? categorySectionBottom,
    double? categorySectionBottomNarrow,
    double? categoryRadius,
    double? categoryIconSize,
    double? categoryIconGap,
    double? categoryTitleFontSize,
    double? categorySubtitleFontSize,
    double? categoryTitleGap,
    int? categorySubtitleMaxLines,
    EdgeInsets? cardPadding,
    double? cardRadius,
    double? cardIconSize,
    EdgeInsets? cardIconPadding,
    double? cardIconRadius,
    double? cardIconGap,
    double? cardTitleFontSize,
    double? cardSubtitleFontSize,
    double? cardTitleGap,
    int? cardTitleMaxLines,
    int? cardSubtitleMaxLines,
    double? labelHeight,
    double? chevronSize,
    double? gridGap,
    double? gridRunSpacing,
    double? twoColumnMinWidth,
    double? threeColumnMinWidth,
    double? wideMinWidth,
    EdgeInsets? emptyStatePadding,
    double? emptyStateIconSize,
  }) {
    return AppSettingsHubMetrics(
      pagePadding: pagePadding ?? this.pagePadding,
      pagePaddingNarrow: pagePaddingNarrow ?? this.pagePaddingNarrow,
      sectionGap: sectionGap ?? this.sectionGap,
      sectionGapNarrow: sectionGapNarrow ?? this.sectionGapNarrow,
      innerGap: innerGap ?? this.innerGap,
      bottomGap: bottomGap ?? this.bottomGap,
      pageTitleFontSize: pageTitleFontSize ?? this.pageTitleFontSize,
      pageSubtitleFontSize: pageSubtitleFontSize ?? this.pageSubtitleFontSize,
      pageSubtitleHeight: pageSubtitleHeight ?? this.pageSubtitleHeight,
      headerTitleGap: headerTitleGap ?? this.headerTitleGap,
      roleBadgePadding: roleBadgePadding ?? this.roleBadgePadding,
      roleBadgeIconSize: roleBadgeIconSize ?? this.roleBadgeIconSize,
      roleBadgeGap: roleBadgeGap ?? this.roleBadgeGap,
      roleBadgeFontSize: roleBadgeFontSize ?? this.roleBadgeFontSize,
      searchMargin: searchMargin ?? this.searchMargin,
      searchMarginNarrow: searchMarginNarrow ?? this.searchMarginNarrow,
      searchContentPadding: searchContentPadding ?? this.searchContentPadding,
      searchContentPaddingNarrow:
          searchContentPaddingNarrow ?? this.searchContentPaddingNarrow,
      searchIconSize: searchIconSize ?? this.searchIconSize,
      searchRadius: searchRadius ?? this.searchRadius,
      controlButtonPadding: controlButtonPadding ?? this.controlButtonPadding,
      controlButtonFontSize: controlButtonFontSize ?? this.controlButtonFontSize,
      setupPadding: setupPadding ?? this.setupPadding,
      setupMargin: setupMargin ?? this.setupMargin,
      setupIconSize: setupIconSize ?? this.setupIconSize,
      setupTitleFontSize: setupTitleFontSize ?? this.setupTitleFontSize,
      setupTitleGap: setupTitleGap ?? this.setupTitleGap,
      listTitleFontSize: listTitleFontSize ?? this.listTitleFontSize,
      listTitleGap: listTitleGap ?? this.listTitleGap,
      categoryHeaderPadding: categoryHeaderPadding ?? this.categoryHeaderPadding,
      categoryHeaderPaddingNarrow:
          categoryHeaderPaddingNarrow ?? this.categoryHeaderPaddingNarrow,
      categoryBodyPadding: categoryBodyPadding ?? this.categoryBodyPadding,
      categoryBodyPaddingNarrow:
          categoryBodyPaddingNarrow ?? this.categoryBodyPaddingNarrow,
      categorySectionBottom: categorySectionBottom ?? this.categorySectionBottom,
      categorySectionBottomNarrow:
          categorySectionBottomNarrow ?? this.categorySectionBottomNarrow,
      categoryRadius: categoryRadius ?? this.categoryRadius,
      categoryIconSize: categoryIconSize ?? this.categoryIconSize,
      categoryIconGap: categoryIconGap ?? this.categoryIconGap,
      categoryTitleFontSize: categoryTitleFontSize ?? this.categoryTitleFontSize,
      categorySubtitleFontSize: categorySubtitleFontSize ?? this.categorySubtitleFontSize,
      categoryTitleGap: categoryTitleGap ?? this.categoryTitleGap,
      categorySubtitleMaxLines: categorySubtitleMaxLines ?? this.categorySubtitleMaxLines,
      cardPadding: cardPadding ?? this.cardPadding,
      cardRadius: cardRadius ?? this.cardRadius,
      cardIconSize: cardIconSize ?? this.cardIconSize,
      cardIconPadding: cardIconPadding ?? this.cardIconPadding,
      cardIconRadius: cardIconRadius ?? this.cardIconRadius,
      cardIconGap: cardIconGap ?? this.cardIconGap,
      cardTitleFontSize: cardTitleFontSize ?? this.cardTitleFontSize,
      cardSubtitleFontSize: cardSubtitleFontSize ?? this.cardSubtitleFontSize,
      cardTitleGap: cardTitleGap ?? this.cardTitleGap,
      cardTitleMaxLines: cardTitleMaxLines ?? this.cardTitleMaxLines,
      cardSubtitleMaxLines: cardSubtitleMaxLines ?? this.cardSubtitleMaxLines,
      labelHeight: labelHeight ?? this.labelHeight,
      chevronSize: chevronSize ?? this.chevronSize,
      gridGap: gridGap ?? this.gridGap,
      gridRunSpacing: gridRunSpacing ?? this.gridRunSpacing,
      twoColumnMinWidth: twoColumnMinWidth ?? this.twoColumnMinWidth,
      threeColumnMinWidth: threeColumnMinWidth ?? this.threeColumnMinWidth,
      wideMinWidth: wideMinWidth ?? this.wideMinWidth,
      emptyStatePadding: emptyStatePadding ?? this.emptyStatePadding,
      emptyStateIconSize: emptyStateIconSize ?? this.emptyStateIconSize,
    );
  }

  @override
  AppSettingsHubMetrics lerp(ThemeExtension<AppSettingsHubMetrics>? other, double t) {
    if (other is! AppSettingsHubMetrics) return this;
    double l(double a, double b) => a + (b - a) * t;
    EdgeInsets e(EdgeInsets a, EdgeInsets b) => EdgeInsets.lerp(a, b, t) ?? a;
    int n(int a, int b) => (a + (b - a) * t).round();
    return AppSettingsHubMetrics(
      pagePadding: e(pagePadding, other.pagePadding),
      pagePaddingNarrow: e(pagePaddingNarrow, other.pagePaddingNarrow),
      sectionGap: l(sectionGap, other.sectionGap),
      sectionGapNarrow: l(sectionGapNarrow, other.sectionGapNarrow),
      innerGap: l(innerGap, other.innerGap),
      bottomGap: l(bottomGap, other.bottomGap),
      pageTitleFontSize: l(pageTitleFontSize, other.pageTitleFontSize),
      pageSubtitleFontSize: l(pageSubtitleFontSize, other.pageSubtitleFontSize),
      pageSubtitleHeight: l(pageSubtitleHeight, other.pageSubtitleHeight),
      headerTitleGap: l(headerTitleGap, other.headerTitleGap),
      roleBadgePadding: e(roleBadgePadding, other.roleBadgePadding),
      roleBadgeIconSize: l(roleBadgeIconSize, other.roleBadgeIconSize),
      roleBadgeGap: l(roleBadgeGap, other.roleBadgeGap),
      roleBadgeFontSize: l(roleBadgeFontSize, other.roleBadgeFontSize),
      searchMargin: e(searchMargin, other.searchMargin),
      searchMarginNarrow: e(searchMarginNarrow, other.searchMarginNarrow),
      searchContentPadding: e(searchContentPadding, other.searchContentPadding),
      searchContentPaddingNarrow:
          e(searchContentPaddingNarrow, other.searchContentPaddingNarrow),
      searchIconSize: l(searchIconSize, other.searchIconSize),
      searchRadius: l(searchRadius, other.searchRadius),
      controlButtonPadding: e(controlButtonPadding, other.controlButtonPadding),
      controlButtonFontSize: l(controlButtonFontSize, other.controlButtonFontSize),
      setupPadding: e(setupPadding, other.setupPadding),
      setupMargin: e(setupMargin, other.setupMargin),
      setupIconSize: l(setupIconSize, other.setupIconSize),
      setupTitleFontSize: l(setupTitleFontSize, other.setupTitleFontSize),
      setupTitleGap: l(setupTitleGap, other.setupTitleGap),
      listTitleFontSize: l(listTitleFontSize, other.listTitleFontSize),
      listTitleGap: l(listTitleGap, other.listTitleGap),
      categoryHeaderPadding: e(categoryHeaderPadding, other.categoryHeaderPadding),
      categoryHeaderPaddingNarrow:
          e(categoryHeaderPaddingNarrow, other.categoryHeaderPaddingNarrow),
      categoryBodyPadding: e(categoryBodyPadding, other.categoryBodyPadding),
      categoryBodyPaddingNarrow:
          e(categoryBodyPaddingNarrow, other.categoryBodyPaddingNarrow),
      categorySectionBottom: l(categorySectionBottom, other.categorySectionBottom),
      categorySectionBottomNarrow:
          l(categorySectionBottomNarrow, other.categorySectionBottomNarrow),
      categoryRadius: l(categoryRadius, other.categoryRadius),
      categoryIconSize: l(categoryIconSize, other.categoryIconSize),
      categoryIconGap: l(categoryIconGap, other.categoryIconGap),
      categoryTitleFontSize: l(categoryTitleFontSize, other.categoryTitleFontSize),
      categorySubtitleFontSize: l(categorySubtitleFontSize, other.categorySubtitleFontSize),
      categoryTitleGap: l(categoryTitleGap, other.categoryTitleGap),
      categorySubtitleMaxLines: n(categorySubtitleMaxLines, other.categorySubtitleMaxLines),
      cardPadding: e(cardPadding, other.cardPadding),
      cardRadius: l(cardRadius, other.cardRadius),
      cardIconSize: l(cardIconSize, other.cardIconSize),
      cardIconPadding: e(cardIconPadding, other.cardIconPadding),
      cardIconRadius: l(cardIconRadius, other.cardIconRadius),
      cardIconGap: l(cardIconGap, other.cardIconGap),
      cardTitleFontSize: l(cardTitleFontSize, other.cardTitleFontSize),
      cardSubtitleFontSize: l(cardSubtitleFontSize, other.cardSubtitleFontSize),
      cardTitleGap: l(cardTitleGap, other.cardTitleGap),
      cardTitleMaxLines: n(cardTitleMaxLines, other.cardTitleMaxLines),
      cardSubtitleMaxLines: n(cardSubtitleMaxLines, other.cardSubtitleMaxLines),
      labelHeight: l(labelHeight, other.labelHeight),
      chevronSize: l(chevronSize, other.chevronSize),
      gridGap: l(gridGap, other.gridGap),
      gridRunSpacing: l(gridRunSpacing, other.gridRunSpacing),
      twoColumnMinWidth: l(twoColumnMinWidth, other.twoColumnMinWidth),
      threeColumnMinWidth: l(threeColumnMinWidth, other.threeColumnMinWidth),
      wideMinWidth: l(wideMinWidth, other.wideMinWidth),
      emptyStatePadding: e(emptyStatePadding, other.emptyStatePadding),
      emptyStateIconSize: l(emptyStateIconSize, other.emptyStateIconSize),
    );
  }
}
