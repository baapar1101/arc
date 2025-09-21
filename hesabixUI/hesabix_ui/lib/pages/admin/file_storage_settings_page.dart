import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/widgets/admin/file_storage/storage_config_list_widget.dart';
import 'package:hesabix_ui/widgets/admin/file_storage/file_statistics_widget.dart';
import 'package:hesabix_ui/widgets/admin/file_storage/file_management_widget.dart';

class FileStorageSettingsPage extends StatefulWidget {
  const FileStorageSettingsPage({super.key});

  @override
  State<FileStorageSettingsPage> createState() => _FileStorageSettingsPageState();
}

class _FileStorageSettingsPageState extends State<FileStorageSettingsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.fileStorageSettings),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.storage),
              text: l10n.storageConfigurations,
            ),
            Tab(
              icon: const Icon(Icons.analytics),
              text: l10n.fileStatistics,
            ),
            Tab(
              icon: const Icon(Icons.folder),
              text: l10n.fileManagement,
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Storage Configurations Tab
          const StorageConfigListWidget(),
          
          // File Statistics Tab
          const FileStatisticsWidget(),
          
          // File Management Tab
          const FileManagementWidget(),
        ],
      ),
    );
  }
}
