import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../windows_desktop/windows_desktop_shell.dart';

Future<void> softphoneLaunchAppToForeground() async {
  if (kIsWeb) return;
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      // launchApp returns void (not Future) in flutter_foreground_task.
      FlutterForegroundTask.launchApp('/');
    } catch (_) {
      try {
        FlutterForegroundTask.launchApp();
      } catch (_) {}
    }
    return;
  }
  if (defaultTargetPlatform == TargetPlatform.windows) {
    await WindowsDesktopShell.showFromTray();
  }
}
