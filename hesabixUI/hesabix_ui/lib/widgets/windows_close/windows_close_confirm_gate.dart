import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hesabix_ui/config/brand_config.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/windows_update_platform.dart';
import '../../main.dart' show navigatorKey;
import '../../services/telephony/softphone_background_presence.dart';
import '../../services/telephony/softphone_engine.dart';
import '../../services/windows_desktop/windows_desktop_shell.dart';

/// Intercepts the Windows title-bar close button (and Alt+F4) for confirmation.
class WindowsCloseConfirmGate extends StatefulWidget {
  final Widget child;

  const WindowsCloseConfirmGate({super.key, required this.child});

  /// Register before [runApp] so the native WM_CLOSE handler can reach Dart immediately.
  static void installPlatformHandler() {
    if (!supportsWindowsDesktopUpdate) return;
    WindowsDesktopShell.install();
    WindowsDesktopShell.onCloseRequested = _confirmClose;
  }

  @override
  State<WindowsCloseConfirmGate> createState() => _WindowsCloseConfirmGateState();
}

class _WindowsCloseConfirmGateState extends State<WindowsCloseConfirmGate> {
  @override
  Widget build(BuildContext context) => widget.child;
}

bool _confirming = false;

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
    final engine = SoftphoneEngineStore.instance.engine;
    final softphoneOnline = engine?.wantsBackgroundPresence == true;
    final decision = windowsCloseDecision(softphoneWantsPresence: softphoneOnline);

    if (decision == WindowsCloseDecision.hideToTray) {
      final choice = await showDialog<String>(
        context: ctx,
        builder: (dialogCtx) {
          return AlertDialog(
            title: Text(t.branded(t.windowsSoftphoneStayInTrayTitle)),
            content: Text(t.windowsSoftphoneStayInTrayMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop('cancel'),
                child: Text(t.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop('exit'),
                child: Text(t.windowsSoftphoneExitAnywayAction),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogCtx).pop('tray'),
                child: Text(t.windowsSoftphoneStayInTrayAction),
              ),
            ],
          );
        },
      );
      if (choice == 'tray') {
        await WindowsDesktopShell.hideToTray(
          tooltip: engine?.windowsTrayTooltip ?? t.windowsSoftphoneStayInTrayTitle,
          showLabel: t.branded(t.windowsTrayShow),
          exitLabel: t.windowsTrayExit,
        );
      } else if (choice == 'exit') {
        await engine?.unregister();
        await WindowsDesktopShell.quit();
      }
      return;
    }

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
      await WindowsDesktopShell.quit();
    }
  } finally {
    _confirming = false;
  }
}
