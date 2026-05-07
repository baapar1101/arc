import 'package:flutter/material.dart';

/// کنترل نمای ریل کناری منو در [BusinessShell] (فقط وقتی `useRail` فعال است).
class BusinessShellSideNavScope extends InheritedWidget {
  const BusinessShellSideNavScope({
    super.key,
    required this.desktopRailSupported,
    required this.desktopRailVisible,
    required this.setDesktopRailVisible,
    required super.child,
  });

  final bool desktopRailSupported;
  final bool desktopRailVisible;
  final ValueChanged<bool> setDesktopRailVisible;

  /// با subscribe به تغییرات؛ برای initState/dispose بدون نیاز به rebuild از [readMaybeOf].
  static BusinessShellSideNavScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BusinessShellSideNavScope>();

  /// بدون subscribe — مناسب `dispose` یا یکبار پس از `addPostFrameCallback`.
  static BusinessShellSideNavScope? readMaybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BusinessShellSideNavScope>();

  bool get canControlDesktopRail =>
      desktopRailSupported;

  /// نمای ریل؛ روی موبایل کاری انجام نمی‌دهد.
  void setRailVisible(bool visible) {
    if (!desktopRailSupported) return;
    setDesktopRailVisible(visible);
  }

  void toggleRail() {
    if (!desktopRailSupported) return;
    setDesktopRailVisible(!desktopRailVisible);
  }

  @override
  bool updateShouldNotify(BusinessShellSideNavScope oldWidget) =>
      desktopRailSupported != oldWidget.desktopRailSupported ||
          desktopRailVisible != oldWidget.desktopRailVisible ||
          setDesktopRailVisible != oldWidget.setDesktopRailVisible;
}
