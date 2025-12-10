import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../core/auth_store.dart';import '../utils/snackbar_helper.dart';


class UserAccountMenuButton extends StatelessWidget {
  final AuthStore authStore;

  const UserAccountMenuButton({
    super.key,
    required this.authStore,
  });

  void _showUserMenu(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.profile),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.person, color: cs.onSurface),
              title: Text(t.profile),
              onTap: () {
                context.pop();
                // Navigate to profile page
              },
            ),
            ListTile(
              leading: Icon(Icons.settings, color: cs.onSurface),
              title: Text(t.settings),
              onTap: () {
                context.pop();
                // Navigate to account settings
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.logout, color: cs.error),
              title: Text(t.logout, style: TextStyle(color: cs.error)),
              onTap: () {
                context.pop();
                // Trigger logout
                _confirmLogout(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    final t = AppLocalizations.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.logoutConfirmTitle),
        content: Text(t.logoutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () async {
              context.pop();
              await authStore.saveApiKey(null);
              if (!context.mounted) return;
              SnackBarHelper.show(context, message: t.logoutDone);
            },
            child: Text(t.logout),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return IconButton(
      icon: CircleAvatar(
        radius: 16,
        backgroundColor: cs.surfaceContainerHighest,
        foregroundColor: cs.onSurface,
        child: const Icon(Icons.person, size: 18),
      ),
      onPressed: () => _showUserMenu(context),
      tooltip: AppLocalizations.of(context).profile,
    );
  }
}
