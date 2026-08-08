import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

Future<void> softphoneLaunchAppToForeground() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await FlutterForegroundTask.launchApp('/');
  } catch (_) {
    try {
      FlutterForegroundTask.launchApp();
    } catch (_) {}
  }
}
