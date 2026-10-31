/// No-op Windows desktop shell (web / non-Windows).
class WindowsDesktopShell {
  static Future<void> Function()? onCloseRequested;
  static Future<void> Function()? onTrayShow;
  static Future<void> Function()? onTrayExit;
  static Future<void> Function()? onIncomingClicked;

  static bool get isSupported => false;

  static void install() {}

  static Future<void> hideToTray({
    String? tooltip,
    String? showLabel,
    String? exitLabel,
  }) async {}

  static Future<void> showFromTray() async {}

  static Future<void> setTray({
    required bool visible,
    String? tooltip,
    String? showLabel,
    String? exitLabel,
  }) async {}

  static Future<void> showIncomingCall({
    required String title,
    required String body,
  }) async {}

  static Future<void> quit() async {}
}
