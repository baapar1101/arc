import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth_store.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';import '../utils/snackbar_helper.dart';


class LogoutButton extends StatelessWidget {
  final AuthStore authStore;
  const LogoutButton({super.key, required this.authStore});

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
    return Tooltip(
      message: t.logout,
      child: InkWell(
        onTap: () => _confirmAndLogout(context),
        customBorder: const CircleBorder(),
        child: CircleAvatar(
          radius: 14,
          backgroundColor: cs.surfaceContainerHighest,
          foregroundColor: cs.onSurface,
          child: const Icon(Icons.logout, size: 16),
        ),
      ),
    );
  }
}


