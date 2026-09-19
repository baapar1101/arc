import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/config/brand_config.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/windows_update_platform.dart';
import '../../main.dart' show navigatorKey;

/// Intercepts the Windows title-bar close button (and Alt+F4) for confirmation.
class WindowsCloseConfirmGate extends StatefulWidget {
  final Widget child;

  const WindowsCloseConfirmGate({super.key, required this.child});

  /// Register before [runApp] so the native WM_CLOSE handler can reach Dart immediately.
  static void installPlatformHandler() {
    if (!_isWindowsDesktop || _handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'requestClose') {
        await _confirmClose();
      }
    });
  }

  @override
  State<WindowsCloseConfirmGate> createState() => _WindowsCloseConfirmGateState();
}

class _WindowsCloseConfirmGateState extends State<WindowsCloseConfirmGate> {
  @override
  Widget build(BuildContext context) => widget.child;
}

const _channel = MethodChannel('hesabix/window_close');

bool _handlerInstalled = false;
bool _confirming = false;

bool get _isWindowsDesktop => supportsWindowsDesktopUpdate;

Future<void> _confirmClose() async {
  if (_confirming) return;

  final ctx = navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _confirmClose());
    return;
  }

  _confirming = true;
  try {
    final t = AppLocalizations.of(ctx);
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(t.branded(t.windowsExitConfirmTitle)),
          content: Text(t.windowsExitConfirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(t.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(t.windowsExitConfirmAction),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      await _channel.invokeMethod<void>('close');
    }
  } finally {
    _confirming = false;
  }
}
