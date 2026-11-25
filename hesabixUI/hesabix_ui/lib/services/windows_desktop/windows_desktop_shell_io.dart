import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/windows_update_platform.dart';

const _channel = MethodChannel('hesabix/window_close');

/// Native Windows close / tray / incoming-call balloon via `hesabix/window_close`.
class WindowsDesktopShell {
  static Future<void> Function()? onCloseRequested;
  static Future<void> Function()? onTrayShow;
  static Future<void> Function()? onTrayExit;
  static Future<void> Function()? onIncomingClicked;

  static bool _installed = false;

  static bool get isSupported => supportsWindowsDesktopUpdate;

  static void install() {
    if (!isSupported || _installed) return;
    _installed = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'requestClose':
          await onCloseRequested?.call();
          break;
        case 'trayShow':
          await onTrayShow?.call();
          await showFromTray();
          break;
        case 'trayExit':
          if (onTrayExit != null) {
            await onTrayExit!.call();
          } else {
            await quit();
          }
          break;
        case 'incomingClicked':
          await onIncomingClicked?.call();
          await showFromTray();
          break;
      }
    });
  }

  static Future<void> hideToTray({
    String? tooltip,
    String? showLabel,
    String? exitLabel,
  }) async {
    if (!isSupported) return;
    await _invoke('hideToTray', <String, dynamic>{
      'tooltip': ?tooltip,
      'showLabel': ?showLabel,
      'exitLabel': ?exitLabel,
    });
  }

  static Future<void> showFromTray() async {
    if (!isSupported) return;
    await _invoke('showFromTray');
  }

  static Future<void> setTray({
    required bool visible,
    String? tooltip,
    String? showLabel,
    String? exitLabel,
  }) async {
    if (!isSupported) return;
    await _invoke('setTray', <String, dynamic>{
      'visible': visible,
      'tooltip': ?tooltip,
      'showLabel': ?showLabel,
      'exitLabel': ?exitLabel,
    });
  }

  static Future<void> showIncomingCall({
    required String title,
    required String body,
  }) async {
    if (!isSupported) return;
    await _invoke('showIncomingCall', <String, dynamic>{
      'title': title,
      'body': body,
    });
  }

  static Future<void> quit() async {
    if (!isSupported) return;
    await _invoke('close');
  }

  static Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      debugPrint('WindowsDesktopShell $method failed: $e');
    }
  }
}
