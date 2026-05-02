import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth_store.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../utils/snackbar_helper.dart';
class LogoutButton extends StatelessWidget {
  final AuthStore authStore;
  final bool toolbarCompact;
  const LogoutButton({super.key, required this.authStore, this.toolbarCompact = false});

  Future<void> _confirmAndLogout(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.logoutConfirmTitle),
          content: Text(t.logoutConfirmMessage),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.logout)),
          ],
        );
      },
    );

    if (ok != true) return;

    await authStore.saveApiKey(null);
    if (!context.mounted) return;
    SnackBarHelper.show(context, message: t.logoutDone);
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    final iconSz = toolbarCompact ? 14.0 : 16.0;
    final avatarR = toolbarCompact ? 12.0 : 14.0;
    return Tooltip(
      message: t.logout,
      child: InkWell(
        onTap: () => _confirmAndLogout(context),
        customBorder: const CircleBorder(),
        child: CircleAvatar(
          radius: avatarR,
          backgroundColor: cs.surfaceContainerHighest,
          foregroundColor: cs.onSurface,
          child: Icon(Icons.logout, size: iconSz),
        ),
      ),
    );
  }
}


