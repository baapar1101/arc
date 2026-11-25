import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/theme/tokens/settings_hub.dart';

void main() {
  const hub = AppSettingsHubMetrics();

  test('uses a 1/2/3 column grid by window width', () {
    expect(hub.gridColumns(767), 1);
    expect(hub.gridColumns(768), 2);
    expect(hub.gridColumns(1199), 2);
    expect(hub.gridColumns(1200), 3);
  });

  test('treats 900px as the wide desktop density breakpoint', () {
    expect(hub.isWide(899), isFalse);
    expect(hub.isWide(900), isTrue);
    expect(hub.pagePaddingFor(900), hub.pagePadding);
    expect(hub.pagePaddingFor(800), hub.pagePaddingNarrow);
  });

  test('keeps card copy to a single dense line', () {
    expect(hub.cardTitleMaxLines, 1);
    expect(hub.cardSubtitleMaxLines, 1);
    expect(hub.categorySubtitleMaxLines, 1);
    expect(hub.cardTitleFontSize, 13);
    expect(hub.cardSubtitleFontSize, 11);
    expect(hub.pageTitleFontSize, 18);
  });

  test('copyWith and lerp preserve the dense defaults', () {
    final copied = hub.copyWith(cardTitleFontSize: 12);
    expect(copied.cardTitleFontSize, 12);
    expect(copied.cardSubtitleFontSize, hub.cardSubtitleFontSize);

    final lerped = hub.lerp(copied, 1.0);
    expect(lerped, isA<AppSettingsHubMetrics>());
    expect((lerped as AppSettingsHubMetrics).cardTitleFontSize, 12);
  });
}
