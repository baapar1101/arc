import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/widgets/admin/file_storage/storage_config_list_widget.dart';
import 'package:hesabix_ui/widgets/admin/file_storage/storage_config_form_dialog.dart';
import 'package:hesabix_ui/widgets/admin/file_storage/storage_share_link_settings_card.dart';

class AdminStorageManagementPage extends StatefulWidget {
  const AdminStorageManagementPage({super.key});

  @override
  State<AdminStorageManagementPage> createState() => _AdminStorageManagementPageState();
}

class _AdminStorageManagementPageState extends State<AdminStorageManagementPage> {
  final GlobalKey<StorageConfigListWidgetState> _listKey = GlobalKey<StorageConfigListWidgetState>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t.storageManagement,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimary,
          ),
        ),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/user/profile/system-settings'),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.1),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: StorageShareLinkSettingsCard(),
            ),
            Expanded(
              child: StorageConfigListWidget(
                key: _listKey,
                onRefresh: () => _listKey.currentState?.loadStorageConfigs(),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context),
        icon: const Icon(Icons.add),
        label: Text(t.addStorageConfig),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => StorageConfigFormDialog(
        onSaved: () {
          // Refresh the list
          _listKey.currentState?.loadStorageConfigs();
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${AppLocalizations.of(context).addStorageConfig} ${AppLocalizations.of(context).save}'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }
}
