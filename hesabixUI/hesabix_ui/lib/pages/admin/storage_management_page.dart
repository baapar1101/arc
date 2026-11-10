import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/widgets/admin/file_storage/storage_config_list_widget.dart';
import 'package:hesabix_ui/widgets/admin/file_storage/storage_config_form_dialog.dart';
import 'package:hesabix_ui/widgets/admin/file_storage/storage_share_link_settings_card.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'admin_compact_scaffold.dart';

class AdminStorageManagementPage extends StatefulWidget {
  const AdminStorageManagementPage({super.key});

  @override
  State<AdminStorageManagementPage> createState() => _AdminStorageManagementPageState();
}

class _AdminStorageManagementPageState extends State<AdminStorageManagementPage> {
  final GlobalKey<StorageConfigListWidgetState> _listKey = GlobalKey<StorageConfigListWidgetState>();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return AdminCompactScaffold(
      title: t.storageManagement,
      subtitle: adminTx(context, 'محل فایل‌ها و پیوندهای اشتراک', 'File locations and share links'),
      actions: [
        IconButton(
          tooltip: t.addStorageConfig,
          onPressed: () => _showCreateDialog(context),
          icon: const Icon(Icons.add, size: 20),
        ),
      ],
      body: Column(
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
              backgroundColor: SemanticColorResolver.positive(context),
            ),
          );
        },
      ),
    );
  }
}
