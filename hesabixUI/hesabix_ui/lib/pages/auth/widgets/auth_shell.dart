import 'package:flutter/material.dart';

import '../../../core/calendar_controller.dart';
import '../../../core/locale_controller.dart';
import '../../../theme/brand_logo.dart';
import '../../../theme/theme_controller.dart';
import '../../../utils/responsive_helper.dart';
import '../../../widgets/calendar_switcher.dart';
import '../../../widgets/language_switcher.dart';
import '../../../widgets/theme_mode_switcher.dart';
import '../../../widgets/theme_palette_switcher.dart';
import 'auth_brand_panel.dart';

/// قالب دو ستونه صفحات auth — برند + فرم.
class AuthShell extends StatelessWidget {
  final Widget formPanel;
  final LocaleController localeController;
  final CalendarController calendarController;
  final ThemeController? themeController;

  /// سازگاری با فراخوانی‌های قدیمی؛ نادیده گرفته می‌شود (لوگو از تم می‌آید).
  @Deprecated('Logo follows theme via BrandLogo')
  final String? logoAsset;

  const AuthShell({
    super.key,
    required this.formPanel,
    required this.localeController,
    required this.calendarController,
    this.themeController,
    this.logoAsset,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = ResponsiveHelper.isDesktop(context) || ResponsiveHelper.isTablet(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            if (isWide)
              Row(
                children: [
                  const Expanded(child: AuthBrandPanel()),
                  Expanded(
                    child: _FormScroll(
                      bottomInset: bottomInset,
                      child: formPanel,
                    ),
                  ),
                ],
              )
            else
              _FormScroll(
                bottomInset: bottomInset,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Row(
                        children: [
                          BrandLogo(height: 36),
                        ],
                      ),
                    ),
                    Expanded(child: formPanel),
                  ],
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (themeController != null) ...[
                    ThemePaletteSwitcher(controller: themeController!),
                    const SizedBox(width: 4),
                    ThemeModeSwitcher(controller: themeController!),
                    const SizedBox(width: 4),
                  ],
                  LanguageSwitcher(controller: localeController),
                ],
              ),
            ),
            if (!isWide)
              Positioned(
                bottom: 8 + bottomInset,
                right: 8,
                child: CalendarSwitcher(controller: calendarController),
              ),
          ],
        ),
      ),
    );
  }
}

class _FormScroll extends StatelessWidget {
  final Widget child;
  final double bottomInset;

  const _FormScroll({required this.child, required this.bottomInset});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 56, 24, bottomInset + 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: child,
        ),
      ),
    );
  }
}
